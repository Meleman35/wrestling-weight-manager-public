// v0.15.28: lock on actual background return, not camera/Face ID interruptions.
// v0.15.22: safely pass app links to the web page and retain undelivered links.
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UIKit
import WebKit

extension Notification.Name {
    static let wrestlingManagerAuthCallback = Notification.Name("WrestlingManagerAuthCallback")
}

/// Native security and password-recovery bridge for Wrestling Manager's WKWebView.
/// Register one retained instance as the `security` WKScriptMessageHandler.
final class WrestlingManagerSecurityBridge: NSObject, WKScriptMessageHandler {
    private enum Keys {
        static let appLockEnabled = "wm.security.appLockEnabled"
        static let keychainService = "app.wrestlingmanager.security"
        static let pinAccount = "app-lock-pin"
    }

    private var returnedFromBackground = false
    private weak var webView: WKWebView?
    private var authenticationContext: LAContext?
    private var pendingExternalURL: URL?
    private var webPageReady = false
    private var externalURLDeliveryInFlight = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(receiveAuthCallback(_:)),
            name: .wrestlingManagerAuthCallback,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground(_:)),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        webPageReady = false
    }

    func webPageDidFinishLoading() {
        webPageReady = true
        deliverPendingExternalURLIfPossible()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "security",
              let body = message.body as? [String: Any],
              let command = body["command"] as? String else { return }

        webView = message.webView ?? webView

        switch command {
        case "status":
            sendStatus()
            deliverPendingExternalURLIfPossible()
        case "configure":
            let requested = (body["appLockEnabled"] as? Bool) ?? false
            let available = deviceOwnerAuthenticationAvailable()
            let enabled = requested && available
            UserDefaults.standard.set(enabled, forKey: Keys.appLockEnabled)
            reply([
                "action": "configured",
                "appLockEnabled": enabled,
                "pinEnabled": hasPIN(),
                "biometricLabel": authenticationLabel(),
                "native": true,
                "deviceSecurityAvailable": available,
                "error": requested && !available ? "Set a device passcode before enabling app lock." : ""
            ])
        case "authenticate":
            authenticate(reason: (body["reason"] as? String) ?? "Unlock Wrestling Manager")
        case "setPin":
            setPIN((body["pin"] as? String) ?? "")
        case "verifyPin":
            verifyPIN((body["pin"] as? String) ?? "")
        case "removePin":
            removePIN()
        default:
            reply(["action": "error", "error": "Unknown security request."])
        }
    }

    private func sendStatus() {
        let available = deviceOwnerAuthenticationAvailable()
        var enabled = UserDefaults.standard.bool(forKey: Keys.appLockEnabled)
        if enabled && !available {
            enabled = false
            UserDefaults.standard.set(false, forKey: Keys.appLockEnabled)
        }
        reply([
            "action": "status",
            "native": true,
            "deviceSecurityAvailable": available,
            "appLockEnabled": enabled,
            "pinEnabled": hasPIN(),
            "biometricLabel": authenticationLabel()
        ])
    }

    private func authenticate(reason: String) {
        let context = LAContext()
        authenticationContext = context
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationContext = nil
            reply([
                "action": "authenticated",
                "success": false,
                "error": error?.localizedDescription ?? "Set a device passcode before enabling app lock."
            ])
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, authError in
            DispatchQueue.main.async {
                self?.authenticationContext = nil
                self?.reply([
                    "action": "authenticated",
                    "success": success,
                    "error": success ? "" : (authError?.localizedDescription ?? "Authentication was not completed.")
                ])
            }
        }
    }

    private func deviceOwnerAuthenticationAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    private func authenticationLabel() -> String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Device Passcode"
        }
        switch context.biometryType {
        case .faceID: return "Face ID or Passcode"
        case .touchID: return "Touch ID or Passcode"
        default: return "Device Security"
        }
    }

    private func setPIN(_ pin: String) {
        guard pin.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil else {
            reply(["action": "pinSet", "success": false, "error": "Use a 4–8 digit numeric PIN."])
            return
        }

        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 16, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            reply(["action": "pinSet", "success": false, "error": "Could not create secure PIN data."])
            return
        }

        let digest = Data(SHA256.hash(data: salt + Data(pin.utf8)))
        let success = savePINRecord(salt + digest)
        reply([
            "action": "pinSet",
            "success": success,
            "error": success ? "" : "The PIN could not be saved to Keychain."
        ])
    }

    private func verifyPIN(_ pin: String) {
        guard let record = loadPINRecord(), record.count == 48 else {
            reply(["action": "pinVerified", "success": false, "error": "No app PIN is set."])
            return
        }
        let salt = record.prefix(16)
        let storedDigest = record.suffix(32)
        let candidateDigest = Data(SHA256.hash(data: Data(salt) + Data(pin.utf8)))
        let success = constantTimeEqual(Data(storedDigest), candidateDigest)
        reply([
            "action": "pinVerified",
            "success": success,
            "error": success ? "" : "Incorrect app PIN."
        ])
    }

    private func removePIN() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.pinAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        let success = status == errSecSuccess || status == errSecItemNotFound
        reply([
            "action": "pinRemoved",
            "success": success,
            "error": success ? "" : "The PIN could not be removed from Keychain."
        ])
    }

    private func hasPIN() -> Bool {
        loadPINRecord() != nil
    }

    private func savePINRecord(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.pinAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func loadPINRecord() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Keys.keychainService,
            kSecAttrAccount as String: Keys.pinAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    @objc private func receiveAuthCallback(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        forwardAuthURL(url)
    }

    func forwardAuthURL(_ url: URL) {
        pendingExternalURL = url
        deliverPendingExternalURLIfPossible()
    }

    private func deliverPendingExternalURLIfPossible() {
        guard webPageReady,
              !externalURLDeliveryInFlight,
              let webView,
              let url = pendingExternalURL,
              // JSONSerialization rejects a bare String with its default options
              // and can raise an Objective-C exception that Swift try? cannot catch.
              let urlData = try? JSONEncoder().encode(url.absoluteString),
              let quotedURL = String(data: urlData, encoding: .utf8) else { return }
        let script = """
        (() => {
            if (typeof window.wrestlingManagerHandleAuthURL !== 'function') return false;
            window.wrestlingManagerHandleAuthURL(\(quotedURL));
            return true;
        })();
        """
        externalURLDeliveryInFlight = true
        DispatchQueue.main.async { [weak self] in
            webView.evaluateJavaScript(script) { result, error in
                guard let self else { return }
                self.externalURLDeliveryInFlight = false
                // A missing page handler is not a successful delivery. Keep the
                // URL for page-ready, status, or foreground to try again.
                if error == nil, (result as? Bool) == true,
                   self.pendingExternalURL == url {
                    self.pendingExternalURL = nil
                }
                // A newer link may have arrived while WebKit handled this one.
                if let pending = self.pendingExternalURL, pending != url {
                    self.deliverPendingExternalURLIfPossible()
                }
            }
        }
    }

    @objc private func appDidEnterBackground(_ notification: Notification) {
        returnedFromBackground = true
        evaluateJavaScript("window.wrestlingManagerAppDidEnterBackground?.();")
    }

    @objc private func appDidBecomeActive(_ notification: Notification) {
        // Camera permission, Face ID, and other system overlays can temporarily
        // deactivate the app. Only a real background transition requires unlock.
        if returnedFromBackground {
            returnedFromBackground = false
            // Repeat the background marker in case WebKit was suspended before
            // it could process the earlier callback. It does not sign out.
            evaluateJavaScript("window.wrestlingManagerAppDidEnterBackground?.(); window.wrestlingManagerAppDidBecomeActive?.();")
        }
        deliverPendingExternalURLIfPossible()
    }

    private func evaluateJavaScript(_ script: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    private func reply(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.wrestlingManagerSecurityResponse(\(json));")
        }
    }
}

