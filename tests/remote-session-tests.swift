import Foundation

@main struct RemoteSessionTests {
    @MainActor static func main() throws {
        let start = Date(timeIntervalSince1970: 1800000000)
        var clock = start
        var gate = WrestlingManagerRemoteScaleClear()
        func observe(_ pounds: Double, _ offset: Double, connected: Bool = true) {
            clock = start.addingTimeInterval(offset)
            gate.observe(pounds: pounds, at: clock, now: clock, connected: connected)
        }
        gate.begin(after: start)
        observe(125, 0.1); observe(125, 0.7)
        precondition(!gate.isClear(at: clock), "Remaining on the scale cannot start another athlete")
        observe(0, 1); observe(0, 1)
        precondition(!gate.isClear(at: clock), "One response with multiple zeros is one observation")
        observe(0.2, 1.6)
        precondition(gate.isClear(at: clock))
        // A later record in the same notification must veto advancement.
        observe(125, 1.6); observe(0, 1.6)
        precondition(!gate.isClear(at: clock))
        observe(0, 2.2); observe(-0.2, 2.8)
        precondition(gate.isClear(at: clock))
        precondition(!gate.isClear(at: start.addingTimeInterval(4.31)), "Stale zeros cannot authorize another scan")
        observe(0, 4.5)
        precondition(!gate.isClear(at: clock), "A silence gap requires a new empty-scale run")
        observe(0, 5.1)
        precondition(gate.isClear(at: clock))
        observe(0, 5.7, connected: false)
        precondition(!gate.isClear(at: clock))
        observe(.nan, 6.3); observe(0, 6.9)
        precondition(!gate.isClear(at: clock))
        gate.begin(after: clock)
        observe(0, 6.9)
        precondition(!gate.isClear(at: clock), "Readings from before the next gate opens are invalid")

        clock = start
        let scope = WrestlingManagerRemoteCapture.Scope(accountID: UUID(), clubID: UUID(), generation: "session",
            programID: "program", windowID: "window", opensAt: start.addingTimeInterval(-1), closesAt: start.addingTimeInterval(120))
        let capture = try WrestlingManagerRemoteCapture(scope: scope, now: { clock })
        let jpeg = Data([0xff, 0xd8, 1, 0xff, 0xd9])
        var submissions = Set<UUID>()
        for attempt in 0..<3 {
            let base = Double(attempt) * 10
            clock = start.addingTimeInterval(base)
            let token = try capture.scan(athleteID: "athlete-\(attempt)", method: "qr")
            // Empty-scale drift must never trigger a picture of an empty platform.
            for offset in [0.1, 0.7, 1.3] {
                clock = start.addingTimeInterval(base + offset)
                try? capture.scaleReading(token: token, pounds: 0.6, observedAt: clock, connected: true)
            }
            precondition(capture.settledWeight == nil)
            var countdown = WrestlingManagerRemoteReadiness()
            var remaining: Int?
            for i in 0...7 {
                let offset = base + 2 + Double(i) * 0.6
                clock = start.addingTimeInterval(offset)
                try capture.scaleReading(token: token, pounds: 125 + Double(attempt), observedAt: clock, connected: true)
                remaining = countdown.remaining(ready: capture.settledWeight != nil, at: offset)
            }
            precondition(remaining == 0)
            try capture.snapshot(token: token, normalizedJPEG: jpeg, capturedAt: clock, noticeAccepted: true)
            let frozen = try capture.freeze(token: token)
            let envelope = try JSONDecoder().decode(WrestlingManagerRemoteCapture.Envelope.self, from: frozen.payload)
            precondition(envelope.athleteId == "athlete-\(attempt)" && envelope.weight == 125 + Double(attempt))
            precondition(submissions.insert(frozen.submissionID).inserted)
            gate.begin(after: clock)
            observe(125, base + 6.5)
            precondition(!gate.isClear(at: clock))
            observe(0, base + 7.1); observe(0, base + 7.7)
            precondition(gate.isClear(at: clock))
            try capture.discard()
            precondition(capture.captureToken == nil)
        }
        precondition(submissions.count == 3)
        print("Continuous session checks passed: three athlete bindings, distinct captures, empty-scale gating, batching, stale data and disconnect.")
    }
}
