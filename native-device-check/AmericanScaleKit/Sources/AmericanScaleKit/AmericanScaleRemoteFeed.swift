import Foundation

/// Prefer immediate notifications while the scale is changing. Fall back to
/// unambiguous direct reads when a change-only scale becomes quiet. A read of
/// metadata/partial data restores notifications rather than hiding live weights
/// behind the characteristic's last non-weight value for several seconds.
struct AmericanScaleRemoteFeed: Sendable {
    private(set) var wantsNotifications = true
    private var lastNotificationWeightAt: TimeInterval = 0
    mutating func start(at now: TimeInterval) {
        wantsNotifications = true; lastNotificationWeightAt = now
    }
    mutating func notificationWeight(at now: TimeInterval) {
        if wantsNotifications { lastNotificationWeightAt = now }
    }
    mutating func readReply(hasWeight: Bool, at now: TimeInterval) {
        if !hasWeight { start(at: now) }
    }
    mutating func tick(at now: TimeInterval) {
        guard now.isFinite, now >= 0 else { return }
        if wantsNotifications && (now < lastNotificationWeightAt || now - lastNotificationWeightAt >= 0.65) {
            wantsNotifications = false
        }
    }
}
