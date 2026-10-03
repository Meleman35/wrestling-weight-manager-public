import Foundation
import WebKit

// Native owner for one authenticated purchase session. The app's native auth
// provider must invalidate or replace its session synchronously on logout,
// account changes and device locking. No web message can enable purchases.
@MainActor
final class WrestlingManagerPurchaseHost {
    private weak var webView: WKWebView?
    private var bridge: WrestlingManagerPurchaseBridge?
    private var registered = false

    init(webView: WKWebView) { self.webView = webView }

    @discardableResult
    func configure(session: WrestlingManagerPurchaseSession, publishableKey: String,
                   productIDs: Set<String>, enabled: Bool = false,
                   currentSession: @escaping () -> WrestlingManagerPurchaseSession?,
                   refreshServerAccess: @escaping () async throws -> Void) -> Bool {
        stop()
        guard enabled, let webView, !publishableKey.isEmpty, !session.accessToken.isEmpty,
              !productIDs.isEmpty, productIDs.isSubset(of: WrestlingManagerStore.proposedProductIDs),
              let current = currentSession(), Self.matches(current, session) else { return false }
        let transport = WrestlingManagerPurchaseURLSession()
        let server = WrestlingManagerPurchaseHTTP(session: session, publishableKey: publishableKey,
            currentSession: currentSession, transport: transport, refreshServerAccess: refreshServerAccess)
        let store = WrestlingManagerStore(server: server, productIDs: productIDs)
        let bridge = WrestlingManagerPurchaseBridge(store: store, enabled: true,
            currentSession: { [weak self] in
                guard let self, self.registered, let current = currentSession() else { return false }
                return Self.matches(current, session)
            }, stopTransport: { server.stop() })
        bridge.attach(to: webView)
        self.bridge = bridge
        webView.configuration.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "wmPurchases")
        registered = true
        store.start()
        return true
    }

    private static func matches(_ current: WrestlingManagerPurchaseSession,
                                _ expected: WrestlingManagerPurchaseSession) -> Bool {
        current.accountID == expected.accountID && current.sessionID == expected.sessionID &&
        current.generation == expected.generation && !current.accessToken.isEmpty
    }

    func stop() {
        if registered {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "wmPurchases", contentWorld: .page)
        }
        registered = false
        bridge?.stop()
        bridge = nil
    }

    func detach() { stop(); webView = nil }
}
