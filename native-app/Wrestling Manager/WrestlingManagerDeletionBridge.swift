import Foundation
import UIKit
import WebKit

// Pilot integration. Native starts remain disabled. Release the companion web
// integration deliberately after an Apple SDK build/device check.
@MainActor
final class WrestlingManagerDeletionBridge: NSObject, WKScriptMessageHandler {
    typealias Request = WrestlingManagerDeletionReceipt.Request
    typealias Job = WrestlingManagerDeletionReceipt.Job
    private weak var webView: WKWebView?
    private let video: WrestlingManagerVideoPilot
    private let biometric: WrestlingManagerBiometricLoginBridge
    private let recovery: WrestlingManagerPINRecoveryBridge
    private var busy = false
    private var checkpoint = WrestlingManagerDeletionReceipt.Checkpoint.request
    private var generation = UUID()
    private let base = "https://vfocpoyexnjsjpxhhyqr.supabase.co"
    private let publicKey = "sb_publishable_aX7mx8Myn8sok3bhPPmphQ_fWN8o38P"
    init(video: WrestlingManagerVideoPilot, biometric: WrestlingManagerBiometricLoginBridge,
         recovery: WrestlingManagerPINRecoveryBridge) {
        self.video = video; self.biometric = biometric; self.recovery = recovery
    }
    func attach(to webView: WKWebView) { self.webView = webView }
    func pageChanged() { generation = UUID(); biometric.endCleanupAccess() }
    func detach() { pageChanged(); webView = nil }
    private func trusted() -> Bool { WrestlingManagerAppOrigin.contains(webView?.url) }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "wmAccountDeletion", message.frameInfo.isMainFrame,
              WrestlingManagerAppOrigin.contains(message.frameInfo.request.url), trusted(),
              let body = message.body as? [String: Any],
              let id = body["id"] as? String, UUID(uuidString: id) != nil,
              let command = body["command"] as? String,
              JSONSerialization.isValidJSONObject(body),
              let count = try? JSONSerialization.data(withJSONObject: body).count, count <= 32768 else { return }
        guard !busy else { reply(id, error: "A deletion status check is already running. Resume shortly."); return }
        busy = true
        checkpoint = .request
        let page = generation
        Task { [self] in
            defer { biometric.endCleanupAccess(); busy = false }
            do {
                let result: [String: Any]
                switch command {
                case "pending":
                    checkpoint = .journal
                    let jobs = try WrestlingManagerDeletionJournal.load().jobs.values.map { try dictionary($0.request) }
                    result = ["jobs": jobs]
                case "begin": result = try await begin(body, page: page)
                case "recover":
                    guard let requestID = body["requestId"] as? String else { throw fault("The deletion request is missing.") }
                    result = try await recover(requestID)
                case "acknowledge":
                    checkpoint = .acknowledge
                    guard let requestID = body["requestId"] as? String else { throw fault("The deletion request is missing.") }
                    var state = try WrestlingManagerDeletionJournal.load()
                    if let job = state.jobs[requestID] {
                        guard job.stage == .nativeCleaned else { throw fault("Device cleanup has not finished.") }
                        guard let serverID = job.serverJobID else { throw fault("The server receipt is missing.") }
                        state.completed[requestID] = WrestlingManagerDeletionReceipt.Completion(id: serverID, state: "completed", personal: job.request.personal, subjectHash: WrestlingManagerDeletionJournal.hash(job.request.actorId))
                        state.jobs.removeValue(forKey: requestID)
                        try WrestlingManagerDeletionJournal.save(state)
                    }
                    result = ["acknowledged": true]
                default: throw fault("This deletion command is unavailable.")
                }
                if page == generation { reply(id, value: result) }
            } catch {
                var code: String?
                if command == "begin", let job = body["job"] as? [String: Any], let requestID = job["requestId"] as? String,
                   let state = try? WrestlingManagerDeletionJournal.load(), state.jobs[requestID] == nil { code = "native_not_started" }
                var message = WrestlingManagerDeletionReceipt.diagnostic(error, checkpoint: checkpoint)
                if code == "native_not_started" {
                    if !message.contains("No deletion request was sent.") { message += " No deletion request was sent." }
                } else {
                    message += " Keep this request and use Resume deletion."
                }
                if page == generation { reply(id, error: message, code: code) }
            }
        }
    }
    private func fault(_ message: String) -> WrestlingManagerDeletionReceipt.Failure {
        WrestlingManagerDeletionReceipt.fail(message)
    }
    private func dictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] else { throw fault("Invalid saved request.") }
        return object
    }
    private func network(_ path: String, body: [String: Any]? = nil, token: String? = nil) async throws -> (Data, Int) {
        let url = URL(string: base + path)!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue(publicKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: WrestlingVideoNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.data(for: request)
        guard response.url == url, bytes.count <= 65536, let http = response as? HTTPURLResponse else {
            throw fault("The server response could not be verified.")
        }
        return (bytes, http.statusCode)
    }
    private func prepareLocal(_ request: Request) async throws -> [String] {
        guard request.personal else { return [] }
        checkpoint = .deviceFiles
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        checkpoint = .legacyFiles
        try WrestlingManagerDeletionLegacyGuard.check(support: support, temporary: FileManager.default.temporaryDirectory)
        checkpoint = .savedLogins
        try await biometric.requireKnownCleanupOwnership()
        checkpoint = .legacyFiles
        try WrestlingManagerDeletionLegacyGuard.check(support: support, temporary: FileManager.default.temporaryDirectory)
        checkpoint = .recordings
        return try video.withQuiescentAccountCleanup { root in
            try WrestlingManagerAccountVideoCleanup(root: root).reviewedIDs(accountID: request.actorId)
        }
    }
    private func requireCurrent(_ account: String, page: UUID) async throws {
        checkpoint = .account
        guard page == generation, trusted(), let webView else { throw fault("The screen changed. Resume this request.") }
        let current: Any? = try await webView.callAsyncJavaScript("return typeof session !== 'undefined' && session?.user?.id === account && !managedLogin;", arguments: ["account": account], in: nil, contentWorld: .page)
        guard current as? Bool == true, page == generation, trusted() else { throw fault("The signed-in account changed. Resume with the original account.") }
    }
    private func begin(_ body: [String: Any], page: UUID) async throws -> [String: Any] {
        guard let raw = body["job"], JSONSerialization.isValidJSONObject(raw),
              let request = try? JSONDecoder().decode(Request.self, from: JSONSerialization.data(withJSONObject: raw)),
              let token = body["accessToken"] as? String, !token.isEmpty, token.utf8.count <= 16000 else {
            throw fault("Sign in with the account you want to delete.")
        }
        _ = try request.validated()
        try await requireCurrent(request.actorId, page: page)
        checkpoint = .authentication
        let (userData, userStatus) = try await network("/auth/v1/user", token: token)
        guard userStatus == 200, let user = try JSONSerialization.jsonObject(with: userData) as? [String: Any],
              user["id"] as? String == request.actorId, let email = user["email"] as? String,
              page == generation, trusted() else { throw fault("Sign in with the account that started this request.") }
        checkpoint = .journal
        var state = try WrestlingManagerDeletionJournal.load()
        if let existing = state.jobs[request.requestId] {
            guard existing.request == request else { throw fault("Resume the original deletion selection.") }
            if existing.stage != .prepared { return try await recover(request.requestId) }
        } else {
            try WrestlingManagerDeletionJournal.requireUsable(request.actorId)
            let ids = try await prepareLocal(request)
            try await requireCurrent(request.actorId, page: page)
            checkpoint = .confirmation
            try await confirm(email: email, request: request, recordings: ids.count)
            guard page == generation, trusted() else { throw fault("The screen changed. No deletion request was sent.") }
            // Re-inventory after the user prompt. An expanded/changed file set must
            // be reviewed again, never silently added to the confirmed selection.
            guard try await prepareLocal(request) == ids else { throw fault("Saved recordings changed. Review deletion again.") }
            try await requireCurrent(request.actorId, page: page)
            biometric.cancel(); recovery.cancel()
            checkpoint = .saveRequest
            state = try WrestlingManagerDeletionJournal.load()
            try state.prepare(Job(request: request, recordingIDs: ids, stage: .prepared, loginEmailHash: WrestlingManagerDeletionJournal.hash(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())))
            try WrestlingManagerDeletionJournal.save(state)
        }
        // Persisted first. A timeout after server acceptance retains the immutable
        // request and capability in device-only Keychain for recovery after restart.
        try await requireCurrent(request.actorId, page: page)
        let payload: [String: Any] = ["action": "begin", "kind": request.kind, "teamIds": request.teamIds,
            "organizationIds": request.organizationIds, "confirmation": "delete", "requestId": request.requestId, "receipt": request.receipt]
        checkpoint = .submit
        let (data, status) = try await network("/functions/v1/scoped-deletion", body: payload, token: token)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw fault("Resume the saved deletion request.") }
        if status == 409 || status == 401 || status == 400 {
            // Only a definitive server rejection permits dropping a prepared
            // request. Lost responses and generic failures never discard it.
            let error = result["error"] as? String ?? ""
            if ["not_enabled", "organization_handoff_required", "team_handoff_required", "linked_teams_not_selected", "already_in_progress", "request_not_accepted", "sign_in_required", "invalid_request"].contains(error) {
                var rejected = try WrestlingManagerDeletionJournal.load()
                if rejected.jobs[request.requestId]?.stage == .prepared {
                    rejected.jobs.removeValue(forKey: request.requestId); try WrestlingManagerDeletionJournal.save(rejected)
                }
                return ["rejected": true, "error": error]
            }
        }
        guard status == 202, let serverID = result["id"] as? String, (try? WrestlingManagerDeletionReceipt.uuid(serverID)) != nil else {
            throw fault("The result is uncertain. Resume this same deletion request.")
        }
        checkpoint = .saveRequest
        var accepted = try WrestlingManagerDeletionJournal.load()
        guard var job = accepted.jobs[request.requestId], job.request == request else { throw fault("The saved request needs review.") }
        if let previous = job.serverJobID, previous != serverID { throw fault("The server request changed. Cleanup stopped.") }
        job.serverJobID = serverID; accepted.jobs[request.requestId] = job
        try WrestlingManagerDeletionJournal.save(accepted)
        return result
    }
    private func recover(_ requestID: String) async throws -> [String: Any] {
        let recoveryPage = generation
        _ = try WrestlingManagerDeletionReceipt.uuid(requestID)
        checkpoint = .journal
        let initial = try WrestlingManagerDeletionJournal.load()
        if let proof = initial.completed[requestID] {
            var result = try dictionary(proof); result["nativeComplete"] = true; return result
        }
        guard var job = initial.jobs[requestID] else {
            return ["error": "native_request_not_found"]
        }
        checkpoint = .recover
        let (data, status) = try await network("/functions/v1/scoped-deletion", body: ["action": "recover", "requestId": requestID, "receipt": job.request.receipt])
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw fault("The server response could not be checked.") }
        if status == 404, result["error"] as? String == "request_not_found", job.stage == .prepared {
            return ["error": "request_not_found"] // Retry needs the original signed-in account.
        }
        if status == 202, result["state"] as? String == "blocked", job.stage == .prepared {
            var state = try WrestlingManagerDeletionJournal.load(); state.jobs.removeValue(forKey: requestID)
            try WrestlingManagerDeletionJournal.save(state); return result
        }
        guard result["state"] as? String == "completed" else {
            guard status == 202, job.stage == .prepared else { throw fault("The server has not confirmed the saved deletion request.") }
            return result
        }
        let subject = WrestlingManagerDeletionJournal.hash(job.request.actorId)
        checkpoint = .verify
        let proof = try WrestlingManagerDeletionReceipt.verifyCompletion(data, status: status, job: job, expectedHash: subject)
        var state = try WrestlingManagerDeletionJournal.load()
        job.serverJobID = proof.id; job.stage = .serverCompleted
        state.jobs[requestID] = job
        if job.request.personal { state.departedSubjects.insert(subject) }
        try WrestlingManagerDeletionJournal.save(state)
        if job.request.personal {
            checkpoint = .legacyFiles
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try WrestlingManagerDeletionLegacyGuard.check(support: support, temporary: FileManager.default.temporaryDirectory)
            guard recoveryPage == generation, trusted() else { throw fault("The screen changed. Resume this deletion request.") }
            checkpoint = .savedLogins
            try await biometric.requireKnownCleanupOwnership()
            guard recoveryPage == generation, trusted() else { throw fault("The screen changed. Resume this deletion request.") }
            checkpoint = .legacyFiles
            try WrestlingManagerDeletionLegacyGuard.check(support: support, temporary: FileManager.default.temporaryDirectory)
            // No awaits between the strict inventory and destructive adapters.
            checkpoint = .cleanup
            let cleaned = try WrestlingManagerAccountCleanup.removeReviewedLocalItems(accountID: job.request.actorId,
                approvedRecordingIDs: Set(job.recordingIDs), video: video, biometric: biometric, recovery: recovery)
            guard cleaned.remainingAccountRecordings == 0, cleaned.unresolvedBiometricItems == 0 else {
                throw fault("The server account is deleted. Some device files or saved logins still need review; keep this request to finish cleanup.")
            }
        }
        checkpoint = .acknowledge
        state = try WrestlingManagerDeletionJournal.load()
        job.stage = .nativeCleaned; state.jobs[requestID] = job
        try WrestlingManagerDeletionJournal.save(state)
        var verified = result; verified["nativeComplete"] = true
        if let hint = job.loginEmailHash { verified["loginEmailHash"] = hint }
        return verified
    }
    private func confirm(email: String, request: Request, recordings: Int) async throws {
        guard let root = webView?.window?.rootViewController, root.presentedViewController == nil else {
            throw fault("Close the open native screen and try account deletion again.")
        }
        let detail = request.personal
            ? "Delete \(email)? After the server confirms deletion, this app will remove its saved sign-in, profile PIN and \(recordings) local recording(s). Copies exported to Photos or Files remain outside the app. Other people's accounts stay intact."
            : "Delete the selected \(request.teamIds.count) team(s) and \(request.organizationIds.count) organization(s)? Personal accounts and locally saved recordings remain."
        let accepted: Bool = await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: "Confirm account deletion", message: detail, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "Continue deletion", style: .destructive) { _ in continuation.resume(returning: true) })
            root.present(alert, animated: true)
        }
        guard accepted else { throw fault("Deletion cancelled. No deletion request was sent.") }
    }
    private func reply(_ id: String, value: [String: Any] = [:], error: String? = nil, code: String? = nil) {
        guard trusted() else { return }
        var result: [String: Any] = ["id": id, "ok": error == nil, "value": value]
        if let error { result["error"] = error }
        if let code { result["code"] = code }
        webView?.callAsyncJavaScript("window.wrestlingManagerDeletionResponse?.(result)", arguments: ["result": result], in: nil, in: .page, completionHandler: nil)
    }
}
