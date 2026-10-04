#if canImport(CoreBluetooth) && canImport(Combine)
import Foundation
@preconcurrency import CoreBluetooth
import Combine

public struct AmericanScaleDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let advertisedName: String
    public let rssi: Int

    public init(id: UUID, advertisedName: String, rssi: Int) {
        self.id = id
        self.advertisedName = advertisedName
        self.rssi = rssi
    }
}

public enum AmericanScaleConnectionState: Equatable, Sendable {
    case idle
    case bluetoothUnavailable
    case scanning
    case connecting
    case discovering
    case ready
    case disconnecting
    case failed(String)
}

/// Native CoreBluetooth transport for the verified American Scale protocol.
///
/// The central manager is explicitly created on DispatchQueue.main, so all
/// CoreBluetooth delegate callbacks for this client arrive on the main queue.
/// The observable UI state is therefore isolated to MainActor. Delegate methods
/// use MainActor.assumeIsolated instead of creating Tasks; this avoids sending
/// CoreBluetooth's non-Sendable reference types across concurrency domains under
/// Swift 6 strict-concurrency checking.
@MainActor
public final class AmericanScaleClient: NSObject, ObservableObject {
    public static let scaleServiceUUID = CBUUID(string: "108D")
    public static let scaleCharacteristicUUID = CBUUID(string: "0001")

    @Published public private(set) var connectionState: AmericanScaleConnectionState = .idle
    @Published public private(set) var discoveredDevices: [AmericanScaleDevice] = []
    @Published public private(set) var selectedPeripheralIdentifier: UUID?
    @Published public private(set) var connectedAdvertisedName: String?
    @Published public private(set) var session = AmericanScaleSessionState()
    @Published public private(set) var lastError: String?

    public var displayUnit: AmericanScaleDisplayUnit = .pounds

    /// Real BLE packet evidence; optional and dormant until an authorized host connects it.
    public var onRemoteWeightPacket: (@MainActor (Double, Date) -> Void)?
    @Published public private(set) var remoteReadStatus = "Direct scale reads inactive."
    private var remoteReadsRequested = false
    private var remoteReads = AmericanScaleReadCycle()
    private var remoteReadTask: Task<Void, Never>?
    private var notificationChangeAt: TimeInterval?
    private var readRequestCount = 0
    private var readReplyCount = 0

    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var connectingPeripheral: CBPeripheral?
    private var knownScaleIdentifiers: Set<UUID> = []
    private var scaleCharacteristic: CBCharacteristic?
    private var parser = AmericanScaleStreamParser()

    private var reconnectTargetIdentifier: UUID?
    private var expectedRenamedName: String?
    private var reconnectAfterRename = false

    private enum PendingCommand {
        case zero(Data)
        case lockIn(Data)
        case rename(Data, expectedName: String)

        var data: Data {
            switch self {
            case .zero(let data), .lockIn(let data), .rename(let data, _):
                return data
            }
        }
    }

    private var pendingCommands: [PendingCommand] = []

    public override init() {
        super.init()
        _ = central
    }

