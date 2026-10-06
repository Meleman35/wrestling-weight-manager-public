import Foundation
import UIKit
import WebKit
import LocalAuthentication

// Recovery is separate from ordinary PIN changes. Never trust a web assertion
// that biometrics or account verification succeeded. Both checks happen here.
@MainActor
final class WrestlingManagerPINRecoveryBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private var operation: UUID?
    private var requestID: String?
    private var context: LAContext?
    private var task: Task<Void, Never>?
    private let endpoint = URL(string: "https://vfocpoyexnjsjpxhhyqr.supabase.co/auth/v1/user")!
    // Public client key; never a service-role credential.
    private let publicKey = "sb_publishable_aX7mx8Myn8sok3bhPPmphQ_fWN8o38P"

    func attach(to webView: WKWebView) { self.webView = webView }
    func detach() { cancel(); webView = nil }
    func cancel() {
        let id = requestID
        operation = nil; requestID = nil
        context?.invalidate(); context = nil
        task?.cancel(); task = nil
        if let id { reply(id, error: "PIN reset cancelled. Your existing PIN was kept.") }
    }
    private func reply(_ id: String, error: String? = nil) {
        guard let webView, WrestlingManagerAppOrigin.contains(webView.url) else { return }
        var value: [String: Any] = ["id": id, "success": error == nil]
        if let error { value["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.WMPINRecovery?.receive(\(json));", completionHandler: nil)
    }
    private func check(_ ticket: UUID, profile: String, generation: UUID, page: URL, started: TimeInterval) throws {
        guard operation == ticket, !Task.isCancelled,
              WrestlingManagerProfilePIN.active == profile,
              WrestlingManagerProfilePIN.selectionGeneration == generation,
              let webView, webView.url == page, WrestlingManagerAppOrigin.contains(webView.url),
              ProcessInfo.processInfo.systemUptime - started < 90 else {
            throw WrestlingManagerProfilePIN.fault("The account or screen changed. Reopen Security and retry.")
        }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "wmPINRecovery", message.frameInfo.isMainFrame,
              let webView, message.webView === webView,
              WrestlingManagerAppOrigin.contains(message.frameInfo.request.url),
              WrestlingManagerAppOrigin.contains(webView.url), let page = webView.url,
              let body = message.body as? [String: Any],
              let id = body["id"] as? String, UUID(uuidString: id) != nil,
              let command = body["command"] as? String else { return }
        if command == "cancel" { if requestID == id { cancel() }; return }
        guard command == "reset" else { return }
        guard operation == nil else { reply(id, error: "Finish the current PIN reset first."); return }
        guard let value = body["profile"] as? String,
              let profile = WrestlingManagerProfilePIN.validProfile(value),
              profile == WrestlingManagerProfilePIN.active,
              let pin = body["pin"] as? String, WrestlingManagerProfilePIN.validPIN(pin),
              let token = body["accessToken"] as? String,
              !token.isEmpty, token.utf8.count <= 16000,
              !token.contains("\r"), !token.contains("\n") else {
            reply(id, error: "Sign in to your profile and enter a new 4–8 digit PIN twice."); return
        }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel PIN Reset"
        ctx.localizedFallbackTitle = ""
        // Always demand a fresh biometric check, including after Face ID sign-in.
        ctx.touchIDAuthenticationAllowableReuseDuration = 0
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            reply(id, error: "Face ID or Touch ID is unavailable. Your existing PIN was kept."); return
        }
        let ticket = UUID(), generation = WrestlingManagerProfilePIN.selectionGeneration
        let started = ProcessInfo.processInfo.systemUptime
        operation = ticket; requestID = id; context = ctx
        task = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            defer {
                ctx.invalidate()
                if self.operation == ticket { self.operation = nil; self.requestID = nil; self.context = nil; self.task = nil }
            }
            do {
                let previousRecord = try WrestlingManagerProfilePIN.read(profile)
                let previousLegacy = try WrestlingManagerProfilePIN.legacy()
                var request = URLRequest(url: self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                request.setValue(self.publicKey, forHTTPHeaderField: "apikey")
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil; configuration.httpCookieStorage = nil
                let authSession = URLSession(configuration: configuration, delegate: WrestlingVideoNoRedirect(), delegateQueue: nil)
                defer { authSession.finishTasksAndInvalidate() }
                let (data, response) = try await authSession.data(for: request)
                try self.check(ticket, profile: profile, generation: generation, page: page, started: started)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      response.url == self.endpoint, data.count <= 256 * 1024,
                      let user = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let userID = user["id"] as? String,
                      WrestlingManagerProfilePIN.validProfile(userID) == profile,
                      user["is_anonymous"] as? Bool != true else {
                    throw WrestlingManagerProfilePIN.fault("Your account could not be verified. Sign in again before resetting your PIN.")
                }
                guard try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Replace the forgotten Wrestling Manager PIN for your signed-in profile") else {
                    throw WrestlingManagerProfilePIN.fault("Biometric verification did not finish. Your existing PIN was kept.")
                }
                try self.check(ticket, profile: profile, generation: generation, page: page, started: started)
                // Recheck the current web account and exact pending user action;
                // this is additional cancellation protection, not authentication.
                let argsData = try JSONSerialization.data(withJSONObject: [id, profile])
                guard let args = String(data: argsData, encoding: .utf8) else { throw CancellationError() }
                let current = try await webView.evaluateJavaScript("window.WMPINRecovery?.isCurrent(...\(args)) === true")
                try self.check(ticket, profile: profile, generation: generation, page: page, started: started)
                guard current as? Bool == true,
                      try WrestlingManagerProfilePIN.read(profile) == previousRecord,
                      try WrestlingManagerProfilePIN.legacy() == previousLegacy else {
                    throw WrestlingManagerProfilePIN.fault("The account, PIN or reset request changed. Reopen Security and retry.")
                }
                // No await between final checks and atomic Keychain replacement.
                // A failed write preserves the old record. Other profiles and the
                // legacy device PIN remain untouched.
                try WrestlingManagerProfilePIN.writeVerifiedPIN(profile, pin: pin)
                let prefix = "wm.profile-pin.\(profile)."
                UserDefaults.standard.removeObject(forKey: prefix + "tries")
                UserDefaults.standard.removeObject(forKey: prefix + "until")
                self.reply(id)
            } catch {
                if self.operation == ticket {
                    let ns = error as NSError
                    let reason: String
                    if ns.domain == LAError.errorDomain { reason = "Face ID or Touch ID was cancelled or unsuccessful. Your existing PIN was kept." }
                    else if ns.domain == NSURLErrorDomain { reason = "Connect to the internet to verify your account. Your existing PIN was kept." }
                    else { reason = error.localizedDescription }
                    self.reply(id, error: reason)
                }
            }
        }
    }

    static let script = #"""
