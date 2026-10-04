import Foundation

@MainActor
final class AuthenticationTransport: WrestlingManagerPurchaseTransport {
    var calls: [URLRequest] = []
    var stopped = false
    var userID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    var status = 200
    var anonymous = false
    var afterRequest: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls.append(request); afterRequest?()
        let data = try JSONSerialization.data(withJSONObject: ["id":userID.uuidString,"is_anonymous":anonymous])
        return (data, HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!)
    }
    func stop() { stopped = true }
}

@main struct PurchaseAuthenticationChecks {
    @MainActor static func main() async throws {
        let account = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let other = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        func token(_ sessionID: UUID, issuer: String = "https://vfocpoyexnjsjpxhhyqr.supabase.co/auth/v1", expires: Int = 2000) throws -> String {
            let bytes = try JSONSerialization.data(withJSONObject: ["sub":account.uuidString,"session_id":sessionID.uuidString,"iss":issuer,"role":"authenticated","exp":expires])
            let payload = bytes.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
            return "synthetic-header." + payload + ".synthetic-signature"
        }
        func snapshot(_ value: String, personal: Bool = true, unlocked: Bool = true) -> WrestlingManagerPurchaseAuthentication.Snapshot {
            .init(accountID:account,accessToken:value,personalAccount:personal,unlocked:unlocked)
        }
        func rejects(_ work: () async throws -> WrestlingManagerPurchaseSession) async {
            do { _ = try await work(); fatalError("Expected authentication rejection") } catch {}
        }
        let transport = AuthenticationTransport()
        var current: WrestlingManagerPurchaseAuthentication.Snapshot? = snapshot(try token(account))
        let auth = WrestlingManagerPurchaseAuthentication(publishableKey:"synthetic-public",transport:transport,readSnapshot:{current},clock:{Date(timeIntervalSince1970:1000)})
        let first = try await auth.authenticate()
        precondition(first.accountID == account && first.sessionID == account)
        precondition(transport.calls[0].url?.absoluteString == "https://vfocpoyexnjsjpxhhyqr.supabase.co/auth/v1/user")
        precondition(transport.calls[0].value(forHTTPHeaderField:"Authorization") == "Bearer " + current!.accessToken)
        precondition(transport.calls[0].value(forHTTPHeaderField:"apikey") == "synthetic-public")
        current = snapshot(try token(account,expires:2100))
        let refreshed = try await auth.authenticate()
        precondition(refreshed.generation == first.generation && refreshed.accessToken != first.accessToken)
        print("PASS server-verified identity and same-session token refresh")

        for invalid in [snapshot("bad"),snapshot(try token(account,expires:900)),snapshot(try token(account,issuer:"https://evil.invalid")),snapshot(try token(account),personal:false),snapshot(try token(account),unlocked:false)] {
            current = invalid; let count = transport.calls.count
            await rejects { try await auth.authenticate() }; precondition(auth.currentSession == nil && transport.calls.count == count)
        }
        current = snapshot(try token(other)); let count = transport.calls.count
        await rejects { try await auth.authenticate() }; precondition(transport.calls.count == count)
        print("PASS expired/malformed/foreign tokens, locked/managed accounts and replaced sessions fail closed")

        current = snapshot(try token(account)); transport.userID = other
        await rejects { try await auth.authenticate() }; precondition(auth.currentSession == nil)
        transport.userID = account; transport.anonymous = true
        await rejects { try await auth.authenticate() }; transport.anonymous = false
        transport.status = 401; await rejects { try await auth.authenticate() }; transport.status = 200
        print("PASS mismatched, anonymous and denied Auth-server responses rejected")

        transport.afterRequest = { current = nil }
        await rejects { try await auth.authenticate() }; precondition(auth.currentSession == nil)
        transport.afterRequest = nil; current = snapshot(try token(account))
        transport.afterRequest = { auth.stop() }
        await rejects { try await auth.authenticate() }; precondition(transport.stopped && auth.currentSession == nil)
        await rejects { try await auth.authenticate() }
        print("PASS logout and stop discard in-flight authentication; stopped provider cannot resume")
    }
}
