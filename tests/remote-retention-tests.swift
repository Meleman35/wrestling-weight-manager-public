import Foundation
@main struct RetentionTests {
    static func main() throws {
        let payload = Data(#"{"capturedAt":"2026-10-04T23:59:59Z","receivedAt":"2026-10-06T00:00:00Z"}"#.utf8)
        let expiry = try WrestlingManagerRemoteRetention.expiresAt(payload: payload)
        let formatter = ISO8601DateFormatter()
        precondition(formatter.string(from: expiry) == "2026-10-14T23:59:59Z")
        let fractional = Data(#"{"capturedAt":"2026-10-04T23:59:59.123Z"}"#.utf8)
        let precise = try WrestlingManagerRemoteRetention.expiresAt(payload: fractional)
        precondition(abs(precise.timeIntervalSince(expiry) - 0.123) < 0.0001)
        do { _ = try WrestlingManagerRemoteRetention.expiresAt(payload: Data("{}".utf8)); fatalError("Missing capture date accepted") }
        catch WrestlingManagerRemoteRetention.Failure.invalidCaptureDate {}
        print("Native ten-day retention passed: original capture, fractional date and invalid input.")
    }
}
