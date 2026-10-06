// Offline Mat Mode shell 0.20.31; PDF sharing over scoring engine 0.20.23. iOS/iPadOS and Mac Catalyst.
import Foundation
import SwiftUI
import WebKit
import PDFKit
import UIKit
import CommonCrypto

private enum OfflineMatLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

@MainActor
struct WrestlingManagerOfflineMatView: View {
    let onExit: () -> Void
    @State private var loadState: OfflineMatLoadState = .loading
    @State private var loadID = UUID()
    @State private var returnRequest = 0
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            OfflineMatWebView(loadState: $loadState, returnRequest: returnRequest, onExit: onExit)
                .id(loadID)
                .opacity(loadState == .ready ? 1 : 0)
                .allowsHitTesting(loadState == .ready)
            if loadState != .ready {
                ScrollView {
                VStack(spacing: 18) {
                    if case .failed(let message) = loadState {
                        Image(systemName: "arrow.clockwise.circle").font(.largeTitle)
                        Text("Mat Mode needs to reopen").font(.title2.bold())
                        Text(message).multilineTextAlignment(.center)
                        Text("Keep the app installed while you retry.").font(.callout)
                        Button("Retry Mat Mode") { loadState = .loading; loadID = UUID() }
                            .accessibilityIdentifier("matRecoveryRetry")
                            .buttonStyle(.borderedProminent)
                        Button("Return to app") { returnRequest += 1 }
                            .accessibilityIdentifier("matRecoveryReturn")
                            .buttonStyle(.bordered)
                        Text("Use your profile PIN, or the original exit PIN for an older mat.").font(.footnote)
                    } else {
                        ProgressView()
                        Text("Opening Mat Mode…").font(.headline)
                    }
                }
                .padding(28).frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .contentShape(Rectangle())
                .zIndex(10)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .interactiveDismissDisabled()
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

@MainActor
private struct OfflineMatWebView: UIViewRepresentable {
    @Binding var loadState: OfflineMatLoadState
    let returnRequest: Int
    let onExit: () -> Void
    func makeCoordinator() -> Coordinator {
        Coordinator(returnRequest: returnRequest, onState: { loadState = $0 }, onExit: onExit)
    }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let coordinator = context.coordinator
        config.userContentController.add(coordinator, name: "wmNearby")
        config.userContentController.add(coordinator, name: "wmMatLifecycle")
        config.userContentController.add(coordinator.profilePINBridge, name: "wmProfilePin")
        config.userContentController.addUserScript(WKUserScript(source: Self.startupScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let restore = coordinator.savedValuesJSON()
        coordinator.profilePINBridge.offline = true
        if let profile = WrestlingManagerProfilePIN.active { coordinator.profilePINBridge.allowedProfiles.insert(profile) }
        if let bytes = restore.data(using: .utf8), let values = try? JSONDecoder().decode([String: String].self, from: bytes) {
            for key in ["wm-mat-session", "wm-mat-recovery"] {
                if let raw = values[key]?.data(using: .utf8), let saved = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
                   let owner = saved["pinProfile"] as? String, let profile = WrestlingManagerProfilePIN.validProfile(owner) { coordinator.profilePINBridge.allowedProfiles.insert(profile) }
            }
        }
        let profileJSON = (try? JSONEncoder().encode(WrestlingManagerProfilePIN.active)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let script = """
        window.wrestlingManagerOfflineNative = true;
        window.wrestlingManagerMatProfile = \(profileJSON);
        (() => {
          const allowed = new Set(['wm-mat-session','wm-mat-history','wm-mat-recovery','wm-nearby-v1','wm-nearby-pending-v1']);
          const saved = \(restore);
          for (const [key,value] of Object.entries(saved)) {
            if (allowed.has(key) && localStorage.getItem(key) === null) localStorage.setItem(key,value);
          }
          const set = Storage.prototype.setItem, remove = Storage.prototype.removeItem;
          let resetting = false;
          function backup(){
            if (resetting) return;
            const values = {}; for(const key of allowed){const value=localStorage.getItem(key);if(value!==null)values[key]=value;}
            window.webkit.messageHandlers.wmNearby.postMessage({command:'backup',values});
          }
          Storage.prototype.setItem = function(key,value){if(resetting&&this===localStorage&&allowed.has(String(key)))return;set.call(this,key,value);if(this===localStorage&&allowed.has(String(key)))backup();};
          Storage.prototype.removeItem = function(key){remove.call(this,key);if(this===localStorage&&allowed.has(String(key)))backup();};
          Object.defineProperty(window, 'wrestlingManagerClearMatTestData', {value: expected => {
            if (!expected || typeof expected !== 'object' || Array.isArray(expected) || Object.keys(expected).some(key => !allowed.has(key))) return false;
            for (const key of allowed) {
              if (localStorage.getItem(key) !== (Object.prototype.hasOwnProperty.call(expected,key) ? expected[key] : null)) return false;
            }
            resetting = true;
            for (const key of allowed) remove.call(localStorage,key);
            return [...allowed].every(key => localStorage.getItem(key) === null);
          }});
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: Self.testDataButtonScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.addUserScript(WKUserScript(source: WrestlingManagerKeyboard.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WrestlingManagerKeyboardWebView(frame: .zero, configuration: config)
        web.navigationDelegate = coordinator
        web.uiDelegate = coordinator
        web.isOpaque = true
        web.backgroundColor = UIColor(red: 238.0/255, green: 242.0/255, blue: 247.0/255, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.underPageBackgroundColor = web.backgroundColor ?? .systemBackground
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.scrollView.alwaysBounceHorizontal = false
        web.scrollView.showsHorizontalScrollIndicator = false
        coordinator.webView = web
        coordinator.armStartupTimeout()
        coordinator.transport.onEvent = { [weak coordinator] event in coordinator?.emit(event) }
        // The generated multiline literal contains line endings. Foundation's
        // strict base64 decoder rejects those bytes. Strip only whitespace so
        // invalid non-whitespace data still fails instead of being ignored.
        let encoded = WrestlingManagerOfflineMatAssets.base64.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let html = Data(base64Encoded: encoded), !html.isEmpty else {
            coordinator.fail("The bundled scorebook could not be decoded. Install the latest native update over this app. Your saved records are retained. (M02A)")
            return web
        }
        do {
            let folder = try coordinator.folder()
            let file = folder.appendingPathComponent("mat-mode.html")
            try html.write(to: file, options: .atomic)
            coordinator.pageURL = file
            coordinator.profilePINBridge.localURL = file
            guard web.loadFileURL(file, allowingReadAccessTo: folder) != nil else {
                coordinator.fail("The local scorebook did not start. Tap Retry Mat Mode. (M01)")
                return web
            }
        } catch {
            let detail = error as NSError
            NSLog("Mat Mode file preparation failed: %@ (%ld)", detail.domain, detail.code)
            coordinator.fail("The scorebook file could not be prepared. Retry, or share this code for help: M02B · \(detail.domain) · \(detail.code). Your saved records are retained.")
        }
        return web
    }
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isUserInteractionEnabled = loadState == .ready
        guard context.coordinator.lastReturnRequest != returnRequest else { return }
        context.coordinator.lastReturnRequest = returnRequest
        context.coordinator.requestRecoveryExit()
    }
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.alive = false
        coordinator.startupTimeout?.cancel()
        coordinator.transport.stop()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wmNearby")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wmMatLifecycle")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wmProfilePin")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private static let testDataButtonScript = #"""
(() => {
  function install() {
    const history = document.getElementById('historyPDF');
    if (!history || document.getElementById('clearMatTestData')) return;
    const button = document.createElement('button');
    button.id = 'clearMatTestData';
    button.type = 'button';
    button.textContent = 'Clear Mat Mode Test Data';
    button.style.cssText = 'display:block;width:100%;margin:16px 0;color:#a51d24;background:#fff;border:1px solid #a51d24;padding:12px;border-radius:10px';
    button.addEventListener('click', () => window.webkit.messageHandlers.wmNearby.postMessage({command:'clear_test_data'}));
    const back = document.getElementById('menu');
    (back || history).insertAdjacentElement('afterend', button);
  }
  new MutationObserver(install).observe(document.body, {childList:true,subtree:true});
  install();
})();
"""#

    private static let startupScript = #"""
/* Report actual scorebook readiness; a loaded document alone is not a ready app. */
(() => {
  const state = window.WMMatStartup = {ready:false, failed:false};
  const send = command => {
    try { window.webkit?.messageHandlers?.wmMatLifecycle?.postMessage({command}); } catch {}
  };
  const fail = () => {
    if (state.ready || state.failed) return;
    state.failed = true;
    send('startupFailed');
  };
  window.addEventListener('error', fail);
  window.addEventListener('unhandledrejection', fail);
  function check() {
    if (state.failed || state.ready) return;
    try {
      const raw = localStorage.getItem('wm-mat-session');
      if (raw !== null && JSON.parse(raw) !== null) {
        const saved = JSON.parse(raw);
        if (!saved || typeof saved !== 'object' || Array.isArray(saved)) { fail(); return; }
      }
    } catch { fail(); return; }
    const control = document.getElementById('pin') || document.getElementById('profilePinSetup') || document.getElementById('single') || document.getElementById('wcControls');
    if (window.MatHost && window.WMNearby && control && control.getClientRects().length) {
      requestAnimationFrame(() => {
        if (!state.failed) {
          try {
            const raw = localStorage.getItem('wm-mat-session');
            if (raw === null || raw === 'null') send('noSession');
          } catch { fail(); return; }
          state.ready = true; send('ready');
        }
      });
    } else {
      setTimeout(check, 50);
    }
  }
  document.addEventListener('DOMContentLoaded', check, {once:true});
})();
"""#

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pageURL: URL?
        let transport = WrestlingManagerNearbyTransport()
        let profilePINBridge = WrestlingManagerProfilePINBridge()
        let onExit: () -> Void
        let onState: (OfflineMatLoadState) -> Void
        var startupTimeout: Task<Void, Never>?
        var lastReturnRequest: Int
        var alive = true
        private var failed = false
        private var noSessionConfirmed = false
        private var exitPromptOpen = false
        private var resetPromptOpen = false
        private var resetting = false
        private let storageKeys = WrestlingManagerMatTestReset.keys
        init(returnRequest: Int, onState: @escaping (OfflineMatLoadState) -> Void, onExit: @escaping () -> Void) {
            lastReturnRequest = returnRequest; self.onState = onState; self.onExit = onExit
        }
        func armStartupTimeout() {
            startupTimeout?.cancel()
            startupTimeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
                self?.fail("The scorebook did not finish opening. Retry to open a fresh Mat Mode view. (M03)")
            }
        }
        func fail(_ message: String) {
            guard alive else { return }
            let wasFailed = failed
            failed = true; startupTimeout?.cancel()
            if !wasFailed { transport.stop() }
            // Do not mutate SwiftUI state inside makeUIView/updateUIView.
            Task { @MainActor [weak self] in
                guard let self, self.alive else { return }
                self.onState(.failed(message))
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            fail("The local scorebook could not load. Tap Retry Mat Mode. (M04)")
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail("The scorebook stopped loading. Tap Retry Mat Mode. (M05)")
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // Never loop-reload a scoring screen or clear its saved state.
            fail("The iPhone stopped the Mat Mode display. Retry to reopen the saved scorebook. (M06)")
        }
        func folder() throws -> URL {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = root.appendingPathComponent("OfflineMat", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        func savedValuesJSON() -> String {
            guard let dir = try? folder(), let bytes = try? Data(contentsOf: dir.appendingPathComponent("records.json")),
                  let values = try? JSONDecoder().decode([String: String].self, from: bytes),
                  let data = try? JSONSerialization.data(withJSONObject: values.filter { storageKeys.contains($0.key) }),
                  let text = String(data: data, encoding: .utf8) else { return "{}" }
            return text
        }
        private func save(_ values: [String: String]) throws {
            guard values.keys.allSatisfy({ storageKeys.contains($0) }) else { throw NSError(domain: "WrestlingManager.Offline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid offline request."]) }
            let bytes = try JSONEncoder().encode(values)
            guard bytes.count <= 24 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
            let file = try folder().appendingPathComponent("records.json")
            try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        private func trusted(_ url: URL?) -> Bool { url?.standardizedFileURL == pageURL?.standardizedFileURL && url?.isFileURL == true }
        func emit(_ event: [String: Any]) {
            guard let webView, trusted(webView.url), let bytes = try? JSONSerialization.data(withJSONObject: event),
                  let json = String(data: bytes, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.wrestlingManagerNearbyEvent?.(\(json));", completionHandler: nil)
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "wmMatLifecycle" {
                guard message.frameInfo.isMainFrame, trusted(message.frameInfo.request.url),
                      trusted(message.webView?.url), let body = message.body as? [String: Any],
                      let command = body["command"] as? String, alive else { return }
                if command == "noSession" { noSessionConfirmed = true }
                if command == "startupFailed" { fail("The saved scorebook could not finish opening. Your records are retained. (M07)") }
                if command == "ready", !failed { startupTimeout?.cancel(); onState(.ready) }
                return
            }
            guard alive, !resetting, message.name == "wmNearby", message.frameInfo.isMainFrame,
                  trusted(message.frameInfo.request.url), trusted(message.webView?.url),
                  let body = message.body as? [String: Any], let command = body["command"] as? String else { return }
            let id = body["id"] as? String ?? ""
            do {
                switch command {
                case "clear_test_data": requestClearTestData(); return
                case "backup", "save":
                    guard let values = body["values"] as? [String: String] else { throw CocoaError(.fileWriteUnknown) }
                    // Clear the no-PIN permission before attempting any session backup.
                    if let session = values["wm-mat-session"], session != "null" { noSessionConfirmed = false }
                    try save(values)
                case "start":
                    guard let role = body["role"] as? String, let code = body["code"] as? String else { throw NSError(domain: "WrestlingManager.Offline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid offline request."]) }
                    try transport.start(role: role, code: code, label: body["label"] as? String ?? "Mat", presenting: presenter())
                case "send":
                    guard let packet = body["packet"] as? [String: Any] else { throw NSError(domain: "WrestlingManager.Offline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid offline request."]) }
                    try transport.send(packet)
                case "stop": transport.stop()
                case "export", "export_pdf":
                    guard let presenter = presenter(), !(presenter is UIActivityViewController) else {
                        throw NSError(domain: "WrestlingManager.Offline", code: 31, userInfo: [NSLocalizedDescriptionKey: "Close the current share sheet and try again."])
                    }
                    let bytes: Data
                    let filename: String
                    if command == "export_pdf" {
                        guard let encoded = body["base64"] as? String, encoded.utf8.count <= 24 * 1024 * 1024,
                              let pdf = Data(base64Encoded: encoded), pdf.count <= 18 * 1024 * 1024,
                              pdf.starts(with: Data("%PDF-".utf8)), let document = PDFDocument(data: pdf), document.pageCount > 0 else {
                            throw NSError(domain: "WrestlingManager.Offline", code: 32, userInfo: [NSLocalizedDescriptionKey: "The PDF could not be prepared. Your saved bouts are unchanged."])
                        }
                        bytes = pdf
                        let requested = body["filename"] as? String ?? "Wrestling-Mat-Bouts"
                        let safe = requested.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "-" }.joined()
                        filename = String(safe.prefix(80).isEmpty ? "Wrestling-Mat-Bouts" : String(safe.prefix(80))) + ".pdf"
                    } else {
                        guard let text = body["text"] as? String, text.utf8.count < 24 * 1024 * 1024 else { throw CocoaError(.fileWriteUnknown) }
                        bytes = Data(text.utf8)
                        filename = "Wrestling-Mat-Bouts-Backup.json"
                    }
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Mat-Share-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let file = directory.appendingPathComponent(filename)
                    try bytes.write(to: file, options: .atomic)
                    let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                    sheet.popoverPresentationController?.sourceView = presenter.view
                    sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                    sheet.completionWithItemsHandler = { _, _, _, _ in
                        try? FileManager.default.removeItem(at: directory)
                    }
                    presenter.present(sheet, animated: true)
                default: return
                }
                if !id.isEmpty { emit(["reply": id, "result": true]) }
            } catch {
                if !id.isEmpty { emit(["reply": id, "error": error.localizedDescription]) }
                else { emit(["type": "error", "message": "Could not save the local backup. Export your bouts before continuing."]) }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard !resetting else { decisionHandler(.cancel); return }
            guard navigationAction.targetFrame?.isMainFrame != false, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if trusted(url) { decisionHandler(.allow); return }
            if (url.isFileURL && url.deletingLastPathComponent() == pageURL?.deletingLastPathComponent() && url.lastPathComponent == "index.html") || (pageURL == nil && url.scheme == "wm-mat-exit") {
                transport.stop(); onExit()
            }
            decisionHandler(.cancel)
        }
        func requestRecoveryExit() {
            guard alive, failed, !exitPromptOpen, !resetPromptOpen, !resetting else { return }
            if noSessionConfirmed { transport.stop(); onExit(); return }
            guard let dir = try? folder(), let bytes = try? Data(contentsOf: dir.appendingPathComponent("records.json")),
                  let values = try? JSONDecoder().decode([String: String].self, from: bytes),
                  let raw = values["wm-mat-session"], let data = raw.data(using: .utf8),
                  let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let presenter = presenter() else {
                fail("The saved exit PIN could not be verified. Retry Mat Mode; keep the app installed so its records are preserved. (M08)")
                return
            }
            let profile = (saved["pinProfile"] as? String).flatMap(WrestlingManagerProfilePIN.validProfile)
            let hash = saved["hash"] as? String ?? "", salt = saved["salt"] as? String ?? ""
            guard profile != nil || (hash.count == 64 && !salt.isEmpty && salt.utf8.count <= 256) else { fail("The saved exit lock could not be read. Keep the app installed and retry. (M08)"); return }
            let defaults = UserDefaults.standard
            let lockKey = "wm.matRecovery.lockedUntil", triesKey = "wm.matRecovery.attempts"
            let now = Date().timeIntervalSince1970 * 1000
            let savedLock = (saved["lockedUntil"] as? NSNumber)?.doubleValue ?? 0
            guard now >= max(defaults.double(forKey: lockKey), savedLock) else {
                fail("Wait 30 seconds before trying the exit PIN again."); return
            }
            exitPromptOpen = true
            let alert = UIAlertController(title: "Return to app", message: profile != nil ? "Enter the profile PIN for the account that started this mat. Saved bouts stay on this device." : "Enter the original exit PIN for this older mat. Saved bouts stay on this device.", preferredStyle: .alert)
            alert.addTextField { field in field.isSecureTextEntry = true; field.keyboardType = .numberPad; field.placeholder = "Exit PIN" }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.exitPromptOpen = false })
            alert.addAction(UIAlertAction(title: "Return", style: .default) { [weak self, weak alert] _ in
                guard let self, self.alive else { return }
                self.exitPromptOpen = false
                let pin = alert?.textFields?.first?.text ?? ""
                if let profile {
                    do { try WrestlingManagerProfilePIN.verify(profile, pin: pin) }
                    catch { self.fail(error.localizedDescription); return }
                    self.transport.stop(); self.onExit(); return
                }
                guard Self.matchesPIN(pin, salt: salt, expected: hash) else {
                    let previous = max(defaults.integer(forKey: triesKey), (saved["attempts"] as? Int) ?? 0)
                    let count = previous + 1
                    defaults.set(count >= 5 ? 0 : count, forKey: triesKey)
                    if count >= 5 { defaults.set(Date().timeIntervalSince1970 * 1000 + 30_000, forKey: lockKey) }
                    self.fail(count >= 5 ? "Wait 30 seconds before trying the exit PIN again." : "Incorrect exit PIN. Your saved mat has not changed.")
                    return
                }
                defaults.removeObject(forKey: triesKey); defaults.removeObject(forKey: lockKey)
                self.transport.stop(); self.onExit()
            })
            presenter.present(alert, animated: true)
        }
        private func requestClearTestData() {
            guard alive, !failed, !resetting, !resetPromptOpen, !exitPromptOpen,
                  let presenter = presenter(), !(presenter is UIAlertController) else { return }
            do {
                let dir = try folder()
                let reviewed = try WrestlingManagerMatTestReset.snapshot(folder: dir)
                guard let raw = reviewed.values["wm-mat-session"]?.data(using: .utf8),
                      let saved = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
                    throw WrestlingManagerDeletionReceipt.fail("Open a mat with an exit PIN before clearing its test data.")
                }
                let profile = (saved["pinProfile"] as? String).flatMap(WrestlingManagerProfilePIN.validProfile)
                let hash = saved["hash"] as? String ?? "", salt = saved["salt"] as? String ?? ""
                guard profile != nil || (hash.count == 64 && !salt.isEmpty && salt.utf8.count <= 256) else {
                    throw WrestlingManagerDeletionReceipt.fail("The saved exit PIN could not be verified. Nothing was cleared.")
                }
                resetPromptOpen = true
                let alert = UIAlertController(title: "Clear Mat Mode test data?", message: "Permanently clear ALL saved bouts, the unfinished mat, recovery data and nearby pairing on this device, then return to the app. Account profiles and exported copies stay unchanged.\n\nEnter this mat's exit PIN and type CLEAR to confirm.", preferredStyle: .alert)
                alert.addTextField { field in field.isSecureTextEntry = true; field.keyboardType = .numberPad; field.placeholder = profile != nil ? "Profile PIN" : "Exit PIN" }
                alert.addTextField { field in field.placeholder = "Type CLEAR"; field.autocapitalizationType = .allCharacters; field.autocorrectionType = .no; field.spellCheckingType = .no }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.resetPromptOpen = false })
                alert.addAction(UIAlertAction(title: "Clear test data", style: .destructive) { [weak self, weak alert] _ in
                    guard let self, self.alive else { return }
                    self.resetPromptOpen = false
                    do {
                        guard alert?.textFields?.last?.text == "CLEAR" else {
                            throw WrestlingManagerDeletionReceipt.fail("Type CLEAR exactly to confirm. Nothing was cleared.")
                        }
                        try Self.verifyResetPIN(alert?.textFields?.first?.text ?? "", saved: saved)
                        try WrestlingManagerMatTestReset.requireUnchanged(folder: dir, reviewed: reviewed)
                        self.clearTestData(folder: dir, reviewed: reviewed)
                    } catch { self.fail(error.localizedDescription) }
                })
                presenter.present(alert, animated: true)
            } catch { fail(error.localizedDescription) }
        }
        private static func verifyResetPIN(_ pin: String, saved: [String: Any]) throws {
            let defaults = UserDefaults.standard
            let lockKey = "wm.matRecovery.lockedUntil", triesKey = "wm.matRecovery.attempts"
            let savedLock = (saved["lockedUntil"] as? NSNumber)?.doubleValue ?? 0
            guard Date().timeIntervalSince1970 * 1000 >= max(defaults.double(forKey: lockKey), savedLock) else {
                throw WrestlingManagerDeletionReceipt.fail("Wait 30 seconds before trying the exit PIN again.")
            }
            if let owner = saved["pinProfile"] as? String {
                guard let profile = WrestlingManagerProfilePIN.validProfile(owner) else {
                    throw WrestlingManagerDeletionReceipt.fail("The saved profile PIN needs review. Nothing was cleared.")
                }
                try WrestlingManagerProfilePIN.verify(profile, pin: pin)
                return
            }
            guard matchesPIN(pin, salt: saved["salt"] as? String ?? "", expected: saved["hash"] as? String ?? "") else {
                let count = max(defaults.integer(forKey: triesKey), (saved["attempts"] as? Int) ?? 0) + 1
                defaults.set(count >= 5 ? 0 : count, forKey: triesKey)
                if count >= 5 { defaults.set(Date().timeIntervalSince1970 * 1000 + 30_000, forKey: lockKey) }
                throw WrestlingManagerDeletionReceipt.fail(count >= 5 ? "Wait 30 seconds before trying the exit PIN again." : "Incorrect exit PIN. Nothing was cleared.")
            }
            defaults.removeObject(forKey: triesKey); defaults.removeObject(forKey: lockKey)
        }
        private func clearTestData(folder: URL, reviewed: WrestlingManagerMatTestReset.Snapshot) {
            guard let webView, trusted(webView.url),
                  let bytes = try? JSONEncoder().encode(reviewed.values),
                  let json = String(data: bytes, encoding: .utf8) else { fail("Mat Mode could not be checked. Nothing was cleared."); return }
            // Refuse queued backups before touching browser storage. The injected
            // script also suppresses late timer/pagehide writes for these five keys.
            // Keep the disk backup until the browser proves its scoped clear.
            resetting = true
            webView.isUserInteractionEnabled = false
            transport.stop()
            webView.evaluateJavaScript("window.wrestlingManagerClearMatTestData(\(json))") { [weak self] result, error in
                guard let self, self.alive else { return }
                guard error == nil, result as? Bool == true else {
                    self.fail("Mat Mode clearing could not be confirmed. Tap Retry Mat Mode and clear the test data again. The saved backup has been retained.")
                    return
                }
                do {
                    try WrestlingManagerMatTestReset.clear(folder: folder, reviewed: reviewed)
                    // Dismissal destroys the old page before it can resume scoring.
                    self.noSessionConfirmed = true
                    self.alive = false
                    self.onExit()
                } catch {
                    self.fail("Mat Mode clearing could not be confirmed. Tap Retry Mat Mode before retrying account deletion.")
                }
            }
        }
        private static func matchesPIN(_ pin: String, salt: String, expected: String) -> Bool {
            guard (4...8).contains(pin.utf8.count), pin.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  expected.utf8.count == 64 else { return false }
            let saltBytes = Array(salt.utf8)
            var derived = [UInt8](repeating: 0, count: 32)
            let result = pin.withCString { password in
                saltBytes.withUnsafeBufferPointer { saltBuffer in
                    derived.withUnsafeMutableBufferPointer { output in
                        CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, pin.utf8.count,
                            saltBuffer.baseAddress, saltBuffer.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                            100_000, output.baseAddress, 32)
                    }
                }
            }
            guard result == kCCSuccess else { return false }
            let actual = Array(derived.map { String(format: "%02x", $0) }.joined().utf8)
            return zip(actual, expected.utf8).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
        }
        private func presenter() -> UIViewController? {
            var result = webView?.window?.rootViewController
            while let presented = result?.presentedViewController { result = presented }
            return result
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard trusted(frame.request.url), let presenter = presenter() else { completionHandler(false); return }
            let alert = UIAlertController(title: "Mat Mode", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in completionHandler(true) })
            presenter.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard trusted(frame.request.url), let presenter = presenter() else { completionHandler(nil); return }
            let alert = UIAlertController(title: "Mat Mode", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText; $0.keyboardType = .numberPad }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            presenter.present(alert, animated: true)
        }
    }
}
