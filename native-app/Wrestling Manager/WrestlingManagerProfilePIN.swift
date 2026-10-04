// 0.20.30: one device-local PIN per signed-in profile. No PIN values leave Keychain verification.
import Foundation
import Security
import CryptoKit
import CommonCrypto
import WebKit

@MainActor
enum WrestlingManagerProfilePIN {
    static let service = "app.wrestlingmanager.profile-pin.v1"
    static let activeKey = "wm.profile-pin.active"
    static var selectionGeneration = UUID()
    static var active: String? { UserDefaults.standard.string(forKey: activeKey).flatMap(validProfile) }
    static func validProfile(_ value: String) -> String? { UUID(uuidString: value)?.uuidString.lowercased() }
    static func query(_ profile: String) -> [String: Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:profile] }
    static func read(_ profile: String) throws -> Data? {
        try WrestlingManagerDeletionJournal.requireUsable(profile)
        var q = query(profile); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &item); if status == errSecItemNotFound { return nil }; guard status == errSecSuccess, let data = item as? Data else { throw fault("Unlock this device and retry the PIN request.") }; return data
    }
    static func legacy() throws -> Data? {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.wrestlingmanager.security",kSecAttrAccount as String:"app-lock-pin",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var item: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &item); if status == errSecItemNotFound { return nil }; guard status == errSecSuccess, let data = item as? Data else { throw fault("Unlock this device and retry the PIN request.") }; return data
    }
    static func equal(_ a: Data, _ b: Data) -> Bool { a.count == b.count && zip(a,b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0 }
    static func validPIN(_ pin: String) -> Bool { (4...8).contains(pin.utf8.count) && pin.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }
    static func digest(_ pin: String, salt: Data) -> Data? {
        var out = [UInt8](repeating:0,count:32)
        let code = pin.withCString { password in salt.withUnsafeBytes { saltBytes in out.withUnsafeMutableBufferPointer { output in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),password,pin.utf8.count,saltBytes.bindMemory(to: UInt8.self).baseAddress,salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),100_000,output.baseAddress,32)
        } } }
        return code == kCCSuccess ? Data(out) : nil
    }
    static func verify(_ profile: String, pin: String, allowLegacy: Bool = false) throws {
        let defaults = UserDefaults.standard, key = "wm.profile-pin.\(profile)."
        guard Date().timeIntervalSince1970 >= defaults.double(forKey:key+"until") else { throw fault("Wait 30 seconds before trying your PIN again.") }
        let record = try read(profile); var matches = false
        if validPIN(pin), let record, record.count == 48, let hash = digest(pin,salt:Data(record.prefix(16))) { matches = equal(Data(record.suffix(32)),hash) }
        else if record == nil, allowLegacy, validPIN(pin), let old = try legacy(), old.count == 48 { matches = equal(Data(old.suffix(32)),Data(SHA256.hash(data:Data(old.prefix(16))+Data(pin.utf8)))) }
        guard matches else {
            let tries = defaults.integer(forKey:key+"tries")+1; defaults.set(tries >= 5 ? 0 : tries,forKey:key+"tries")
            if tries >= 5 { defaults.set(Date().timeIntervalSince1970+30,forKey:key+"until") }
            throw fault(tries >= 5 ? "Wait 30 seconds before trying your PIN again." : "Incorrect PIN.")
        }
        defaults.removeObject(forKey:key+"tries"); defaults.removeObject(forKey:key+"until")
    }
    static func set(_ profile: String, pin: String, current: String) throws {
        guard validPIN(pin) else { throw fault("Use a 4–8 digit PIN.") }
        if try read(profile) != nil || legacy() != nil { try verify(profile,pin:current,allowLegacy:true) }
        try writeVerifiedPIN(profile, pin: pin)
    }
    // Called only after current-PIN verification above or native recovery authentication.
    static func writeVerifiedPIN(_ profile: String, pin: String) throws {
        try WrestlingManagerDeletionJournal.requireUsable(profile)
        guard validProfile(profile) == profile, validPIN(pin) else { throw fault("Use a 4–8 digit PIN for the current profile.") }
        var salt = Data(count:16)
        let code = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault,16,$0.baseAddress!) }
        guard code == errSecSuccess, let hash = digest(pin,salt:salt) else { throw fault("Could not create secure PIN data.") }
        let bytes = salt+hash, q = query(profile)
        let updated = SecItemUpdate(q as CFDictionary,[kSecValueData as String:bytes] as CFDictionary)
        if updated == errSecItemNotFound {
            var item = q; item[kSecValueData as String] = bytes; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw fault("Could not save your PIN. The previous PIN has not been removed.") }
        } else if updated != errSecSuccess { throw fault("Could not change your PIN. Try again after unlocking the device.") }
    }
    static func fault(_ message: String) -> NSError { NSError(domain:"WrestlingManager.ProfilePIN",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }

    // Internal primitive for an independently authorized account-deletion workflow.
    // Do not call through the profile-selection bridge; selection is not identity proof.
    static func removeForAccountCleanup(_ accountID: String) throws {
        let profile = try WrestlingManagerAccountCleanupPolicy.account(accountID)
        let status = SecItemDelete(query(profile) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw fault("Could not remove the profile PIN. Account cleanup is incomplete.")
        }
        var check = query(profile)
        check[kSecReturnAttributes as String] = true
        check[kSecMatchLimit as String] = kSecMatchLimitOne
        var remaining: CFTypeRef?
        let verified = SecItemCopyMatching(check as CFDictionary, &remaining)
        guard verified == errSecItemNotFound else {
            throw fault("Could not verify removal of the profile PIN. Account cleanup is incomplete.")
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "wm.profile-pin.\(profile).tries")
        defaults.removeObject(forKey: "wm.profile-pin.\(profile).until")
        if active == profile {
            selectionGeneration = UUID()
            defaults.removeObject(forKey: activeKey)
        }
        // The legacy device PIN, app lock and every other profile remain unchanged.
    }
}

