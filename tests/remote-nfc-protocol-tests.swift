import Foundation

// Run the real Foundation-only production decoder with xcrun swiftc; no BLE mocks.
@main
@MainActor
struct ACR1555ProtocolTests {
    typealias P = WrestlingManagerACRProtocol
    static func bytes(_ hex: String) -> [UInt8] {
        let value = Array(hex.filter { !$0.isWhitespace })
        return stride(from: 0, to: value.count, by: 2).map { UInt8(String(value[$0..<$0 + 2]), radix: 16)! }
    }
    static func rejects(_ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected rejection") } catch {}
    }
    @MainActor static func main() throws {
        let power = P.command(0x62, sequence: 0)
        precondition([UInt8](P.frame(power, total: 10, host: 0, reader: 0)) == bytes("5500000a0000006200000000000000000068aa"))
        precondition(P.command(0x6F, sequence: 7, data: bytes("ffb0000304")) == bytes("6f050000000007000000ffb0000304"))
        precondition(P.cardPresent(Data(bytes("5003"))) == true)
        precondition(P.cardPresent(Data(bytes("5002"))) == false)
        precondition(P.cardPresent(Data(bytes("5201"))) == nil)
        precondition(!P.validToken("5003"))
        precondition(!P.validToken("WMC-" + String(repeating: "A", count: 22) + "\n"))
        precondition(P.validToken("WMWC-" + String(repeating: "a", count: 48)))
        let capacity = try P.capacity(bytes("e1101200")); precondition(capacity == 144)
        rejects { _ = try P.capacity(bytes("e11012f0")) }

        // A 14-byte CCID response split into two independently wrapped GATT values.
        let reply = bytes("8004000000000700000001029000")
        var decoder = P.Decoder()
        let partial = try decoder.accept(P.frame(Array(reply.prefix(8)), total: 14, host: 1, reader: 0))
        precondition(partial == nil)
        let complete = try decoder.accept(P.frame(Array(reply.dropFirst(8)), total: 14, host: 1, reader: 1))
        precondition(complete?.sequence == 7 && complete?.data == [1, 2, 0x90, 0])
        var corrupt = [UInt8](P.frame(reply, total: 14, host: 1, reader: 2)); corrupt[8] ^= 1
        rejects { _ = try decoder.accept(Data(corrupt)) }
        _ = try decoder.accept(P.frame(Array(reply.prefix(8)), total: 14, host: 1, reader: 3))
        rejects { _ = try decoder.accept(P.frame(Array(reply.dropFirst(8)), total: 14, host: 1, reader: 5)) }
        rejects { _ = try decoder.accept(P.frame(reply, total: 13, host: 1, reader: 6)) }
        var wrongLength = reply; wrongLength[1] = 5
        rejects { _ = try decoder.accept(P.frame(wrongLength, total: 14, host: 1, reader: 7)) }
        let recovered = try decoder.accept(P.frame(reply, total: 14, host: 1, reader: 8))
        precondition(recovered?.data == [1, 2, 0x90, 0])

        let memory = bytes("0321d1011d5402656e574d432d41414141414141414141414141414141414141414141fe")
        let token = try P.credential(in: memory + [UInt8](repeating: 0, count: 144 - memory.count))
        precondition(token == "WMC-" + String(repeating: "A", count: 22))
        rejects { _ = try P.credential(in: [0x03, 0, 0xFE]) }
        rejects { _ = try P.credential(in: Array(memory.dropLast(3))) }
        rejects { _ = try P.credential(in: [0x02, 3, 0, 0, 0] + memory) }
        var chunked = memory; chunked[2] |= 0x20
        rejects { _ = try P.credential(in: chunked) }
        var noEnd = memory; noEnd[2] &= 0xBF
        rejects { _ = try P.credential(in: noEnd) }
        var urlRecord = memory; urlRecord[5] = 0x55
        rejects { _ = try P.credential(in: urlRecord) }
        rejects { _ = try P.credential(in: Array(memory.dropLast()) + memory) }
        print("PASS: ACS command/fragments/checksum/length/sequence recovery, card presence, NTAG capacity, and NDEF credential boundaries")
    }
}
