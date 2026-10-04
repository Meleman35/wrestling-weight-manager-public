// Private, device-only Video Pilot. Every media command requires a native-verified,
// short-lived grant from the fixed Wrestling Manager Supabase project.
import UIKit
import WebKit
@preconcurrency import AVFoundation

@MainActor
final class WrestlingManagerVideoPilot: NSObject, WKScriptMessageHandler {
    private struct Grant {
        let user: String, team: String, token: String, key: String
        let cloud: Bool
        let athletes: Set<String>
        let until: TimeInterval
    }
    private weak var webView: WKWebView?
    private var grant: Grant?
    private var epoch = 0
    private var authorizationRequest = 0
    private let uploader = WrestlingManagerVideoUpload()
    private let scoreRenderer = WrestlingManagerVideoScoreOverlay()
    private var store: WrestlingManagerVideoStore?
    private var capture: WrestlingManagerVideoCapture?
    private var preview: WrestlingManagerVideoPreview?
    private var previewHost: UIView?
    private var replay: WrestlingManagerVideoReplay?
    private var activeTake: [String: Any]?
    private var recordingActivity: UUID?
    private var previewMatch = ""
    private var opening = false, stopping = false, finishing = false, readingMedia = false
    private var lastToken = "", stopReason = ""
    private var timer: Timer?
    private var sessionObservers: [NSObjectProtocol] = []
    private var lastHeartbeat = ProcessInfo.processInfo.systemUptime
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var previousIdleTimerDisabled: Bool?
    private var previousWebAppearance: (opaque: Bool, background: UIColor?, scrollBackground: UIColor?)?
    var isCameraBusy: Bool { opening || capture != nil || activeTake != nil }

