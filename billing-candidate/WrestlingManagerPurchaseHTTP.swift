import Foundation

struct WrestlingManagerPurchaseSession: Equatable {
    let accountID: UUID
    let sessionID: UUID
    let generation: UUID
    let accessToken: String
}

@MainActor
protocol WrestlingManagerPurchaseTransport: AnyObject {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func stop()
}

// Each authenticated adapter owns its own ephemeral session. Redirects are
// rejected so a bearer token cannot be forwarded to another endpoint.
final class WrestlingManagerPurchaseURLSession: NSObject, URLSessionTaskDelegate, WrestlingManagerPurchaseTransport {
    private var session: URLSession!
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    @MainActor
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 65536 else {
            throw WrestlingManagerPurchaseHTTP.AdapterError.invalidResponse
        }
        return (data, response)
    }
    @MainActor func stop() { session.invalidateAndCancel() }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class WrestlingManagerPurchaseHTTP: WrestlingManagerPurchaseServer {
    enum AdapterError: Error { case sessionEnded, invalidResponse, signInRequired, notAuthorized, unavailable }
    private let endpoint = URL(string: "https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/wrestling-manager-billing")!
    private let identity: WrestlingManagerPurchaseSession
    private let currentSession: () -> WrestlingManagerPurchaseSession?
    private let refreshServerAccess: () async throws -> Void
    private let transport: any WrestlingManagerPurchaseTransport
    private var stopped = false
    init(session: WrestlingManagerPurchaseSession,
         currentSession: @escaping () -> WrestlingManagerPurchaseSession?,
         transport: any WrestlingManagerPurchaseTransport,
         refreshServerAccess: @escaping () async throws -> Void) {
        identity = session
        self.currentSession = currentSession
        self.transport = transport
        self.refreshServerAccess = refreshServerAccess
    }
    func stop() { stopped = true; transport.stop() }
    private func snapshot() throws -> WrestlingManagerPurchaseSession {
        guard !stopped, let current = currentSession(), current.accountID == identity.accountID,
              current.sessionID == identity.sessionID, current.generation == identity.generation,
              !current.accessToken.isEmpty else { throw AdapterError.sessionEnded }
        return current
    }
    private func request(action: String, data: [String: Any]) async throws -> [String: Any] {
        let session = try snapshot()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": action, "data": data])
        let (body, response) = try await transport.send(request)
        _ = try snapshot()
        guard response.url == endpoint, body.count <= 65536,
              response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true else {
            throw AdapterError.invalidResponse
        }
        switch response.statusCode {
        case 200: break
        case 401: throw AdapterError.signInRequired
        case 403: throw AdapterError.notAuthorized
        default: throw AdapterError.unavailable
        }
        guard let result = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw AdapterError.invalidResponse
        }
        return result
    }
    func preparePurchase(productID: String, target: WrestlingManagerPurchaseTarget) async throws -> UUID {
        var scope: [String: Any]
        switch target {
        case .team(let teamID): scope = ["kind": "team", "teamID": teamID.uuidString.lowercased()]
        case .family: scope = ["kind": "family"]
        }
        let result = try await request(action: "prepare", data: ["productID": productID, "target": scope])
        guard Set(result.keys) == ["appAccountToken"], let raw = result["appAccountToken"] as? String,
              let token = UUID(uuidString: raw) else { throw AdapterError.invalidResponse }
        return token
    }
    func abandonPurchase(token: UUID) async throws {
        let result = try await request(action: "abandon", data: ["appAccountToken": token.uuidString.lowercased()])
        guard Set(result.keys) == ["cancelled"], result["cancelled"] as? Bool == true else { throw AdapterError.invalidResponse }
    }
    func deliver(signedTransaction: String) async throws -> WrestlingManagerPurchaseAck {
        let result = try await request(action: "deliver", data: ["signedTransaction": signedTransaction])
        func validID(_ key: String) -> String? {
            guard let value = result[key] as? String, (1...40).contains(value.count),
                  value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
            return value
        }
        guard Set(result.keys) == ["transactionID", "originalTransactionID"],
              let transactionID = validID("transactionID"), let original = validID("originalTransactionID") else {
            throw AdapterError.invalidResponse
        }
        return WrestlingManagerPurchaseAck(transactionID: transactionID, originalTransactionID: original)
    }
    func refreshAccess() async throws {
        _ = try snapshot()
        // Integration must reload authoritative server access; no local paid flag.
        try await refreshServerAccess()
        _ = try snapshot()
    }
}
