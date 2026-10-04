import Foundation
import WebKit

/// The page can request activation, but only a live authenticated billing service
/// can make purchases available. No page flag, token, product list or endpoint is accepted.
@MainActor
final class WrestlingManagerPurchaseActivation: NSObject, WKScriptMessageHandlerWithReply {
    private weak var webView: WKWebView?
    private let host: WrestlingManagerPurchaseHost
    private var attempt = UUID()
    private var busy = false
    private var transport: WrestlingManagerPurchaseURLSession?

    init(webView: WKWebView, host: WrestlingManagerPurchaseHost) {
        self.webView = webView; self.host = host
    }
    private func trusted(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.host == "theteammanager.app",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return ["", "/", "/index.html"].contains(url.path)
    }
    func stop() { attempt = UUID(); busy = false; transport?.stop(); transport = nil; host.stop() }
    func detach() { stop(); webView = nil }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let webView, message.webView === webView, message.frameInfo.isMainFrame,
              trusted(webView.url), trusted(message.frameInfo.request.url),
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "theteammanager.app",
              [0,443].contains(message.frameInfo.securityOrigin.port),
              message.name == "wmPurchaseActivation", let body = message.body as? [String: String],
              [ ["command":"activate"], ["command":"stop"] ].contains(body) else {
            replyHandler(nil, "Open plans from your unlocked personal account."); return
        }
        if body["command"] == "stop" { stop(); replyHandler(["stopped":true], nil); return }
        guard !busy else { replyHandler(nil, "A purchase request is already running."); return }
        stop(); busy = true
        let ticket = attempt
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { replyHandler(nil, "Purchase session ended."); return }
            defer { if self.attempt == ticket { self.busy = false } }
            let wire = WrestlingManagerPurchaseURLSession(); self.transport = wire
            var authentication: WrestlingManagerPurchaseAuthentication?
            do {
                let keyValue = try await webView.callAsyncJavaScript("return typeof SUPABASE_KEY === 'string' ? SUPABASE_KEY : null;", arguments: [:], in: nil, contentWorld: .page)
                guard self.attempt == ticket, self.trusted(webView.url),
                      let key = keyValue as? String, !key.isEmpty, key.utf8.count <= 8192,
                      !key.contains("\n"), !key.contains("\r") else { throw Failure.unavailable }
                let auth = WrestlingManagerPurchaseAuthentication(publishableKey: key,
                    transport: WrestlingManagerPurchaseURLSession(), readSnapshot: { [weak webView] in
                        guard let webView else { return nil }
                        return try await WrestlingManagerPurchasePageSession.read(from: webView)
                    })
                authentication = auth
                let identity = try await auth.authenticate()
                guard self.attempt == ticket else { throw Failure.unavailable }
                let endpoint = URL(string: "https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-billing")!
                var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(key, forHTTPHeaderField: "apikey")
                request.setValue("Bearer " + identity.accessToken, forHTTPHeaderField: "Authorization")
                request.httpBody = Data(#"{"action":"capabilities","data":{}}"#.utf8)
                let (bytes, response) = try await wire.send(request)
                guard self.attempt == ticket, response.url == endpoint, response.statusCode == 200,
                      response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
                      bytes.count <= 8192, let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      Set(value.keys) == ["ready","productIDs"], value["ready"] as? Bool == true,
                      let ids = value["productIDs"] as? [String], !ids.isEmpty,
                      ids.count == Set(ids).count, Set(ids).isSubset(of: WrestlingManagerStore.proposedProductIDs) else { throw Failure.unavailable }
                let installed = await self.host.configureAuthenticated(authentication: auth, publishableKey: key,
                    productIDs: Set(ids), enabled: true, refreshServerAccess: {})
                guard self.attempt == ticket, installed else { throw Failure.unavailable }
                replyHandler(["ready":true,"generation":identity.generation.uuidString.lowercased()], nil)
            } catch {
                authentication?.stop()
                if self.attempt == ticket { self.host.stop() }
                replyHandler(nil, "Purchases are unavailable right now. Please try again later.")
            }
            wire.stop()
            if self.attempt == ticket { self.transport = nil }
        }
    }
    private enum Failure: Error { case unavailable }
}
