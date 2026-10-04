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
    private var authentication: WrestlingManagerPurchaseAuthentication?
    private var activation = UUID()

    init(webView: WKWebView) { self.webView = webView }

    @discardableResult
    func configure(session: WrestlingManagerPurchaseSession, publishableKey: String,
                   productIDs: Set<String>, enabled: Bool = false,
                   currentSession: @escaping () -> WrestlingManagerPurchaseSession?,
                   refreshServerAccess: @escaping () async throws -> Void) -> Bool {
        stop()
        return install(session:session, publishableKey:publishableKey, productIDs:productIDs,
            enabled:enabled, currentSession:currentSession, refreshServerAccess:refreshServerAccess,
            revalidateSession:{})
    }

    @discardableResult
    func configureAuthenticated(authentication: WrestlingManagerPurchaseAuthentication,
                   publishableKey: String, productIDs: Set<String>, enabled: Bool = false,
                   refreshServerAccess: @escaping () async throws -> Void) async -> Bool {
        stop()
        guard enabled else { return false }
        let attempt = activation
        self.authentication = authentication
        do {
            let session = try await authentication.authenticate()
            guard attempt == activation else { return false }
            let installed = install(session:session, publishableKey:publishableKey,
                productIDs:productIDs, enabled:true, currentSession:{authentication.currentSession},
                refreshServerAccess:refreshServerAccess,
                revalidateSession:{_ = try await authentication.authenticate()})
            if !installed { stop() }
            return installed
        } catch {
            if attempt == activation { stop() }
            return false
        }
    }

    private func install(session: WrestlingManagerPurchaseSession, publishableKey: String,
                   productIDs: Set<String>, enabled: Bool,
                   currentSession: @escaping () -> WrestlingManagerPurchaseSession?,
                   refreshServerAccess: @escaping () async throws -> Void,
                   revalidateSession: @escaping () async throws -> Void) -> Bool {
        guard enabled, let webView, !publishableKey.isEmpty, !session.accessToken.isEmpty,
              !productIDs.isEmpty, productIDs.isSubset(of: WrestlingManagerStore.proposedProductIDs),
              let current = currentSession(), Self.matches(current, session) else { return false }
        let transport = WrestlingManagerPurchaseURLSession()
        let server = WrestlingManagerPurchaseHTTP(session: session, publishableKey: publishableKey,
            currentSession: currentSession, transport: transport, refreshServerAccess: refreshServerAccess,
            revalidateSession: revalidateSession)
        let store = WrestlingManagerStore(server: server, productIDs: productIDs)
        let bridge = WrestlingManagerPurchaseBridge(store: store, enabled: true,
            currentSession: { [weak self] in
                guard let self, self.registered, let current = currentSession() else { return false }
                return Self.matches(current, session)
            }, stopTransport: { server.stop() }, revalidateSession: revalidateSession)
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
        activation = UUID()
        authentication?.stop()
        authentication = nil
        if registered {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "wmPurchases", contentWorld: .page)
        }
        registered = false
        bridge?.stop()
        bridge = nil
    }

    func detach() { stop(); webView = nil }
}
