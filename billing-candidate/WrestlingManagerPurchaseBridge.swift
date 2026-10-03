import Foundation
import StoreKit
import WebKit

// Candidate integration. Register as a WKScriptMessageHandlerWithReply under
// "wmPurchases" only after the host creates an authenticated native store session.
// No web command can install credentials, enable this bridge, or grant access.
@MainActor
final class WrestlingManagerPurchaseBridge: NSObject, WKScriptMessageHandlerWithReply {
    private let store: WrestlingManagerStore
    private let currentSession: () -> Bool
    private let stopTransport: () -> Void
    private weak var webView: WKWebView?
    private var enabled: Bool
    private var stopped = false
    private var busy = false

    init(store: WrestlingManagerStore, enabled: Bool = false,
         currentSession: @escaping () -> Bool, stopTransport: @escaping () -> Void) {
        self.store = store
        self.enabled = enabled
        self.currentSession = currentSession
        self.stopTransport = stopTransport
    }

    func attach(to webView: WKWebView) { self.webView = webView }

    // Host MUST invoke on logout, account change, navigation away or dismantling.
    // A new authenticated account requires a new bridge, store and HTTP adapter.
    func stop() {
        guard !stopped else { return }
        stopped = true
        enabled = false
        store.stop()
        stopTransport()
        webView = nil
    }

    private func authorized(_ message: WKScriptMessage) -> Bool {
        guard enabled, !stopped, currentSession(), message.name == "wmPurchases",
              message.frameInfo.isMainFrame,
              message.webView === webView,
              Self.trusted(message.frameInfo.request.url), Self.trusted(webView?.url),
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "theteammanager.app",
              [0,443].contains(message.frameInfo.securityOrigin.port) else { return false }
        return true
    }

    private static func trusted(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "theteammanager.app",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return ["", "/", "/index.html"].contains(url.path)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard authorized(message), let body = message.body as? [String: Any],
              JSONSerialization.isValidJSONObject(body),
              let bytes = try? JSONSerialization.data(withJSONObject: body), bytes.count <= 2048,
              let command = body["command"] as? String else {
            replyHandler(nil, "Purchase session unavailable.")
            return
        }
        guard !busy else { replyHandler(nil, "A purchase request is already running."); return }
        let allowed: Set<String> = command == "purchase" ? ["command", "productID", "target"] : ["command"]
        guard Set(body.keys).isSubset(of: allowed),
              ["products", "purchase", "restore", "recover"].contains(command) else {
            replyHandler(nil, "Invalid purchase request.")
            return
        }
        var purchase: (String, WrestlingManagerPurchaseTarget)?
        if command == "purchase" {
            guard let productID = body["productID"] as? String,
                  WrestlingManagerStore.proposedProductIDs.contains(productID),
                  let target = body["target"] as? [String: Any],
                  let kind = target["kind"] as? String else {
                replyHandler(nil, "Invalid purchase target."); return
            }
            if kind == "team", Set(target.keys) == ["kind", "teamID"],
               let team = target["teamID"] as? String, let teamID = UUID(uuidString: team),
               productID.contains(".teampro.") {
                purchase = (productID, .team(teamID))
            } else if kind == "family", Set(target.keys) == ["kind"], productID.contains(".familyvideo.") {
                purchase = (productID, .family)
            } else { replyHandler(nil, "Invalid purchase target."); return }
        }
        busy = true
        Task { [self] in
            defer { busy = false }
            do {
                let response: [String: Any]
                switch command {
                case "products":
                    let products = try await store.loadProducts()
                    response = ["products": products.map {
                        ["id": $0.id, "displayPrice": $0.displayPrice, "type": "autoRenewable"]
                    }]
                case "purchase":
                    guard let purchase else { throw WrestlingManagerStore.StoreError.invalidTarget }
                    response = ["outcome": Self.name(try await store.purchase(productID: purchase.0, target: purchase.1))]
                case "restore": response = ["outcome": Self.name(try await store.restore())]
                default: response = ["outcome": Self.name(try await store.recover())]
                }
                guard authorized(message) else { replyHandler(nil, "Purchase session ended."); return }
                replyHandler(response, nil)
            } catch {
                // Keep provider errors, receipt payloads and server details private.
                replyHandler(nil, !stopped && currentSession()
                             ? "Purchase request could not be confirmed. Reconnect and restore purchases."
                             : "Purchase session ended.")
            }
        }
    }

    private static func name(_ outcome: WrestlingManagerStore.Outcome) -> String {
        switch outcome {
        case .delivered: return "delivered"
        case .awaitingServer: return "awaitingServer"
        case .pending: return "pending"
        case .cancelled: return "cancelled"
        }
    }
}