@MainActor
final class WrestlingManagerProfilePINBridge: NSObject, WKScriptMessageHandler {
    var localURL: URL?
    var offline = false
    var allowedProfiles = Set<String>()
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "wmProfilePin", message.frameInfo.isMainFrame, let web = message.webView,
              trusted(message.frameInfo.request.url), trusted(web.url), let body = message.body as? [String: Any],
              let id = body["id"] as? String, id.count < 100, let command = body["command"] as? String else { return }
        var result: [String: Any] = ["id":id,"success":true]
        do {
            if command == "select", !offline {
                WrestlingManagerProfilePIN.selectionGeneration = UUID()
                if let value = body["profile"] as? String, let profile = WrestlingManagerProfilePIN.validProfile(value) { UserDefaults.standard.set(profile,forKey:WrestlingManagerProfilePIN.activeKey) }
                else { UserDefaults.standard.removeObject(forKey:WrestlingManagerProfilePIN.activeKey) }
            } else {
                guard let value = body["profile"] as? String, let profile = WrestlingManagerProfilePIN.validProfile(value),
                      (offline ? allowedProfiles.contains(profile) : WrestlingManagerProfilePIN.active == profile) else { throw WrestlingManagerProfilePIN.fault("Open the matching profile before using its PIN.") }
                switch command {
                case "status": result["exists"] = try WrestlingManagerProfilePIN.read(profile) != nil; result["legacy"] = try !offline && WrestlingManagerProfilePIN.legacy() != nil
                case "verify": try WrestlingManagerProfilePIN.verify(profile,pin:body["pin"] as? String ?? "")
                case "set":
                    guard !offline else { throw WrestlingManagerProfilePIN.fault("Change your PIN in Profile → Security.") }
                    try WrestlingManagerProfilePIN.set(profile,pin:body["pin"] as? String ?? "",current:body["current"] as? String ?? "")
                default: throw WrestlingManagerProfilePIN.fault("Unknown profile PIN request.")
                }
            }
        } catch { result["success"] = false; result["error"] = error.localizedDescription }
        guard let bytes = try? JSONSerialization.data(withJSONObject:result), let json = String(data:bytes,encoding:.utf8) else { return }
        web.evaluateJavaScript("window.wrestlingManagerProfilePINResponse?.(\(json));",completionHandler:nil)
    }
    private func trusted(_ url: URL?) -> Bool {
        guard let url else { return false }
        if offline { return url.isFileURL && url.standardizedFileURL == localURL?.standardizedFileURL }
        return WrestlingManagerAppOrigin.contains(url)
    }
}
