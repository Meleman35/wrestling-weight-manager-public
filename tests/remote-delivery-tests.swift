import Foundation
import CryptoKit

enum TestFailure: Error { case offline, denied, disk }
actor DeliveryFixture: WrestlingManagerRemoteDeliveryStore {
    let id = UUID()
    let evidence = UUID().uuidString
    var receipt: Data?
    var payload: Data { get throws { try JSONSerialization.data(withJSONObject: ["submissionId": id.uuidString, "evidenceId": evidence], options: [.sortedKeys]) } }
    var authorizationCount = 0
    var uploads = 0
    var submits = 0
    var failSubmit = false
    var failPersistence = false
    var deny = false
    var badPhoto = false
    var badReceipt = false
    var locked = false
    var deliveredPayloads: [Data] = []
    func set(_ field: String, _ value: Bool) {
        switch field {
        case "submit": failSubmit = value
        case "disk": failPersistence = value
        case "deny": deny = value
        case "photo": badPhoto = value
        case "receipt": badReceipt = value
        default: break
        }
    }
    func deliveryRecord(_ id: UUID) throws -> WrestlingManagerRemoteDeliveryRecord {
        guard !locked, id == self.id else { throw TestFailure.denied }
        return .init(payload: try payload, jpeg: Data([0xff, 0xd8, 0xff, 0xd9]), receipt: receipt)
    }
    func confirmDelivery(_ id: UUID, receipt: Data) throws {
        if failPersistence { throw TestFailure.disk }; self.receipt = receipt
    }
    func lockDeliveryStore() { locked = true }
    func authorize(_ data: Data) throws { authorizationCount += 1; if deny { throw TestFailure.denied } }
    func upload(_ data: Data, _ jpeg: Data) throws -> Data {
        uploads += 1; deliveredPayloads.append(data)
        return try JSONSerialization.data(withJSONObject: ["evidenceId": badPhoto ? "other" : evidence,
            "status": "uploaded", "digest": SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined(), "byteCount": jpeg.count])
    }
    func submit(_ data: Data) throws -> Data {
        submits += 1; deliveredPayloads.append(data)
        if failSubmit { throw TestFailure.offline }
        return try JSONSerialization.data(withJSONObject: ["submissionId": badReceipt ? UUID().uuidString : id.uuidString,
            "status": "submitted", "receiptId": "receipt", "receivedAt": "2026-10-04T02:00:00.123Z"])
    }
    func counts() -> (Int, Int) { (uploads, submits) }
    func isAccepted() -> Bool { receipt != nil }
    func identical() -> Bool { deliveredPayloads.allSatisfy { $0 == deliveredPayloads.first } }
}
@main struct DeliveryTests {
    static func rejects(_ body: () async throws -> Void) async {
        do { try await body(); fatalError("Expected failure") } catch {}
    }
    static func delivery(_ fixture: DeliveryFixture) -> WrestlingManagerRemoteDelivery {
        .init(store: fixture, transport: .init(authorize: { try await fixture.authorize($0) },
            uploadPhoto: { try await fixture.upload($0, $1) }, submit: { try await fixture.submit($0) }))
    }
    static func main() async throws {
        let fixture = DeliveryFixture(), worker = delivery(fixture), id = fixture.id
        await fixture.set("submit", true)
        await rejects { _ = try await worker.deliver(id) }
        let failed = await fixture.isAccepted(); precondition(!failed)
        await fixture.set("submit", false); await fixture.set("disk", true)
        await rejects { _ = try await worker.deliver(id) }
        let persisted = await fixture.isAccepted(); precondition(!persisted)
        await fixture.set("disk", false)
        let receipt = try await worker.deliver(id)
        let counts = await fixture.counts()
        let repeated = try await worker.deliver(id)
        let repeatedCounts = await fixture.counts()
        precondition(receipt == repeated && counts.0 == repeatedCounts.0 && counts.1 == repeatedCounts.1)
        let identical = await fixture.identical(); precondition(identical)
        await fixture.set("deny", true)
        await rejects { _ = try await worker.deliver(id) }
        await worker.lock()
        await rejects { _ = try await worker.deliver(id) }
        let recoveredFixture = DeliveryFixture()
        let recoveredID = recoveredFixture.id
        let acceptedReceipt = try await recoveredFixture.submit(Data())
        let recovery = WrestlingManagerRemoteDelivery(store: recoveredFixture, transport: .init(
            authorize: { try await recoveredFixture.authorize($0) },
            uploadPhoto: { try await recoveredFixture.upload($0, $1) },
            submit: { try await recoveredFixture.submit($0) },
            findReceipt: { _ in acceptedReceipt }))
        let recovered = try await recovery.deliver(recoveredID)
        let recoveredCounts = await recoveredFixture.counts()
        precondition(recovered == acceptedReceipt && recoveredCounts.0 == 0 && recoveredCounts.1 == 1)
        for field in ["photo", "receipt"] {
            let f = DeliveryFixture(), w = delivery(f), i = f.id
            await f.set(field, true)
            await rejects { _ = try await w.deliver(i) }
            let accepted = await f.isAccepted(); precondition(!accepted)
            if field == "photo" { let c = await f.counts(); precondition(c.1 == 0) }
        }
        print("Native delivery passed: upload binding, ambiguous submit, receipt persistence, exact retries, revoked access and lock.")
    }
}
