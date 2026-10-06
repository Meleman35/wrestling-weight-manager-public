import Foundation
import StoreKit

// Candidate component. No web bridge or production server adapter is installed.
// Product IDs must be confirmed against App Store Connect before integration.
@MainActor
protocol WrestlingManagerPurchaseServer: AnyObject {
    // Implementation must use the current authenticated server session.
    // The server validates team authority and binds this opaque token durably.
    func preparePurchase(productID: String, target: WrestlingManagerPurchaseTarget) async throws -> UUID
    func abandonPurchase(token: UUID) async throws
    // Return only after Apple evidence is verified, ownership checked and the
    // transaction durably processed. Acknowledgement does not itself grant UI access.
    func deliver(signedTransaction: String) async throws -> WrestlingManagerPurchaseAck
    func refreshAccess() async throws
}

struct WrestlingManagerPurchaseAck {
    let transactionID: String
    let originalTransactionID: String
}

enum WrestlingManagerPurchaseTarget: Equatable {
    case team(UUID)
    // The server resolves the family owner from the signed-in account.
    case family
}

@MainActor
final class WrestlingManagerStore {
    enum Outcome: Equatable {
        case delivered
        case awaitingServer
        case pending
        case cancelled
    }

    enum StoreError: Error {
        case unavailableProduct
        case busy
        case unverified
        case unexpectedAcknowledgement
        case unknownResult
        case sessionEnded
        case invalidTarget
    }

    static let proposedProductIDs: Set<String> = [
        "com.damonmele.wrestlingmanager.teampro.annual",
        "com.damonmele.wrestlingmanager.teampro.monthly",
        "com.damonmele.wrestlingmanager.familyvideo.annual",
        "com.damonmele.wrestlingmanager.familyvideo.monthly"
    ]

    private let server: any WrestlingManagerPurchaseServer
    private let productIDs: Set<String>
    private var productsByID: [String: Product] = [:]
    private var observer: Task<Void, Never>?
    private var busy = false
    private var sessionActive = true
    // Serializes duplicate purchase/listener/recovery delivery within this instance.
    // The server must also enforce idempotency across processes and devices.
    private var delivering = Set<UInt64>()

    init(server: any WrestlingManagerPurchaseServer, productIDs: Set<String>) {
        self.server = server
        self.productIDs = productIDs.intersection(Self.proposedProductIDs)
    }

    deinit { observer?.cancel() }

    func loadProducts() async throws -> [Product] {
        try requireSession()
        let loaded = try await Product.products(for: Array(productIDs))
        try requireSession()
        productsByID = Dictionary(uniqueKeysWithValues: loaded.filter {
            productIDs.contains($0.id) && $0.type == .autoRenewable
        }.map { ($0.id, $0) })
        return productsByID.values.sorted { $0.id < $1.id }
    }

    // Start once when a signed-in store session is constructed.
    // On logout, destroy this session and its authenticated server adapter.
    func start() {
        guard sessionActive, observer == nil else { return }
        observer = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                _ = try? await self.deliver(result)
                // No success/paid state is inferred from a failed delivery.
            }
        }
    }

    func stop() {
        // This instance belongs to one authenticated session and cannot be reused.
        sessionActive = false
        observer?.cancel()
        observer = nil
        productsByID.removeAll()
    }

    func purchase(productID: String, target: WrestlingManagerPurchaseTarget) async throws -> Outcome {
        try requireSession()
        guard !busy else { throw StoreError.busy }
        guard productIDs.contains(productID), let product = productsByID[productID]
        else { throw StoreError.unavailableProduct }
        switch target {
        case .team:
            guard productID.contains(".teampro.") else { throw StoreError.invalidTarget }
        case .family:
            guard productID.contains(".familyvideo.") else { throw StoreError.invalidTarget }
        }
        busy = true
        defer { busy = false }
        let token = try await server.preparePurchase(productID: productID, target: target)
        try requireSession()
        let result = try await product.purchase(options: [.appAccountToken(token)])
        try requireSession()
        switch result {
        case .success(let result):
            return try await deliver(result)
        case .pending:
            return .pending
        case .userCancelled:
            // Cancel only an unbound intent. The server cannot release a paid
            // original purchase or another account's team reservation.
            try? await server.abandonPurchase(token: token)
            try requireSession()
            return .cancelled
        @unknown default:
            throw StoreError.unknownResult
        }
    }

    // Explicit user action only; don't invoke AppStore.sync on startup.
    // No selected team is supplied: restore preserves the server's original binding.
    func restore() async throws -> Outcome {
        try requireSession()
        guard !busy else { throw StoreError.busy }
        busy = true
        defer { busy = false }
        try await AppStore.sync()
        try requireSession()
        return try await recover()
    }

    // Call on sign-in/foreground and after a network recovery. StoreKit retains
    // unfinished transactions; signed purchase evidence isn't copied to UserDefaults.
    func recover() async throws -> Outcome {
        try requireSession()
        var awaitingServer = false
        for await result in Transaction.unfinished {
            try requireSession()
            do { if try await deliver(result) == .awaitingServer { awaitingServer = true } }
            catch { try requireSession(); awaitingServer = true }
        }
        for await result in Transaction.currentEntitlements {
            try requireSession()
            do { if try await deliver(result) == .awaitingServer { awaitingServer = true } }
            catch { try requireSession(); awaitingServer = true }
        }
        do { try await server.refreshAccess() }
        catch { awaitingServer = true }
        try requireSession()
        return awaitingServer ? .awaitingServer : .delivered
    }

    private func deliver(_ result: VerificationResult<Transaction>) async throws -> Outcome {
        try requireSession()
        guard case .verified(let transaction) = result else { throw StoreError.unverified }
        // Other product types remain available to their own handlers.
        guard productIDs.contains(transaction.productID), transaction.productType == .autoRenewable
        else { return .delivered }
        guard !delivering.contains(transaction.id) else { return .awaitingServer }
        delivering.insert(transaction.id)
        defer { delivering.remove(transaction.id) }
        let ack: WrestlingManagerPurchaseAck
        do { ack = try await server.deliver(signedTransaction: result.jwsRepresentation) }
        catch { return .awaitingServer }
        try requireSession()
        guard ack.transactionID == String(transaction.id),
              ack.originalTransactionID == String(transaction.originalID)
        else { throw StoreError.unexpectedAcknowledgement }
        await transaction.finish()
        try requireSession()
        do { try await server.refreshAccess() }
        catch { return .awaitingServer }
        try requireSession()
        return .delivered
    }

    private func requireSession() throws {
        try Task.checkCancellation()
        guard sessionActive else { throw StoreError.sessionEnded }
    }
}
