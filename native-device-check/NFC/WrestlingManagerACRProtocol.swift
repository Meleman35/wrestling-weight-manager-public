import Foundation

// ACS ACR1555U reference manual, §§5.2.3–5.2.4, 5.5.3.4.
// BLE fragmentation/sequence behavior cross-checked against nvx/go-acr1555ble
// (MIT; see Verification/THIRD-PARTY-NOTICES.txt). This is a read-only PICC client.
enum WrestlingManagerACRProtocol {
    enum Failure: Error { case malformed, unsupported, noCredential, ambiguous }

    static func command(_ type: UInt8, sequence: UInt8, data: [UInt8] = []) -> [UInt8] {
        let n = UInt32(data.count)
        return [type, UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8),
                UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24),
                0, sequence, 0, 0, 0] + data
    }

    static func frame(_ chunk: [UInt8], total: Int, host: UInt8, reader: UInt8) -> Data {
        var bytes: [UInt8] = [0x55, 0, UInt8((total >> 8) & 255), UInt8(total & 255), 0, host, reader]
        bytes += chunk
        bytes.append(bytes.dropFirst().reduce(0, ^))
        bytes.append(0xAA)
        return Data(bytes)
    }

    struct Response: Equatable, Sendable {
        let type: UInt8
        let sequence: UInt8
        let status: UInt8
        let error: UInt8
        let chain: UInt8
        let data: [UInt8]
    }

    struct Decoder: Sendable {
        private var buffer: [UInt8] = []
        private var total = 0
        private var lastSequence: UInt8?

        mutating func reset() { buffer = []; total = 0; lastSequence = nil }

        // Each GATT value is an independently wrapped ACS fragment. The length
        // field describes the whole CCID message, not this fragment's size.
        mutating func accept(_ value: Data) throws -> Response? {
            let b = [UInt8](value)
            guard b.count >= 10, b[0] == 0x55, b.last == 0xAA, b[1] == 0, b[4] == 0,
                  b.dropFirst().dropLast(2).reduce(0, ^) == b[b.count - 2] else {
                reset(); throw Failure.malformed
            }
            let n = Int(b[2]) << 8 | Int(b[3])
            let fragment = Array(b[7..<(b.count - 2)])
            guard (10...2048).contains(n), fragment.count <= n else { reset(); throw Failure.malformed }
            if buffer.isEmpty { total = n }
            else if n != total || b[6] != (lastSequence! &+ 1) { reset(); throw Failure.malformed }
            lastSequence = b[6]
            buffer += fragment
            guard buffer.count <= total else { reset(); throw Failure.malformed }
            guard buffer.count == total else { return nil }
            let message = buffer
            reset()
            let length = UInt32(message[1]) | UInt32(message[2]) << 8 |
                         UInt32(message[3]) << 16 | UInt32(message[4]) << 24
            guard message[5] == 0, length == UInt32(message.count - 10) else { throw Failure.malformed }
            return Response(type: message[0], sequence: message[6], status: message[7],
                            error: message[8], chain: message[9], data: Array(message.dropFirst(10)))
        }
    }

    static func cardPresent(_ bytes: Data) -> Bool? {
        let b = [UInt8](bytes)
        guard b.count == 2, b[0] == 0x50 else { return nil }
        return b[1] & 1 != 0
    }

    static func validToken(_ value: String) -> Bool {
        value.range(of: "\\A(WMC-[A-Za-z0-9_-]{22}|WMWC-[a-f0-9]{48})\\z", options: .regularExpression) != nil
    }

    static func capacity(_ cc: [UInt8]) throws -> Int {
        guard cc.count == 4, cc[0] == 0xE1, cc[1] >> 4 == 1, cc[3] >> 4 == 0 else {
            throw Failure.unsupported
        }
        let size = Int(cc[2]) * 8
        // NTAG213 / 215 / 216. Other mappings need their own tested reader.
        guard [144, 496, 872].contains(size) else { throw Failure.unsupported }
        return size
    }

    static func credential(in memory: [UInt8]) throws -> String {
        var cursor = 0
        var found: String?
        while cursor < memory.count {
            let type = memory[cursor]; cursor += 1
            if type == 0 { continue }
            if type == 0xFE { break }
            guard cursor < memory.count else { throw Failure.malformed }
            var length = Int(memory[cursor]); cursor += 1
            if length == 255 {
                guard cursor + 2 <= memory.count else { throw Failure.malformed }
                length = Int(memory[cursor]) << 8 | Int(memory[cursor + 1]); cursor += 2
            }
            guard cursor + length <= memory.count else { throw Failure.malformed }
            // A memory-control TLV could introduce reserved holes into NDEF;
            // fail closed rather than interpreting that alternate mapping.
            if type == 2 { throw Failure.unsupported }
            if type == 3 {
                let token = try textCredential(Array(memory[cursor..<(cursor + length)]))
                if let token {
                    guard found == nil else { throw Failure.ambiguous }
                    found = token
                }
            }
            cursor += length
        }
        guard let found else { throw Failure.noCredential }
        return found
    }

    private static func textCredential(_ bytes: [UInt8]) throws -> String? {
        var cursor = 0, records = 0
        var ended = false
        var found: String?
        while cursor < bytes.count {
            guard cursor + 2 <= bytes.count, !ended else { throw Failure.malformed }
            let flags = bytes[cursor], typeLength = Int(bytes[cursor + 1]); cursor += 2
            guard (flags & 0x80 != 0) == (records == 0), flags & 0x20 == 0 else { throw Failure.malformed }
            let short = flags & 0x10 != 0
            guard cursor + (short ? 1 : 4) <= bytes.count else { throw Failure.malformed }
            var payloadLength = 0
            for _ in 0..<(short ? 1 : 4) { payloadLength = payloadLength << 8 | Int(bytes[cursor]); cursor += 1 }
            var idLength = 0
            if flags & 8 != 0 {
                guard cursor < bytes.count else { throw Failure.malformed }
                idLength = Int(bytes[cursor]); cursor += 1
            }
            guard payloadLength <= bytes.count, cursor + typeLength + idLength + payloadLength <= bytes.count else {
                throw Failure.malformed
            }
            let type = Array(bytes[cursor..<(cursor + typeLength)])
            cursor += typeLength + idLength
            let payload = Array(bytes[cursor..<(cursor + payloadLength)])
            cursor += payloadLength
            if flags & 7 == 1, type == [0x54], let status = payload.first {
                let start = 1 + Int(status & 0x3F)
                guard status & 0x40 == 0, start <= payload.count else { throw Failure.malformed }
                let text = String(data: Data(payload.dropFirst(start)), encoding: status & 0x80 == 0 ? .utf8 : .utf16)
                if let text, validToken(text) {
                    guard found == nil else { throw Failure.ambiguous }
                    found = text
                }
            }
            records += 1
            ended = flags & 0x40 != 0
        }
        guard ended else { throw Failure.malformed }
        return found
    }
}
