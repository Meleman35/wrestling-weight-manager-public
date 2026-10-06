import Foundation

// NXP NTAG213/215/216 Rev. 3.2, §§8.5–8.7, 10.1; ACS §§5.5.3.5, 5.5.4.1.
// The observed Feiju 144-byte variant uses the same bounded Type 2 user area.
// See Verification/NFC-WRITER-REVISION-19.md for evidence and device-test limits.
// Never emits a command for UID, CC, lock, password or configuration pages.
enum WrestlingManagerNFCWritePlan {
    struct Failure: LocalizedError, Sendable {
        let message: String
        var errorDescription: String? { message }
    }
    struct Layout: Equatable, Sendable {
        let capacity: Int
        let lockPage: Int
    }
    private static func validateVersion(_ version: [UInt8]) throws {
        let nxp = version.count == 8 && Array(version.prefix(6)) == [0, 4, 4, 2, 1, 0] && version[7] == 3
        // Exact identification captured from Damon's card. Do not accept every
        // Feiju chip or infer support for larger/different variants from vendor.
        let feiju144 = version == [0x00, 0x53, 0x04, 0x02, 0x01, 0x00, 0x0F, 0x03]
        guard nxp || feiju144 else {
            // This is public chip-model metadata, never the card UID or athlete
            // credential. Keep unknown variants read-only until their memory
            // mapping has been verified instead of guessing from capacity.
            let code = version.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            throw Failure(message: "This chip variant is not enabled for programming yet. Card-type code: \(code.isEmpty ? "no reply" : code). The card was not changed. Send a screenshot of this code.")
        }
    }
    static func layout(version: [UInt8], header: [UInt8], protection: [UInt8]) throws -> Layout {
        try validateVersion(version)
        let layout: Layout
        switch version[6] {
        case 0x0F: layout = Layout(capacity: 144, lockPage: 0x28)
        case 0x11: layout = Layout(capacity: 496, lockPage: 0x82)
        case 0x13: layout = Layout(capacity: 872, lockPage: 0xE2)
        default: throw Failure(message: "This NFC card type is not supported for programming.")
        }
        guard header.count == 16, header[12] == 0xE1, header[13] == 0x10,
              Int(header[14]) * 8 == layout.capacity, header[15] == 0 else {
            throw Failure(message: "This card is unformatted, read-only, or has an unsupported memory layout. Use a writable NDEF NTAG card.")
        }
        // CC/block-lock bits may be set; no user page may be locked. Be
        // conservative about dynamic locking: do not alter any lock settings.
        guard header[10] & 0xF0 == 0, header[11] == 0, protection.count == 12,
              protection.prefix(3).allSatisfy({ $0 == 0 }), protection[7] == 0xFF,
              protection[4] & 0xC0 == 0 else {
            throw Failure(message: "This card is locked, password-protected, or uses memory mirroring. Use an unlocked card; no protection settings were changed.")
        }
        return layout
    }
    static func lockPage(version: [UInt8]) throws -> Int {
        try validateVersion(version)
        switch version[6] {
        case 0x0F: return 0x28
        case 0x11: return 0x82
        case 0x13: return 0xE2
        default: throw Failure(message: "This NFC card type is not supported for programming.")
        }
    }
    static func memory(token: String, capacity: Int, prefix: [UInt8] = []) throws -> [UInt8] {
        guard WrestlingManagerACRProtocol.validToken(token) else { throw Failure(message: "Open the athlete's current card and try again.") }
        let text = Array(token.utf8)
        let record: [UInt8] = [0xD1, 1, UInt8(text.count + 3), 0x54, 2, 0x65, 0x6E] + text
        let tlv: [UInt8] = prefix + [3, UInt8(record.count)] + record + [0xFE]
        guard tlv.count <= capacity else { throw Failure(message: "This card does not have enough space for the athlete credential.") }
        return tlv + Array(repeating: 0, count: capacity - tlv.count)
    }
    static func isBlank(_ memory: [UInt8]) -> Bool {
        // Accept an erased user area, empty NDEF TLV, or NXP's factory empty
        // record only. Anything else requires explicit replacement consent.
        if memory.allSatisfy({ $0 == 0 }) { return true }
        let bytes = Array(memory.drop(while: { $0 == 0 }))
        for prefix in ([[3, 0, 0xFE], [3, 3, 0xD0, 0, 0, 0xFE], [0xFE]] as [[UInt8]]) {
            if bytes.starts(with: prefix), bytes.dropFirst(prefix.count).allSatisfy({ $0 == 0 }) { return true }
        }
        return false
    }
    // Returns the existing NDEF tag offset so its control prefix stays intact.
    // NXP NTAG213 datasheet §8.5.6/Table 5 defines 01 03 A0 0C 34:
    // 12 dynamic lock bits at byte 160, outside the 144-byte user area.
    @discardableResult
    static func validateMapping(_ memory: [UInt8]) throws -> Int {
        var cursor = 0
        var ndefOffset: Int?
        var sawLock = false
        var sawContent = false
        func unsupported(_ start: Int) -> Failure {
            // Only the control descriptor is reported, never NDEF/credentials.
            let code = memory[start..<min(start + 5, memory.count)].map { String(format: "%02X", $0) }.joined(separator: " ")
            return Failure(message: "This memory-control entry is not supported yet. Layout code: \(code). The card was not changed. Send a screenshot of this code.")
        }
        func result() throws -> Int {
            if let ndefOffset { return ndefOffset }
            guard !sawLock else { throw Failure(message: "The card has lock-control data but no NDEF entry. The card was not changed.") }
            return 0
        }
        while cursor < memory.count {
            let start = cursor
            let type = memory[cursor]; cursor += 1
            if type == 0 { continue }
            if type == 0xFE { return try result() }
            if type == 1 || type == 2 {
                // Preserve the documented factory lock descriptor. A real
                // Memory Control TLV (02) or another lock map stays blocked.
                guard type == 1, memory.count == 144, !sawLock, !sawContent,
                      cursor + 4 <= memory.count,
                      Array(memory[cursor..<(cursor + 4)]) == [3, 0xA0, 0x0C, 0x34] else {
                    throw unsupported(start)
                }
                sawLock = true; cursor += 4
                continue
            }
            sawContent = true
            guard cursor < memory.count else { throw Failure(message: "The card has an incomplete data entry. The card was not changed.") }
            var count = Int(memory[cursor]); cursor += 1
            if count == 255 {
                guard cursor + 2 <= memory.count else { throw Failure(message: "The card has an incomplete data length. The card was not changed.") }
                count = Int(memory[cursor]) << 8 | Int(memory[cursor + 1]); cursor += 2
            }
            guard cursor + count <= memory.count else { throw Failure(message: "The card's data length exceeds its memory. The card was not changed.") }
            if type == 3 && ndefOffset == nil { ndefOffset = start }
            cursor += count
        }
        return try result()
    }
    static func pages(memory: [UInt8], ndefOffset: Int = 0) -> [(page: Int, data: [UInt8])] {
        // NFC Forum T2T §6.4.3: invalidate the actual NDEF length first, keep
        // every preceding control byte, write payload, then commit length last.
        precondition([144, 496, 872].contains(memory.count))
        precondition(ndefOffset >= 0 && ndefOffset + 1 < memory.count && memory[ndefOffset] == 3)
        let lengthIndex = ndefOffset + 1
        let commitOffset = (lengthIndex / 4) * 4
        let commit = Array(memory[commitOffset..<(commitOffset + 4)])
        var invalid = commit
        invalid[lengthIndex % 4] = 0
        var pages: [(page: Int, data: [UInt8])] = [(4 + commitOffset / 4, invalid)]
        for offset in stride(from: (ndefOffset / 4) * 4, to: memory.count, by: 4) {
            if offset == commitOffset { continue }
            pages.append((4 + offset / 4, Array(memory[offset..<(offset + 4)])))
        }
        pages.append((4 + commitOffset / 4, commit))
        return pages
    }
}
