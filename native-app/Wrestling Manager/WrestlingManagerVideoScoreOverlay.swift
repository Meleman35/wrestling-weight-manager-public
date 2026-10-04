import UIKit
import CryptoKit
@preconcurrency import AVFoundation

// Render a SECOND movie from the protected original + timestamped score ledger.
// No capture control, referee decision, privacy grant, or source movie is changed.
@MainActor
final class WrestlingManagerVideoScoreOverlay {
    struct Failure: LocalizedError {
        let message: String
        nonisolated var errorDescription: String? { message }
    }
    private var session: AVAssetExportSession?
    private var cancelled = false
    private var preparing = false
    func cancel() { cancelled = true; session?.cancelExport() }

    static func fingerprint(_ row: [String: Any]) throws -> String {
        let values: [String: Any] = ["renderer": 1, "id": row["id"] ?? "", "events": row["events"] ?? [], "durationMs": row["durationMs"] ?? 0]
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func cachedURL(row: [String: Any], store: WrestlingManagerVideoStore) throws -> URL? {
        guard let id = row["id"] as? String,
              let info = row["scoreOverlay"] as? [String: Any], info["status"] as? String == "ready",
              let signature = info["timelineSHA256"] as? String, signature == (try fingerprint(row)),
              let name = info["file"] as? String, name == "scored-v1-" + String(signature.prefix(16)) + ".mp4" else { return nil }
        let url = try store.directory(id).appendingPathComponent(name)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else { return nil }
        return url
    }
    private func check() throws {
        if cancelled || Task.isCancelled || UIApplication.shared.applicationState != .active {
            throw Failure(message: "Score rendering paused. The original video and score history are safe; reopen Replay to retry.")
        }
    }
    func prepare(row source: [String: Any], store: WrestlingManagerVideoStore) async throws -> [String: Any] {
        guard !preparing, session == nil, let id = source["id"] as? String else { throw Failure(message: "A scored video is already being prepared.") }
        preparing = true
        let activity = WrestlingManagerVideoActivity.begin()
        defer { preparing = false; WrestlingManagerVideoActivity.end(activity) }
        cancelled = false
        try check()
        if let cached = try Self.cachedURL(row: source, store: store) {
            _ = try await store.verifyVideo(at: cached)
            return source
        }
        let original = try store.movie(id)
        let asset = AVURLAsset(url: original)
        let assetDuration = try await asset.load(.duration)
        let videos = try await asset.loadTracks(withMediaType: .video)
        guard let video = videos.first else { throw Failure(message: "The source movie has no video track. Original files were kept.") }
        let videoRange = try await video.load(.timeRange)
        let duration = min(assetDuration.seconds, CMTimeRangeGetEnd(videoRange).seconds)
        guard duration.isFinite, duration > 0, duration <= 1202 else { throw Failure(message: "The source movie duration could not be verified.") }
        let entries = WrestlingVideoScoreTimeline.entries(source, duration: duration)
        guard entries.first?.seconds == 0, entries.count <= 512 else {
            throw Failure(message: "A complete starting score history is required for a scored copy. The original video remains available.")
        }
        let size = try await video.load(.naturalSize)
        let preferredTransform = try await video.load(.preferredTransform)
        let transformed = CGRect(origin: .zero, size: size).applying(preferredTransform)
        let renderSize = CGSize(width: ceil(abs(transformed.width) / 2) * 2, height: ceil(abs(transformed.height) / 2) * 2)
        guard renderSize.width >= 100, renderSize.height >= 100, renderSize.width <= 4096, renderSize.height <= 4096 else {
            throw Failure(message: "The movie dimensions are unsupported. The original was kept.")
        }
        let originalBytes = (try original.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let free = try store.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        // Reserve enough space for a second complete file and a safety margin; never remove the original to make room.
        guard free >= max(Int64(512 * 1024 * 1024), Int64(originalBytes) * 2 + 256 * 1024 * 1024) else {
            throw Failure(message: "Free more device space to create the scored copy. Your original recording is safe.")
        }
        try check()
        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure(message: "Could not prepare the scored movie.")
        }
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        try compositionVideo.insertTimeRange(range, of: video, at: .zero)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for audio in audioTracks {
            let audioRange = try await audio.load(.timeRange)
            let intersection = CMTimeRangeGetIntersection(range, otherRange: audioRange)
            if intersection.duration.seconds > 0, let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try target.insertTimeRange(intersection, of: audio, at: intersection.start)
            }
        }
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideo)
        let normalized = preferredTransform.concatenating(CGAffineTransform(translationX: -transformed.minX, y: -transformed.minY))
        layerInstruction.setTransform(normalized, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range; instruction.layerInstructions = [layerInstruction]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer(); videoLayer.frame = parent.bounds; parent.addSublayer(videoLayer)
        let width = min(360, max(210, renderSize.width * 0.30))
        let badgeSize = CGSize(width: width, height: width * 0.30)
        let badge = CALayer()
        let inset = max(12, renderSize.width * 0.015)
        // Core Animation's export coordinate system has its origin at the bottom left.
        badge.frame = CGRect(x: inset, y: renderSize.height - inset - badgeSize.height, width: badgeSize.width, height: badgeSize.height)
        badge.contentsGravity = .resize; badge.contentsScale = 1
        let images = entries.map { Self.image($0.frame, size: badgeSize).cgImage! }
        badge.contents = images.last
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = images + [images.last!]
        animation.keyTimes = entries.map { NSNumber(value: min(1, $0.seconds / duration)) } + [NSNumber(value: 1.0)]
        animation.calculationMode = .discrete
        animation.duration = duration; animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false; animation.fillMode = .both
        badge.add(animation, forKey: "timestampedScore")
        parent.addSublayer(badge)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)

