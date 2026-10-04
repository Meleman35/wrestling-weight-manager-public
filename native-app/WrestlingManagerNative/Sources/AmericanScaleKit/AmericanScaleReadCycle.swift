import Foundation

/// A bounded sequence of actual GATT reads. No cached weight enters this type.
/// Stopping invalidates delivery but retains an outstanding request until drained.
struct AmericanScaleReadCycle: Sendable {
    enum Action: Equatable { case read, timeout, none }
    private(set) var enabled = false
    private var generation = 0
    private var pending: (at: TimeInterval, generation: Int)?
    private var nextAt: TimeInterval = 0
    var awaitingReply: Bool { pending != nil }

    mutating func start(at now: TimeInterval) {
        guard !enabled else { return }
        generation += 1; enabled = true; nextAt = now
    }
    mutating func stop() { enabled = false; generation += 1 }
    mutating func reset() { self = Self() }
    mutating func tick(at now: TimeInterval, canRead: Bool) -> Action {
        guard now.isFinite, now >= 0 else { return .none }
        if let pending {
            if now < pending.at || now - pending.at >= 2 { return .timeout }
            return .none
        }
        guard enabled, canRead, now >= nextAt else { return .none }
        pending = (now, generation)
        return .read
    }
    /// True only for the response to a request from the current active run.
    mutating func received(at now: TimeInterval) -> Bool {
        guard let request = pending else { return false }
        pending = nil; nextAt = now + 0.5
        return enabled && request.generation == generation && now.isFinite
            && now >= request.at && now - request.at < 2
    }
}
