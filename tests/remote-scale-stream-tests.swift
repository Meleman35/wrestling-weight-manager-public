import Foundation

@main struct RemoteScaleStreamTests {
    @MainActor static func main() throws {
        let start = Date(timeIntervalSince1970: 1800000000)
        var clock = start
        var parser = AmericanScaleStreamParser()
        let scope = WrestlingManagerRemoteCapture.Scope(accountID: UUID(), clubID: UUID(), generation: "stream-test",
            programID: "program", windowID: "window", opensAt: start.addingTimeInterval(-1), closesAt: start.addingTimeInterval(120))
        let capture = try WrestlingManagerRemoteCapture(scope: scope, now: { clock })
        var token = try capture.scan(athleteID: "adult-test", method: "qr")
        func reset() throws {
            parser.reset(); clock = start
            token = try capture.scan(athleteID: "adult-test", method: "qr")
        }
        func receive(_ bytes: String, at offset: Double) {
            clock = start.addingTimeInterval(offset)
            // The real client timestamps a notification once, then forwards
            // every parsed Weight record with that same receipt timestamp.
            for message in parser.append(Data(bytes.utf8)) {
                if case .weight(let pounds) = message {
                    try? capture.scaleReading(token: token, pounds: pounds, observedAt: clock, connected: true)
                }
            }
        }
        for offset in [0.1, 0.6] {
            receive("Weight=125#Weight=125#BatteryLevel=80#Weight=125#", at: offset)
            precondition(capture.settledWeight == nil, "A batch must not count as three receipt times")
        }
        receive("Weight=125#Weight=125#Weight=125#", at: 1.1)
        precondition(capture.settledWeight == 125, "Repeated records must not reset stable evidence")
        // Returning to the original weight within a batch cannot conceal movement.
        receive("Weight=125#Weight=130#Weight=125#", at: 1.6)
        precondition(capture.settledWeight == nil)
        for offset in [2.1, 2.6, 3.1] { receive("Weight=125#Weight=125#", at: offset) }
        precondition(capture.settledWeight == 125)
        // Invalid records in the middle of a batch discard prior readiness.
        receive("Weight=125#Weight=0#Weight=125#", at: 3.6)
        precondition(capture.settledWeight == nil)
        for offset in [4.1, 4.6] { receive("Weight=125#", at: offset) }
        precondition(capture.settledWeight == 125)
        // Battery messages and cached/replayed receipt times never extend freshness.
        receive("BatteryLevel=80#", at: 6.11)
        precondition(capture.settledWeight == nil)
        try? capture.scaleReading(token: token, pounds: 125, observedAt: start.addingTimeInterval(4.6), connected: true)
        precondition(capture.settledWeight == nil)
        try reset()
        // Fragmented transport yields no weight until the delimiter arrives.
        receive("Weight=12", at: 0.1)
        receive("5#Weight=125#", at: 0.6)
        receive("Weight=125#Weight=125#", at: 1.1)
        precondition(capture.settledWeight == nil)
        receive("Weight=125#", at: 1.6)
        precondition(capture.settledWeight == 125)
        try reset()
        // Small variation within the permitted total range can still settle.
        for offset in [0.1, 0.6, 1.1] { receive("Weight=125.1#Weight=125.2#Weight=125.1#", at: offset) }
        precondition(capture.settledWeight == 125.1)
        // Each record individually near the chosen value is insufficient when
        // the complete notification's range exceeds the stability tolerance.
        receive("Weight=125#Weight=125.3#Weight=125.1#", at: 1.6)
        precondition(capture.settledWeight == nil)
        try reset()
        // The final record in the packet that first becomes ready must still
        // be compared with the entire preceding run, not only its newest weight.
        receive("Weight=125#", at: 0.1)
        receive("Weight=125.1#", at: 0.6)
        receive("Weight=125.2#Weight=125.4#", at: 1.1)
        precondition(capture.settledWeight == nil)
        try reset()
        for offset in [0.1, 0.6, 1.1] { receive("Weight=124#Weight=126#Weight=125#", at: offset) }
        precondition(capture.settledWeight == nil)
        // Normal streaming stays ready through the entire automatic countdown.
        for i in 0...10 { receive("Weight=125#Weight=125#", at: 1.6 + Double(i) * 0.5) }
        precondition(capture.settledWeight == 125)
        let jpeg = Data([0xff, 0xd8, 1, 0xff, 0xd9])
        try capture.snapshot(token: token, normalizedJPEG: jpeg, capturedAt: clock, noticeAccepted: true)
        let result = try capture.freeze(token: token)
        let envelope = try JSONDecoder().decode(WrestlingManagerRemoteCapture.Envelope.self, from: result.payload)
        precondition(envelope.weight == 125)
        print("Bluetooth stream checks passed: batching, distinct receipts, movement, invalid weight, fragments, freshness and capture.")
    }
}