        let signature = try Self.fingerprint(source)
        let filename = "scored-v1-" + String(signature.prefix(16)) + ".mp4"
        let folder = try store.directory(id)
        let temporary = folder.appendingPathComponent("score-work-" + UUID().uuidString + ".mp4")
        let output = folder.appendingPathComponent(filename)
        // Only this operation's incomplete derived file can be removed; never a source or existing exported copy.
        defer { try? FileManager.default.removeItem(at: temporary); session = nil }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality), export.supportedFileTypes.contains(.mp4) else {
            throw Failure(message: "This device cannot prepare the scored MP4. The original video was kept.")
        }
        export.outputURL = temporary; export.outputFileType = .mp4
        export.videoComposition = videoComposition; export.shouldOptimizeForNetworkUse = true
        session = export
        try check()
        // The SDK completion is @Sendable; AVAssetExportSession is not.
        // Capture only the Sendable continuation in that callback. Resuming it
        // returns to this @MainActor method before status/error are inspected.
        // Keep the completion-based API for the existing iOS 17.6 target.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously {
                continuation.resume()
            }
        }
        guard export.status == .completed else {
            throw Failure(message: export.error?.localizedDescription ?? "Score rendering was interrupted. Original files were kept.")
        }
        try check()
        let (outputMs, _) = try await store.verifyVideo(at: temporary)
        guard abs(outputMs / 1000 - duration) <= 0.25 else { throw Failure(message: "The scored movie duration did not match. The original video was kept.") }
        if !audioTracks.isEmpty {
            guard !(try await AVURLAsset(url: temporary).loadTracks(withMediaType: .audio)).isEmpty else {
                throw Failure(message: "The scored copy lost its audio track. The original video was kept.")
            }
        }
        try check()
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        if FileManager.default.fileExists(atPath: output.path) {
            // A crash may have left a verified derived movie before metadata was committed. Do not replace it blindly.
            let (existingMs, _) = try await store.verifyVideo(at: output)
            guard abs(existingMs - outputMs) <= 250 else { throw Failure(message: "An existing scored copy needs review. The original and existing copy were preserved.") }
        } else { try FileManager.default.moveItem(at: temporary, to: output) }
        let (savedMs, savedBytes) = try await store.verifyVideo(at: output)
        try check()
        var row = source
        row["scoreOverlay"] = ["status": "ready", "renderer": 1, "file": filename, "timelineSHA256": signature,
                               "bytes": savedBytes, "durationMs": savedMs, "mime": "video/mp4"]
        try store.write(row)
        return row
    }

    static func image(_ frame: WrestlingVideoScoreFrame, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rowHeight = size.height * 0.39, captionHeight = size.height - 2 * rowHeight
            let colors = [UIColor(red: 0.67, green: 0.06, blue: 0.14, alpha: 0.96), frame.otherIsGreen ? UIColor(red: 0.03, green: 0.40, blue: 0.23, alpha: 0.96) : UIColor(red: 0.06, green: 0.26, blue: 0.68, alpha: 0.96)]
            let names = [frame.redName, frame.otherName], labels = ["RED", frame.otherIsGreen ? "GREEN" : "BLUE"], values = [frame.red, frame.other]
            for i in 0..<2 {
                let y = CGFloat(i) * rowHeight
                colors[i].setFill(); UIBezierPath(rect: CGRect(x: 0, y: y, width: size.width, height: rowHeight)).fill()
                let small = rowHeight * 0.25
                draw(labels[i], rect: CGRect(x: 9, y: y + 4, width: size.width - 64, height: small + 2), font: .systemFont(ofSize: small, weight: .bold))
                draw(names[i], rect: CGRect(x: 9, y: y + rowHeight * 0.41, width: size.width - 66, height: rowHeight * 0.53), font: .systemFont(ofSize: rowHeight * 0.38, weight: .semibold))
                draw(String(values[i]), rect: CGRect(x: size.width - 61, y: y + rowHeight * 0.13, width: 53, height: rowHeight * 0.8), font: .monospacedDigitSystemFont(ofSize: rowHeight * 0.66, weight: .bold), alignment: .right)
            }
            UIColor.black.withAlphaComponent(0.86).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: rowHeight * 2, width: size.width, height: captionHeight)).fill()
            draw(frame.caption, rect: CGRect(x: 9, y: rowHeight * 2 + 3, width: size.width - 18, height: captionHeight - 3), font: .systemFont(ofSize: captionHeight * 0.58, weight: .semibold))
        }
    }
    private static func draw(_ text: String, rect: CGRect, font: UIFont, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; paragraph.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
    }
}
