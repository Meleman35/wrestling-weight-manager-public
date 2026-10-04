import Foundation

/// Native-only evidence state. Host supplies authorized scope and real BLE callbacks.
/// This type does not authorize an operator or certify weight/identity.
@MainActor
final class WrestlingManagerRemoteCapture {
    struct Scope {
        let accountID: UUID
        let clubID: UUID
        let generation: String
        let programID: String
        let windowID: String
        let opensAt: Date
        let closesAt: Date
    }
    struct Envelope: Codable, Equatable {
        let submissionId: String
        let captureId: String
        let programId: String
        let windowId: String
        let clubId: String
        let athleteId: String
        let operatorId: String
        let generation: String
        let method: String
        let weight: Double
        let unit: String
        let capturedAt: String
        let photoCapturedAt: String
        let evidenceId: String
    }
    struct Frozen {
        let submissionID: UUID
        let accountID: UUID
        let clubID: UUID
        let payload: Data
        let jpeg: Data
    }
    enum Failure: Error { case closed, windowClosed, invalidScan, changed, frozen, unsettled, expired, photoRequired, invalidPhoto }
    private struct Sample {
        let weight: Double
        let at: Date
        var lowest: Double
        var highest: Double
        init(weight: Double, at: Date) {
            self.weight = weight; self.at = at; lowest = weight; highest = weight
        }
    }
    private struct Pending {
        let token: UUID
        let athleteID: String
        let method: String
        let scannedAt: Date
        var samples: [Sample] = []
        var reading: Sample?
        var jpeg: Data?
        var photoAt: Date?
        var evidenceID: UUID?
        var frozen: Frozen?
    }
    private let scope: Scope
    private let now: () -> Date
    private var active = true
    private var pending: Pending?
    var captureToken: UUID? { pending?.token }
    var settledWeight: Double? {
        guard let row = pending, let reading = row.reading,
              fresh(reading.at), inWindow(now()), hasRecentPacket(row, at: now()) else { return nil }
        return reading.weight
    }

    init(scope: Scope, now: @escaping () -> Date = Date.init) throws {
        guard scope.opensAt < scope.closesAt,
              [scope.generation, scope.programID, scope.windowID].allSatisfy(Self.validID) else { throw Failure.windowClosed }
        self.scope = scope; self.now = now
    }
    private static func validID(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 160 }
    private func require(_ token: UUID) throws -> Pending {
        guard active else { throw Failure.closed }
        guard let pending, pending.token == token else { throw Failure.changed }
        return pending
    }
    private func inWindow(_ date: Date) -> Bool { date >= scope.opensAt && date < scope.closesAt }
    private func fresh(_ date: Date) -> Bool { let age = now().timeIntervalSince(date); return age >= 0 && age <= 30 }
    private func hasRecentPacket(_ row: Pending, at date: Date) -> Bool {
        guard let last = row.samples.last else { return false }
        // Camera processing can finish after another BLE packet arrives. Use
        // absolute distance at exposure and separately require a live packet now.
        return abs(date.timeIntervalSince(last.at)) <= 1.5
    }

