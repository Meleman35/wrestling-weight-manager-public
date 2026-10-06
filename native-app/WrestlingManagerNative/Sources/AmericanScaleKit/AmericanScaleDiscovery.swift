import Foundation

/// Limits the picker to the scale service or an identity previously verified by
/// the host app. Device names are editable and never identify hardware by themselves.
public enum AmericanScaleDiscovery {
    public static func includes(
        identifier: UUID,
        advertisedServices: [String],
        knownScaleIdentifiers: Set<UUID>
    ) -> Bool {
        if knownScaleIdentifiers.contains(identifier) { return true }
        return advertisedServices.contains { value in
            switch value.uppercased() {
            case "108D", "0000108D", "0000108D-0000-1000-8000-00805F9B34FB": return true
            default: return false
            }
        }
    }
}
