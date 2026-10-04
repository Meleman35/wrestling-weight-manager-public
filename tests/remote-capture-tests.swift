import Foundation

@main struct RemoteCaptureTests {
    @MainActor static func main() throws {
        var clock = Date(timeIntervalSince1970: 1800000000)
        let start = clock
        let scope = WrestlingManagerRemoteCapture.Scope(accountID: UUID(), clubID: UUID(), generation: "personal-session",
            programID: "network", windowID: "week", opensAt: start.addingTimeInterval(-10), closesAt: start.addingTimeInterval(60))
        let jpeg = Data([0xff, 0xd8, 1, 0xff, 0xd9]) // Model-only fixture; photo adapter separately decodes real camera output.
        func fails(_ body: () throws -> Void) {
            do { try body(); fatalError("Expected rejection") } catch {}
        }
        let capture = try WrestlingManagerRemoteCapture(scope: scope, now: { clock })
        let old = try capture.scan(athleteID: "athlete-a", method: "nfc")
        fails { try capture.scaleReading(token: old, pounds: 125, observedAt: start, connected: true) }
        for offset in [0.1, 0.6, 1.1] {
            clock = start.addingTimeInterval(offset)
            try capture.scaleReading(token: old, pounds: 125, observedAt: clock, connected: true)
        }
        precondition(capture.settledWeight == 125)
        try capture.snapshot(token: old, normalizedJPEG: jpeg, capturedAt: clock, noticeAccepted: true)
        clock = start.addingTimeInterval(1.6)
        try capture.scaleReading(token: old, pounds: 125, observedAt: clock, connected: true)
        let frozen = try capture.freeze(token: old)
        let envelope = try JSONDecoder().decode(WrestlingManagerRemoteCapture.Envelope.self, from: frozen.payload)
        precondition(envelope.athleteId == "athlete-a" && envelope.weight == 125 && envelope.method == "nfc")
        precondition(envelope.clubId == scope.clubID.uuidString.lowercased())
        clock = start.addingTimeInterval(120)
        let retried = try capture.freeze(token: old)
        precondition(retried.payload == frozen.payload)
        fails { _ = try capture.scan(athleteID: "athlete-b", method: "qr") }
        capture.close()
        fails { _ = try capture.freeze(token: old) }

        clock = start
        let changed = try WrestlingManagerRemoteCapture(scope: scope, now: { clock })
        let first = try changed.scan(athleteID: "athlete-a", method: "qr")
        let second = try changed.scan(athleteID: "athlete-b", method: "nfc")
        clock = start.addingTimeInterval(0.1)
        fails { try changed.snapshot(token: first, normalizedJPEG: jpeg, capturedAt: clock, noticeAccepted: true) }
        for offset in [0.1, 0.6, 1.1] {
            clock = start.addingTimeInterval(offset)
            try changed.scaleReading(token: second, pounds: 130, observedAt: clock, connected: true)
        }
        fails { try changed.snapshot(token: second, normalizedJPEG: jpeg, capturedAt: clock, noticeAccepted: false) }
        try changed.snapshot(token: second, normalizedJPEG: jpeg, capturedAt: clock, noticeAccepted: true)
        clock = start.addingTimeInterval(1.6)
        try changed.scaleReading(token: second, pounds: 140, observedAt: clock, connected: true)
        precondition(changed.settledWeight == nil)
        fails { _ = try changed.freeze(token: second) }
        for offset in [2.1, 2.6] {
            clock = start.addingTimeInterval(offset)
            try changed.scaleReading(token: second, pounds: 140, observedAt: clock, connected: true)
        }
        precondition(changed.settledWeight == 140)
        try changed.snapshot(token: second, normalizedJPEG: jpeg, capturedAt: clock, noticeAccepted: true)
        changed.scaleDisconnected()
        fails { _ = try changed.freeze(token: second) }
        for offset in [3.1, 3.6, 4.1] {
            clock = start.addingTimeInterval(offset)
            try changed.scaleReading(token: second, pounds: 140, observedAt: clock, connected: true)
        }
        clock = start.addingTimeInterval(35)
        fails { try changed.snapshot(token: second, normalizedJPEG: jpeg, capturedAt: clock, noticeAccepted: true) }
        changed.close()
        fails { try changed.scaleReading(token: second, pounds: 140, observedAt: clock, connected: true) }
        print("Native capture checks passed: freshness, stability, camera token, movement, consent, disconnect, scope, retries and lock.")
    }
}
