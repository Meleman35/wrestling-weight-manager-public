import Foundation

struct WrestlingManagerRemoteHTTPSession: Sendable {
    let accountID: UUID
    let sessionID: UUID
    let generation: String
    let accessToken: String
}
private final class RemoteRedirectGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
/// Fixed-endpoint native client. No bearer token or JPEG is exposed to page JavaScript.
/// Session provider must come from the app's trusted personal-auth coordinator.
actor WrestlingManagerRemoteHTTP {
    enum Failure: Error { case closed, sessionChanged, invalidCapture, invalidResponse, unavailable }
    private let identity: WrestlingManagerRemoteHTTPSession
    private let currentSession: @Sendable () async throws -> WrestlingManagerRemoteHTTPSession
    private let publishableKey: String
    private let session: URLSession
    private var active = true
    private let base = URL(string: "https://vfocpoyexnjsjpxhhyqr.supabase.co/functions/v1/remote-weighins")!
    init(identity: WrestlingManagerRemoteHTTPSession, publishableKey: String,
         currentSession: @escaping @Sendable () async throws -> WrestlingManagerRemoteHTTPSession) {
        self.identity = identity; self.publishableKey = publishableKey; self.currentSession = currentSession
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 45
        session = URLSession(configuration: config, delegate: RemoteRedirectGate(), delegateQueue: nil)
    }
    private func snapshot(payload: Data) async throws -> WrestlingManagerRemoteHTTPSession {
        guard active else { throw Failure.closed }
        let current = try await currentSession()
        guard active, current.accountID == identity.accountID, current.sessionID == identity.sessionID,
              current.generation == identity.generation, !current.accessToken.isEmpty,
              !current.accessToken.contains("\n"), !current.accessToken.contains("\r") else { throw Failure.sessionChanged }
        guard payload.count <= 12000,
              let body = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let operatorID = body["operatorId"] as? String, UUID(uuidString: operatorID) == current.accountID,
              body["generation"] as? String == current.generation else { throw Failure.invalidCapture }
        return current
    }
    private func send(action: String, payload: Data, jpeg: Data? = nil) async throws -> Data {
        let current = try await snapshot(payload: payload)
        guard !publishableKey.isEmpty, !publishableKey.contains("\n"), !publishableKey.contains("\r") else { throw Failure.unavailable }
        let endpoint = base.appendingPathComponent(action)
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        if let jpeg {
            guard !jpeg.isEmpty, jpeg.count <= 5 * 1024 * 1024 else { throw Failure.invalidCapture }
            let body = try JSONSerialization.jsonObject(with: payload)
            request.httpBody = try JSONSerialization.data(withJSONObject: ["payload": body, "jpegBase64": jpeg.base64EncodedString()])
        } else { request.httpBody = payload }
        let (data, response) = try await session.data(for: request)
        _ = try await snapshot(payload: payload)
        guard let response = response as? HTTPURLResponse, response.url == endpoint,
              response.statusCode == 200, data.count <= 12000,
              response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true else {
            throw Failure.invalidResponse
        }
        return data
    }
    func transport() -> WrestlingManagerRemoteDelivery.Transport {
        .init(authorize: { [self] payload in
            let data = try await send(action: "authorize", payload: payload)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  result["authorized"] as? Bool == true else { throw Failure.unavailable }
        }, uploadPhoto: { [self] payload, jpeg in try await send(action: "photo", payload: payload, jpeg: jpeg) },
           submit: { [self] payload in try await send(action: "submit", payload: payload) },
           findReceipt: { [self] payload in
               let data = try await send(action: "receipt", payload: payload)
               guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                     result.keys.contains("receipt") else { throw Failure.invalidResponse }
               if result["receipt"] is NSNull { return nil }
               guard let receipt = result["receipt"] as? [String: Any] else { throw Failure.invalidResponse }
               return try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
           })
    }
    func stop() { active = false; session.invalidateAndCancel() }
}
