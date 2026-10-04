import Foundation
@preconcurrency import AVFoundation

// Foreground resumable uploads. The original and timeline are never automatically deleted.
@MainActor
final class WrestlingManagerVideoUpload {
    struct Failure: LocalizedError {
        let message: String
        nonisolated var errorDescription: String? { message }
    }
    private let api = "https://vfocpoyexnjsjpxhhyqr.supabase.co"
    private let storageOrigin = "https://vfocpoyexnjsjpxhhyqr.storage.supabase.co"
    private var task: Task<Void, Never>?
    private var connection: URLSession?
    var isBusy: Bool { task != nil }
    func cancel() { task?.cancel(); connection?.invalidateAndCancel() }

    func enqueue(store: WrestlingManagerVideoStore, id: String, user: String, team: String,
                 token: String, key: String, allowed: @escaping @MainActor () -> Bool,
                 changed: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        let activity = WrestlingManagerVideoActivity.begin()
        task = Task { [weak self] in
            defer { WrestlingManagerVideoActivity.end(activity) }
            guard let owner = self else { return }
            defer { owner.connection?.finishTasksAndInvalidate(); owner.connection = nil; owner.task = nil; changed() }
            var row: [String: Any]?
            do {
                guard allowed(), !Task.isCancelled else { return }
                row = try store.read(id, user: user, team: team)
                guard let original = row, original["boutId"] is String,
                      ["ready", "partial"].contains((original["status"] as? String) ?? ""),
                      (original["upload"] as? [String: Any])?["status"] as? String != "ready" else { return }
                let config = URLSessionConfiguration.ephemeral
                config.urlCache = nil; config.httpCookieStorage = nil; config.timeoutIntervalForRequest = 60
                let session = URLSession(configuration: config, delegate: WrestlingVideoNoRedirect(), delegateQueue: nil)
                owner.connection = session
                let check = { if !allowed() || Task.isCancelled { throw Failure(message: "Upload paused. Return to this account and team with the app open.") } }
                var upload = (original["upload"] as? [String: Any]) ?? [:]
                upload["status"] = "uploading"; upload["error"] = ""; row?["upload"] = upload
                try store.write(row!)
                let score = original.filter { ["schema", "id", "matchId", "athleteIds", "label", "createdAt", "events"].contains($0.key) }
                let scoreData = try JSONSerialization.data(withJSONObject: score, options: [.sortedKeys])
                let scoreURL = try store.directory(id).appendingPathComponent("upload-timeline.json")
                try scoreData.write(to: scoreURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                let plan = try await owner.rpc("prepare", data: ["id": id, "team_id": team, "match_id": original["matchId"] ?? "",
                    "bytes": original["bytes"] ?? 0, "timeline_bytes": scoreData.count, "mime": "video/quicktime",
                    "duration_ms": Int((original["durationMs"] as? Double) ?? 0), "partial": original["status"] as? String == "partial"], session: session, token: token, key: key)
                try check()
                if plan["status"] as? String != "ready" {
                    // Reconcile a completed upload whose final response was lost.
                    let completed = try? await owner.rpc("complete", data: ["id": id, "team_id": team], session: session, token: token, key: key)
                    if completed == nil {
                        for (kind, url, mime, pathKey) in [("video", try store.movie(id), "video/quicktime", "video_path"), ("timeline", scoreURL, "application/json", "timeline_path")] {
                            if plan[kind + "_uploaded"] as? Bool == true { continue }
                            guard let path = plan[pathKey] as? String else { throw Failure(message: "Upload address is missing. Device files were kept.") }
                            upload = try await owner.uploadFile(url, mime: mime, path: path, kind: kind, upload: upload, session: session, token: token, key: key, check: check) { progress in
                                row?["upload"] = progress
                                if let row { try store.write(row) }
                            }
                        }
                        _ = try await owner.rpc("complete", data: ["id": id, "team_id": team], session: session, token: token, key: key)
                    }
                }
                try check()
                try await owner.verifyReady(id: id, team: team, token: token, key: key)
                try check()
                row?["upload"] = ["status": "ready", "verifiedAt": ISO8601DateFormatter().string(from: Date())]
                try store.write(row!)
            } catch {
                if var kept = row {
                    var pending = (kept["upload"] as? [String: Any]) ?? [:]
                    pending["status"] = "waiting"; pending["error"] = error.localizedDescription
                    kept["upload"] = pending; try? store.write(kept)
                }
            }
        }
    }
    private func request(_ url: URL, method: String, token: String, key: String) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        r.httpMethod = method; r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        r.setValue(key, forHTTPHeaderField: "apikey"); return r
    }
    private func rpc(_ action: String, data: [String: Any], session: URLSession, token: String, key: String) async throws -> [String: Any] {
        var r = request(URL(string: api + "/rest/v1/rpc/video_match_request")!, method: "POST", token: token, key: key)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["p_action": action, "p_data": data])
        let (body, response) = try await session.data(for: r)
        guard body.count <= 1024 * 1024, let result = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw Failure(message: "Upload server response could not be read.") }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(message: (result["message"] as? String) ?? "Upload paused. Device files were kept.") }
        return result
    }
    private func safeUploadURL(_ text: String) throws -> URL {
        guard let url = URL(string: text, relativeTo: URL(string: storageOrigin))?.absoluteURL,
              url.scheme == "https", url.host == "vfocpoyexnjsjpxhhyqr.storage.supabase.co",
              url.port == nil || url.port == 443, url.user == nil, url.password == nil,
              url.path.hasPrefix("/storage/v1/upload/resumable/") else { throw Failure(message: "Untrusted upload address. Device files were kept.") }
        return url
    }
    private func uploadFile(_ file: URL, mime: String, path: String, kind: String, upload original: [String: Any], session: URLSession,
                            token: String, key: String, check: () throws -> Void, save: ([String: Any]) throws -> Void) async throws -> [String: Any] {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw Failure(message: "Device file is empty. Original files were kept.") }
        var upload = original, offset: Int64 = 0
        var target: URL? = try (upload[kind] as? String).map { try safeUploadURL($0) }
        if let url = target {
            try check(); var r = request(url, method: "HEAD", token: token, key: key); r.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
            let (_, response) = try await session.data(for: r); try check()
            guard let http = response as? HTTPURLResponse else { throw Failure(message: "Upload could not be resumed.") }
            if [404, 410].contains(http.statusCode) { target = nil; upload.removeValue(forKey: kind); try save(upload) }
            else { guard http.statusCode == 200 || http.statusCode == 204, let value = http.value(forHTTPHeaderField: "Upload-Offset"), let n = Int64(value), n >= 0, n <= size else { throw Failure(message: "Upload could not be resumed. Device files were kept.") }; offset = n }
        }
        if target == nil {
            try check(); var r = request(URL(string: storageOrigin + "/storage/v1/upload/resumable")!, method: "POST", token: token, key: key)
            r.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable"); r.setValue(String(size), forHTTPHeaderField: "Upload-Length")
            let metadata = ["bucketName": "match-video-pilot", "objectName": path, "contentType": mime, "cacheControl": "0"]
            r.setValue(metadata.sorted { $0.key < $1.key }.map { $0.key + " " + Data($0.value.utf8).base64EncodedString() }.joined(separator: ","), forHTTPHeaderField: "Upload-Metadata")
            let (_, response) = try await session.data(for: r); try check()
            guard let http = response as? HTTPURLResponse, http.statusCode == 201, let location = http.value(forHTTPHeaderField: "Location") else { throw Failure(message: "Upload could not start. Device files were kept.") }
            target = try safeUploadURL(location); upload[kind] = target!.absoluteString; try save(upload)
        }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        while offset < size {
            try check(); try handle.seek(toOffset: UInt64(offset))
            guard let chunk = try handle.read(upToCount: 6 * 1024 * 1024), !chunk.isEmpty else { throw Failure(message: "Could not read the next video segment.") }
            var r = request(target!, method: "PATCH", token: token, key: key)
            r.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable"); r.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
            r.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await session.upload(for: r, from: chunk); try check()
            guard let http = response as? HTTPURLResponse, http.statusCode == 204,
                  let value = http.value(forHTTPHeaderField: "Upload-Offset"), Int64(value) == offset + Int64(chunk.count) else { throw Failure(message: "Upload interrupted. It will resume when service returns.") }
            offset += Int64(chunk.count); upload["progress"] = Int(Double(offset) / Double(size) * 100); try save(upload)
        }
        return upload
    }
    func verifyReady(id: String, team: String, token: String, key: String) async throws {
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: WrestlingVideoNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let row = try await rpc("playback", data: ["id": id, "team_id": team], session: session, token: token, key: key)
        guard let path = row["video_path"] as? String, path.hasPrefix(team + "/"), !path.contains("..") else { throw Failure(message: "Cloud copy could not be verified.") }
        var r = request(URL(string: api + "/storage/v1/object/sign/match-video-pilot/" + path)!, method: "POST", token: token, key: key)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = Data("{\"expiresIn\":120}".utf8)
        let (data, response) = try await session.data(for: r)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 65536,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let signed = result["signedURL"] as? String,
              signed.hasPrefix("/object/sign/") else { throw Failure(message: "Cloud playback could not be checked. Keep the device copy.") }
        let asset = AVURLAsset(url: URL(string: api + "/storage/v1" + signed)!)
        guard try await asset.load(.isPlayable) else { throw Failure(message: "Cloud copy is not playable. Keep the device copy.") }
        let generator = AVAssetImageGenerator(asset: asset); generator.maximumSize = CGSize(width: 320, height: 320)
        _ = try await generator.image(at: CMTime(seconds: 0, preferredTimescale: 600))
    }
}
