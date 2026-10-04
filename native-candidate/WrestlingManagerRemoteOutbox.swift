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
    private static let coordination = NSRecursiveLock()
    private static let revokedService = "com.damonmele.wrestlingmanager.remote-outbox.departed.v1"
    private static let service = "com.damonmele.wrestlingmanager.remote-outbox.v1"
    private let maxBytes = 32 * 1024 * 1024
    private let maxEntries = 200

    init(accountID: UUID, clubID: UUID, now: @escaping @Sendable () -> Date = { Date() }) throws {
        Self.coordination.lock(); defer { Self.coordination.unlock() }
        try Self.requireActiveAccount(accountID)
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
    private func requireKey() throws -> SymmetricKey { try Self.requireActiveAccount(accountID); guard let key else { throw Failure.locked }; return key }
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
        Self.coordination.lock(); defer { Self.coordination.unlock() }
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
        Self.coordination.lock(); defer { Self.coordination.unlock() }
        _ = try requireKey()
        var ids: [UUID] = []
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where url.pathExtension == "sealed" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw Failure.conflict }
            do { _ = try read(id); ids.append(id) }
            catch Failure.expired { continue }
        }
        return ids.sorted { $0.uuidString < $1.uuidString }
    }
    func capture(_ id: UUID) throws -> Capture {
        Self.coordination.lock(); defer { Self.coordination.unlock() }
        return try read(id)
    }
    private static func receiptDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: text) { return date }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: text)
    }
    func confirm(_ id: UUID, receipt: Data) throws {
        Self.coordination.lock(); defer { Self.coordination.unlock() }
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
        Self.coordination.lock(); defer { Self.coordination.unlock() }
        guard try read(id).receipt != nil else { throw Failure.unconfirmed }
        try FileManager.default.removeItem(at: path(id))
    }
    func lock() { key = nil }
    private static func accountMarker(_ accountID: UUID) -> [String: Any] {
        let digest = SHA256.hash(data: Data(accountID.uuidString.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:revokedService,kSecAttrAccount as String:digest]
    }
    private static func requireActiveAccount(_ accountID: UUID) throws {
        let status = SecItemCopyMatching(accountMarker(accountID) as CFDictionary, nil)
        guard status == errSecItemNotFound else { throw status == errSecSuccess ? Failure.locked : Failure.keyUnavailable }
    }
    private struct OwnedFolder { let scope: String; let folder: URL; let files: [URL] }
    private static func accountFolders(_ accountID: UUID) throws -> [OwnedFolder] {
        let fm = FileManager.default
        let support = try fm.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:false)
        let base = support.appendingPathComponent("RemoteWeighInOutbox",isDirectory:true)
        if fm.fileExists(atPath:base.path) {
            guard try fm.attributesOfItem(atPath:base.path)[.type] as? FileAttributeType == .typeDirectory else { throw Failure.conflict }
        }
        var result: CFTypeRef?
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
            kSecReturnAttributes as String:true,kSecMatchLimit as String:kSecMatchLimitAll]
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keyUnavailable }
        let entries: [[String:Any]]
        if status == errSecItemNotFound { entries = [] }
        else if let found = result as? [[String:Any]] { entries = found }
        else { throw Failure.keyUnavailable }
        var owned: [OwnedFolder] = []
        var knownFolders: Set<String> = []
        for entry in entries {
            guard let scope = entry[kSecAttrAccount as String] as? String else { throw Failure.conflict }
            let parts = scope.split(separator:":",omittingEmptySubsequences:false)
            guard parts.count == 2, let owner = UUID(uuidString:String(parts[0])), let club = UUID(uuidString:String(parts[1])),
                  scope == "\(owner.uuidString):\(club.uuidString)" else { throw Failure.conflict }
            let digest = SHA256.hash(data:Data(scope.utf8)).map { String(format:"%02x",$0) }.joined()
            knownFolders.insert(digest)
            guard owner == accountID else { continue }
            let folder = base.appendingPathComponent(digest,isDirectory:true)
            var files: [URL] = []
            if fm.fileExists(atPath:folder.path) {
                guard try fm.attributesOfItem(atPath:folder.path)[.type] as? FileAttributeType == .typeDirectory else { throw Failure.conflict }
                files = try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
                guard files.count <= 200 else { throw Failure.capacity }
                for file in files {
                    let attributes = try fm.attributesOfItem(atPath:file.path)
                    guard file.pathExtension == "sealed", UUID(uuidString:file.deletingPathExtension().lastPathComponent) != nil,
                          attributes[.type] as? FileAttributeType == .typeRegular,
                          (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else { throw Failure.conflict }
                }
            }
            owned.append(OwnedFolder(scope:scope,folder:folder,files:files))
        }
        if fm.fileExists(atPath:base.path) {
            for folder in try fm.contentsOfDirectory(at:base,includingPropertiesForKeys:nil) where !knownFolders.contains(folder.lastPathComponent) {
                guard try fm.attributesOfItem(atPath:folder.path)[.type] as? FileAttributeType == .typeDirectory,
                      try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).isEmpty else { throw Failure.conflict }
            }
        }
        return owned
    }
    /// Read-only native deletion preflight. No photo bytes or other account IDs escape.
    static func reviewAccountDeletion(_ accountID: UUID) throws -> Int {
        coordination.lock(); defer { coordination.unlock() }
        return try accountFolders(accountID).reduce(0) { $0 + $1.files.count }
    }
    /// Call only after independently verified personal-account deletion. A durable
    /// hashed tombstone rejects old/new queue instances before removing owned files.
    /// The shared synchronous lock prevents a queued save racing this cleanup.
    static func removeForAccountDeletion(_ accountID: UUID) throws {
        coordination.lock(); defer { coordination.unlock() }
        let owned = try accountFolders(accountID)
        var marker = accountMarker(accountID)
        marker[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        marker[kSecValueData as String] = Data([1])
        let marked = SecItemAdd(marker as CFDictionary,nil)
        guard marked == errSecSuccess || marked == errSecDuplicateItem else { throw Failure.keyUnavailable }
        for item in owned {
            if FileManager.default.fileExists(atPath:item.folder.path) {
                // Inventory is strict and there are no awaits between review/removal.
                for file in item.files { try FileManager.default.removeItem(at:file) }
                try FileManager.default.removeItem(at:item.folder)
            }
            let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:item.scope]
            let removed = SecItemDelete(query as CFDictionary)
            guard removed == errSecSuccess || removed == errSecItemNotFound else { throw Failure.keyUnavailable }
        }
        guard try accountFolders(accountID).isEmpty else { throw Failure.conflict }
    }

}
