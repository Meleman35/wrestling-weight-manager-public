import Foundation

// Shared by the real bridge and executable Foundation tests. No credentials,
// identity or completion supplied by JavaScript are trusted as server evidence.
enum WrestlingManagerDeletionReceipt {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func fail(_ message: String) -> Failure { Failure(message: message) }
    // Only fixed stage labels and numeric error codes reach the UI. Never expose
    // NSError.userInfo, URLs, paths, credentials or raw provider responses.
    enum Checkpoint: String {
        case request = "checking the request"
        case account = "checking the signed-in account"
        case authentication = "verifying sign-in with the server"
        case journal = "checking the saved deletion request"
        case deviceFiles = "opening this app's saved files"
        case legacyFiles = "checking shared Mat Mode and export files"
        case savedLogins = "checking saved Face ID sign-ins"
        case recordings = "checking local recordings"
        case confirmation = "showing the phone confirmation"
        case saveRequest = "saving the deletion request securely"
        case submit = "submitting the deletion request"
        case recover = "checking server deletion status"
        case verify = "verifying server completion"
        case cleanup = "finishing this account's device cleanup"
        case acknowledge = "saving the completion receipt"
    }
    static func diagnostic(_ error: Error, checkpoint: Checkpoint) -> String {
        if let known = error as? Failure { return known.message }
        if let known = error as? WrestlingManagerAccountCleanupPolicy.Failure { return known.message }
        let value = error as NSError
        let category: String
        switch value.domain {
        case NSURLErrorDomain: category = "network"
        case NSCocoaErrorDomain: category = "device file"
        case NSPOSIXErrorDomain: category = "device storage"
        case "WKErrorDomain": category = "app screen"
        default: category = "app"
        }
        return "Deletion stopped while \(checkpoint.rawValue). Reference: \(category) \(value.code)."
    }
    static func uuid(_ value: String) throws -> String {
        let canonical = try WrestlingManagerAccountCleanupPolicy.account(value)
        guard value == canonical else { throw fail("The deletion identifier is invalid.") }
        return canonical
    }
    struct Request: Codable, Equatable {
        let requestId: String
        let actorId: String
        let personal: Bool
        let kind: String
        let teamIds: [String]
        let organizationIds: [String]
        let receipt: String

        func validated() throws -> Self {
            _ = try uuid(requestId); _ = try uuid(actorId)
            guard ["personal", "team", "organization", "all"].contains(kind),
                  personal == ["personal", "all"].contains(kind),
                  receipt.utf8.count == 64, receipt.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  teamIds.count <= 100, organizationIds.count <= 100,
                  Set(teamIds).count == teamIds.count, Set(organizationIds).count == organizationIds.count else {
                throw fail("The saved deletion request is invalid. No local data was removed.")
            }
            for id in teamIds + organizationIds { _ = try uuid(id) }
            guard kind != "personal" || (teamIds.isEmpty && organizationIds.isEmpty),
                  kind != "team" || (teamIds.count == 1 && organizationIds.isEmpty),
                  kind != "organization" || (organizationIds.count == 1 && teamIds.isEmpty) else {
                throw fail("The deletion selection does not match its scope.")
            }
            return self
        }
    }
    enum Stage: String, Codable { case prepared, serverCompleted, nativeCleaned }
    struct Job: Codable, Equatable {
        let request: Request
        let recordingIDs: [String]
        var stage: Stage
        var serverJobID: String?
        var loginEmailHash: String?
        func validated() throws -> Self {
            _ = try request.validated()
            guard recordingIDs.count <= 10000, Set(recordingIDs).count == recordingIDs.count,
                  request.personal || recordingIDs.isEmpty else { throw fail("Saved device cleanup needs review.") }
            for id in recordingIDs { _ = try uuid(id) }
            if let serverJobID { _ = try uuid(serverJobID) }
            guard stage == .prepared || serverJobID != nil else { throw fail("The server completion record is missing.") }
            return self
        }
    }
    struct Journal: Codable, Equatable {
        var version = 1
        var jobs: [String: Job] = [:]
        var completed: [String: Completion] = [:]
        // Only a SHA256 of the departed UUID remains after acknowledgement.
        var departedSubjects: Set<String> = []
        func validated() throws -> Self {
            guard version == 1, jobs.count <= 30,
                  departedSubjects.allSatisfy({ $0.count == 64 && $0.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) }) else {
                throw fail("Saved deletion status needs review. No local data was removed.")
            }
            for (key, job) in jobs {
                _ = try job.validated()
                guard key == job.request.requestId else { throw fail("Saved deletion request mismatch.") }
            }
            for (key, proof) in completed {
                _ = try uuid(key); _ = try uuid(proof.id)
                guard proof.state == "completed", proof.subjectHash.count == 64 else { throw fail("Saved completion needs review.") }
            }
            return self
        }
        mutating func prepare(_ job: Job) throws {
            _ = try job.validated()
            if let old = jobs[job.request.requestId] {
                guard old.request == job.request else { throw fail("Resume the original deletion selection.") }
                return // Never expand an existing device-file selection on retry.
            }
            guard !jobs.values.contains(where: { $0.request.actorId == job.request.actorId }) else {
                throw fail("Resume this account's existing deletion request first.")
            }
            jobs[job.request.requestId] = job
            _ = try validated()
        }
    }
    struct Completion: Codable, Equatable {
        let id: String
        let state: String
        let personal: Bool
        let subjectHash: String
    }
    static func verifyCompletion(_ data: Data, status: Int, job: Job, expectedHash: String) throws -> Completion {
        _ = try job.validated()
        guard status == 200, data.count <= 65536,
              let proof = try? JSONDecoder().decode(Completion.self, from: data),
              proof.state == "completed", proof.personal == job.request.personal,
              proof.subjectHash == expectedHash, (try? uuid(proof.id)) != nil,
              job.serverJobID == nil || job.serverJobID == proof.id else {
            throw fail("The server has not confirmed completion for this account. Resume the same request.")
        }
        return proof
    }
}

