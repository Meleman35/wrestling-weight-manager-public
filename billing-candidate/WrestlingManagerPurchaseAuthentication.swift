import Foundation
import CoreFoundation

// Native reads the page session through an origin-checked host callback.
// JWT decoding below only correlates identity/session; the Auth server verifies
// the bearer token. Billing routes must still verify live auth.sessions and
// current authorization; this provider grants no subscription access.
@MainActor
final class WrestlingManagerPurchaseAuthentication {
    struct Snapshot: Equatable {
        let accountID: UUID
        let accessToken: String
        let personalAccount: Bool
        let unlocked: Bool
    }
    enum Failure: Error { case unavailable, sessionEnded, invalidSession }
    private let endpoint = URL(string: "https://vfocpoyexnjsjpxhhyqr.supabase.co/auth/v1/user")!
    private let issuer = "https://vfocpoyexnjsjpxhhyqr.supabase.co/auth/v1"
    private let publishableKey: String
    private let readSnapshot: () async throws -> Snapshot?
    private let transport: any WrestlingManagerPurchaseTransport
    private let generation = UUID()
    private let clock: () -> Date
    private var owner: (UUID, UUID)?
    private var stopped = false
    private var busy = false
    private(set) var currentSession: WrestlingManagerPurchaseSession?

    init(publishableKey: String, transport: any WrestlingManagerPurchaseTransport,
         readSnapshot: @escaping () async throws -> Snapshot?, clock: @escaping () -> Date = Date.init) {
        self.publishableKey = publishableKey
        self.transport = transport
        self.readSnapshot = readSnapshot
        self.clock = clock
    }

    func stop() { stopped = true; currentSession = nil; transport.stop() }

    private func decode(_ snapshot: Snapshot) throws -> UUID {
        guard snapshot.personalAccount, snapshot.unlocked,
              !snapshot.accessToken.isEmpty, snapshot.accessToken.utf8.count <= 16000 else { throw Failure.invalidSession }
        let parts = snapshot.accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[2].isEmpty else { throw Failure.invalidSession }
        var raw = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
        guard let bytes = Data(base64Encoded: raw),
              let payload = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              payload["iss"] as? String == issuer, payload["role"] as? String == "authenticated",
              let subject = payload["sub"] as? String, UUID(uuidString: subject) == snapshot.accountID,
              let session = payload["session_id"] as? String, let sessionID = UUID(uuidString: session),
              let expires = payload["exp"] as? NSNumber, CFGetTypeID(expires) != CFBooleanGetTypeID(),
              expires.doubleValue.isFinite, expires.doubleValue > clock().timeIntervalSince1970 else { throw Failure.invalidSession }
        return sessionID
    }

    func authenticate() async throws -> WrestlingManagerPurchaseSession {
        guard !stopped else { throw Failure.sessionEnded }
        guard !busy else { throw Failure.unavailable }
        busy = true; currentSession = nil
        defer { busy = false }
        do {
            guard !publishableKey.isEmpty, let snapshot = try await readSnapshot(), !stopped else { throw Failure.sessionEnded }
            let sessionID = try decode(snapshot)
            if let owner, owner.0 != snapshot.accountID || owner.1 != sessionID { throw Failure.sessionEnded }
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer " + snapshot.accessToken, forHTTPHeaderField: "Authorization")
            let (bytes, response) = try await transport.send(request)
            guard !stopped, response.url == endpoint, response.statusCode == 200, bytes.count <= 65536,
                  response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
                  let user = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let id = user["id"] as? String, UUID(uuidString: id) == snapshot.accountID,
                  user["is_anonymous"] as? Bool == false else { throw Failure.invalidSession }
            guard let after = try await readSnapshot(), !stopped, after == snapshot,
                  try decode(after) == sessionID else { throw Failure.sessionEnded }
            let session = WrestlingManagerPurchaseSession(accountID: snapshot.accountID,
                sessionID: sessionID, generation: generation, accessToken: snapshot.accessToken)
            owner = (snapshot.accountID, sessionID)
            currentSession = session
            return session
        } catch {
            currentSession = nil
            // Never forward token, provider response or transport diagnostics.
            if let failure = error as? Failure { throw failure }
            throw Failure.unavailable
        }
    }
}