    public func startScanning(knownScaleIdentifier: UUID? = nil) {
        if let knownScaleIdentifier { knownScaleIdentifiers.insert(knownScaleIdentifier) }
        guard connectionState != .ready && connectionState != .connecting && connectionState != .discovering && connectionState != .disconnecting else { return }
        guard central.state == .poweredOn else {
            connectionState = .bluetoothUnavailable
            return
        }

        lastError = nil
        reconnectTargetIdentifier = nil
        expectedRenamedName = nil
        reconnectAfterRename = false
        discoveredDevices.removeAll()
        peripheralsByID.removeAll()
        connectionState = .scanning

        // New scales advertise 108D. A saved, verified scale may omit it after
        // renaming; broader discovery still publishes only eligible identities.
        central.scanForPeripherals(withServices: knownScaleIdentifiers.isEmpty ? [Self.scaleServiceUUID] : nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    public func stopScanning() {
        central.stopScan()
        reconnectTargetIdentifier = nil
        expectedRenamedName = nil
        reconnectAfterRename = false
        if connectionState == .scanning {
            connectionState = .idle
        }
    }

    public func connect(to device: AmericanScaleDevice) {
        guard let peripheral = peripheralsByID[device.id] else {
            fail("The selected Bluetooth peripheral is no longer available. Scan again.")
            return
        }

        switch connectionState {
        case .scanning, .idle, .failed: break
        default: return
        }
        central.stopScan()
        lastError = nil
        connectingPeripheral = peripheral
        selectedPeripheralIdentifier = device.id
        connectedAdvertisedName = device.advertisedName
        connectionState = .connecting
        peripheral.delegate = self
        central.connect(peripheral)
    }

    public func disconnect() {
        reconnectAfterRename = false
        reconnectTargetIdentifier = nil
        expectedRenamedName = nil
        guard let peripheral = connectedPeripheral ?? connectingPeripheral else {
            central.stopScan()
            connectionState = .idle
            return
        }
        connectionState = .disconnecting
        central.cancelPeripheralConnection(peripheral)
    }

    public func zeroScale() {
        queueOrSend(.zero(AmericanScaleCommand.zero))
    }

    public func lockInWeight() {
        queueOrSend(.lockIn(AmericanScaleCommand.lockIn))
    }

    public func renameScale(to name: String) throws {
        let command = try AmericanScaleCommand.rename(name)
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        queueOrSend(.rename(command, expectedName: normalized))
    }

    public func clearLockedWeight() {
        var next = session
        next.clearLockedWeight()
        session = next
    }

    /// Used only during an explicit remote-capture attempt. Temporarily suspend
    /// notifications so each callback can be attributed to one requested read.
    public func setRemoteWeightReadingEnabled(_ enabled: Bool) {
        if enabled {
            guard connectionState == .ready, onRemoteWeightPacket != nil else { return }
            guard !remoteReadsRequested else { return }
            remoteReadsRequested = true
            readRequestCount = 0; readReplyCount = 0
            remoteReadStatus = "Preparing direct scale reads…"
            remoteReads.start(at: ProcessInfo.processInfo.systemUptime)
        } else {
            remoteReadsRequested = false; remoteReads.stop()
            remoteReadStatus = "Direct scale reads inactive."
        }
        configureRemoteReadMode()
        startRemoteReadTaskIfNeeded()
    }

    private func configureRemoteReadMode() {
        guard connectionState == .ready, notificationChangeAt == nil,
              let peripheral = connectedPeripheral, let characteristic = scaleCharacteristic else { return }
        // Drain a cancelled read before restoring notifications or issuing another.
        guard !remoteReads.awaitingReply else { return }
        let shouldNotify = !remoteReadsRequested
        if characteristic.isNotifying != shouldNotify {
            parser.reset()
            notificationChangeAt = ProcessInfo.processInfo.systemUptime
            peripheral.setNotifyValue(shouldNotify, for: characteristic)
        }
    }

    private func startRemoteReadTaskIfNeeded() {
        guard remoteReadTask == nil,
              remoteReadsRequested || remoteReads.awaitingReply || notificationChangeAt != nil else { return }
        remoteReadTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.connectionState == .ready else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if let changedAt = self.notificationChangeAt, now - changedAt >= 2 {
                    self.failRemoteRead("Scale read setup timed out. Reconnect the scale."); return
                }
                let canRead = self.notificationChangeAt == nil && self.scaleCharacteristic?.isNotifying == false
                switch self.remoteReads.tick(at: now, canRead: canRead) {
                case .read:
                    guard let peripheral = self.connectedPeripheral, let characteristic = self.scaleCharacteristic else { return }
                    self.readRequestCount += 1
                    peripheral.readValue(for: characteristic)
                case .timeout:
                    self.failRemoteRead("The scale did not answer a fresh read. Reconnect the scale."); return
                case .none: break
                }
                if !self.remoteReadsRequested && !self.remoteReads.awaitingReply && self.notificationChangeAt == nil {
                    self.remoteReadTask = nil; return
                }
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            }
        }
    }

    private func failRemoteRead(_ message: String) {
        remoteReadStatus = message
        onRemoteWeightPacket?(.nan, Date())
        remoteReadsRequested = false; remoteReads.reset()
        remoteReadTask?.cancel(); remoteReadTask = nil; notificationChangeAt = nil
        fail(message)
        if let peripheral = connectedPeripheral { central.cancelPeripheralConnection(peripheral) }
    }

    public func reconnectLastScale(knownScaleIdentifier: UUID? = nil) {
        switch connectionState {
        case .scanning, .idle, .failed: break
        default: return
        }
        if let knownScaleIdentifier { knownScaleIdentifiers.insert(knownScaleIdentifier) }
        let verifiedSelection = selectedPeripheralIdentifier.flatMap { knownScaleIdentifiers.contains($0) ? $0 : nil }
        guard let identifier = knownScaleIdentifier ?? verifiedSelection else {
            startScanning()
            return
        }
        reconnectByIdentifier(identifier)
    }

    private func queueOrSend(_ command: PendingCommand) {
        guard connectionState == .ready,
              let peripheral = connectedPeripheral,
              scaleCharacteristic != nil else {
            fail("Connect to the scale before sending a command.")
            return
        }

        if peripheral.canSendWriteWithoutResponse {
            performWrite(command)
        } else {
            pendingCommands.append(command)
        }
    }

