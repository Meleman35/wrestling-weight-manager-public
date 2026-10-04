import Foundation

public enum AmericanScaleDisplayUnit: String, CaseIterable, Identifiable, Sendable {
    case pounds = "lb"
    case kilograms = "kg"

    public var id: String { rawValue }
}

public enum AmericanScaleMessage: Equatable, Sendable {
    case weight(Double)
    case batteryLevel(Double)
    case capacity(Double)
    case lockInState(Double)
    case info(String)
    case unknown(String)
}

public struct AmericanScaleStreamParser: Sendable {
    private var buffer = Data()

    public init() {}

    /// Appends arbitrary notification bytes and returns every complete `#`-terminated record.
    /// Empty records created by repeated `#` padding are ignored and unterminated fragments
    /// remain buffered until a later notification completes them.
    public mutating func append(_ data: Data) -> [AmericanScaleMessage] {
        buffer.append(data)

        var messages: [AmericanScaleMessage] = []

        while let delimiterIndex = buffer.firstIndex(of: 0x23) { // '#'
            let recordData = buffer[..<delimiterIndex]
            let nextIndex = buffer.index(after: delimiterIndex)
            buffer.removeSubrange(..<nextIndex)

            guard !recordData.isEmpty else { continue }

            let rawRecord = String(decoding: recordData, as: UTF8.self)
            let record = rawRecord.trimmingCharacters(in: .newlines)
            guard !record.isEmpty else { continue }

            messages.append(Self.parseRecord(record))
        }

        return messages
    }

    public var bufferedByteCount: Int { buffer.count }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }

    static func parseRecord(_ record: String) -> AmericanScaleMessage {
        if let value = numericValue(in: record, prefix: "Weight=") {
            return .weight(value)
        }
        if let value = numericValue(in: record, prefix: "BatteryLevel=") {
            return .batteryLevel(value)
        }
        if let value = numericValue(in: record, prefix: "Capacity=") {
            return .capacity(value)
        }
        if let value = numericValue(in: record, prefix: "Lockin=") {
            return .lockInState(value)
        }
        if record.hasPrefix("Info=") {
            return .info(String(record.dropFirst("Info=".count)))
        }
        return .unknown(record)
    }

    private static func numericValue(in record: String, prefix: String) -> Double? {
        guard record.hasPrefix(prefix) else { return nil }
        return Double(record.dropFirst(prefix.count))
    }
}

public enum AmericanScaleRenameValidationError: Error, Equatable, LocalizedError, Sendable {
    case empty
    case nonASCII
    case containsDelimiter
    case tooLong(maxBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Scale name cannot be empty."
        case .nonASCII:
            return "Scale name must use single-byte printable ASCII characters."
        case .containsDelimiter:
            return "Scale name cannot contain #."
        case .tooLong(let maxBytes):
            return "Scale name must be no more than \(maxBytes) ASCII bytes."
        }
    }
}

public enum AmericanScaleCommand: Sendable {
    public static let maxVerifiedRenameBytes = 8

    public static var zero: Data {
        Data("Zero=1#".utf8)
    }

    public static var lockIn: Data {
        Data("Lockin=1#".utf8)
    }

    public static func rename(_ proposedName: String) throws -> Data {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AmericanScaleRenameValidationError.empty }
        guard !name.contains("#") else { throw AmericanScaleRenameValidationError.containsDelimiter }

        let bytes = Array(name.utf8)
        guard bytes.count <= maxVerifiedRenameBytes else {
            throw AmericanScaleRenameValidationError.tooLong(maxBytes: maxVerifiedRenameBytes)
        }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else {
            throw AmericanScaleRenameValidationError.nonASCII
        }

        return Data("DeviceName=\(name)#".utf8)
    }
}

public enum AmericanScaleUnits: Sendable {
    public static let poundsPerKilogram = 2.2046226218

    public static func kilograms(fromPounds pounds: Double) -> Double {
        pounds / poundsPerKilogram
    }

    public static func displayedWeight(pounds: Double, unit: AmericanScaleDisplayUnit) -> Double {
        switch unit {
        case .pounds:
            return pounds
        case .kilograms:
            return kilograms(fromPounds: pounds)
        }
    }
}
