import Foundation

// Invoked only by the native deletion coordinator after an independent server
// completion lookup, immutable device-file review and durable account revocation.
// No sign-out, profile selection or web-supplied UUID can call this adapter alone.
@MainActor
enum WrestlingManagerAccountCleanup {
    struct PartialResult {
        let removedRecordings: [String]
        let alreadyAbsentRecordings: [String]
        let remainingAccountRecordings: Int
        let removedBiometricLogins: Int
        let unresolvedBiometricItems: Int
        // No `complete` flag: this covers only credentials and approved video files.
        // Offline Mat, WebKit, exports and server records are outside this adapter.
    }
    static func removeReviewedLocalItems(accountID: String, approvedRecordingIDs: Set<String>,
                                         video: WrestlingManagerVideoPilot,
                                         biometric: WrestlingManagerBiometricLoginBridge,
                                         recovery: WrestlingManagerPINRecoveryBridge) throws -> PartialResult {
        let account = try WrestlingManagerAccountCleanupPolicy.account(accountID)
        guard let remoteAccount = UUID(uuidString: account) else { throw WrestlingManagerRemoteOutbox.Failure.wrongScope }
        return try video.withQuiescentAccountCleanup { root in
            recovery.cancel()
            try WrestlingManagerRemoteOutbox.removeForAccountDeletion(remoteAccount)
            let media = try WrestlingManagerAccountVideoCleanup(root: root)
                .removeReviewed(accountID: account, recordingIDs: approvedRecordingIDs)
            let login = try biometric.removeForAccountCleanup(account)
            try WrestlingManagerProfilePIN.removeForAccountCleanup(account)
            return PartialResult(removedRecordings: media.removedIDs, alreadyAbsentRecordings: media.alreadyAbsentIDs,
                                 remainingAccountRecordings: media.remainingAccountRecordings,
                                 removedBiometricLogins: login.removedCount,
                                 unresolvedBiometricItems: login.unresolvedLegacyItems)
        }
    }
}
