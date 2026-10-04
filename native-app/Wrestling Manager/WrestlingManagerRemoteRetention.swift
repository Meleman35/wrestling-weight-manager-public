import Foundation

enum WrestlingManagerRemoteRetention {
    nonisolated static let duration: TimeInterval = 10 * 24 * 60 * 60
    nonisolated static func expiresAt(payload: Data) throws -> Date {
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        guard let text = object?["capturedAt"] as? String else { throw Failure.invalidCaptureDate }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var captured = formatter.date(from: text)
        if captured == nil {
            formatter.formatOptions = [.withInternetDateTime]
            captured = formatter.date(from: text)
        }
        guard let captured else { throw Failure.invalidCaptureDate }
        return captured.addingTimeInterval(duration)
    }
    enum Failure: Error { case invalidCaptureDate }
}
