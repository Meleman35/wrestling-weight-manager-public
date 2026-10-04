import Foundation
import CryptoKit
import Security

/// Remote-only persistent capture queue. Host owns one instance per account/club.
/// No bridge/session activation is installed by this file.
actor WrestlingManagerRemoteOutbox {
    struct Capture: Codable, Equatable {
        let submissionID: UUID
        let accountID: UUID
        let clubID: UUID
        let payload: Data
        let jpeg: Data
        var receipt: Data?
    }
    enum Failure: Error { case locked, keyUnavailable, wrongScope, conflict, capacity, unconfirmed, expired }
    private let accountID: UUID
    private let clubID: UUID
    private let now: @Sendable () -> Date
    private let folder: URL
    private var key: SymmetricKey?
    private static let service = "com.damonmele.wrestlingmanager.remote-outbox.v1"
    private let maxBytes = 32 * 1024 * 1024
    private let maxEntries = 200

    init(accountID: UUID, clubID: UUID, now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.now = now
        self.accountID = accountID
        self.clubID = clubID
        let scope = "\(accountID.uuidString):\(clubID.uuidString)"
        let digest = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        folder = base.appendingPathComponent("RemoteWeighInOutbox", isDirectory: true).appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var location = folder; try location.setResourceValues(excluded)
        let hasFiles = !(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)).isEmpty
        key = try Self.loadKey(scope: scope, allowCreate: !hasFiles)
    }
    private static func loadKey(scope: String, allowCreate: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: scope,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        if status == errSecSuccess, let data = found as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound, allowCreate else { throw Failure.keyUnavailable }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: scope,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data]
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw Failure.keyUnavailable }
        return key
    }
    private func requireKey() throws -> SymmetricKey { guard let key else { throw Failure.locked }; return key }
    private func path(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString).appendingPathExtension("sealed") }
    private func identity(_ id: UUID) -> Data { Data("\(accountID.uuidString):\(clubID.uuidString):\(id.uuidString)".utf8) }
    private func read(_ id: UUID) throws -> Capture {
        let key = try requireKey()
        let box = try AES.GCM.SealedBox(combined: Data(contentsOf: path(id)))
        let bytes = try AES.GCM.open(box, using: key, authenticating: identity(id))
        let capture = try JSONDecoder().decode(Capture.self, from: bytes)
        guard capture.submissionID == id, capture.accountID == accountID, capture.clubID == clubID else { throw Failure.wrongScope }
        if now() >= (try WrestlingManagerRemoteRetention.expiresAt(payload: capture.payload)) {
            try FileManager.default.removeItem(at: path(id))
            throw Failure.expired
        }
        return capture
    }
    private func write(_ capture: Capture) throws {
        let bytes = try JSONEncoder().encode(capture)
        let sealed = try AES.GCM.seal(bytes, using: requireKey(), authenticating: identity(capture.submissionID))
        guard let combined = sealed.combined else { throw Failure.keyUnavailable }
        try combined.write(to: path(capture.submissionID), options: [.atomic, .completeFileProtection])
    }
    func save(_ capture: Capture) throws {
        _ = try requireKey()
        guard capture.accountID == accountID, capture.clubID == clubID,
              capture.jpeg.count <= 5 * 1024 * 1024, capture.payload.count <= 12000,
              capture.receipt == nil else { throw Failure.wrongScope }
        guard now() < (try WrestlingManagerRemoteRetention.expiresAt(payload: capture.payload)) else { throw Failure.expired }
        if FileManager.default.fileExists(atPath: path(capture.submissionID).path) {
            let previous = try read(capture.submissionID)
            guard previous.payload == capture.payload, previous.jpeg == capture.jpeg else { throw Failure.conflict }
            return
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        let size = try files.reduce(0) { total, url in total + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        // JSON base64 expansion + encryption overhead are included conservatively.
        guard files.count < maxEntries, size + capture.jpeg.count * 2 + capture.payload.count * 2 + 4096 <= maxBytes else { throw Failure.capacity }
        try write(capture)
    }
    func pending() throws -> [UUID] {
        _ = try requireKey()
        var ids: [UUID] = []
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.pathExtension == "sealed" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw Failure.conflict }
            do { _ = try read(id); ids.append(id) }
            catch Failure.expired { continue }
        }
        return ids.sorted { $0.uuidString < $1.uuidString }
    }
    func capture(_ id: UUID) throws -> Capture { try read(id) }
    private static func receiptDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: text)
    }
    func confirm(_ id: UUID, receipt: Data) throws {
        var row = try read(id)
        let value = try JSONSerialization.jsonObject(with: receipt) as? [String: Any]
        guard let rawID = value?["submissionId"] as? String, UUID(uuidString: rawID) == id,
              value?["status"] as? String == "submitted", value?["receiptId"] as? String != nil,
              let received = value?["receivedAt"] as? String,
              Self.receiptDate(received) != nil, receipt.count <= 12000 else { throw Failure.unconfirmed }
        if let previous = row.receipt { guard previous == receipt else { throw Failure.conflict }; return }
        row.receipt = receipt; try write(row)
    }
    func removeConfirmed(_ id: UUID) throws {
        guard try read(id).receipt != nil else { throw Failure.unconfirmed }
        try FileManager.default.removeItem(at: path(id))
    }
    func lock() { key = nil }
}