    /// Call only after a QR/NFC credential has resolved to an authorized roster athlete.
    @discardableResult func scan(athleteID: String, method: String) throws -> UUID {
        guard active else { throw Failure.closed }
        guard pending?.frozen == nil else { throw Failure.frozen }
        guard Self.validID(athleteID), ["qr", "nfc"].contains(method) else { throw Failure.invalidScan }
        let at = now(); guard inWindow(at) else { throw Failure.windowClosed }
        let token = UUID()
        pending = Pending(token: token, athleteID: athleteID, method: method, scannedAt: at)
        return token
    }
    /// Stamp at receipt of each BLE packet. Never call from cached UI values.
    /// Three distinct receipt times spanning >=1s, spread <=0.2lb and gaps <=1.5s form a candidate.
    /// Records from one BLE notification share a timestamp and count as one sample.
    func scaleReading(token: UUID, pounds: Double, observedAt: Date, connected: Bool) throws {
        var row = try require(token)
        guard row.frozen == nil else { throw Failure.frozen }
        guard connected, pounds.isFinite, pounds > 0, pounds <= 800,
              observedAt > row.scannedAt, fresh(observedAt), inWindow(observedAt),
              row.samples.last.map({ observedAt >= $0.at }) ?? true else {
            row.samples = []; row.reading = nil; row.jpeg = nil; row.photoAt = nil; row.evidenceID = nil
            pending = row; throw Failure.unsettled
        }
        var sample = Sample(weight: pounds, at: observedAt)
        let last = row.samples.last
        if let last, observedAt == last.at {
            // Retain the entire batch's range so movement cannot be hidden by
            // a final record that returns to the original weight.
            sample.lowest = min(last.lowest, pounds)
            sample.highest = max(last.highest, pounds)
            row.samples.removeLast()
        }
        // Stable packets keep the chosen reading/photo together without refreshing its age.
        // Movement or a packet gap invalidates the chosen reading and any photo.
        if let reading = row.reading, fresh(reading.at), reading.at < observedAt, let last,
           abs(sample.lowest - reading.weight) <= 0.200001,
           abs(sample.highest - reading.weight) <= 0.200001,
           sample.highest - sample.lowest <= 0.200001,
           observedAt.timeIntervalSince(last.at) <= 1.5 {
            row.samples = [sample]; pending = row; return
        }
        row.reading = nil; row.jpeg = nil; row.photoAt = nil; row.evidenceID = nil
        if let last, observedAt.timeIntervalSince(last.at) > 1.5 { row.samples = [] }
        row.samples.append(sample)
        row.samples.removeAll { observedAt.timeIntervalSince($0.at) > 3 }
        // A changing scale must first establish a new run of stable samples.
        while row.samples.count > 1,
              (row.samples.map(\.highest).max()! - row.samples.map(\.lowest).min()!) > 0.200001 {
            row.samples.removeFirst()
        }
        if row.samples.count >= 3, observedAt.timeIntervalSince(row.samples[0].at) >= 1 {
            row.reading = Sample(weight: pounds, at: observedAt)
        }
        pending = row
    }
    func scaleDisconnected() {
        guard var row = pending, row.frozen == nil else { return }
        row.samples = []; row.reading = nil; row.jpeg = nil; row.photoAt = nil; row.evidenceID = nil
        pending = row
    }
    /// The photo adapter decodes and re-encodes camera output; no gallery selection.
    func snapshot(token: UUID, normalizedJPEG: Data, capturedAt: Date, noticeAccepted: Bool) throws {
        var row = try require(token); guard row.frozen == nil else { throw Failure.frozen }
        guard let reading = row.reading, fresh(reading.at),
              hasRecentPacket(row, at: now()), hasRecentPacket(row, at: capturedAt) else { throw Failure.unsettled }
        guard noticeAccepted, !normalizedJPEG.isEmpty, normalizedJPEG.count <= 5 * 1024 * 1024,
              normalizedJPEG.starts(with: [0xff, 0xd8]), normalizedJPEG.suffix(2).elementsEqual([0xff, 0xd9]),
              capturedAt >= reading.at, fresh(capturedAt), inWindow(capturedAt) else { throw Failure.invalidPhoto }
        row.jpeg = normalizedJPEG; row.photoAt = capturedAt; row.evidenceID = UUID(); pending = row
    }
    /// Freezes identical bytes for retries, including after the capture window expires.
    func freeze(token: UUID) throws -> Frozen {
        var row = try require(token)
        if let frozen = row.frozen { return frozen }
        guard let reading = row.reading, fresh(reading.at) else { throw Failure.expired }
        guard let jpeg = row.jpeg, let photoAt = row.photoAt, let evidenceID = row.evidenceID,
              fresh(photoAt) else { throw Failure.photoRequired }
        let submissionID = UUID()
        let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let envelope = Envelope(submissionId: submissionID.uuidString.lowercased(), captureId: token.uuidString.lowercased(),
            programId: scope.programID, windowId: scope.windowID, clubId: scope.clubID.uuidString.lowercased(),
            athleteId: row.athleteID, operatorId: scope.accountID.uuidString.lowercased(), generation: scope.generation,
            method: row.method, weight: reading.weight, unit: "lb", capturedAt: format.string(from: reading.at),
            photoCapturedAt: format.string(from: photoAt), evidenceId: evidenceID.uuidString.lowercased())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let frozen = Frozen(submissionID: submissionID, accountID: scope.accountID, clubID: scope.clubID,
                            payload: try encoder.encode(envelope), jpeg: jpeg)
        row.frozen = frozen; pending = row; return frozen
    }
    func discard() throws { guard active else { throw Failure.closed }; pending = nil }
    /// Host calls on lock, background, logout, account/club change and page navigation.
    func close() { active = false; pending = nil }
}
