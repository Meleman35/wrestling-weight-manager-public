import Foundation
import Combine
@preconcurrency import CoreBluetooth

@MainActor
final class WrestlingManagerBluetoothNFC: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    struct Device: Identifiable, Sendable { let id: UUID; let name: String; let rssi: Int }
    struct ReadFailure: LocalizedError, Sendable {
        let message: String
        var cancelled = false
        var timedOut = false
        var errorDescription: String? { message }
    }
    enum State: String { case idle = "Disconnected", unavailable = "Bluetooth unavailable", scanning = "Looking for reader", connecting = "Connecting", discovering = "Preparing reader", ready = "Connected" }
    private static let service = CBUUID(string: "00003970-817C-48DF-8DB2-476A8134EDE0")
    private static let request = CBUUID(string: "00003971-817C-48DF-8DB2-476A8134EDE0")
    private static let response = CBUUID(string: "00003972-817C-48DF-8DB2-476A8134EDE0")
    private static let notification = CBUUID(string: "00003973-817C-48DF-8DB2-476A8134EDE0")
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private let rememberedKey = "wrestlingManager.lastNFCPeripheralID"
    private let rememberedNameKey = "wrestlingManager.lastNFCPeripheralName"
    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [Device] = []
    @Published private(set) var readerName: String?
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var cardPresent = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var readerNicknames: [String: String] = UserDefaults.standard.dictionary(forKey: "wrestlingManager.nfcReaderNicknames") as? [String: String] ?? [:]
    @Published var autoConnect: Bool = UserDefaults.standard.object(forKey: "wrestlingManager.autoConnectNFC") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: "wrestlingManager.autoConnectNFC")
            if autoConnect { paused = false; reconnectIfNeeded() }
            else {
                retryTask?.cancel()
                // Turning off automatic connection leaves an established link
                // and a manually requested connection alone.
                if automaticConnection, !available {
                    stopSearch(); clearConnection(message: nil)
                }
            }
        }
    }
    var available: Bool { state == .ready && peripheral?.state == .connected && responseCharacteristic?.isNotifying == true && statusCharacteristic?.isNotifying == true }
    private var rememberedID: UUID? { UserDefaults.standard.string(forKey: rememberedKey).flatMap(UUID.init(uuidString:)) }
    var savedReaderIdentifier: UUID? { rememberedID }
    var hasRememberedReader: Bool { rememberedID != nil }
    var rememberedName: String? { UserDefaults.standard.string(forKey: rememberedNameKey) }
    var displayName: String? {
        if let peripheral { return readerNicknames[peripheral.identifier.uuidString] ?? readerName ?? peripheral.name }
        return savedReaderDisplayName
    }
    var savedReaderDisplayName: String? {
        rememberedID.flatMap { readerNicknames[$0.uuidString] } ?? rememberedName
    }
    func displayName(for device: Device) -> String { readerNicknames[device.id.uuidString] ?? device.name }
    func renameReader(to name: String, expectedReaderID: UUID) throws {
        guard let id = rememberedID, id == expectedReaderID else {
            throw ReadFailure(message: "The saved reader changed. Cancel and reopen Rename Reader for the reader you want to name.")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ReadFailure(message: "Use a reader name with 1–40 characters on one line.")
        }
        var names = readerNicknames; names[id.uuidString] = trimmed
        readerNicknames = names
        UserDefaults.standard.set(names, forKey: "wrestlingManager.nfcReaderNicknames")
    }

    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var discovered: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var batteryCharacteristic: CBCharacteristic?
    private var lastBatteryRead: Date?
    private var keepAliveTask: Task<Void, Never>?
    private var automaticConnection = false
    private var readNeedsStatus = false
    private var foreground = true
    private var paused = false
    private var reconnectTarget: UUID?
    private var retryTask: Task<Void, Never>?
    private var connectionTimeout: Task<Void, Never>?
    private var scanTimeout: Task<Void, Never>?
    private var hostSequence: UInt8 = 0
    private var readerSequence: UInt8 = 0
    private var ccidSequence: UInt8 = 0
    private var decoder = WrestlingManagerACRProtocol.Decoder()
    private var outgoing: [[UInt8]] = []
    private var outgoingTotal = 0
    private struct Command {
        let sequence: UInt8
        let responseType: UInt8
        let complete: (Result<WrestlingManagerACRProtocol.Response, ReadFailure>) -> Void
    }
    private var command: Command?
    private var commandTimeout: Task<Void, Never>?
    private var readID: UUID?
    private var readCompletion: ((Result<String, ReadFailure>) -> Void)?
    private var readTimeout: Task<Void, Never>?
    private var readingCard = false
    private var writeToken: String?
    private var writeDidStart = false
    private var writeWaitTask: Task<Void, Never>?
    private var writeStage = "Waiting for card"
    private var writeAuthorization: ((@escaping (Bool) -> Void) -> Void)?
    private var writeConfirmation: ((@escaping (Bool) -> Void) -> Void)?

    override init() { super.init(); _ = central }

    func setScaleReady(_ ready: Bool) {
        if ready { reconnectIfNeeded() }
        // This is only an extra opportunity to retry. Opening the app, enabling
        // auto-connect, and restoring Bluetooth work without a connected scale.
    }
    func setForeground(_ active: Bool) {
        foreground = active
        if active { reconnectIfNeeded(); startKeepAlive(); refreshBattery(force: true) }
        else {
            retryTask?.cancel(); keepAliveTask?.cancel(); stopSearch(); cancelRead()
            if state == .connecting || state == .discovering { clearConnection(message: nil) }
        }
    }
    func scan() {
        if available { lastMessage = "Reader is already connected."; return }
        paused = true // Browsing for a replacement must not auto-select the old reader.
        retryTask?.cancel()
        if peripheral != nil { clearConnection(message: nil) }
        startScan(target: nil)
    }
    func cancelConnection() { disconnect() }

    private func startScan(target: UUID?, automatic: Bool = false) {
        guard foreground, peripheral == nil else { return }
        guard central.state == .poweredOn else { changeState(.unavailable); return }
        retryTask?.cancel(); scanTimeout?.cancel()
        devices = []; discovered = [:]; reconnectTarget = target; automaticConnection = automatic
        changeState(.scanning)
        // Reuse a known peripheral even if it is not presently advertising.
        if let target, let known = central.retrievePeripherals(withIdentifiers: [target]).first {
            discovered[target] = known
            let device = Device(id: target, name: known.name ?? rememberedName ?? "ACS NFC reader", rssi: 0)
            devices = [device]
            connect(device, automatic: automatic)
            return
        }
        // Some advertising packets omit the service UUID. Accept only the
        // ACS service or ACR1555 name, then verify service/properties on connect.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, self.state == .scanning else { return }
            self.stopSearch()
            self.lastMessage = "Reader not found. Turn it on and disconnect it in nRF Connect or the ACS utility."
            self.scheduleReconnect()
        }
    }
    func stopSearch() {
        central.stopScan(); scanTimeout?.cancel(); reconnectTarget = nil
        if state == .scanning { changeState(.idle) }
    }
    func connect(_ device: Device, automatic: Bool = false) {
        guard peripheral == nil, let selected = discovered[device.id] else { return }
        paused = false; stopSearch(); retryTask?.cancel(); automaticConnection = automatic
        peripheral = selected; readerName = device.name; lastMessage = nil
        batteryPercent = nil; batteryCharacteristic = nil; lastBatteryRead = nil
        selected.delegate = self
        changeState(.connecting)
        central.connect(selected)
        connectionTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, self.peripheral === selected, self.state != .ready else { return }
            self.connectionFailed("Reader connection timed out. Disconnect other reader apps and try again.")
        }
    }
    func reconnect() { paused = false; reconnectIfNeeded(manual: true) }
    private func reconnectIfNeeded(manual: Bool = false) {
        guard foreground, !paused, peripheral == nil, state != .scanning,
              manual || autoConnect,
              let id = rememberedID else { return }
        startScan(target: id, automatic: !manual)
    }
    private func scheduleReconnect() {
        guard foreground, autoConnect, !paused, hasRememberedReader else { return }
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            self?.reconnectIfNeeded()
        }
    }
    func disconnect() {
        paused = true; retryTask?.cancel(); keepAliveTask?.cancel(); stopSearch()
        cancelRead(); clearConnection(message: nil)
    }
    func forget() {
        let forgottenID = rememberedID
        disconnect()
        if let forgottenID {
            var names = readerNicknames; names.removeValue(forKey: forgottenID.uuidString)
            readerNicknames = names
            UserDefaults.standard.set(names, forKey: "wrestlingManager.nfcReaderNicknames")
        }
        UserDefaults.standard.removeObject(forKey: rememberedKey)
        UserDefaults.standard.removeObject(forKey: rememberedNameKey)
        readerName = nil
    }
    private func changeState(_ value: State) { state = value }
    private func startKeepAlive() {
        keepAliveTask?.cancel()
        guard foreground, available else { return }
        keepAliveTask = Task { @MainActor [weak self] in
            // ACS sleeps after 60 seconds without an operation by default.
            // A read-only status operation keeps an active station responsive;
            // do not leave permanent sleep settings changed on the accessory.
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                guard let self, self.foreground, self.available else { return }
                self.refreshBattery()
                self.pollIdleReader()
            }
        }
    }
    private func refreshBattery(force: Bool = false) {
        // Optional telemetry uses the standard GATT read, never a card command.
        // Give card work priority; notifications can still update while scanning.
        guard foreground, command == nil, !readingCard, readID == nil,
              let peripheral, peripheral.state == .connected,
              let characteristic = batteryCharacteristic, characteristic.properties.contains(.read) else { return }
        let now = Date()
        if !force, let lastBatteryRead, now.timeIntervalSince(lastBatteryRead) < 60 { return }
        lastBatteryRead = now
        peripheral.readValue(for: characteristic)
    }
    private func pollIdleReader(allowWriteWait: Bool = false) {
        guard command == nil, !readingCard, writeToken == nil || allowWriteWait else { return }
        exchange(0x65, expected: 0x81) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                self.cardPresent = response.status & 3 < 2
                if self.cardPresent, let id = self.readID { self.beginCard(id) }
            case .failure(let error): self.connectionFailed(error.message)
            }
        }
    }
    private func connectionFailed(_ message: String) {
        clearConnection(message: message)
        scheduleReconnect()
    }
    private func clearConnection(message: String?) {
        connectionTimeout?.cancel(); commandTimeout?.cancel(); keepAliveTask?.cancel()
        let old = peripheral
        automaticConnection = false
        peripheral = nil; writeCharacteristic = nil; responseCharacteristic = nil; statusCharacteristic = nil
        batteryCharacteristic = nil; lastBatteryRead = nil; batteryPercent = nil
        command = nil; outgoing = []; decoder.reset()
        hostSequence = 0; readerSequence = 0; ccidSequence = 0; cardPresent = false
        if let message { lastMessage = message }
        finishRead(.failure(ReadFailure(message: message ?? "Reader disconnected.")))
        changeState(central.state == .poweredOn ? .idle : .unavailable)
        if let old { central.cancelPeripheralConnection(old) }
    }

    func read(timeout: Double, completion: @escaping (Result<String, ReadFailure>) -> Void) {
        guard available, foreground else { completion(.failure(ReadFailure(message: "Connect the NFC reader in Scale & Card Reader Setup."))); return }
        guard readID == nil else { completion(.failure(ReadFailure(message: "The reader is finishing a scan. Try again."))); return }
        let id = UUID(); readID = id; readCompletion = completion; readingCard = false; readNeedsStatus = true
        lastMessage = "Hold one programmed athlete card on the reader."
        readTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(min(30, max(1, timeout)) * 1_000_000_000)) } catch { return }
            guard let self, self.readID == id else { return }
            self.finishRead(.failure(ReadFailure(message: "No athlete card read in time. Tap NFC to try again.", timedOut: true)))
        }
        startRequestedReadIfIdle()
    }
    private func startRequestedReadIfIdle() {
        guard let id = readID, readNeedsStatus, command == nil, available else { return }
        readNeedsStatus = false
        // Query slot status so a card already resting on the reader is found.
        exchange(0x65, expected: 0x81) { [weak self] result in
            guard let self, self.readID == id else { return }
            switch result {
            case .success(let response):
                self.cardPresent = response.status & 3 < 2
                if self.cardPresent { self.beginCard(id) }
            case .failure(let error): self.finishRead(.failure(error))
            }
        }
    }
    func cancelRead() { finishRead(.failure(ReadFailure(message: "NFC cancelled.", cancelled: true))) }
    private func finishRead(_ result: Result<String, ReadFailure>) {
        guard readID != nil else { return }
        let wasWriting = writeToken != nil
        var result = result
        if writeDidStart, case .failure(let error) = result {
            result = .failure(ReadFailure(message: error.message + " The card may be partially programmed. Keep it out of use and program it again to verify it.", cancelled: error.cancelled, timedOut: error.timedOut))
        }
        let complete = readCompletion
        readID = nil; readCompletion = nil; readTimeout?.cancel(); readTimeout = nil; readingCard = false; readNeedsStatus = false
        writeToken = nil; writeDidStart = false; writeAuthorization = nil; writeConfirmation = nil
        writeWaitTask?.cancel(); writeWaitTask = nil
        switch result {
        case .success: lastMessage = wasWriting ? "Athlete card programmed and verified." : "Athlete card read."
        case .failure(let error): lastMessage = error.message
        }
        if wasWriting, !outgoing.isEmpty {
            // Discard an unsent page on cancellation/failure and reset only the
            // NFC transport so a partial frame cannot reach a later operation.
            clearConnection(message: lastMessage); scheduleReconnect()
        }
        complete?(result)
    }
    private func beginCard(_ id: UUID) {
        guard readID == id, !readingCard, command == nil else { return }
        readingCard = true; readNeedsStatus = false
        if writeToken != nil {
            writeWaitTask?.cancel(); writeWaitTask = nil
            setWriteStage("Card detected. Starting the reader…", id: id)
        }
        exchange(0x62, expected: 0x80) { [weak self] result in
            guard let self, self.readID == id else { return }
            switch result {
            case .failure(let error): self.finishRead(.failure(error))
            case .success:
                if self.writeToken != nil { self.inspectForWrite(id); return }
                self.readPage(3, count: 4, id: id) { [weak self] result in
                    guard let self, self.readID == id else { return }
                    do {
                        let cc = try result.get()
                        let size = try WrestlingManagerACRProtocol.capacity(cc)
                        self.readMemory([], size: size, id: id)
                    } catch {
                        self.finishRead(.failure(ReadFailure(message: "Use an NTAG213, NTAG215 or NTAG216 card programmed in Wrestling Manager. This card could not be read as a supported athlete card.")))
                    }
                }
            }
        }
    }
    private func readMemory(_ bytes: [UInt8], size: Int, id: UUID) {
        guard readID == id else { return }
        if bytes.count == size {
            do { finishRead(.success(try WrestlingManagerACRProtocol.credential(in: bytes))) }
            catch {
                finishRead(.failure(ReadFailure(message: "This card has no readable Wrestling Manager athlete credential. Program it from Athlete Cards, then try again.")))
            }
            return
        }
        let count = min(64, size - bytes.count)
        readPage(4 + bytes.count / 4, count: count, id: id) { [weak self] result in
            guard let self, self.readID == id else { return }
            switch result {
            case .success(let data): self.readMemory(bytes + data, size: size, id: id)
            case .failure(let error): self.finishRead(.failure(error))
            }
        }
    }
    private func readPage(_ page: Int, count: Int, id: UUID, completion: @escaping (Result<[UInt8], ReadFailure>) -> Void) {
        exchange(0x6F, data: [0xFF, 0xB0, UInt8(page >> 8), UInt8(page & 255), UInt8(count)], expected: 0x80) { [weak self] result in
            guard self?.readID == id else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let response):
                guard response.data.count == count + 2, response.data.suffix(2).elementsEqual([0x90, 0]) else {
                    completion(.failure(ReadFailure(message: "Card read failed. Keep one supported, programmed card on the reader."))); return
                }
                completion(.success(Array(response.data.dropLast(2))))
            }
        }
    }
    private func exchange(_ type: UInt8, data: [UInt8] = [], expected: UInt8,
                          completion: @escaping (Result<WrestlingManagerACRProtocol.Response, ReadFailure>) -> Void) {
        guard command == nil, let peripheral, let _ = writeCharacteristic, available else {
            completion(.failure(ReadFailure(message: "NFC reader is not ready."))); return
        }
        let sequence = ccidSequence; ccidSequence &+= 1
        let payload = WrestlingManagerACRProtocol.command(type, sequence: sequence, data: data)
        let limit = min(236, peripheral.maximumWriteValueLength(for: .withoutResponse) - 9)
        guard limit > 0 else { connectionFailed("Reader Bluetooth packet size is unsupported."); return }
        command = Command(sequence: sequence, responseType: expected, complete: completion)
        outgoingTotal = payload.count
        outgoing = stride(from: 0, to: payload.count, by: limit).map { Array(payload[$0..<min($0 + limit, payload.count)]) }
        decoder.reset()
        commandTimeout?.cancel()
        commandTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            guard let self, self.command?.sequence == sequence else { return }
            self.connectionFailed("The NFC reader did not respond. Reconnect and try again.")
        }
        flush()
    }
    private func flush() {
        guard let peripheral, let characteristic = writeCharacteristic else { return }
        while !outgoing.isEmpty, peripheral.canSendWriteWithoutResponse {
            let chunk = outgoing.removeFirst()
            let data = WrestlingManagerACRProtocol.frame(chunk, total: outgoingTotal, host: hostSequence, reader: readerSequence)
            hostSequence &+= 1
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { if state == .unavailable { changeState(.idle) }; reconnectIfNeeded() }
        else { stopSearch(); clearConnection(message: "Bluetooth is unavailable. Enable Bluetooth for Wrestling Manager.") }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard state == .scanning else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "ACS NFC reader"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []) + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        guard services.contains(Self.service) || name.uppercased().hasPrefix("ACR1555") || peripheral.identifier == reconnectTarget else { return }
        discovered[peripheral.identifier] = peripheral
        if !devices.contains(where: { $0.id == peripheral.identifier }) {
            devices.append(Device(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        }
        if reconnectTarget == peripheral.identifier, let device = devices.first(where: { $0.id == peripheral.identifier }) { connect(device, automatic: automaticConnection) }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral === peripheral else { return }
        changeState(.discovering); peripheral.discoverServices([Self.service, Self.batteryService])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        connectionFailed("Could not connect to the NFC reader. Disconnect it in other apps and try again.")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        connectionFailed("NFC reader disconnected.")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            connectionFailed("The selected device does not expose the ACS reader service."); return
        }
        peripheral.discoverCharacteristics([Self.request, Self.response, Self.notification], for: service)
        if let battery = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: battery)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral === peripheral else { return }
        if service.uuid == Self.batteryService {
            // Missing/unreadable battery data must not disconnect a working reader.
            guard error == nil, let battery = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else { return }
            batteryCharacteristic = battery
            refreshBattery(force: true)
            if battery.properties.contains(.notify) { peripheral.setNotifyValue(true, for: battery) }
            return
        }
        guard service.uuid == Self.service else { return }
        guard error == nil, let chars = service.characteristics,
              let write = chars.first(where: { $0.uuid == Self.request && $0.properties.contains(.writeWithoutResponse) }),
              let response = chars.first(where: { $0.uuid == Self.response && $0.properties.contains(.notify) }),
              let status = chars.first(where: { $0.uuid == Self.notification && $0.properties.contains(.notify) }) else {
            connectionFailed("The NFC reader's Bluetooth services are incomplete."); return
        }
        writeCharacteristic = write; responseCharacteristic = response; statusCharacteristic = status
        peripheral.setNotifyValue(true, for: response); peripheral.setNotifyValue(true, for: status)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        // Battery notifications are optional; periodic reads provide a fallback.
        if characteristic.uuid == Self.batteryLevel { return }
        guard error == nil, characteristic.isNotifying else { connectionFailed("Could not receive data from the NFC reader."); return }
        if responseCharacteristic?.isNotifying == true, statusCharacteristic?.isNotifying == true, state != .ready {
            connectionTimeout?.cancel()
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: rememberedKey)
            UserDefaults.standard.set(readerName, forKey: rememberedNameKey)
            lastMessage = "Reader ready. Scan a programmed athlete card in weigh-ins."
            changeState(.ready)
            startKeepAlive()
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if self.peripheral === peripheral { flush() }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        if characteristic.uuid == Self.batteryLevel {
            guard characteristic === batteryCharacteristic else { return }
            guard error == nil, let value = characteristic.value, value.count == 1,
                  let percent = value.first, percent <= 100 else { batteryPercent = nil; return }
            batteryPercent = Int(percent)
            return
        }
        guard error == nil, let value = characteristic.value else { connectionFailed("NFC reader data could not be received."); return }
        if characteristic.uuid == Self.notification {
            guard let present = WrestlingManagerACRProtocol.cardPresent(value) else { return }
            cardPresent = present
            if !present, readingCard { finishRead(.failure(ReadFailure(message: writeToken == nil ? "Card removed too soon. Hold it on the reader until the athlete appears." : "Card removed before programming was verified."))) }
            if present, let id = readID { beginCard(id) }
            return
        }
        guard characteristic.uuid == Self.response else { return }
        do {
            let response = try decoder.accept(value)
            readerSequence &+= 1
            guard let response, let pending = command, response.sequence == pending.sequence else { return }
            if response.status & 0xC0 == 0x80 { return } // CCID time extension, bounded by our timer.
            command = nil; commandTimeout?.cancel(); outgoing = []
            if response.type == 0x53 || response.status & 0xC0 != 0 {
                pending.complete(.failure(ReadFailure(message: "Reader rejected the card command (\(String(format: "%02X", response.error))). Keep the card still and retry.")))
            } else if response.type != pending.responseType || (response.type == 0x80 && response.chain != 0) {
                pending.complete(.failure(ReadFailure(message: "Reader returned an unsupported card response.")))
            } else { pending.complete(.success(response)) }
            startRequestedReadIfIdle()
        } catch { connectionFailed("The NFC reader sent an incomplete or damaged response. Reconnect and try again.") }
    }
}

