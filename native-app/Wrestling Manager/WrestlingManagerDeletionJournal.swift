import Foundation
import Security
import CryptoKit

@MainActor
enum WrestlingManagerDeletionJournal {
    typealias Journal = WrestlingManagerDeletionReceipt.Journal
    static func hash(_ account: String) -> String {
        SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "WrestlingManager") + ".deletion.v1",
         kSecAttrAccount as String: "journal", kSecAttrSynchronizable as String: false]
    }
    static func load() throws -> Journal {
        var q = query
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return Journal() }
        guard status == errSecSuccess, let bytes = item as? Data, bytes.count <= 2 * 1024 * 1024,
              let value = try? JSONDecoder().decode(Journal.self, from: bytes) else {
            throw WrestlingManagerDeletionReceipt.fail("Unlock this device to check its saved deletion request.")
        }
        return try value.validated()
    }
    static func save(_ value: Journal) throws {
        let bytes = try JSONEncoder().encode(value.validated())
        guard bytes.count <= 2 * 1024 * 1024 else { throw WrestlingManagerDeletionReceipt.fail("The deletion journal is full.") }
        var changes: [String: Any] = [kSecValueData as String: bytes]
        changes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; changes.forEach { q[$0.key] = $0.value }
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WrestlingManagerDeletionReceipt.fail("The deletion request could not be saved securely. Resume it after unlocking the device.") }
        let readback = try load()
        guard readback == value else {
            throw WrestlingManagerDeletionReceipt.fail("The saved deletion request could not be verified.")
        }
    }
    static func requireUsable(_ account: String) throws {
        let id = try WrestlingManagerAccountCleanupPolicy.account(account), state = try load()
        guard !state.departedSubjects.contains(hash(id)),
              !state.jobs.values.contains(where: { $0.request.personal && $0.request.actorId == id }) else {
            throw WrestlingManagerDeletionReceipt.fail("This account has a deletion request. Resume its deletion status before using saved account data.")
        }
    }
}
