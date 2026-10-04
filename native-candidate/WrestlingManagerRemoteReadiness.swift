import Foundation

/// A continuous stable interval before the automatic shutter. Monotonic device
/// time drives the countdown; wall-clock timestamps remain separate evidence.
@MainActor
struct WrestlingManagerRemoteReadiness {
    private var startedAt: TimeInterval?
    mutating func remaining(ready: Bool, at now: TimeInterval) -> Int? {
        guard ready, now.isFinite, now >= 0 else { startedAt = nil; return nil }
        if startedAt == nil || now < startedAt! { startedAt = now }
        return Int(ceil(max(0, 3 - (now - startedAt!))))
    }
}
