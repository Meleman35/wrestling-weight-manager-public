import UIKit

/// One instance per authorized personal session + club. No web-supplied scope is trusted.
/// App integration supplies live authorization and routes actual BLE packet callbacks here.
@MainActor
final class WrestlingManagerRemoteCaptureHost {
    enum Failure: Error { case unauthorized, closed, noReading }
    private let capture: WrestlingManagerRemoteCapture
    private let photos = WrestlingManagerRemotePhoto()
    private let outbox: WrestlingManagerRemoteOutbox
    private let authorize: () async throws -> Void
    private var active = true
    private var backgroundObserver: NSObjectProtocol?
    private var photoInProgress = false
    private var saveInProgress = false

    init(scope: WrestlingManagerRemoteCapture.Scope, authorize: @escaping () async throws -> Void) throws {
        capture = try WrestlingManagerRemoteCapture(scope: scope)
        outbox = try WrestlingManagerRemoteOutbox(accountID: scope.accountID, clubID: scope.clubID)
        self.authorize = authorize
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.close() }
            }
    }
    /// Existing scanner/NFC adapter resolves credentials against the authorized roster first.
    func scan(athleteID: String, method: String) async throws -> UUID {
        guard active, !photoInProgress, !saveInProgress else { throw Failure.closed }
        try await authorize()
        guard active, !photoInProgress, !saveInProgress else { throw Failure.closed }
        return try capture.scan(athleteID: athleteID, method: method)
    }
    /// Called once per real incoming BLE weight packet, stamped at native receipt.
    func receiveScalePacket(pounds: Double, observedAt: Date) throws {
        guard active, let token = capture.captureToken else { throw Failure.closed }
        try capture.scaleReading(token: token, pounds: pounds, observedAt: observedAt, connected: true)
    }
    func scaleDisconnected() { capture.scaleDisconnected(); photos.cancel() }
    var settledWeight: Double? { capture.settledWeight }

    /// Completion means durably queued, never server accepted.
    func takeSnapshot(from presenter: UIViewController, noticeAccepted: Bool,
                      completion: @escaping (Result<UUID, Error>) -> Void) async {
        guard active, !photoInProgress, !saveInProgress, noticeAccepted else { completion(.failure(Failure.unauthorized)); return }
        do { try await authorize() } catch { completion(.failure(error)); return }
        guard active, !photoInProgress, !saveInProgress, let token = capture.captureToken, capture.settledWeight != nil else {
            completion(.failure(Failure.noReading)); return
        }
        photoInProgress = true
        photos.take(token: token, from: presenter) { [weak self] photoToken, result in
            guard let self else { return }
            self.photoInProgress = false
            guard self.active else { completion(.failure(Failure.closed)); return }
            do {
                let (jpeg, at) = try result.get()
                try self.capture.snapshot(token: photoToken, normalizedJPEG: jpeg, capturedAt: at, noticeAccepted: noticeAccepted)
                let frozen = try self.capture.freeze(token: photoToken)
                self.saveInProgress = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    defer { self.saveInProgress = false }
                    do {
                        try await self.authorize()
                        guard self.active, self.capture.captureToken == photoToken else { throw Failure.closed }
                        try await self.outbox.save(.init(submissionID: frozen.submissionID, accountID: frozen.accountID,
                            clubID: frozen.clubID, payload: frozen.payload, jpeg: frozen.jpeg, receipt: nil))
                        guard self.active, self.capture.captureToken == photoToken else { throw Failure.closed }
                        completion(.success(frozen.submissionID))
                    } catch { completion(.failure(error)) }
                }
            } catch { completion(.failure(error)) }
        }
    }
    /// Retry a failed local save with exactly the original envelope/photo bytes.
    func retrySave() async throws -> UUID {
        guard active, !photoInProgress, !saveInProgress, let token = capture.captureToken else { throw Failure.closed }
        let frozen = try capture.freeze(token: token)
        saveInProgress = true
        defer { saveInProgress = false }
        try await authorize()
        guard active, capture.captureToken == token else { throw Failure.closed }
        try await outbox.save(.init(submissionID: frozen.submissionID, accountID: frozen.accountID,
            clubID: frozen.clubID, payload: frozen.payload, jpeg: frozen.jpeg, receipt: nil))
        guard active, capture.captureToken == token else { throw Failure.closed }
        return frozen.submissionID
    }
    /// Call after durable save to advance, or explicitly discard an unsaved attempt.
    func discard() throws { guard active, !photoInProgress, !saveInProgress else { throw Failure.closed }; try capture.discard() }
    /// Lock/logout/account change/navigation must also call this, in addition to automatic background cancellation.
    func close() {
        guard active else { return }; active = false
        capture.close(); photos.cancel()
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer); backgroundObserver = nil }
        Task { await outbox.lock() }
    }
    deinit { if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) } }
}
