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
    private var setupInProgress = false
    private var setupConfirmed = false
    private var setupReview: WrestlingManagerRemoteSetupReview?

    init(scope: WrestlingManagerRemoteCapture.Scope, outbox: WrestlingManagerRemoteOutbox? = nil,
         authorize: @escaping () async throws -> Void) throws {
        capture = try WrestlingManagerRemoteCapture(scope: scope)
        self.outbox = try outbox ?? WrestlingManagerRemoteOutbox(accountID: scope.accountID, clubID: scope.clubID)
        self.authorize = authorize
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.close() }
            }
    }
    /// Test framing before scanning. Test images stay in memory and never enter
    /// the evidence queue. Re-run after moving the camera, scale or device.
    func prepareCamera(from presenter: UIViewController,
                       completion: @escaping (Result<Void, Error>) -> Void) async {
        guard active, !setupInProgress, !photoInProgress, !saveInProgress,
              capture.captureToken == nil else { completion(.failure(Failure.closed)); return }
        setupConfirmed = false; setupInProgress = true
        do { try await authorize() } catch { setupInProgress = false; completion(.failure(error)); return }
        guard active else { setupInProgress = false; completion(.failure(Failure.closed)); return }
        photos.take(token: UUID(), from: presenter, setup: true) { [weak self, weak presenter] _, result in
            guard let self else { return }
            guard self.active, let presenter else { self.setupInProgress = false; completion(.failure(Failure.closed)); return }
            do {
                let (jpeg, _) = try result.get()
                let review = WrestlingManagerRemoteSetupReview(jpeg: jpeg) { [weak self, weak presenter] decision in
                    guard let self else { return }
                    self.setupReview = nil; self.setupInProgress = false
                    guard self.active else { completion(.failure(Failure.closed)); return }
                    switch decision {
                    case .confirmed: self.setupConfirmed = true; completion(.success(()))
                    case .cancelled: completion(.failure(WrestlingManagerRemotePhoto.Failure.cancelled))
                    case .retake:
                        guard let presenter else { completion(.failure(Failure.closed)); return }
                        Task { @MainActor [weak self] in await self?.prepareCamera(from: presenter, completion: completion) }
                    }
                }
                self.setupReview = review; presenter.present(review, animated: false)
            } catch { self.setupInProgress = false; completion(.failure(error)) }
        }
    }
    func invalidateCameraSetup() { setupConfirmed = false }
    /// Existing scanner/NFC adapter resolves credentials against the authorized roster first.
    func scan(athleteID: String, method: String) async throws -> UUID {
        guard active, setupConfirmed, !setupInProgress, !photoInProgress, !saveInProgress else { throw Failure.unauthorized }
        try await authorize()
        guard active, setupConfirmed, !setupInProgress, !photoInProgress, !saveInProgress else { throw Failure.closed }
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
        guard active, setupConfirmed, !setupInProgress, !photoInProgress, !saveInProgress, noticeAccepted else { completion(.failure(Failure.unauthorized)); return }
        do { try await authorize() } catch { completion(.failure(error)); return }
        guard active, setupConfirmed, !setupInProgress, !photoInProgress, !saveInProgress, let token = capture.captureToken, capture.settledWeight != nil else {
            completion(.failure(Failure.noReading)); return
        }
        photoInProgress = true
        photos.take(token: token, from: presenter, readyToCapture: { [weak self] in
            guard let self else { return false }
            return self.active && self.setupConfirmed && self.capture.captureToken == token && self.capture.settledWeight != nil
        }) { [weak self] photoToken, result in
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
        setupConfirmed = false; capture.close(); photos.cancel(); setupReview?.cancel(); setupReview = nil
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer); backgroundObserver = nil }
        Task { await outbox.lock() }
    }
    deinit { if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) } }
}