    // Internal integration point only: not a web command, not a deletion grant.
    // Refuse while cancellation/finalization can still write. The closure must stay
    // synchronous; reset invalidates queued bridge tasks and in-flight grants first.
    func withQuiescentAccountCleanup<T>(_ operation: (URL) throws -> T) throws -> T {
        guard !isCameraBusy, !stopping, !finishing, !readingMedia, !uploader.isBusy,
              replay == nil, !WrestlingManagerVideoActivity.isBusy else {
            throw MessageError("Close recording and replay and wait for video work to finish before account cleanup.")
        }
        let storage = try disk()
        reset()
        return try operation(storage.root)
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let owner = self else { return }
            Task { @MainActor in owner.monitor() }
        }
    }
    func detach() { reset(); timer?.invalidate(); timer = nil; webView = nil }
    func reset() {
        epoch += 1; authorizationRequest += 1; grant = nil; uploader.cancel(); scoreRenderer.cancel()
        interrupt("Recording interrupted by an account, team, or page change.")
        replay?.endPlayback(); replay?.navigationController?.dismiss(animated: false); replay = nil
    }
    func enteredBackground() {
        uploader.cancel(); scoreRenderer.cancel()
        if activeTake != nil, backgroundTask == .invalid {
            // Only finish the file; this does not authorize background capture.
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish private match recording") { [weak self] in
                guard let owner = self else { return }
                Task { @MainActor in owner.endBackgroundTask() }
            }
        }
        replay?.endPlayback(); replay?.navigationController?.dismiss(animated: false); replay = nil
        interrupt("Recording stopped when the app moved to the background.")
    }
    private func trusted(_ url: URL?) -> Bool {
        WrestlingManagerAppOrigin.contains(url)
    }
    private func access() throws -> Grant {
        guard let grant, ProcessInfo.processInfo.systemUptime < grant.until, trusted(webView?.url) else {
            throw MessageError("Video test access ended. Reconnect and reopen Match Book.")
        }
        try WrestlingManagerDeletionJournal.requireUsable(grant.user)
        return grant
    }
    private struct MessageError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        nonisolated var errorDescription: String? { message }
    }
    private func disk() throws -> WrestlingManagerVideoStore {
        if let store { return store }
        let created = try WrestlingManagerVideoStore(); store = created; return created
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "wmVideoPilot", message.frameInfo.isMainFrame,
              trusted(message.frameInfo.request.url), trusted(webView?.url),
              let body = message.body as? [String: Any],
              let command = body["command"] as? String else { return }
        let request = body["requestId"] as? String
        guard request == nil || (request!.count <= 80 && UUID(uuidString: request!) != nil),
              JSONSerialization.isValidJSONObject(body),
              let size = try? JSONSerialization.data(withJSONObject: body).count, size <= 192 * 1024 else { return }
        // Stop/reset remain available after the lease expires.
        if command == "reset" { reset(); reply(request, value: [:]); return }
        if command == "stop" { stop(); reply(request, value: ["status": activeTake == nil ? "idle" : "stopping"]); return }
        if command == "close" {
            if activeTake == nil { closeCamera() }
            reply(request, value: [:]); return
        }
        if command == "heartbeat" {
            lastHeartbeat = ProcessInfo.processInfo.systemUptime
            return
        }
        let capturedEpoch = epoch
        let activity = WrestlingManagerVideoActivity.begin()
        Task { [self] in
            defer { WrestlingManagerVideoActivity.end(activity) }
            do {
                guard epoch == capturedEpoch else { throw MessageError("The screen changed before this video action started.") }
                if command == "authorize" { reply(request, value: try await authorize(body)); return }
                let scope = try access()
                switch command {
                case "preview":
                    try await openCamera(body, scope: scope, expectedEpoch: capturedEpoch)
                    reply(request, value: ["status": "preview"])
                case "layout": layout(body)
                case "start":
                    try start(body, scope: scope)
                    reply(request, value: ["status": "starting"])
                case "snapshot":
                    let state = try validateState(body["state"], scope: scope)
                    if state["id"] as? String != previewMatch { interrupt("Match changed during capture."); return }
                    preview?.show(wrestlingVideoScoreText(state))
                    append(state, label: String(((body["label"] as? String) ?? "Match state updated").prefix(120)))
                case "display":
                    let state = try validateState(body["state"], scope: scope)
                    guard state["id"] as? String == previewMatch else { throw MessageError("Match changed. Reopen the camera.") }
                    preview?.show(wrestlingVideoScoreText(state))
                case "uploadNext":
                    guard scope.cloud, !isCameraBusy, !readingMedia, replay == nil, !uploader.isBusy,
                          UIApplication.shared.applicationState == .active else { reply(request); return }
                    let storage = try disk()
                    if let row = try storage.list(user: scope.user, team: scope.team).first(where: {
                        $0["boutId"] is String && ["ready", "partial"].contains(($0["status"] as? String) ?? "") && ($0["upload"] as? [String: Any])?["status"] as? String != "ready"
                    }), let id = row["id"] as? String {
                        uploader.enqueue(store: storage, id: id, user: scope.user, team: scope.team, token: scope.token, key: scope.key, allowed: { [weak self] in
                            guard let owner = self, let current = try? owner.access() else { return false }
                            return owner.epoch == capturedEpoch && current.user == scope.user && current.team == scope.team && current.cloud && !owner.isCameraBusy && UIApplication.shared.applicationState == .active
                        }, changed: { [weak self] in self?.emit("uploadChanged", value: [:]) })
                    }
                    reply(request)
                case "list": reply(request, value: ["takes": try disk().list(user: scope.user, team: scope.team)])
                case "recover", "play":
                    guard !isCameraBusy, !readingMedia, replay == nil, let id = body["id"] as? String else { throw MessageError("Close the camera and replay before opening a saved video.") }
                    readingMedia = true
                    defer { readingMedia = false }
                    let storage = try disk()
                    var row = try storage.read(id, user: scope.user, team: scope.team)
                    let wasReady = ["ready", "partial"].contains((row["status"] as? String) ?? "")
                    if command == "play", !wasReady { throw MessageError("Check recovery for this interrupted recording first.") }
                    let (duration, bytes) = try await storage.verify(id)
                    let current = try access()
                    guard epoch == capturedEpoch, current.user == scope.user, current.team == scope.team, !isCameraBusy, replay == nil else { return }
                    row["durationMs"] = duration; row["bytes"] = bytes
                    if !wasReady { row["status"] = "partial"; row["reason"] = "Recovered after an interruption. The ending may be missing." }
                    try storage.write(row)
                    if command == "play" { try showReplay(row, storage: storage) }
                    reply(request, value: ["take": storage.summary(row)])
                case "delete":
                    guard !isCameraBusy, !readingMedia, !uploader.isBusy, replay == nil, let id = body["id"] as? String else { throw MessageError("Close recording and replay and wait for upload before deleting a video.") }
                    let row = try disk().read(id, user: scope.user, team: scope.team)
                    if row["boutId"] is String {
                        guard (row["upload"] as? [String: Any])?["status"] as? String == "ready" else { throw MessageError("Wait for the verified upload before removing this device copy.") }
                        readingMedia = true
                        defer { readingMedia = false }
                        try await uploader.verifyReady(id: id, team: scope.team, token: scope.token, key: scope.key)
                        guard epoch == capturedEpoch, !isCameraBusy, !uploader.isBusy else { throw MessageError("Screen changed. The device copy was kept.") }
                    }
                    try disk().remove(id, user: scope.user, team: scope.team); reply(request, value: [:])
                default: throw MessageError("This video command is not supported by this app build.")
                }
            } catch {
                reply(request, error: error.localizedDescription)
                if request == nil, activeTake != nil { interrupt("Recording stopped because the score timeline could not be updated.") }
            }
        }
    }
    private func authorize(_ body: [String: Any]) async throws -> [String: Any] {
        guard let team = body["teamId"] as? String, UUID(uuidString: team) != nil,
              let user = body["userId"] as? String, UUID(uuidString: user) != nil,
              let token = body["accessToken"] as? String, !token.isEmpty, token.count <= 16000,
              let key = body["apiKey"] as? String, !key.isEmpty, key.count <= 16000 else { throw MessageError("Sign in again to check video test access.") }
        try WrestlingManagerDeletionJournal.requireUsable(user)
        if let grant, grant.user != user || grant.team != team { reset() }
        authorizationRequest += 1
        let requestNumber = authorizationRequest, requestedEpoch = epoch, started = ProcessInfo.processInfo.systemUptime
        let url = URL(string: "https://vfocpoyexnjsjpxhhyqr.supabase.co/rest/v1/rpc/video_pilot_context")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_team_id": team])
        // Keep credentials in memory for the bounded grant and foreground uploads; never write or log them.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        let authorizationSession = URLSession(configuration: configuration, delegate: WrestlingVideoNoRedirect(), delegateQueue: nil)
        defer { authorizationSession.finishTasksAndInvalidate() }
        let (data, response) = try await authorizationSession.data(for: request)
        guard epoch == requestedEpoch, authorizationRequest == requestNumber, trusted(webView?.url) else { throw MessageError("The screen changed while checking access.") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { reset(); return ["allowed": false] }
        guard status == 200, response.url == url, data.count <= 256 * 1024,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MessageError("Video test access could not be checked. Reconnect and try again.") }
        guard result["allowed"] as? Bool == true, result["user_id"] as? String == user, result["team_id"] as? String == team,
              let lease = result["lease_seconds"] as? Double, lease.isFinite, lease > 0,
              let athletes = result["athlete_ids"] as? [String] else { reset(); return ["allowed": false] }
        let remaining = max(0, min(7200, lease) - (ProcessInfo.processInfo.systemUptime - started))
        guard remaining > 0 else { reset(); return ["allowed": false] }
        try WrestlingManagerDeletionJournal.requireUsable(user)
        grant = Grant(user: user, team: team, token: token, key: key, cloud: result["cloud_upload"] as? Bool == true, athletes: Set(athletes), until: started + min(7200, lease))
        if let row = activeTake, let state = (row["events"] as? [[String: Any]])?.last?["state"] as? [String: Any] {
            do { _ = try validateState(state, scope: grant!) }
            catch { interrupt("An athlete is no longer on the approved team roster.") }
        }
        return ["allowed": true, "lease_seconds": remaining, "user_id": user, "team_id": team, "athlete_ids": athletes, "cloud_upload": result["cloud_upload"] ?? false, "camera_overlay": true]
    }
    private func validateState(_ value: Any?, scope: Grant) throws -> [String: Any] {
        guard let state = value as? [String: Any], let id = state["id"] as? String, !id.isEmpty, id.count <= 128,
              let ledger = state["ledger"] as? [[String: Any]], ledger.count <= 2000,
              let remaining = state["remainingMs"] as? Double, remaining.isFinite, remaining >= 0, remaining <= 24 * 3600 * 1000,
              state["running"] is Bool,
              let encoded = try? JSONSerialization.data(withJSONObject: state), encoded.count <= 128 * 1024 else { throw WrestlingManagerVideoStore.Failure.invalid }
        for award in ledger {
            if let points = award["points"] as? Double, !points.isFinite || abs(points) > 10000 { throw WrestlingManagerVideoStore.Failure.invalid }
        }
        let athletes = [state["red_id"], state["other_id"]].compactMap { $0 as? String }.filter { !$0.isEmpty }
        guard athletes.allSatisfy({ scope.athletes.contains($0) }), state["book_type"] as? String == "test" || !athletes.isEmpty else {
            throw MessageError("Select an athlete on the approved team roster, or use a Test scorebook.")
        }
        return state
    }
    private func openCamera(_ body: [String: Any], scope: Grant, expectedEpoch: Int) async throws {
        guard !isCameraBusy, !readingMedia, replay == nil, body["permissionConfirmed"] as? Bool == true,
              UIApplication.shared.applicationState == .active else { throw MessageError("Confirm event recording permission, then close other camera or replay windows.") }
        let state = try validateState(body["state"], scope: scope)
        guard state["status"] as? String != "complete" else { throw MessageError("Open an unfinished match to record.") }
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription"] {
            guard !((Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MessageError("Camera and microphone recording permissions are missing from this app build.")
            }
        }
        try disk().requireSpace()
        opening = true
        defer { opening = false }
        for media in [AVMediaType.video, .audio] {
            let status = AVCaptureDevice.authorizationStatus(for: media)
            let allowed: Bool
            if status == .authorized { allowed = true }
            else if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: media) }
            else { allowed = false }
            guard allowed else { throw MessageError("Allow Camera and Microphone for Wrestling Manager in iPhone Settings, then retry.") }
        }
        _ = try access()
        guard epoch == expectedEpoch, UIApplication.shared.applicationState == .active, let webView else { throw MessageError("The screen changed before the camera opened.") }
        let angle = WrestlingVideoOrientation.angle(webView.window?.windowScene?.interfaceOrientation ?? .portrait)
        let camera = WrestlingManagerVideoCapture(onStart: { [weak self] in self?.didStart() },
                                                  onFinish: { [weak self] good, interrupted in self?.didFinish(good: good, interrupted: interrupted) })
        capture = camera
        do {
            try await camera.open(rotation: angle)
            _ = try access()
            guard epoch == expectedEpoch, UIApplication.shared.applicationState == .active, capture === camera else { throw MessageError("The screen changed before the camera opened.") }
            previewMatch = (state["id"] as? String) ?? ""
            let host = UIView(frame: webView.bounds)
            host.autoresizingMask = [.flexibleWidth, .flexibleHeight]; host.clipsToBounds = true; host.isUserInteractionEnabled = false
            let view = WrestlingManagerVideoPreview(session: camera.session, rotation: angle)
            view.isHidden = true; view.show(wrestlingVideoScoreText(state)); host.addSubview(view)
            previousWebAppearance = (webView.isOpaque, webView.backgroundColor, webView.scrollView.backgroundColor)
            webView.isOpaque = false; webView.backgroundColor = .clear; webView.scrollView.backgroundColor = .clear
            // Camera behind the web content: the actual HTML score buttons remain visible and tappable.
            webView.insertSubview(host, belowSubview: webView.scrollView)
            NotificationCenter.default.post(name: Notification.Name("wmVideoCameraVisible"), object: nil, userInfo: ["visible": true])
            previewHost = host; preview = view; lastHeartbeat = ProcessInfo.processInfo.systemUptime
            for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
                sessionObservers.append(NotificationCenter.default.addObserver(forName: name, object: camera.session, queue: .main) { [weak self] _ in
                    guard let owner = self else { return }
                    Task { @MainActor in owner.interrupt("Camera or microphone capture was interrupted.") }
                })
            }
        } catch { camera.stop(); if capture === camera { capture = nil }; throw error }
    }
    private func layout(_ body: [String: Any]) {
        guard let webView, let preview else { return }
        if let text = body["text"] as? String { preview.show(text) }
        let overlay = body["overlay"] as? Bool == true
        preview.overlayControls(overlay)
        // Legacy web pages still use a bounded preview above the web surface.
        if let previewHost {
            if overlay { webView.insertSubview(previewHost, belowSubview: webView.scrollView) }
            else { webView.bringSubviewToFront(previewHost) }
        }
        preview.rotate(WrestlingVideoOrientation.angle(webView.window?.windowScene?.interfaceOrientation ?? .portrait))
        guard body["visible"] as? Bool == true, let x = body["x"] as? Double, let y = body["y"] as? Double,
              let width = body["width"] as? Double, let height = body["height"] as? Double,
              let viewport = body["viewportWidth"] as? Double,
              [x, y, width, height, viewport].allSatisfy({ $0.isFinite && abs($0) <= 100000 }),
              width > 0, height > 0, viewport > 0 else { preview.isHidden = true; return }
        let scale = webView.bounds.width / CGFloat(viewport)
        preview.frame = CGRect(x: x, y: y, width: width, height: height).applying(CGAffineTransform(scaleX: scale, y: scale))
        preview.isHidden = !preview.frame.intersects(webView.bounds)
    }
    private func start(_ body: [String: Any], scope: Grant) throws {
        guard let capture, !opening, activeTake == nil, !stopping, body["permissionConfirmed"] as? Bool == true,
              UIApplication.shared.applicationState == .active else { throw MessageError("Open the camera and confirm recording permission first.") }
        let state = try validateState(body["state"], scope: scope)
        guard state["id"] as? String == previewMatch, state["status"] as? String != "complete" else { throw MessageError("Open an unfinished match to record.") }
        let storage = try disk()
        var row = try storage.create(state: state, user: scope.user, team: scope.team)
        var saved = state; saved.removeValue(forKey: "token")
        row["scoreOverlay"] = ["status": "pending", "renderer": 1]
        row["events"] = [["seq": 0, "atMs": 0, "label": "Recording started", "state": saved]]
        try storage.write(row)
        activeTake = row; lastToken = (state["token"] as? String) ?? ""; stopReason = ""; stopping = false; finishing = false
        recordingActivity = WrestlingManagerVideoActivity.begin()
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        let orientation = webView?.window?.windowScene?.interfaceOrientation ?? .portrait
        WrestlingVideoOrientation.recordingStarted(orientation, root: webView?.window?.rootViewController)
        capture.record(to: try storage.movie(row["id"] as! String), rotation: WrestlingVideoOrientation.angle(orientation))
    }
    private func didStart() {
        guard activeTake != nil else { return }
        if !stopping { emit("recording", value: ["status": "recording"]) }
    }
    private func append(_ state: [String: Any], label: String) {
        guard activeTake != nil, !stopping, let capture else { return }
        let token = (state["token"] as? String) ?? ""
        guard token != lastToken else { return }; lastToken = token
        let id = activeTake?["id"] as? String
        capture.timestamp { [weak self] ms in
            guard let self, var row = self.activeTake, row["id"] as? String == id else { return }
            var events = (row["events"] as? [[String: Any]]) ?? []
            var saved = state; saved.removeValue(forKey: "token")
            let when = max(ms, (events.last?["atMs"] as? Double) ?? 0)
            events.append(["seq": events.count, "atMs": when, "label": label, "state": saved])
            row["events"] = events; row["durationMs"] = when
            do { try self.disk().write(row); self.activeTake = row }
            catch { self.interrupt("The score history could not be saved. Video files were kept.") }
        }
    }
    private func stop() {
        guard activeTake != nil else { closeCamera(); return }
        stopping = true; preview?.isHidden = true; capture?.stop()
    }
    private func interrupt(_ reason: String) {
        if activeTake != nil {
            if stopReason.isEmpty { stopReason = reason }
            stop(); emit("stopping", value: ["status": "stopping", "reason": reason])
        } else {
            if opening { epoch += 1 }
            closeCamera(); emit("closed", value: ["reason": reason])
        }
    }
    private func didFinish(good: Bool, interrupted: Bool) {
        guard activeTake != nil, !finishing else { return }
        finishing = true; stopping = true
        let finalizationEpoch = epoch
        // The capture callback has stopped its serial session; rendering is not capture.
        capture = nil
        if interrupted, stopReason.isEmpty { stopReason = "A capture limit or interruption ended this recording." }
        Task {
            defer {
                if let recordingActivity { WrestlingManagerVideoActivity.end(recordingActivity); self.recordingActivity = nil }
            }
            guard let id = activeTake?["id"] as? String else { return }
            var verified: (Double, Int64)?
            do { verified = try await disk().verify(id) } catch { /* Keep every original file. */ }
            guard var row = activeTake else { return }
            if let (duration, bytes) = verified {
                row["durationMs"] = duration; row["bytes"] = bytes
                row["status"] = good && stopReason.isEmpty ? "ready" : "partial"
                row["reason"] = stopReason.isEmpty && !good ? "Capture ended with an error. Playable footage was kept." : stopReason
            } else { row["status"] = "failed"; row["reason"] = "Playback could not be verified. Original files were kept for recovery." }
            do {
                // Commit a recoverable raw recording BEFORE attempting the derivative.
                let storage = try disk()
                try storage.write(row)
                if verified != nil, epoch == finalizationEpoch, UIApplication.shared.applicationState == .active,
                   let current = try? access(), row["userId"] as? String == current.user, row["teamId"] as? String == current.team {
                    emit("stopping", value: ["status": "stopping", "reason": "Original saved. Preparing a permanent score overlay…"])
                    do { row = try await scoreRenderer.prepare(row: row, store: storage) }
                    catch {
                        row["scoreOverlay"] = ["status": "pending", "renderer": 1, "error": error.localizedDescription]
                        try storage.write(row)
                    }
                }
                emit("saved", value: ["take": storage.summary(row)])
            } catch {
                emit("failed", value: ["reason": "The final save could not be confirmed. Reopen Match Book and check recovery; original files were kept."])
            }
            activeTake = nil; stopping = false; finishing = false
            if let previousIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled; self.previousIdleTimerDisabled = nil }
            closeCamera(); endBackgroundTask()
        }
    }
    private func closeCamera() {
        guard activeTake == nil else { return }
        capture?.stop(); capture = nil; previewMatch = ""
        previewHost?.removeFromSuperview(); previewHost = nil; preview = nil
        if let webView, let previousWebAppearance {
            webView.isOpaque = previousWebAppearance.opaque
            webView.backgroundColor = previousWebAppearance.background
            webView.scrollView.backgroundColor = previousWebAppearance.scrollBackground
        }
        previousWebAppearance = nil
        WrestlingVideoOrientation.unlock(root: webView?.window?.rootViewController)
        NotificationCenter.default.post(name: Notification.Name("wmVideoCameraVisible"), object: nil, userInfo: ["visible": false])
        sessionObservers.forEach { NotificationCenter.default.removeObserver($0) }; sessionObservers.removeAll()
    }
    private func endBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    private func monitor() {
        if grant != nil, (try? access()) == nil { reset(); emit("revoked", value: [:]); return }
        if capture != nil, ProcessInfo.processInfo.systemUptime - lastHeartbeat > 5 {
            interrupt("The scoring screen stopped responding. Recording was stopped.")
        }
        if capture != nil, ProcessInfo.processInfo.thermalState == .critical { interrupt("The device became too hot to continue recording.") }
    }
    private func showReplay(_ row: [String: Any], storage: WrestlingManagerVideoStore) throws {
        guard let root = webView?.window?.rootViewController, row["id"] is String else { throw MessageError("The replay window is not ready.") }
        var presenter = root
        while let next = presenter.presentedViewController { presenter = next }
        guard !presenter.isBeingDismissed, !presenter.isBeingPresented else { throw MessageError("Close the current dialog and try replay again.") }
        let controller = WrestlingManagerVideoReplay(row: row, store: storage)
        controller.onClose = { [weak self] in self?.replay = nil }
        replay = controller
        WrestlingVideoOrientation.unlock(root: root)
        let navigation = WrestlingVideoNavigationController(rootViewController: controller); navigation.modalPresentationStyle = .fullScreen
        presenter.present(navigation, animated: true)
    }
    private func reply(_ request: String?, value: [String: Any] = [:], error: String? = nil) {
        guard let request else { return }
        var message: [String: Any] = ["requestId": request, "ok": error == nil, "value": value]
        if let error { message["error"] = error }
        send(message)
    }
    private func emit(_ event: String, value: [String: Any]) {
        var message: [String: Any] = ["event": event, "value": value]
        if let row = activeTake { message["scope"] = "\((row["userId"] as? String) ?? ""):\((row["teamId"] as? String) ?? "")" }
        send(message)
    }
    private func send(_ message: [String: Any]) {
        guard trusted(webView?.url) else { return }
        webView?.callAsyncJavaScript("window.wrestlingManagerVideoPilotMessage?.(message)", arguments: ["message": message], in: nil, in: .page, completionHandler: nil)
    }
}

// Never forward the authorization header through an HTTP redirect.
final class WrestlingVideoNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
