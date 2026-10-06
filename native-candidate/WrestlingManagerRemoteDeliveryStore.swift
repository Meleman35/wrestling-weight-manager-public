import Foundation

extension WrestlingManagerRemoteOutbox: WrestlingManagerRemoteDeliveryStore {
    func deliveryRecord(_ id: UUID) throws -> WrestlingManagerRemoteDeliveryRecord {
        let row = try capture(id)
        return .init(payload: row.payload, jpeg: row.jpeg, receipt: row.receipt)
    }
    func confirmDelivery(_ id: UUID, receipt: Data) throws { try confirm(id, receipt: receipt) }
    func lockDeliveryStore() { lock() }
}
