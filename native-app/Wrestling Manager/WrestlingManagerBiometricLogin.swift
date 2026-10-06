import Foundation
import UIKit
import WebKit
import LocalAuthentication
import Security

// A single opt-in personal login, protected by the current enrolled biometrics.
// Passwords never enter UserDefaults, web storage, logs or a shared Keychain group.
@MainActor
final class WrestlingManagerBiometricLoginBridge: NSObject, WKScriptMessageHandler {
    private struct SavedLogin: Codable { let email: String; let password: String; let userID: String }
    private weak var webView: WKWebView?
    private var context: LAContext?
    private var operation: UUID?
    private var requestID: String?
    // Separate from normal sign-in. Retained only for one deletion command so
    // repeated metadata checks use the context the device owner authenticated.
    private var cleanupContext: LAContext?
    private let slotKey = "wm.biometric.login.slot.v1"
    private var service: String { (Bundle.main.bundleIdentifier ?? "WrestlingManager") + ".biometric-login.v1" }
    private var slot: String? { UserDefaults.standard.string(forKey: slotKey) }
    private func trusted(_ url: URL?) -> Bool {
        WrestlingManagerAppOrigin.contains(url)
    }
    func attach(to webView: WKWebView) { self.webView = webView }
    func detach() { cancel(); endCleanupAccess(); webView = nil }
    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    private func available(_ ctx: LAContext) -> Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        let usage = (Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String) ?? ""
        return !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        #endif
    }
    func sendStatus() {
        let ctx = LAContext(), canUse = available(ctx)
        send(["event": "status", "available": canUse, "saved": slot != nil,
              "label": ctx.biometryType == .faceID ? "Face ID" : ctx.biometryType == .touchID ? "Touch ID" : "Biometrics"])
        ctx.invalidate()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, trusted(message.frameInfo.request.url), trusted(webView?.url),
              let body = message.body as? [String: Any], let command = body["command"] as? String else { return }
        if command == "status" { sendStatus(); return }
        if command == "cancel" { cancel(); return }
        guard let id = body["requestId"] as? String, UUID(uuidString: id) != nil else { return }
        guard cleanupContext == nil else {
            send(["requestId": id, "ok": false, "message": "Finish or cancel account deletion before changing saved sign-ins."]); return
        }
        if command == "forget" {
            cancel()
            if let slot {
                let status = SecItemDelete(baseQuery(slot) as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    send(["requestId": id, "ok": false, "message": "Could not remove the saved login. Unlock the phone and try again."]); return
                }
            }
            UserDefaults.standard.removeObject(forKey: slotKey)
            send(["requestId": id, "ok": true]); sendStatus(); return
        }
        guard ["enroll", "read"].contains(command) else { return }
        guard operation == nil else { send(["requestId": id, "ok": false, "message": "Finish the current biometric request first."]); return }
        let ctx = LAContext()
        guard available(ctx) else { send(["requestId": id, "ok": false, "message": "Face ID or Touch ID is unavailable. Use your password."]); return }
        var newLogin: SavedLogin?
        if command == "enroll" {
            guard let email = body["email"] as? String, !email.isEmpty, email.utf8.count <= 320,
                  let password = body["password"] as? String, !password.isEmpty, password.utf8.count <= 4096,
                  let userID = body["userID"] as? String, UUID(uuidString: userID) != nil else {
                send(["requestId": id, "ok": false, "message": "Sign in with your password before enabling biometrics."]); return
            }
            newLogin = SavedLogin(email: email, password: password, userID: userID)
        } else if slot == nil {
            send(["requestId": id, "ok": false, "message": "Sign in with your password and enable Face ID in Sign-In & App Security."]); return
        }
        let ticket = UUID()
        operation = ticket; requestID = id; context = ctx
        ctx.localizedCancelTitle = "Use Password"
        ctx.localizedFallbackTitle = ""
        let reason = command == "enroll" ? "Protect your Wrestling Manager sign-in on this device" : "Sign in to Wrestling Manager"
        let loginToSave = newLogin
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                guard let self, self.operation == ticket, let ctx = self.context else { return }
                guard success else { self.complete(["requestId": id, "ok": false, "cancelled": true, "message": "Use your password or try Face ID again."]); return }
                if let login = loginToSave { self.store(login, context: ctx, request: id) }
                else { self.read(context: ctx, request: id) }
            }
        }
    }
    private func store(_ login: SavedLogin, context: LAContext, request: String) {
        do { try WrestlingManagerDeletionJournal.requireUsable(login.userID) }
        catch { complete(["requestId": request, "ok": false, "message": error.localizedDescription]); return }
        guard let data = try? JSONEncoder().encode(login),
              let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil) else {
            complete(["requestId": request, "ok": false, "message": "Could not protect the saved login. Use password sign-in."]); return
        }
        let nextSlot = UUID().uuidString
        var query = baseQuery(nextSlot)
        query[kSecAttrAccessControl as String] = access
        query[kSecValueData as String] = data
        // Non-secret ownership metadata permits scoped removal without decrypting
        // a password. No email, password or authentication token is stored here.
        query[kSecAttrGeneric as String] = try? WrestlingManagerAccountCleanupPolicy.ownerTag(login.userID)
        query[kSecUseAuthenticationContext as String] = context
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            complete(["requestId": request, "ok": false, "message": "Could not save Face ID sign-in. Your previous saved login is unchanged."]); return
        }
        let oldSlot = slot
        UserDefaults.standard.set(nextSlot, forKey: slotKey)
        if let oldSlot { SecItemDelete(baseQuery(oldSlot) as CFDictionary) }
        complete(["requestId": request, "ok": true]); sendStatus()
    }
    private func read(context: LAContext, request: String) {
        guard let slot else { complete(["requestId": request, "ok": false, "message": "No saved login. Use your password."]); return }
        var query = baseQuery(slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let login = try? JSONDecoder().decode(SavedLogin.self, from: data) else {
            if status == errSecItemNotFound {
                UserDefaults.standard.removeObject(forKey: slotKey)
            }
            complete(["requestId": request, "ok": false, "message": "Saved sign-in is unavailable. Sign in with your password and enable Face ID again."])
            sendStatus(); return
        }
        do { try WrestlingManagerDeletionJournal.requireUsable(login.userID) }
        catch { complete(["requestId": request, "ok": false, "message": error.localizedDescription]); return }
        // Only the allow-listed main app receives this transient payload. The web
        // client must still authenticate with Supabase; a biometric match grants no role.
        // Backfill legacy ownership only after actually decrypting this exact item.
        // If the update fails, deletion inventory continues to classify it unknown.
        if let tag = try? WrestlingManagerAccountCleanupPolicy.ownerTag(login.userID) {
            var update = baseQuery(slot)
            update[kSecUseAuthenticationContext as String] = context
            _ = SecItemUpdate(update as CFDictionary, [kSecAttrGeneric as String: tag] as CFDictionary)
        }
        complete(["requestId": request, "ok": true, "email": login.email, "password": login.password, "userID": login.userID])
    }

    struct AccountCleanupResult {
        let removedCount: Int
        let unresolvedLegacyItems: Int
    }
    private struct CleanupAccessFailure: Error { let status: OSStatus }
    private func cleanupFailure(_ error: Error) -> Error {
        guard let access = error as? CleanupAccessFailure else { return error }
        return WrestlingManagerAccountCleanupPolicy.Failure(message: "Saved Face ID/Touch ID sign-ins could not be checked (Keychain status \(access.status)). Unlock this device and retry the same deletion request.")
    }
    func endCleanupAccess() {
        cleanupContext?.invalidate()
        cleanupContext = nil
    }
    private func requireKnown(_ rows: [WrestlingManagerAccountCleanupPolicy.BiometricItem]) throws {
        guard rows.allSatisfy({ WrestlingManagerAccountCleanupPolicy.owner($0.ownerTag) != nil }) else {
            throw WrestlingManagerDeletionReceipt.fail("An older saved sign-in needs review. Use its normal Face ID sign-in or Forget saved login before in-app deletion.")
        }
    }
    func requireKnownCleanupOwnership() async throws {
        guard operation == nil else {
            throw WrestlingManagerDeletionReceipt.fail("Finish the current Face ID/Touch ID sign-in before retrying deletion.")
        }
        let ctx = cleanupContext ?? LAContext()
        cleanupContext = ctx
        ctx.interactionNotAllowed = true
        do {
            do {
                try requireKnown(cleanupInventory())
                return
            } catch let failure as CleanupAccessFailure where failure.status == errSecInteractionNotAllowed {
                // Authentication is required. Never treat protected/hidden items
                // as an empty inventory or skip them to make deletion proceed.
            }
            guard UIApplication.shared.applicationState == .active,
                  UIApplication.shared.isProtectedDataAvailable else {
                throw WrestlingManagerDeletionReceipt.fail("Unlock this device and keep Wrestling Manager open, then retry the same deletion request.")
            }
            guard available(ctx) else {
                throw WrestlingManagerDeletionReceipt.fail("Face ID or Touch ID is unavailable for checking saved sign-ins. Unlock the device and try again.")
            }
            ctx.interactionNotAllowed = false
            ctx.localizedCancelTitle = "Cancel"
            ctx.localizedFallbackTitle = ""
            let success: Bool = await withCheckedContinuation { continuation in
                ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Verify saved sign-ins for Wrestling Manager account deletion") { success, _ in
                    continuation.resume(returning: success)
                }
            }
            guard cleanupContext === ctx else {
                throw WrestlingManagerDeletionReceipt.fail("The screen changed while checking saved sign-ins. Retry the same deletion request.")
            }
            ctx.interactionNotAllowed = true
            guard success else {
                throw WrestlingManagerDeletionReceipt.fail("Face ID/Touch ID verification was cancelled or failed. Saved sign-ins were kept.")
            }
            guard UIApplication.shared.applicationState != .background,
                  UIApplication.shared.isProtectedDataAvailable else {
                throw WrestlingManagerDeletionReceipt.fail("Unlock this device and return to Wrestling Manager to finish checking saved sign-ins.")
            }
            // Full inventory, including every other account, with authenticated
            // context reuse. No passwords are requested or delivered to the page.
            try requireKnown(cleanupInventory())
        } catch {
            if cleanupContext === ctx { endCleanupAccess() }
            throw cleanupFailure(error)
        }
    }
    private func cleanupInventory() throws -> [WrestlingManagerAccountCleanupPolicy.BiometricItem] {
        guard let inventoryContext = cleanupContext else {
            throw WrestlingManagerDeletionReceipt.fail("Saved sign-ins have not been checked for this deletion request. Resume deletion to verify them.")
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true, kSecReturnPersistentRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll, kSecUseAuthenticationContext as String: inventoryContext]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw CleanupAccessFailure(status: status) }
        guard let rows = result as? [[String: Any]] else {
            throw WrestlingManagerAccountCleanupPolicy.Failure(message: "The saved-login inventory could not be verified. Saved sign-ins were kept.")
        }
        return try rows.map { row in
            guard let account = row[kSecAttrAccount as String] as? String,
                  let reference = row[kSecValuePersistentRef as String] as? Data else {
                throw WrestlingManagerAccountCleanupPolicy.Failure(message: "Saved-login identity could not be verified.")
            }
            return .init(slot: account, reference: reference, ownerTag: row[kSecAttrGeneric as String] as? Data)
        }
    }
    // Internal only. A UUID alone is not deletion authorization. Unknown legacy
    // entries are preserved and reported, never guessed from the currently open UI.
    func removeForAccountCleanup(_ accountID: String) throws -> AccountCleanupResult {
        do { return try removeVerifiedLogins(accountID) }
        catch { throw cleanupFailure(error) }
    }
    private func removeVerifiedLogins(_ accountID: String) throws -> AccountCleanupResult {
        let account = try WrestlingManagerAccountCleanupPolicy.account(accountID)
        cancel() // invalidates any delayed biometric callback before removal
        guard let cleanupContext else {
            throw WrestlingManagerDeletionReceipt.fail("Resume deletion to verify saved sign-ins before cleanup.")
        }
        let plan = try WrestlingManagerAccountCleanupPolicy.biometricPlan(accountID: account, items: cleanupInventory())
        for item in plan.matching {
            var query = baseQuery(item.slot)
            query[kSecValuePersistentRef as String] = item.reference
            query[kSecAttrGeneric as String] = try WrestlingManagerAccountCleanupPolicy.ownerTag(account)
            query[kSecUseAuthenticationContext as String] = cleanupContext
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw WrestlingManagerAccountCleanupPolicy.Failure(message: "A saved login could not be removed. Account cleanup is incomplete.")
            }
        }
        let after = try cleanupInventory()
        let remaining = try WrestlingManagerAccountCleanupPolicy.biometricPlan(accountID: account, items: after)
        guard remaining.matching.isEmpty, plan.matching.allSatisfy({ old in !after.contains { $0.reference == old.reference } }) else {
            throw WrestlingManagerAccountCleanupPolicy.Failure(message: "Saved-login removal could not be verified. Account cleanup is incomplete.")
        }
        if let activeSlot = slot, plan.matching.contains(where: { $0.slot == activeSlot }) {
            UserDefaults.standard.removeObject(forKey: slotKey)
        }
        return AccountCleanupResult(removedCount: plan.matching.count, unresolvedLegacyItems: remaining.unresolvedCount)
    }
    private func complete(_ result: [String: Any]) {
        operation = nil; requestID = nil; context?.invalidate(); context = nil
        send(result)
    }
    func cancel() {
        let id = requestID
        operation = nil; requestID = nil; context?.invalidate(); context = nil
        if let id { send(["requestId": id, "ok": false, "cancelled": true]) }
    }
    private func send(_ result: [String: Any]) {
        guard let webView, trusted(webView.url),
              let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.wrestlingManagerBiometricLoginResult?.(\(json));", completionHandler: nil)
    }
}
