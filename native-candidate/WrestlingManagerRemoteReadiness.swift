import Foundation

/// A continuous stable interval before the automatic shutter. Monotonic device
/// time drives the countdown; wall-clock timestamps remain separate evidence.
@MainActor
struct WrestlingManagerRemoteReadiness {
    private var startedAt: TimeInterval?
    mutating func remaining(ready: Bool, at now: TimeInterval) -> Int? {
        guard ready, now.isFinite, now >= 0 else { startedAt = nil; return nil }
        if startedAt == nil || now < startedAt! { startedAt = now }
        return Int(ceil(max(0, 2 - (now - startedAt!))))
    }
}

/// Advance only after two distinct, fresh empty-scale responses over >=0.5s.
/// Begin after each completed capture; a previous athlete's zero cannot carry over.
@MainActor
struct WrestlingManagerRemoteScaleClear {
    private var after: Date?
    private var firstEmptyAt: Date?
    private var lastObservedAt: Date?
    private var lastEmptyAt: Date?
    private var count = 0
    mutating func begin(after date: Date) { self = Self(); after = date }
    mutating func reset() { self = Self() }
    mutating func invalidate() { firstEmptyAt = nil; lastEmptyAt = nil; lastObservedAt = nil; count = 0 }
    mutating func observe(pounds: Double, at: Date, now: Date, connected: Bool) {
        guard let after else { return }
        let age = now.timeIntervalSince(at)
        guard connected, at > after, age >= 0, age <= 1.5,
              lastObservedAt.map({ at >= $0 }) ?? true else { invalidate(); return }
        let duplicate = at == lastObservedAt
        lastObservedAt = at
        guard pounds.isFinite, abs(pounds) <= WrestlingManagerRemoteCapture.emptyScaleMaximumPounds else {
            firstEmptyAt = nil; lastEmptyAt = nil; count = 0; return
        }
        guard !duplicate else { return }
        if let lastEmptyAt, at.timeIntervalSince(lastEmptyAt) > 1.5 {
            firstEmptyAt = nil; count = 0
        }
        if firstEmptyAt == nil { firstEmptyAt = at }
        lastEmptyAt = at; count += 1
    }
    func isClear(at now: Date) -> Bool {
        guard after != nil, count >= 2, let firstEmptyAt, let lastEmptyAt else { return false }
        let age = now.timeIntervalSince(lastEmptyAt)
        return age >= 0 && age <= 1.5 && lastEmptyAt.timeIntervalSince(firstEmptyAt) >= 0.5
    }
}