// Legacy Mat Mode files are shared and have no reliable per-account inventory.
// Block this pilot before sending a deletion request; never wipe the shared store.
enum WrestlingManagerDeletionLegacyGuard {
    static func check(support: URL, temporary: URL) throws {
        let fm = FileManager.default
        let records = support.appendingPathComponent("OfflineMat/records.json")
        do {
            let attributes = try fm.attributesOfItem(atPath: records.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 24 * 1024 * 1024,
                  let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: records)) as? [String: String],
                  saved.isEmpty else {
                throw WrestlingManagerDeletionReceipt.fail("This device has shared Mat Mode records that need review before in-app deletion. Your saved bouts have been kept.")
            }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { }
        for file in try fm.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil) {
            if ["WM-WeighIn-", "Mat-Share-"].contains(where: { file.lastPathComponent.hasPrefix($0) }) {
                throw WrestlingManagerDeletionReceipt.fail("Close the shared export and restart the app before deletion. A temporary shared file needs review.")
            }
        }
    }
}

// Explicit device-local Mat Mode reset. This is separate from account deletion:
// it never clears account storage, exported files, media, PINs or deletion receipts.
enum WrestlingManagerMatTestReset {
    static let keys: Set<String> = ["wm-mat-session", "wm-mat-history", "wm-mat-recovery", "wm-nearby-v1", "wm-nearby-pending-v1"]
    struct Snapshot {
        let bytes: Data
        let values: [String: String]
    }
    static func snapshot(folder: URL) throws -> Snapshot {
        let fm = FileManager.default
        guard folder.lastPathComponent == "OfflineMat",
              try fm.attributesOfItem(atPath: folder.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw WrestlingManagerDeletionReceipt.fail("The local Mat Mode folder needs review. Nothing was cleared.")
        }
        let file = folder.appendingPathComponent("records.json")
        let attributes = try fm.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 24 * 1024 * 1024 else {
            throw WrestlingManagerDeletionReceipt.fail("The local Mat Mode file needs review. Nothing was cleared.")
        }
        let bytes = try Data(contentsOf: file)
        guard bytes.count <= 24 * 1024 * 1024,
              let values = try? JSONDecoder().decode([String: String].self, from: bytes),
              values.keys.allSatisfy({ keys.contains($0) }) else {
            throw WrestlingManagerDeletionReceipt.fail("The local Mat Mode backup could not be verified. Nothing was cleared.")
        }
        return Snapshot(bytes: bytes, values: values)
    }
    static func requireUnchanged(folder: URL, reviewed: Snapshot) throws {
        guard try snapshot(folder: folder).bytes == reviewed.bytes else {
            throw WrestlingManagerDeletionReceipt.fail("Mat Mode changed while the prompt was open. Review Saved bouts and try again.")
        }
    }
    // Call only after the exit PIN, typed confirmation, and browser-store clear
    // have succeeded, with the coordinator refusing further backup writes.
    static func clear(folder: URL, reviewed: Snapshot) throws {
        try requireUnchanged(folder: folder, reviewed: reviewed)
        let file = folder.appendingPathComponent("records.json")
        #if os(iOS)
        try Data("{}".utf8).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try Data("{}".utf8).write(to: file, options: .atomic)
        #endif
        guard try snapshot(folder: folder).values.isEmpty else {
            throw WrestlingManagerDeletionReceipt.fail("Mat Mode clearing could not be confirmed. Reopen Mat Mode before retrying deletion.")
        }
    }
}
