import UIKit

/// Retained by the app coordinator for one authorized program/window/club session.
/// This owns ONE queue shared between capture and delivery, not separate instances.
@MainActor
final class WrestlingManagerRemoteReportingSession {
    enum Failure: Error { case scopeChanged, closed }
    let capture: WrestlingManagerRemoteCaptureHost
    private let outbox: WrestlingManagerRemoteOutbox
    private let http: WrestlingManagerRemoteHTTP
    private var delivery: WrestlingManagerRemoteDelivery?
    private var active = true
    private var observer: NSObjectProtocol?

    init(scope: WrestlingManagerRemoteCapture.Scope, identity: WrestlingManagerRemoteHTTPSession,
         publishableKey: String,
         currentSession: @escaping @Sendable () async throws -> WrestlingManagerRemoteHTTPSession,
         authorizeActivation: @escaping @Sendable () async throws -> Void) throws {
        guard scope.accountID == identity.accountID, scope.generation == identity.generation else { throw Failure.scopeChanged }
        let queue = try WrestlingManagerRemoteOutbox(accountID: scope.accountID, clubID: scope.clubID)
        outbox = queue
        http = WrestlingManagerRemoteHTTP(identity: identity, publishableKey: publishableKey, currentSession: currentSession)
        capture = try WrestlingManagerRemoteCaptureHost(scope: scope, outbox: queue, authorize: {
            let current = try await currentSession()
            guard current.accountID == identity.accountID, current.sessionID == identity.sessionID,
                  current.generation == identity.generation else { throw Failure.scopeChanged }
            try await authorizeActivation()
        })
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.close() } }
    }
    private func worker() async throws -> WrestlingManagerRemoteDelivery {
        guard active else { throw Failure.closed }
        if let delivery { return delivery }
        let transport = await http.transport()
        guard active else { throw Failure.closed }
        // A second main-actor call may have installed the worker while awaiting HTTP.
        if let delivery { return delivery }
        let worker = WrestlingManagerRemoteDelivery(store: outbox, transport: transport)
        delivery = worker; return worker
    }
    /// Call when an unlocked reporting screen opens, including without connectivity.
    /// Enumeration removes expired protected files before returning pending IDs.
    func pendingCaptures() async throws -> [UUID] {
        guard active else { throw Failure.closed }
        let ids = try await outbox.pending()
        guard active else { throw Failure.closed }
        return ids
    }
    /// Called by retry UI/background sync while this personal session is unlocked.
    /// Return means receipt was saved, not merely photo upload completed.
    func deliver(_ submissionID: UUID) async throws -> Data {
        let worker = try await worker()
        let receipt = try await worker.deliver(submissionID)
        guard active else { throw Failure.closed }; return receipt
    }
    /// Host must call synchronously on lock/logout/club or account changes/navigation/deletion.
    func close() {
        guard active else { return }; active = false
        capture.close()
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        let delivery = delivery, http = http, outbox = outbox
        Task { await http.stop(); await delivery?.lock(); await outbox.lock() }
    }
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        let http = http, delivery = delivery, outbox = outbox
        Task { await http.stop(); await delivery?.lock(); await outbox.lock() }
    }
}