    private func performWrite(_ command: PendingCommand) {
        guard let peripheral = connectedPeripheral,
              let characteristic = scaleCharacteristic else {
            fail("Scale write characteristic is not available.")
            return
        }

        switch command {
        case .zero:
            break

        case .lockIn:
            var next = session
            next.armLockIn()
            session = next

        case .rename(_, let expectedName):
            reconnectAfterRename = true
            reconnectTargetIdentifier = peripheral.identifier
            expectedRenamedName = expectedName
        }

        peripheral.writeValue(command.data, for: characteristic, type: .withoutResponse)
    }

    private func flushPendingWritesIfPossible() {
        guard let peripheral = connectedPeripheral else { return }
        while peripheral.canSendWriteWithoutResponse, !pendingCommands.isEmpty {
            let command = pendingCommands.removeFirst()
            performWrite(command)
        }
    }

    private func reconnectByIdentifier(_ identifier: UUID) {
        central.stopScan()
        lastError = nil
        selectedPeripheralIdentifier = identifier
        connectionState = .connecting

        if let known = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            known.delegate = self
            peripheralsByID[identifier] = known
            connectingPeripheral = known
            central.connect(known)
            return
        }

        reconnectTargetIdentifier = identifier
        connectionState = .scanning
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    private func apply(_ messages: [AmericanScaleMessage]) {
        guard !messages.isEmpty else { return }
        var next = session
        for message in messages {
            next.apply(message)
        }
        session = next
    }

    private func resetTransportState() {
        remoteReadsRequested = false; remoteReads.reset()
        remoteReadTask?.cancel(); remoteReadTask = nil; notificationChangeAt = nil
        parser.reset()
        scaleCharacteristic = nil
        connectedPeripheral = nil
        connectingPeripheral = nil
    }

    private func fail(_ message: String) {
        remoteReadTask?.cancel(); remoteReadTask = nil
        remoteReadsRequested = false; remoteReads.reset(); notificationChangeAt = nil
        lastError = message
        connectionState = .failed(message)
    }

    /// CoreBluetooth is configured to invoke delegates on DispatchQueue.main.
    /// This helper expresses that invariant to Swift 6 without moving CB objects
    /// through an asynchronous Task boundary.
    nonisolated private func onMainActor(_ body: @MainActor () -> Void) {
        MainActor.assumeIsolated(body)
    }
}

