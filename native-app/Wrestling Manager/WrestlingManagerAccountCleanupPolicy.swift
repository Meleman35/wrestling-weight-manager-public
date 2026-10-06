import Foundation
import CoreFoundation

// Scope selection only. This is NOT authentication or approval to delete an account.
// The native coordinator verifies the server subject and persists the exact reviewed
// video IDs before intake. These primitives are not directly exposed to JavaScript.
enum WrestlingManagerAccountCleanupPolicy {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func account(_ value: String) throws -> String {
        guard let id = UUID(uuidString: value), value.lowercased() == id.uuidString.lowercased() else {
            throw Failure(message: "The cleanup account or recording identifier is invalid.")
        }
        return id.uuidString.lowercased()
    }
    static func ownerTag(_ accountID: String) throws -> Data {
        Data(("wm.owner.v1:" + (try account(accountID))).utf8)
    }
    static func owner(_ tag: Data?) -> String? {
        guard let tag, let text = String(data: tag, encoding: .utf8), text.hasPrefix("wm.owner.v1:"),
              let id = try? account(String(text.dropFirst("wm.owner.v1:".count))),
              text == "wm.owner.v1:" + id else { return nil }
        return id
    }
    struct BiometricItem {
        let slot: String
        let reference: Data
        let ownerTag: Data?
    }
    struct BiometricPlan {
        let matching: [BiometricItem]
        let unresolvedCount: Int
    }
    static func biometricPlan(accountID: String, items: [BiometricItem]) throws -> BiometricPlan {
        let id = try account(accountID)
        guard Set(items.map(\.slot)).count == items.count,
              Set(items.map(\.reference)).count == items.count,
              items.allSatisfy({ !$0.slot.isEmpty && !$0.reference.isEmpty }) else {
            throw Failure(message: "Saved-login ownership could not be checked. Existing logins were kept.")
        }
        return BiometricPlan(matching: items.filter { owner($0.ownerTag) == id },
                             unresolvedCount: items.filter { owner($0.ownerTag) == nil }.count)
    }
}

// Counts work until its async body actually returns, including cancellation cleanup.
// Shared across renderer instances, including a replay that has already been dismissed.
@MainActor
enum WrestlingManagerVideoActivity {
    private static var tickets = Set<UUID>()
    static var isBusy: Bool { !tickets.isEmpty }
    static func begin() -> UUID { let id = UUID(); tickets.insert(id); return id }
    static func end(_ id: UUID) { tickets.remove(id) }
}

// Strict inventory of this app's private VideoPilot/v1 directory, across all teams.
// Other accounts, unapproved recordings and external exports are never removed.
// Missing/corrupt ownership metadata blocks this operation; it is not treated as empty.
@MainActor
struct WrestlingManagerAccountVideoCleanup {
    typealias Failure = WrestlingManagerAccountCleanupPolicy.Failure
    private struct Record {
        let id: String
        let owner: String
        let manifest: Data
        let inode: UInt64
        let device: UInt64
    }
    struct Result {
        let removedIDs: [String]
        let alreadyAbsentIDs: [String]
        let remainingAccountRecordings: Int
    }
    let root: URL
    private let fm = FileManager.default
    private func checkedDirectory(_ url: URL) throws -> [FileAttributeKey: Any] {
        let attributes = try fm.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw Failure(message: "Recording storage contains an unexpected path. Files were kept.")
        }
        return attributes
    }
    private func inventory() throws -> [String: Record] {
        _ = try checkedDirectory(root)
        var result: [String: Record] = [:]
        for directory in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let name = directory.lastPathComponent
            let id = try WrestlingManagerAccountCleanupPolicy.account(name)
            guard id == name else { throw Failure(message: "Recording folder ownership needs review.") }
            let attributes = try checkedDirectory(directory)
            guard let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
                  let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value else {
                throw Failure(message: "Recording folder identity could not be verified.")
            }
            // The current video format is flat. Do not traverse unknown directories,
            // symlinks, aliases or multiply-linked files, even inside an approved take.
            for file in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let properties = try fm.attributesOfItem(atPath: file.path)
                guard properties[.type] as? FileAttributeType == .typeRegular,
                      (properties[.referenceCount] as? NSNumber)?.intValue == 1 else {
                    throw Failure(message: "Recording storage has an unrecognized file. Files were kept.")
                }
            }
            let manifestURL = directory.appendingPathComponent("timeline.json")
            let size = (try fm.attributesOfItem(atPath: manifestURL.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= 16 * 1024 * 1024 else {
                throw Failure(message: "A recording's ownership record is missing or too large. Files were kept.")
            }
            let manifest = try Data(contentsOf: manifestURL)
            guard let row = try JSONSerialization.jsonObject(with: manifest) as? [String: Any],
                  let schema = row["schema"] as? NSNumber, CFGetTypeID(schema) != CFBooleanGetTypeID(), schema.stringValue == "1",
                  row["id"] as? String == id,
                  let user = row["userId"] as? String, let owner = try? WrestlingManagerAccountCleanupPolicy.account(user),
                  let team = row["teamId"] as? String, (try? WrestlingManagerAccountCleanupPolicy.account(team)) != nil else {
                throw Failure(message: "A recording's ownership could not be verified. Files were kept.")
            }
            result[id] = Record(id: id, owner: owner, manifest: manifest, inode: inode, device: device)
        }
        return result
    }
    // Synchronous and called only inside VideoPilot.withQuiescentAccountCleanup on
    // the main actor. There is deliberately no await between inventory and removal.
    func reviewedIDs(accountID: String) throws -> [String] {
        let account = try WrestlingManagerAccountCleanupPolicy.account(accountID)
        return try inventory().values.filter { $0.owner == account }.map(\.id).sorted()
    }
    func removeReviewed(accountID: String, recordingIDs: Set<String>) throws -> Result {
        let owner = try WrestlingManagerAccountCleanupPolicy.account(accountID)
        let ids = try Set(recordingIDs.map { try WrestlingManagerAccountCleanupPolicy.account($0) })
        let before = try inventory()
        for id in ids {
            if let record = before[id], record.owner != owner {
                throw Failure(message: "An approved recording belongs to another account. Files were kept.")
            }
        }
        // Recheck the complete inventory before the first destructive operation.
        let current = try inventory()
        guard Set(current.keys) == Set(before.keys), before.allSatisfy({ id, record in
            guard let now = current[id] else { return false }
            return now.manifest == record.manifest && now.inode == record.inode && now.device == record.device
        }) else { throw Failure(message: "Recordings changed during cleanup. Retry after video work finishes.") }
        var removed: [String] = []
        for id in ids.sorted() where current[id] != nil {
            let directory = root.appendingPathComponent(id, isDirectory: true)
            try fm.removeItem(at: directory)
            // attributesOfItem distinguishes absence from access or I/O errors.
            do {
                _ = try fm.attributesOfItem(atPath: directory.path)
                throw Failure(message: "A recording remained after cleanup. Cleanup is incomplete.")
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                removed.append(id)
            }
        }
        let after = try inventory()
        guard ids.allSatisfy({ after[$0] == nil }) else {
            throw Failure(message: "A recording returned during cleanup. Cleanup is incomplete.")
        }
        return Result(removedIDs: removed, alreadyAbsentIDs: ids.filter { before[$0] == nil }.sorted(),
                      remainingAccountRecordings: after.values.filter { $0.owner == owner }.count)
    }
}
