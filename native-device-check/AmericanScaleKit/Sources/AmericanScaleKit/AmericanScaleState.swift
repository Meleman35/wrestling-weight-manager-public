import Foundation

public struct AmericanScaleSessionState: Equatable, Sendable {
    public private(set) var liveWeightLb: Double?
    public private(set) var batteryPercent: Double?
    public private(set) var capacityLb: Double?
    public private(set) var lockInState: Double?
    public private(set) var latestInfo: String?
    public private(set) var pendingLockIn = false
    public private(set) var lockedWeightLb: Double?

    public init() {}

    public mutating func armLockIn() {
        pendingLockIn = true
    }

    public mutating func cancelPendingLockIn() {
        pendingLockIn = false
    }

    public mutating func clearLockedWeight() {
        lockedWeightLb = nil
    }

    public mutating func apply(_ message: AmericanScaleMessage) {
        switch message {
        case .weight(let pounds):
            liveWeightLb = pounds
            if pendingLockIn {
                lockedWeightLb = pounds
                pendingLockIn = false
            }

        case .batteryLevel(let percent):
            batteryPercent = percent

        case .capacity(let pounds):
            capacityLb = pounds

        case .lockInState(let value):
            lockInState = value

        case .info(let message):
            latestInfo = message

        case .unknown:
            break
        }
    }
}