extension AmericanScaleClient: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onMainActor {
            switch central.state {
            case .poweredOn:
                if self.connectionState == .bluetoothUnavailable {
                    self.connectionState = .idle
                }
            default:
                self.resetTransportState()
                self.connectionState = .bluetoothUnavailable
            }
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Pull the only value we need out of the Objective-C dictionary before
        // entering the MainActor-isolated closure. Capturing `[String: Any]`
        // directly is rejected by Swift 6 because `Any` is not Sendable.
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
            + Array((advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]).keys)
        let advertisedServices = serviceUUIDs.map { $0.uuidString }

        onMainActor {
            let id = peripheral.identifier
            guard self.connectionState == .scanning,
                  AmericanScaleDiscovery.includes(identifier: id, advertisedServices: advertisedServices,
                      knownScaleIdentifiers: self.knownScaleIdentifiers) else { return }
            let advertisedName = localName
                ?? peripheral.name
                ?? "American Scale"

            self.peripheralsByID[id] = peripheral

            let device = AmericanScaleDevice(
                id: id,
                advertisedName: advertisedName,
                rssi: RSSI.intValue
            )

            if let index = self.discoveredDevices.firstIndex(where: { $0.id == id }) {
                self.discoveredDevices[index] = device
            } else {
                self.discoveredDevices.append(device)
                self.discoveredDevices.sort { $0.rssi > $1.rssi }
            }

            if let reconnectID = self.reconnectTargetIdentifier, reconnectID == id {
                central.stopScan()
                self.reconnectTargetIdentifier = nil
                peripheral.delegate = self
                self.connectionState = .connecting
                self.connectingPeripheral = peripheral
                central.connect(peripheral)
                return
            }

            // Name is only a fallback after a verified rename, never the primary identity.
            if self.reconnectAfterRename,
               let expectedName = self.expectedRenamedName,
               advertisedName == expectedName {
                central.stopScan()
                self.reconnectTargetIdentifier = nil
                peripheral.delegate = self
                self.connectionState = .connecting
                self.connectingPeripheral = peripheral
                central.connect(peripheral)
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onMainActor {
            self.connectingPeripheral = nil
            self.connectedPeripheral = peripheral
            self.selectedPeripheralIdentifier = peripheral.identifier
            self.connectedAdvertisedName = peripheral.name ?? self.connectedAdvertisedName
            self.reconnectAfterRename = false
            self.reconnectTargetIdentifier = nil
            self.expectedRenamedName = nil
            self.parser.reset()
            self.scaleCharacteristic = nil
            self.connectionState = .discovering

            peripheral.delegate = self
            // Discover only the verified custom service. Legacy DFU is intentionally ignored.
            peripheral.discoverServices([Self.scaleServiceUUID])
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        onMainActor {
            self.resetTransportState()
            self.fail(error?.localizedDescription ?? "Failed to connect to the scale.")
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        onMainActor {
            let disconnectedID = peripheral.identifier
            self.resetTransportState()

            if self.reconnectAfterRename,
               let reconnectID = self.reconnectTargetIdentifier,
               reconnectID == disconnectedID {
                self.reconnectByIdentifier(reconnectID)
                return
            }

            if let error {
                self.lastError = error.localizedDescription
            }
            self.connectionState = .idle
        }
    }
}

extension AmericanScaleClient: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        onMainActor {
            if let error {
                self.fail(error.localizedDescription)
                return
            }

            guard let service = peripheral.services?.first(where: { $0.uuid == Self.scaleServiceUUID }) else {
                self.fail("American Scale service 108D was not found on this peripheral.")
                return
            }

            peripheral.discoverCharacteristics([Self.scaleCharacteristicUUID], for: service)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        onMainActor {
            if let error {
                self.fail(error.localizedDescription)
                return
            }

            guard service.uuid == Self.scaleServiceUUID,
                  let characteristic = service.characteristics?.first(where: { $0.uuid == Self.scaleCharacteristicUUID }) else {
                self.fail("American Scale characteristic 0001 was not found.")
                return
            }

            let properties = characteristic.properties
            guard properties.contains(.read),
                  properties.contains(.notify),
                  properties.contains(.writeWithoutResponse) else {
                self.fail("Characteristic 0001 does not expose the verified Read/Notify/Write Without Response properties.")
                return
            }

            self.scaleCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            peripheral.readValue(for: characteristic)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        onMainActor {
            guard characteristic.uuid == Self.scaleCharacteristicUUID,
                  self.connectedPeripheral === peripheral, self.scaleCharacteristic === characteristic else { return }

            if let error {
                self.notificationChangeAt = nil
                self.fail(error.localizedDescription)
                return
            }

            if self.notificationChangeAt != nil {
                self.notificationChangeAt = nil
                self.parser.reset()
                self.configureRemoteReadMode()
                return
            }

            guard characteristic.isNotifying else {
                self.fail("Notifications could not be enabled on characteristic 0001.")
                return
            }

            self.knownScaleIdentifiers.insert(peripheral.identifier)
            self.connectionState = .ready
            self.lastError = nil
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        onMainActor {
            guard characteristic.uuid == Self.scaleCharacteristicUUID,
                  self.connectedPeripheral === peripheral, self.scaleCharacteristic === characteristic else { return }
            // With notifications suspended, only a pending GATT read can supply
            // remote evidence. Never re-stamp session.liveWeightLb or cached bytes.
            if !characteristic.isNotifying, self.remoteReads.awaitingReply {
                let deliver = self.remoteReads.received(at: ProcessInfo.processInfo.systemUptime)
                let observedAt = Date()
                if let error { self.failRemoteRead("Scale read failed: \(error.localizedDescription)"); return }
                if deliver {
                    self.readReplyCount += 1
                    var responseParser = AmericanScaleStreamParser()
                    let messages = responseParser.append(characteristic.value ?? Data())
                    let complete = responseParser.bufferedByteCount == 0
                    let weights = complete ? messages.compactMap { message -> Double? in
                        if case .weight(let pounds) = message { return pounds }; return nil
                    } : []
                    let reply = !complete ? "Incomplete reply" : weights.isEmpty ? "No weight in reply" : "Weight received"
                    self.remoteReadStatus = "Read requests: \(self.readRequestCount) • replies: \(self.readReplyCount) • \(reply)"
                    if complete { self.apply(messages) }
                    for pounds in weights { self.onRemoteWeightPacket?(pounds, observedAt) }
                }
                self.configureRemoteReadMode()
                return
            }
            if let error {
                self.lastError = error.localizedDescription
                return
            }
            guard let data = characteristic.value, !data.isEmpty else { return }
            let messages = self.parser.append(data)
            let observedAt = Date()
            // Reject callbacks from a stale peripheral or incomplete connection.
            if self.connectionState == .ready, !self.remoteReadsRequested, self.notificationChangeAt == nil {
                for message in messages {
                    if case .weight(let pounds) = message {
                        self.onRemoteWeightPacket?(pounds, observedAt)
                    }
                }
            }
            self.apply(messages)
        }
    }

    nonisolated public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        onMainActor {
            self.flushPendingWritesIfPossible()
        }
    }
}
#endif
