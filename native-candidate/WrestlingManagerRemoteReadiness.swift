import Foundation

/// One fresh empty-scale response confirms step-off. Do not require another
/// zero response from a change-only scale. The caller evaluates after the whole
/// BLE response; any nonempty/invalid record in that response vetoes advancement.
@MainActor
struct WrestlingManagerRemoteScaleClear {
    private var after: Date?
    private var lastObservedAt: Date?
    private var emptyAt: Date?
    private var batchBlocked = false
    mutating func begin(after date: Date) { self = Self(); after = date }
    mutating func reset() { self = Self() }
    mutating func invalidate() { emptyAt = nil; batchBlocked = true }
    mutating func observe(pounds: Double, at: Date, now: Date, connected: Bool) {
        guard let after else { return }
        let age = now.timeIntervalSince(at)
        guard connected, at > after, age >= 0, age <= 1.5,
              lastObservedAt.map({ at >= $0 }) ?? true else { invalidate(); return }
        if at != lastObservedAt { batchBlocked = false }
        lastObservedAt = at
        guard pounds.isFinite, abs(pounds) <= WrestlingManagerRemoteCapture.emptyScaleMaximumPounds else {
            invalidate(); return
        }
        if !batchBlocked { emptyAt = at }
    }
    func isClear(at now: Date) -> Bool {
        guard after != nil, !batchBlocked, let emptyAt else { return false }
        let age = now.timeIntervalSince(emptyAt)
        return age >= 0 && age <= 1.5
    }
}
