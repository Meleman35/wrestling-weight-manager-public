import Foundation
import CryptoKit

struct WrestlingManagerRemoteDeliveryRecord: Sendable {
    let payload: Data
    let jpeg: Data
    let receipt: Data?
}
protocol WrestlingManagerRemoteDeliveryStore: Sendable {
    func deliveryRecord(_ id: UUID) async throws -> WrestlingManagerRemoteDeliveryRecord
    func confirmDelivery(_ id: UUID, receipt: Data) async throws
    func lockDeliveryStore() async
}

/// Native-only delivery. Adapters own authenticated HTTPS and server authorization.
/// Upload failure, ambiguous acceptance and failed receipt persistence retain evidence.
actor WrestlingManagerRemoteDelivery {
    struct Transport: Sendable {
        let authorize: @Sendable (Data) async throws -> Void
        let uploadPhoto: @Sendable (Data, Data) async throws -> Data
        let submit: @Sendable (Data) async throws -> Data
    }
    enum Failure: Error { case locked, busy, invalidCapture, unconfirmedPhoto, unconfirmedReceipt }
    private let store: any WrestlingManagerRemoteDeliveryStore
    private let transport: Transport
    private var active = true
    private var delivering = false
    init(store: any WrestlingManagerRemoteDeliveryStore, transport: Transport) {
        self.store = store; self.transport = transport
    }
    private func check() throws { guard active else { throw Failure.locked } }
    private func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 12000, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalidCapture
        }
        return value
    }
    func deliver(_ id: UUID) async throws -> Data {
        try check(); guard !delivering else { throw Failure.busy }
        delivering = true; defer { delivering = false }
        let record = try await store.deliveryRecord(id); try check()
        let capture = try object(record.payload)
        guard let submissionID = capture["submissionId"] as? String, UUID(uuidString: submissionID) == id,
              let evidenceID = capture["evidenceId"] as? String, !evidenceID.isEmpty,
              !record.jpeg.isEmpty, record.jpeg.count <= 5 * 1024 * 1024 else { throw Failure.invalidCapture }
        try await transport.authorize(record.payload); try check()
        // Even an accepted local receipt is hidden from a revoked/locked caller.
        if let receipt = record.receipt { try validateReceipt(receipt, id: id); return receipt }
        let uploaded = try await transport.uploadPhoto(record.payload, record.jpeg); try check()
        let photo = try object(uploaded)
        guard photo["status"] as? String == "uploaded", photo["evidenceId"] as? String == evidenceID,
              let digest = photo["digest"] as? String, digest.count == 64,
              digest == SHA256.hash(data: record.jpeg).map({ String(format: "%02x", $0) }).joined(),
              (photo["byteCount"] as? NSNumber)?.intValue == record.jpeg.count else { throw Failure.unconfirmedPhoto }
        try await transport.authorize(record.payload); try check()
        let receipt = try await transport.submit(record.payload); try check()
        try validateReceipt(receipt, id: id)
        try await transport.authorize(record.payload); try check()
        // Only successful durable receipt persistence lets the UI show submitted.
        try await store.confirmDelivery(id, receipt: receipt); try check()
        return receipt
    }
    private func validateReceipt(_ data: Data, id: UUID) throws {
        let value = try object(data)
        guard let rawID = value["submissionId"] as? String, UUID(uuidString: rawID) == id,
              value["status"] as? String == "submitted",
              let receiptID = value["receiptId"] as? String, !receiptID.isEmpty, receiptID.utf8.count <= 160,
              let received = value["receivedAt"] as? String else { throw Failure.unconfirmedReceipt }
        let date = ISO8601DateFormatter(); date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if date.date(from: received) == nil {
            date.formatOptions = [.withInternetDateTime]
            guard date.date(from: received) != nil else { throw Failure.unconfirmedReceipt }
        }
    }
    func lock() async { active = false; await store.lockDeliveryStore() }
}
