import Foundation
import WebKit

@MainActor
enum WrestlingManagerPurchasePageSession {
    private static func trusted(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.host == "theteammanager.app",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return ["", "/", "/index.html"].contains(url.path)
    }

    // Native pull only: no web message supplies credentials or enables billing.
    // Auth server verification happens afterward in PurchaseAuthentication.
    static func read(from webView: WKWebView) async throws -> WrestlingManagerPurchaseAuthentication.Snapshot? {
        guard trusted(webView.url) else { return nil }
        let page = webView.url
        let raw = try await webView.callAsyncJavaScript("""
        if (typeof session === 'undefined' || !session?.user?.id || !session?.access_token ||
            typeof managedLogin === 'undefined' || managedLogin ||
            document.body.classList.contains('kiosk-locked') || document.body.classList.contains('app-locked') ||
            (document.getElementById('appLockOverlay') && !document.getElementById('appLockOverlay').classList.contains('hidden')) ||
            (typeof teamProfileChoice !== 'undefined' && teamProfileChoice) ||
            (typeof teamProfileSelecting !== 'undefined' && teamProfileSelecting) ||
            (typeof teamLoginSigningOut !== 'undefined' && teamLoginSigningOut)) return null;
        return {accountID:session.user.id, accessToken:session.access_token};
        """, arguments: [:], in: nil, contentWorld: .page)
        guard webView.url == page, trusted(webView.url), let value = raw as? [String: Any],
              Set(value.keys) == ["accountID","accessToken"],
              let id = value["accountID"] as? String, let accountID = UUID(uuidString:id),
              let token = value["accessToken"] as? String, !token.isEmpty, token.utf8.count <= 16000 else { return nil }
        return .init(accountID:accountID,accessToken:token,personalAccount:true,unlocked:true)
    }
}