// Shares the existing single-command transport and operation ID with reads.
extension WrestlingManagerBluetoothNFC {
    func write(token: String, authorize: @escaping (@escaping (Bool) -> Void) -> Void,
               confirmReplacement: @escaping (@escaping (Bool) -> Void) -> Void,
               completion: @escaping (Result<String, ReadFailure>) -> Void) {
        guard available, foreground, WrestlingManagerACRProtocol.validToken(token) else {
            completion(.failure(ReadFailure(message: "Connect the selected NFC reader and open the athlete's current card."))); return
        }
        guard readID == nil else { completion(.failure(ReadFailure(message: "Finish or cancel the current card operation first."))); return }
        let id = UUID()
        readID = id; readCompletion = completion; readingCard = false; readNeedsStatus = true
        writeToken = token; writeDidStart = false; writeAuthorization = authorize; writeConfirmation = confirmReplacement
        setWriteStage("Waiting for a card. Place one writable card flat on the reader.", id: id)
        readTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
            guard let self, self.readID == id else { return }
            self.finishRead(.failure(ReadFailure(message: "Programming timed out at: \(self.writeStage). Lift the card off, place it flat on the reader and try again.", timedOut: true)))
        }
        startRequestedReadIfIdle()
        // A missing card-arrival notification must not leave programming
        // waiting forever. Poll slot status only while waiting for a card;
        // stop this task before power-on, inspection, confirmation or writing.
        writeWaitTask?.cancel()
        writeWaitTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard let self, self.readID == id, self.writeToken != nil,
                      self.foreground, self.available, !self.readingCard else { return }
                self.pollIdleReader(allowWriteWait: true)
            }
        }
    }
    private func setWriteStage(_ text: String, id: UUID) {
        guard readID == id, writeToken != nil else { return }
        writeStage = text; lastMessage = text
    }
    private func writeAllowed(_ id: UUID, then: @escaping () -> Void) {
        guard readID == id, writeToken != nil, foreground, available, let check = writeAuthorization else { return }
        check { [weak self] allowed in
            guard let self, self.readID == id else { return }
            guard allowed, self.foreground, self.available else {
                self.finishRead(.failure(ReadFailure(message: "The athlete, team, account or programming screen changed. Open the intended athlete card and try again.", cancelled: true))); return
            }
            then()
        }
    }
    private func writeAPDU(_ bytes: [UInt8], count: Int, id: UUID,
                           completion: @escaping ([UInt8]) -> Void) {
        guard readID == id else { return }
        exchange(0x6F, data: bytes, expected: 0x80) { [weak self] result in
            guard let self, self.readID == id else { return }
            switch result {
            case .failure(let error): self.finishRead(.failure(ReadFailure(message: "\(self.writeStage) \(error.message)", cancelled: error.cancelled, timedOut: error.timedOut)))
            case .success(let response):
                guard response.data.count == count + 2, response.data.suffix(2).elementsEqual([0x90, 0]) else {
                    let code = response.data.count >= 2 ? response.data.suffix(2).map { String(format: "%02X", $0) }.joined() : "short reply"
                    let hint = bytes == [0xFF, 0, 0, 0, 1, 0x60]
                        ? "The reader could not identify this card with the supported command."
                        : "The reader rejected this card operation."
                    self.finishRead(.failure(ReadFailure(message: "\(self.writeStage) \(hint) Reader code: \(code)."))); return
                }
                completion(Array(response.data.dropLast(2)))
            }
        }
    }
    private func writeReadPage(_ page: Int, count: Int, id: UUID, completion: @escaping ([UInt8]) -> Void) {
        readPage(page, count: count, id: id) { [weak self] result in
            guard let self, self.readID == id else { return }
            switch result {
            case .success(let bytes): completion(bytes)
            case .failure(let error): self.finishRead(.failure(ReadFailure(message: "\(self.writeStage) \(error.message)", cancelled: error.cancelled, timedOut: error.timedOut)))
            }
        }
    }
    private func writeUID(_ id: UUID, completion: @escaping ([UInt8]) -> Void) {
        // Read the physical manufacturer pages, not the reader's cached UID.
        // This identifies card continuity only; athlete identity is the NDEF token.
        writeReadPage(0, count: 12, id: id) { bytes in
            completion(Array(bytes[0..<3]) + Array(bytes[4..<8]))
        }
    }
    private func writeMemory(_ bytes: [UInt8] = [], size: Int, id: UUID, completion: @escaping ([UInt8]) -> Void) {
        guard readID == id else { return }
        if bytes.count == size { completion(bytes); return }
        writeReadPage(4 + bytes.count / 4, count: min(64, size - bytes.count), id: id) { [weak self] data in
            self?.writeMemory(bytes + data, size: size, id: id, completion: completion)
        }
    }
    private func inspectForWrite(_ id: UUID) {
        writeAllowed(id) { [weak self] in
            guard let self else { return }
            // GET_VERSION requires ACS pass-through firmware support. Failure
            // is safe and explicit; do not guess a type from capacity alone.
            self.setWriteStage("Checking card type…", id: id)
            self.writeAPDU([0xFF, 0, 0, 0, 1, 0x60], count: 8, id: id) { [weak self] version in
                guard let self else { return }
                do {
                    let lockPage = try WrestlingManagerNFCWritePlan.lockPage(version: version)
                    self.setWriteStage("Checking card memory and protection…", id: id)
                    self.writeReadPage(0, count: 16, id: id) { [weak self] header in
                        self?.writeReadPage(lockPage, count: 12, id: id) { [weak self] protection in
                            guard let self else { return }
                            do {
                                let layout = try WrestlingManagerNFCWritePlan.layout(version: version, header: header, protection: protection)
                                guard let token = self.writeToken else { return }
                                self.writeUID(id) { [weak self] uid in
                                    self?.setWriteStage("Reading the card's current contents…", id: id)
                                    self?.writeMemory(size: layout.capacity, id: id) { [weak self] old in
                                        guard let self else { return }
                                        do {
                                            let ndefOffset = try WrestlingManagerNFCWritePlan.validateMapping(old)
                                            let target = try WrestlingManagerNFCWritePlan.memory(token: token, capacity: layout.capacity, prefix: Array(old.prefix(ndefOffset)))
                                            self.reviewWrite(id, uid: uid, old: old, target: target, ndefOffset: ndefOffset, header: header, protection: protection, lockPage: lockPage)
                                        } catch { self.finishRead(.failure(ReadFailure(message: error.localizedDescription))) }
                                    }
                                }
                            } catch { self.finishRead(.failure(ReadFailure(message: error.localizedDescription))) }
                        }
                    }
                } catch { self.finishRead(.failure(ReadFailure(message: error.localizedDescription))) }
            }
        }
    }
    private func reviewWrite(_ id: UUID, uid: [UInt8], old: [UInt8], target: [UInt8], ndefOffset: Int, header: [UInt8], protection: [UInt8], lockPage: Int) {
        guard readID == id else { return }
        let proceed: () -> Void = { [weak self] in
            self?.writeAllowed(id) { [weak self] in
                guard let self else { return }
                // Recheck the same physical card, protection and complete old
                // contents after the potentially long replacement prompt.
                self.writeUID(id) { [weak self] current in
                    guard let self else { return }
                    guard current == uid else { self.changedWriteCard(); return }
                    self.writeReadPage(0, count: 16, id: id) { [weak self] currentHeader in
                        guard let self else { return }
                        guard currentHeader == header else { self.changedWriteCard(); return }
                        self.writeReadPage(lockPage, count: 12, id: id) { [weak self] currentProtection in
                            guard let self else { return }
                            guard currentProtection == protection else { self.changedWriteCard(); return }
                            self.writeMemory(size: old.count, id: id) { [weak self] currentMemory in
                                guard let self else { return }
                                guard currentMemory == old else { self.changedWriteCard(); return }
                                self.lastMessage = "Programming card. Keep it still until verification finishes."
                                self.writeNextPage(0, pages: WrestlingManagerNFCWritePlan.pages(memory: target, ndefOffset: ndefOffset), id: id, uid: uid, target: target)
                            }
                        }
                    }
                }
            }
        }
        if WrestlingManagerNFCWritePlan.isBlank(Array(old.dropFirst(ndefOffset))) { proceed() }
        else {
            setWriteStage("This card already has content. Confirm replacement below.", id: id)
            guard let confirm = writeConfirmation else { cancelRead(); return }
            confirm { [weak self] accepted in
                guard let self, self.readID == id else { return }
                if accepted { proceed() }
                else { self.finishRead(.failure(ReadFailure(message: "Replacement cancelled. The card was not changed.", cancelled: true))) }
            }
        }
    }
    private func changedWriteCard() {
        finishRead(.failure(ReadFailure(message: "The card or its contents changed. Remove other cards and restart programming.")))
    }
    private func writeNextPage(_ index: Int, pages: [(page: Int, data: [UInt8])], id: UUID, uid: [UInt8], target: [UInt8]) {
        writeAllowed(id) { [weak self] in
            guard let self else { return }
            self.writeUID(id) { [weak self] current in
                guard let self else { return }
                guard current == uid else { self.changedWriteCard(); return }
                if index == pages.count { self.verifyWrittenCard(id, uid: uid, target: target); return }
                // Validate web scope again after the identity round trip and
                // immediately before sending each destructive page command.
                self.writeAllowed(id) { [weak self] in
                    guard let self else { return }
                    let next = pages[index]
                    self.setWriteStage("Programming card: \(index * 100 / pages.count)%. Keep it still.", id: id)
                    self.writeDidStart = true
                    self.writeAPDU([0xFF, 0xD6, UInt8(next.page >> 8), UInt8(next.page & 255), 4] + next.data, count: 0, id: id) { [weak self] _ in
                        self?.writeNextPage(index + 1, pages: pages, id: id, uid: uid, target: target)
                    }
                }
            }
        }
    }
    private func verifyWrittenCard(_ id: UUID, uid: [UInt8], target: [UInt8]) {
        setWriteStage("Reading the card back to verify it…", id: id)
        writeMemory(size: target.count, id: id) { [weak self] actual in
            guard let self, let token = self.writeToken else { return }
            guard actual == target, (try? WrestlingManagerACRProtocol.credential(in: actual)) == token else {
                self.finishRead(.failure(ReadFailure(message: "Card verification failed. Keep the card still and program it again."))); return
            }
            self.writeUID(id) { [weak self] current in
                guard let self else { return }
                guard current == uid else { self.changedWriteCard(); return }
                self.writeAllowed(id) { [weak self] in self?.finishRead(.success(token)) }
            }
        }
    }
}
