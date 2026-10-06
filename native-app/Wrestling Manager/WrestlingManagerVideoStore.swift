import Foundation
@preconcurrency import AVFoundation

@MainActor
final class WrestlingManagerVideoStore {
    enum Failure: LocalizedError {
        case invalid, storage, missing, unplayable, timelineFull
        nonisolated var errorDescription: String? {
            switch self {
            case .invalid: return "This recording request is not valid. Reopen the match."
            case .storage: return "Not enough free device storage. Export older recordings and free space first."
            case .missing: return "The recording or score history could not be read. Existing files were kept."
            case .unplayable: return "Playback could not be verified. The original files were kept for recovery."
            case .timelineFull: return "The score history reached this pilot's storage limit. Recording stopped."
            }
        }
    }
    private let fm = FileManager.default
    private(set) var root: URL
    init() throws {
        root = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("WrestlingManager/VideoPilot/v1", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }
    func requireSpace() throws {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values.volumeAvailableCapacityForImportantUsage, free >= 512 * 1024 * 1024 else { throw Failure.storage }
    }
    func directory(_ id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id.lowercased() else { throw Failure.invalid }
        return root.appendingPathComponent(uuid.uuidString.lowercased(), isDirectory: true)
    }
    func movie(_ id: String) throws -> URL { try directory(id).appendingPathComponent("original.mov") }
    func timeline(_ id: String) throws -> URL { try directory(id).appendingPathComponent("timeline.json") }
    func read(_ id: String, user: String, team: String) throws -> [String: Any] {
        let file = try timeline(id)
        let size = (try fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= 16 * 1024 * 1024,
              let row = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
              row["id"] as? String == id, row["userId"] as? String == user, row["teamId"] as? String == team else { throw Failure.missing }
        return row
    }
    func write(_ row: [String: Any]) throws {
        guard let id = row["id"] as? String else { throw Failure.invalid }
        let bytes = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        guard bytes.count <= 16 * 1024 * 1024 else { throw Failure.timelineFull }
        try bytes.write(to: timeline(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func create(state: [String: Any], user: String, team: String) throws -> [String: Any] {
        try requireSpace()
        let id = UUID().uuidString.lowercased()
        try fm.createDirectory(at: directory(id), withIntermediateDirectories: false,
                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let row: [String: Any] = ["schema": 1, "id": id, "teamId": team, "userId": user,
            "boutId": state["bout_id"] ?? NSNull(), "matchId": state["id"] ?? "", "athleteIds": [state["red_id"], state["other_id"]].compactMap { $0 as? String },
            "label": "\((state["red_name"] as? String) ?? "Red") vs \((state["other_name"] as? String) ?? "Opponent")",
            "demo": state["book_type"] as? String == "test", "mime": "video/quicktime",
            "createdAt": ISO8601DateFormatter().string(from: Date()), "status": "recording",
            "durationMs": 0, "bytes": 0, "events": [], "reason": ""]
        try write(row); return row
    }
    func list(user: String, team: String) throws -> [[String: Any]] {
        try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url in
            guard let row = try? read(url.lastPathComponent, user: user, team: team) else { return nil }
            return summary(row)
        }.sorted { (($0["createdAt"] as? String) ?? "") > (($1["createdAt"] as? String) ?? "") }
    }
    func summary(_ row: [String: Any]) -> [String: Any] {
        var result = row.filter { ["id", "matchId", "label", "demo", "status", "createdAt", "durationMs", "bytes", "reason", "boutId", "upload", "scoreOverlay"].contains($0.key) }
        if ["ready", "partial"].contains((row["status"] as? String) ?? ""), let overlay = row["scoreOverlay"] as? [String: Any] {
            let explanation = overlay["status"] as? String == "ready" ? "Permanent score overlay ready. Export the scored video to keep scores outside the app." : "Original video saved. Scored copy is pending; open Replay & export, then Export scored video to retry."
            result["reason"] = [row["reason"] as? String ?? "", explanation].filter { !$0.isEmpty }.joined(separator: " ")
        }
        return result
    }
    func verify(_ id: String) async throws -> (Double, Int64) {
        try await verifyVideo(at: movie(id))
    }
    func verifyVideo(at url: URL) async throws -> (Double, Int64) {
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard playable, duration.isFinite, duration > 0, !tracks.isEmpty else { throw Failure.unplayable }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        for seconds in [min(0.1, duration / 2), duration / 2, max(0, duration - 0.1)] {
            _ = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        }
        let bytes = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard bytes > 0 else { throw Failure.unplayable }
        return (duration * 1000, bytes)
    }
    func remove(_ id: String, user: String, team: String) throws {
        _ = try read(id, user: user, team: team)
        try fm.removeItem(at: directory(id))
    }
}

@MainActor
func wrestlingVideoScoreText(_ state: [String: Any], elapsedMs: Double = 0) -> String {
    var red = 0.0, other = 0.0
    for event in (state["ledger"] as? [[String: Any]]) ?? [] where event["voided"] as? Bool != true {
        let points = (event["points"] as? NSNumber)?.doubleValue ?? 0
        if event["corner"] as? String == "red" { red += points }
        if event["corner"] as? String == "other" { other += points }
    }
    let remaining = max(0, ((state["remainingMs"] as? Double) ?? 0) - (state["running"] as? Bool == true ? max(0, elapsedMs) : 0))
    let seconds = Int(ceil(remaining / 1000))
    let phase = (state["phaseLabel"] as? String) ?? ""
    return "\(String(((state["red_name"] as? String) ?? "Red").prefix(55)))  \(Int(red))   •   \(Int(other))  \(String(((state["other_name"] as? String) ?? "Opponent").prefix(55)))\n\(phase)   \(seconds / 60):\(String(format: "%02d", seconds % 60))"
}