(() => {
  const appURL = new URL(location.href);
  const customApp = appURL.origin === 'https://theteammanager.app' && ['', '/', '/index.html'].includes(appURL.pathname);
  const legacyApp = appURL.origin === 'https://meleman35.github.io' && (appURL.pathname === '/wrestling-weight-manager-public' || appURL.pathname.startsWith('/wrestling-weight-manager-public/'));
  if (appURL.username || appURL.password || !(customApp || legacyApp)) return;
  if (window.WMPINRecovery || !window.webkit?.messageHandlers?.wmPINRecovery) return;
  const $ = id => document.getElementById(id), api = window.WMProfilePIN;
  const save = $('saveSecurityPinBtn'), status = $('securityPinStatus'), sheet = $('securitySheet');
  if (!api || !save || !status || !sheet) return;
  let pending = null, starting = false;
  const button = document.createElement('button');
  button.id = 'resetForgottenProfilePinBtn'; button.type = 'button'; button.className = 'wide secondary';
  button.textContent = 'Forgot PIN? Reset with Face ID / Touch ID';
  save.parentElement.insertAdjacentElement('afterend', button);
  const help = document.createElement('p'); help.className = 'fine';
  help.textContent = 'Forgot the old PIN? Enter a new PIN and confirm it above, then reset with Face ID or Touch ID. Internet is required. Your recordings stay on this device.';
  button.insertAdjacentElement('afterend', help);
  const note = text => { status.textContent = text; };
  const tell = text => { note(text); if (typeof message === 'function') message(text, true); };
  const post = payload => window.webkit.messageHandlers.wmPINRecovery.postMessage(payload);
  const same = p => !!p && api.profile() === p.profile && typeof session !== 'undefined' && session?.user?.id === p.profile && !sheet.classList.contains('hidden');
  function finish(text) {
    if (pending) { clearTimeout(pending.timer); clearInterval(pending.watch); }
    pending = null; starting = false; button.disabled = false; save.disabled = false;
    note(text);
  }
  function cancel(text = 'PIN reset cancelled. Your existing PIN was kept.') {
    if (pending) { try { post({command:'cancel', id:pending.id}); } catch {} }
    finish(text);
  }
  window.WMPINRecovery = {
    isCurrent: (id, profile) => !!pending && pending.id === id && pending.profile === profile && same(pending),
    receive: result => {
      if (!pending || result.id !== pending.id) return;
      if (!same(pending)) { cancel('The account or screen changed. Reopen Security.'); return; }
      if (!result.success) { const error = result.error || 'PIN reset failed. Your existing PIN was kept.'; finish(error); tell(error); return; }
      for (const id of ['securityCurrentPin','securityPin','securityPinConfirm']) $(id).value = '';
      finish('Your new profile PIN is saved on this device.');
      window.WMProfilePINUI?.refresh();
      if (typeof message === 'function') message('Profile PIN reset and saved on this device.');
    }
  };
  button.onclick = async () => {
    if (pending || starting) return;
    const pin = $('securityPin').value, confirm = $('securityPinConfirm').value;
    if (!/^\d{4,8}$/.test(pin)) { tell('Enter a new 4–8 digit PIN above.'); return; }
    if (pin !== confirm) { tell('The new PIN entries do not match.'); return; }
    const profile = api.profile();
    if (!profile || !same({profile})) { tell('Sign in to your profile and reopen Security.'); return; }
    starting = true; button.disabled = true; save.disabled = true;
    try {
      await api.select();
      const auth = await client.auth.getSession();
      if (!same({profile}) || auth.error || auth.data.session?.user?.id !== profile || !auth.data.session?.access_token) throw Error('Sign in again before resetting your PIN.');
      const id = crypto.randomUUID();
      pending = {id, profile};
      pending.timer = setTimeout(() => cancel('PIN reset timed out. Reopen Security and check your PIN status.'), 90000);
      pending.watch = setInterval(() => { if (!same(pending)) cancel('The account or screen changed. Reopen Security.'); }, 250);
      note('Verifying your account, then requesting Face ID or Touch ID…');
      post({command:'reset', id, profile, pin, accessToken:auth.data.session.access_token});
    } catch (error) { cancel(error.message); tell(error.message); }
    finally { starting = false; if (!pending) { button.disabled = false; save.disabled = false; } }
  };
  window.addEventListener('pagehide', () => cancel());
})();
"""#
}
