import Foundation

@MainActor
final class MockPurchaseTransport: WrestlingManagerPurchaseTransport {
    var response: [String: Any] = [:]
    var requests: [URLRequest] = []
    var beforeResponse: (() -> Void)?
    var stopped = false
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        beforeResponse?()
        return (try JSONSerialization.data(withJSONObject: response),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                headerFields: ["Content-Type": "application/json"])!)
    }
    func stop() { stopped = true }
}

@main
struct PurchaseHTTPChecks {
    @MainActor
    static func main() async throws {
        let original = WrestlingManagerPurchaseSession(accountID: UUID(), sessionID: UUID(), generation: UUID(), accessToken: "synthetic-token")
        var current: WrestlingManagerPurchaseSession? = original
        let transport = MockPurchaseTransport()
        var refreshes = 0
        let adapter = WrestlingManagerPurchaseHTTP(session: original, publishableKey: "synthetic-public-key", currentSession: { current },
                                                  transport: transport, refreshServerAccess: { refreshes += 1 })
        let token = UUID()
        transport.response = ["appAccountToken": token.uuidString]
        let received = try await adapter.preparePurchase(productID: "com.damonmele.wrestlingmanager.familyvideo.monthly", target: .family)
        precondition(received == token)
        let body = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
        let data = body["data"] as! [String: Any]
        let target = data["target"] as! [String: Any]
        precondition(target["kind"] as? String == "family" && target["teamID"] == nil)
        precondition(transport.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
        precondition(transport.requests[0].value(forHTTPHeaderField: "apikey") == "synthetic-public-key")
        transport.response = ["transactionID": "1001", "originalTransactionID": "1001"]
        let ack = try await adapter.deliver(signedTransaction: "synthetic-receipt")
        precondition(ack.transactionID == "1001")
        transport.response = ["transactionID": "1001", "originalTransactionID": "1001", "paid": true]
        do { _ = try await adapter.deliver(signedTransaction: "synthetic"); fatalError("Unexpected response keys accepted") }
        catch WrestlingManagerPurchaseHTTP.AdapterError.invalidResponse {}
        transport.response = ["cancelled": true]
        try await adapter.abandonPurchase(token: token)
        try await adapter.refreshAccess()
        precondition(refreshes == 1)
        transport.response = ["appAccountToken": token.uuidString]
        transport.beforeResponse = { current = WrestlingManagerPurchaseSession(accountID: UUID(), sessionID: original.sessionID, generation: original.generation, accessToken: "other-token") }
        do { _ = try await adapter.preparePurchase(productID: "com.damonmele.wrestlingmanager.familyvideo.monthly", target: .family); fatalError("Account change accepted") }
        catch WrestlingManagerPurchaseHTTP.AdapterError.sessionEnded {}
        current = original
        transport.beforeResponse = nil
        adapter.stop()
        precondition(transport.stopped)
        let count = transport.requests.count
        do { _ = try await adapter.preparePurchase(productID: "com.damonmele.wrestlingmanager.familyvideo.monthly", target: .family); fatalError("Stopped adapter reused") }
        catch WrestlingManagerPurchaseHTTP.AdapterError.sessionEnded {}
        precondition(transport.requests.count == count)
        print("PASS native purchase scope, authentication, strict acknowledgement, account changes and logout")
    }
}
