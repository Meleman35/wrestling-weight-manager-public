// v0.20.30 native shell: Mat Mode recovery; bounded kiosk NFC reads; Tab navigation, NFC, offline nearby Mat Mode bridge; based on v0.16.8 lifecycle/scanner/scale work.
import SwiftUI
import WebKit
import UIKit
import AmericanScaleKit
#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
@preconcurrency import CoreNFC
#endif

private func isWrestlingManagerPage(_ url: URL?) -> Bool {
    WrestlingManagerAppOrigin.contains(url)
}

@MainActor
struct ContentView: View {
    // Keep one client per accessory alive for the lifetime of Wrestling Manager.
    // The setup sheet can open/close without dropping either BLE connection.
    @StateObject private var scaleClient = AmericanScaleClient()
    @StateObject private var nfcClient = WrestlingManagerBluetoothNFC()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("wrestlingManager.lastScalePeripheralID") private var lastScalePeripheralID = ""
    @AppStorage("wrestlingManager.autoConnectScale") private var autoConnectScale = true
    @State private var pauseAutoReconnect = false
    @State private var athleteScaleReleased = false
    @State private var showScale = false
    @AppStorage("wm.offlineMatOpen") private var reopenOfflineMat = false
    @State private var showOfflineMat = false
    @State private var mainWebStarted = false
    @State private var checkedMatRestore = false
    @State private var webUnavailable = false
    @State private var webLoadID = UUID()
    @State private var kioskLocked = false
    @State private var videoCameraVisible = false
    var body: some View {
        NavigationStack {
            Group {
                // On a saved Mat launch, avoid loading the full online app and
                // the local scorebook simultaneously. Keep an already-open app alive.
                if !reopenOfflineMat || mainWebStarted {
                    WrestlingManagerWebView(
                        kioskLocked: $kioskLocked,
                        offlineMatOpen: $showOfflineMat,
                        liveScaleWeight: scaleClient.session.liveWeightLb,
                        scaleBatteryPercent: scaleClient.session.batteryPercent,
                        scaleConnected: scaleClient.connectionState == .ready,
                        nfcClient: nfcClient,
                        onScaleCheckCommand: { command in handleScaleCheckCommand(command) },
                        onLoadState: { available in webUnavailable = !available }
                    )
                    .onAppear { mainWebStarted = true }
                } else {
                    ProgressView("Opening saved Mat Mode…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .id(webLoadID)
            .overlay {
                if webUnavailable && !showOfflineMat {
                    VStack(spacing: 18) {
                        Text("The app could not connect").font(.title2.bold())
                        Text("Offline Mat Mode is available on this device.")
                        Button("Open Offline Mat Mode") { showOfflineMat = true }
                            .buttonStyle(.borderedProminent)
                        Button("Retry connection") { webUnavailable = false; webLoadID = UUID() }
                    }
                    .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Wrestling Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(kioskLocked || videoCameraVisible ? .hidden : .visible, for: .navigationBar)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("wmVideoCameraVisible"))) { note in
                videoCameraVisible = (note.userInfo?["visible"] as? Bool) == true
            }
            .toolbar {
                if !kioskLocked {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showOfflineMat = true } label: {
                            WrestlingMatIcon()
                        }
                        .accessibilityLabel("Offline Mat Mode")
                        .help("Open Offline Mat Mode")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            athleteScaleReleased = false
                            pauseAutoReconnect = false
                            showScale = true
                        } label: {
                            HStack(spacing: 8) {
                                if scaleClient.connectionState == .ready {
                                    WrestlingScaleBatteryIndicator(percent: scaleClient.session.batteryPercent)
                                }
                                Image(systemName: scaleClient.connectionState == .ready ? "scalemass.fill" : "scalemass")
                            }
                        }
                        .accessibilityLabel("Scale & Card Reader Setup")
                    }
                }
            }
            .sheet(isPresented: $showScale) {
                WrestlingScaleSetupView(
                    client: scaleClient,
                    nfcClient: nfcClient,
                    autoConnectEnabled: $autoConnectScale,
                    autoReconnectPaused: $pauseAutoReconnect
                )
            }
        }
        .fullScreenCover(isPresented: $showOfflineMat) {
            WrestlingManagerOfflineMatView { showOfflineMat = false }
        }
        .task {
            guard !checkedMatRestore else { return }
            checkedMatRestore = true
            // Present only after the root view exists; retain the existing exit lock.
            if reopenOfflineMat {
                await Task.yield()
                showOfflineMat = true
            }
        }
        .onChange(of: showOfflineMat) { _, open in
            reopenOfflineMat = open
            nfcClient.setForeground(scenePhase != .background && !open)
            UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && (kioskLocked || open)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = kioskLocked || showOfflineMat
            nfcClient.setForeground(scenePhase != .background && !showOfflineMat)
            nfcClient.setScaleReady(scaleClient.connectionState == .ready)
            attemptAutoScaleConnection()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Permission prompts and Control Center produce .inactive. Only
            // actual backgrounding should suspend reader discovery/keep-alive.
            if newPhase != .inactive { nfcClient.setForeground(newPhase == .active && !showOfflineMat) }
            UIApplication.shared.isIdleTimerDisabled = (newPhase == .active && (kioskLocked || showOfflineMat))
            if newPhase == .active {
                if !athleteScaleReleased { pauseAutoReconnect = false }
                attemptAutoScaleConnection()
            } else if case .scanning = scaleClient.connectionState {
                scaleClient.stopScanning()
            }
        }
        .onChange(of: kioskLocked) { _, locked in
            // While a weigh-in kiosk is locked, keep the iPhone/iPad awake so
            // the operator does not have to unlock the physical device between wrestlers.
            UIApplication.shared.isIdleTimerDisabled = (scenePhase == .active && (locked || showOfflineMat))
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: autoConnectScale) { _, enabled in
            if enabled {
                athleteScaleReleased = false
                pauseAutoReconnect = false
                attemptAutoScaleConnection()
            } else if case .scanning = scaleClient.connectionState {
                scaleClient.stopScanning()
            }
        }
        .onChange(of: scaleClient.connectionState) { _, newState in
            nfcClient.setScaleReady(newState == .ready && !athleteScaleReleased)
            switch newState {
            case .ready:
                if athleteScaleReleased {
                    pauseAutoReconnect = true
                    scaleClient.disconnect()
                    return
                }
                if let identifier = scaleClient.selectedPeripheralIdentifier {
                    lastScalePeripheralID = identifier.uuidString
                }
                pauseAutoReconnect = false
            case .idle, .failed:
                attemptAutoScaleConnection()
            default:
                break
            }
        }
        .onChange(of: scaleClient.discoveredDevices) { _, _ in
            connectRememberedScaleIfFound()
        }
    }
    private func handleScaleCheckCommand(_ command: String) {
        if command == "release" {
            athleteScaleReleased = true
            pauseAutoReconnect = true
            if case .scanning = scaleClient.connectionState { scaleClient.stopScanning() }
            scaleClient.disconnect()
            nfcClient.setScaleReady(false)
        } else if command == "acquire" {
            athleteScaleReleased = false
            pauseAutoReconnect = false
            if scaleClient.connectionState == .ready { return }
            if autoConnectScale, UUID(uuidString: lastScalePeripheralID) != nil {
                attemptAutoScaleConnection()
            } else {
                showScale = true
            }
        }
    }
    private func attemptAutoScaleConnection() {
        guard autoConnectScale,
              !athleteScaleReleased,
              !pauseAutoReconnect,
              scenePhase == .active,
              UUID(uuidString: lastScalePeripheralID) != nil else {
            return
        }
        switch scaleClient.connectionState {
        case .ready, .connecting, .discovering, .scanning, .disconnecting:
            connectRememberedScaleIfFound()
        case .idle, .failed:
            scaleClient.startScanning(knownScaleIdentifier: UUID(uuidString: lastScalePeripheralID))
        case .bluetoothUnavailable:
            // CoreBluetooth will move back to .idle when Bluetooth becomes available.
            break
        }
    }
    private func connectRememberedScaleIfFound() {
        guard autoConnectScale,
              !athleteScaleReleased,
              !pauseAutoReconnect,
              let rememberedID = UUID(uuidString: lastScalePeripheralID),
              case .scanning = scaleClient.connectionState,
              let device = scaleClient.discoveredDevices.first(where: { $0.id == rememberedID }) else {
            return
        }
        scaleClient.connect(to: device)
    }
}


// A wrestling mat: square mat boundary, wrestling circle and center circle.
private struct WrestlingMatIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .stroke(lineWidth: 2)
            Circle()
                .stroke(lineWidth: 1.8)
                .padding(4)
            Circle()
                .stroke(lineWidth: 1.4)
                .frame(width: 7, height: 7)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

@MainActor
private struct WrestlingScaleBatteryIndicator: View {
    let percent: Double?
    private var value: Int? {
        guard let percent, percent.isFinite else { return nil }
        return Int(min(100, max(0, percent)).rounded())
    }
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.65), lineWidth: 1.4)
                if let value {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(value <= 20 ? Color.red.opacity(0.65) : Color.green.opacity(0.65))
                        .frame(width: 36 * CGFloat(value) / 100, height: 14)
                        .padding(.leading, 2)
                }
                Text(value.map { "\($0)%" } ?? "—")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit().frame(width: 40)
            }.frame(width: 40, height: 18)
            Capsule().fill(.primary.opacity(0.65)).frame(width: 2, height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "Scale battery \($0) percent" } ?? "Scale battery unavailable")
    }
}

@MainActor
private struct WrestlingScaleSetupView: View {
    @ObservedObject var client: AmericanScaleClient
    @ObservedObject var nfcClient: WrestlingManagerBluetoothNFC
    @Binding var autoConnectEnabled: Bool
    @Binding var autoReconnectPaused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var statusMessage: String?
    private enum RenameSheet: Identifiable {
        case scale
        case reader(UUID)
        var id: String {
            switch self {
            case .scale: return "scale"
            case .reader(let id): return "reader-" + id.uuidString
            }
        }
    }
    @State private var renameSheet: RenameSheet?
    @State private var renameText = ""
    @State private var renameError: String?
    var body: some View {
        NavigationStack {
            List {
                scaleSection
                WrestlingManagerNFCSetupSection(client: nfcClient) {
                    guard let id = nfcClient.savedReaderIdentifier else { return }
                    renameSheet = .reader(id)
                }
                Section {
                    DisclosureGroup("Connection help") {
                        Text("Turn on your scale or NFC reader, keep it nearby, then tap Find. Only supported devices and your saved scale appear.")
                        Text("If a device is missing, close its connection in other apps, switch it off and on, then search again. The NFC reader connects over Bluetooth.")
                        Text("Auto-connect uses the device you saved. Turning it off keeps the current connection until you disconnect.")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scale & NFC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Own presentation above the List. A Section modifier may be hosted by
        // multiple/recycled rows; scale/reader updates must not dismiss editing.
        .sheet(item: $renameSheet) { target in
            switch target {
            case .reader(let readerID):
                WrestlingManagerNFCRenameView(
                    initialName: nfcClient.savedReaderDisplayName ?? "",
                    save: { name in try nfcClient.renameReader(to: name, expectedReaderID: readerID) },
                    close: { renameSheet = nil }
                )
            case .scale:
                NavigationStack {
                    Form {
                        Section {
                            TextField("Scale name", text: $renameText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } footer: {
                            Text("Use 1–8 characters, without #. The scale reconnects after renaming.")
                        }
                        if let renameError {
                            Text(renameError)
                                .foregroundStyle(.red)
                        }
                    }
                    .navigationTitle("Rename Scale")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { renameSheet = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Rename") {
                                do {
                                    try client.renameScale(to: renameText)
                                    statusMessage = "Rename command sent. The scale may disconnect briefly."
                                    renameSheet = nil
                                } catch {
                                    renameError = error.localizedDescription
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    @AppStorage("wrestlingManager.lastScalePeripheralID") private var savedScaleID = ""
    private var scaleBusy: Bool {
        client.connectionState == .connecting || client.connectionState == .discovering || client.connectionState == .disconnecting
    }
    private var scaleSection: some View {
        Section("Bluetooth scale") {
            HStack(spacing: 12) {
                Image(systemName: "scalemass").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.connectedAdvertisedName ?? "American Scale").font(.headline)
                    Text(connectionLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if client.connectionState == .ready {
                    WrestlingScaleBatteryIndicator(percent: client.session.batteryPercent)
                } else if scaleBusy || client.connectionState == .scanning {
                    ProgressView().accessibilityLabel(connectionLabel)
                }
            }
            Toggle("Auto-connect", isOn: $autoConnectEnabled)
                .accessibilityLabel("Auto-connect scale")
            if client.connectionState == .ready {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(liveWeightText).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("lb").foregroundStyle(.secondary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.5)
                    HStack {
                        Button("Zero") { client.zeroScale(); statusMessage = "Zero command sent." }
                            .accessibilityLabel("Zero scale")
                        Button(client.session.pendingLockIn ? "Waiting…" : "Lock Weight") {
                            client.lockInWeight(); statusMessage = "Waiting for the next scale reading."
                        }
                        .disabled(client.session.pendingLockIn)
                    }
                    .buttonStyle(.bordered)
                    if let statusMessage { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                DisclosureGroup("Scale settings") {
                    Button("Rename Scale") {
                        renameText = client.connectedAdvertisedName ?? ""; renameError = nil; renameSheet = .scale
                    }
                    if let capacity = client.session.capacityLb {
                        LabeledContent("Capacity", value: String(format: "%.1f lb", capacity))
                    }
                    Button("Disconnect", role: .destructive) {
                        autoReconnectPaused = true; client.disconnect()
                    }
                }
            } else if scaleBusy {
                Button("Cancel Connection") { autoReconnectPaused = true; client.disconnect() }
                    .disabled(client.connectionState == .disconnecting)
            } else {
                Button(client.connectionState == .scanning ? "Stop Search" : "Find Scale") {
                    statusMessage = nil
                    if client.connectionState == .scanning {
                        autoReconnectPaused = true; client.stopScanning()
                    } else {
                        // Let the operator select a different scale instead of auto-selecting the saved one.
                        autoReconnectPaused = true
                        client.startScanning(knownScaleIdentifier: UUID(uuidString: savedScaleID))
                    }
                }
                if UUID(uuidString: savedScaleID) != nil && client.connectionState != .scanning {
                    Button("Reconnect Saved Scale") {
                        autoReconnectPaused = false; statusMessage = nil
                        client.reconnectLastScale(knownScaleIdentifier: UUID(uuidString: savedScaleID))
                    }
                }
                ForEach(client.discoveredDevices) { device in
                    Button {
                        statusMessage = nil; client.connect(to: device)
                    } label: {
                        HStack {
                            Text(device.advertisedName).foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            if device.id.uuidString == savedScaleID { Text("Saved").font(.caption).foregroundStyle(.secondary) }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if client.connectionState == .scanning && client.discoveredDevices.isEmpty {
                    Text("Looking for scales…").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error = client.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }
    private var liveWeightText: String {
        guard let weight = client.session.liveWeightLb else { return "—" }
        return String(format: "%.1f", weight)
    }
    private var connectionLabel: String {
        switch client.connectionState {
        case .idle:
            return "Disconnected"
        case .bluetoothUnavailable:
            return "Bluetooth unavailable"
        case .scanning:
            return "Scanning"
        case .connecting:
            return "Connecting"
        case .discovering:
            return "Preparing scale"
        case .ready:
            return "Connected"
        case .disconnecting:
            return "Disconnecting"
        case .failed(let reason):
            return reason.isEmpty ? "Connection error" : "Connection error"
        }
    }
}
@MainActor
struct WrestlingManagerWebView: UIViewRepresentable {
    @Binding var kioskLocked: Bool
    @Binding var offlineMatOpen: Bool
    let liveScaleWeight: Double?
    let scaleBatteryPercent: Double?
    let scaleConnected: Bool
    @ObservedObject var nfcClient: WrestlingManagerBluetoothNFC
    let onScaleCheckCommand: @MainActor @Sendable (String) -> Void
    let onLoadState: @MainActor (Bool) -> Void
    func makeCoordinator() -> Coordinator {
        Coordinator(kioskLocked: $kioskLocked, offlineMatOpen: $offlineMatOpen, onScaleCheckCommand: onScaleCheckCommand, onLoadState: onLoadState)
    }
    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "kioskState")
        controller.add(context.coordinator, name: "athleteScaleCheck")
        controller.add(context.coordinator, name: "officialWeighInExport")
        controller.add(context.coordinator, name: "offlineMatMode")
        controller.add(context.coordinator.securityBridge, name: "security")
        controller.add(context.coordinator.profilePINBridge, name: "wmProfilePin")
        controller.add(context.coordinator.pinRecoveryBridge, name: "wmPINRecovery")
        controller.add(context.coordinator.biometricLoginBridge, name: "biometricLogin")
        controller.add(context.coordinator.travelBridge, name: "travel")
        controller.add(context.coordinator, name: "credentialScanner")
        controller.add(context.coordinator.videoPilotBridge, name: "wmVideoPilot")
        controller.add(context.coordinator.deletionBridge, name: "wmAccountDeletion")
        controller.add(context.coordinator.nfcBridge, name: "athleteNfc")
        controller.add(context.coordinator.notificationBridge, name: "notifications")
        // Use a Wrestling Manager-specific alias as the primary notification
        // channel. Keeping the original name preserves compatibility with
        // already-deployed website builds.
        controller.add(context.coordinator.notificationBridge, name: "wrestlingManagerNotifications")
        controller.addUserScript(
            WKUserScript(
                source: "window.wrestlingManagerNativeShellVersion = '0.20.29'; window.wrestlingManagerNativeLifecycle = true; window.wrestlingManagerNativeOfflineMat = true; window.wrestlingManagerNativeVideoPilot = 1; window.wrestlingManagerNativeVideoSourceRevision = 10;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        controller.addUserScript(WKUserScript(source: WrestlingManagerKeyboard.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: WrestlingManagerVideoScorerUI.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: WrestlingManagerPINRecoveryBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: WrestlingManagerNfcBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: WrestlingManagerNFCWriterUI.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let configuration = WKWebViewConfiguration()
        // iPhone defaults HTML video to the system full-screen player, which
        // hides the web score controls and may leave a paused preview on exit.
        // The web camera already uses playsinline. Set the native half before
        // constructing WKWebView; do not weaken user-gesture/media permissions.
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController = controller
        let webView = WrestlingManagerKeyboardWebView(frame: .zero, configuration: configuration)
        context.coordinator.securityBridge.attach(to: webView)
        context.coordinator.biometricLoginBridge.attach(to: webView)
        context.coordinator.pinRecoveryBridge.attach(to: webView)
        context.coordinator.travelBridge.attach(to: webView)
        context.coordinator.credentialScannerBridge.attach(to: webView)
        context.coordinator.videoPilotBridge.attach(to: webView)
        context.coordinator.deletionBridge.attach(to: webView)
        context.coordinator.nfcBridge.configure(nfcClient)
        context.coordinator.nfcBridge.attach(to: webView)
        context.coordinator.notificationBridge.attach(to: webView)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Wrestling Manager is an app-style interface, not a browser page.
        // Keep the UI at a fixed scale so accidental pinch/double-tap zoom does not
        // leave controls oversized or off screen.
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        context.coordinator.latestNativeScaleWeight = liveScaleWeight
        context.coordinator.scaleBatteryPercent = scaleBatteryPercent
        context.coordinator.scaleConnected = scaleConnected
        context.coordinator.webView = webView
        context.coordinator.purchaseHost = WrestlingManagerPurchaseHost(webView: webView)
        let activation = WrestlingManagerPurchaseActivation(webView: webView, host: context.coordinator.purchaseHost!)
        context.coordinator.purchaseActivation = activation
        controller.addScriptMessageHandler(activation, contentWorld: .page, name: "wmPurchaseActivation")
        context.coordinator.installCameraBackgroundObserver()
        if let url = URL(string: "https://theteammanager.app/?nativeBuild=0.20.31&nativeRevision=20") {
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 30
            )
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            webView.load(request)
        }
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.latestNativeScaleWeight = liveScaleWeight
        context.coordinator.scaleBatteryPercent = scaleBatteryPercent
        context.coordinator.scaleConnected = scaleConnected
        context.coordinator.onScaleCheckCommand = onScaleCheckCommand
        context.coordinator.nfcBridge.sendStatus(force: false)
        context.coordinator.sendScaleConnectionStatus()
        context.coordinator.sendLatestScaleWeightIfPossible()
    }
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "kioskState")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "athleteScaleCheck")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "officialWeighInExport")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "offlineMatMode")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "security")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wmProfilePin")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "credentialScanner")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "notifications")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wrestlingManagerNotifications")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wmVideoPilot")
        coordinator.videoPilotBridge.detach()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wmAccountDeletion")
        coordinator.deletionBridge.detach()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wmPurchaseActivation", contentWorld: .page)
        coordinator.purchaseActivation?.detach()
        coordinator.purchaseActivation = nil
        coordinator.purchaseHost?.detach()
        coordinator.purchaseHost = nil
        coordinator.removeCameraBackgroundObserver()
        coordinator.credentialScannerBridge.cancelForBackground()
        coordinator.notificationBridge.detach(from: webView)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "athleteNfc")
        coordinator.nfcBridge.detach()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "biometricLogin")
        coordinator.biometricLoginBridge.detach()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wmPINRecovery")
        coordinator.pinRecoveryBridge.detach()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "travel")
        coordinator.travelBridge.detach()
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        coordinator.webView = nil
    }
    @MainActor
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        private var kioskLocked: Binding<Bool>
        private var offlineMatOpen: Binding<Bool>
        let securityBridge = WrestlingManagerSecurityBridge()
        let profilePINBridge = WrestlingManagerProfilePINBridge()
        let pinRecoveryBridge = WrestlingManagerPINRecoveryBridge()
        let biometricLoginBridge = WrestlingManagerBiometricLoginBridge()
        let travelBridge = WrestlingManagerTravelBridge()
        let credentialScannerBridge = WrestlingManagerCredentialScannerBridge()
        let videoPilotBridge = WrestlingManagerVideoPilot()
        lazy var deletionBridge = WrestlingManagerDeletionBridge(video: videoPilotBridge, biometric: biometricLoginBridge, recovery: pinRecoveryBridge)
        let nfcBridge = WrestlingManagerNfcBridge()
        let notificationBridge = WrestlingManagerNotificationBridge.shared
        weak var webView: WKWebView?
        var purchaseHost: WrestlingManagerPurchaseHost?
        var purchaseActivation: WrestlingManagerPurchaseActivation?
        private var isSharingOfficialPDF = false
        var latestNativeScaleWeight: Double?
        var scaleBatteryPercent: Double?
        private var lastSentBatteryPercent: Int?
        var scaleConnected = false
        var onScaleCheckCommand: @MainActor @Sendable (String) -> Void
        private var lastSentScaleConnected: Bool?
        private var pageReady = false
        private var lastSentWeight: Double?
        var onLoadState: @MainActor (Bool) -> Void
        init(kioskLocked: Binding<Bool>, offlineMatOpen: Binding<Bool>, onScaleCheckCommand: @escaping @MainActor @Sendable (String) -> Void, onLoadState: @escaping @MainActor (Bool) -> Void) {
            self.onLoadState = onLoadState
            self.kioskLocked = kioskLocked
            self.offlineMatOpen = offlineMatOpen
            self.onScaleCheckCommand = onScaleCheckCommand
        }
        // Close the scanner if the phone really backgrounds. App locking itself
        // is owned by WrestlingManagerSecurityBridge, not by camera visibility.
        func installCameraBackgroundObserver() {
            NotificationCenter.default.addObserver(self, selector: #selector(appEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        }
        func removeCameraBackgroundObserver() { NotificationCenter.default.removeObserver(self) }
        @objc private func appEnteredBackground() {
            purchaseActivation?.stop()
            videoPilotBridge.enteredBackground()
            credentialScannerBridge.cancelForBackground()
            biometricLoginBridge.cancel()
            pinRecoveryBridge.cancel()
            travelBridge.cancel()
        }
        // MARK: - Native Bluetooth -> web kiosk bridge
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            purchaseActivation?.stop()
            deletionBridge.pageChanged()
            videoPilotBridge.reset()
            pageReady = false
            nfcBridge.cancel()
            biometricLoginBridge.cancel()
            pinRecoveryBridge.cancel()
            travelBridge.cancel()
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            purchaseActivation?.stop()
            deletionBridge.pageChanged()
            nfcBridge.cancel()
            pinRecoveryBridge.cancel()
            videoPilotBridge.reset()
            pageReady = false
            onLoadState(false)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onLoadState(false) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onLoadState(false) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadState(true)
            pageReady = true
            self.webView = webView
            sendScaleConnectionStatus(force: true)
            sendLatestScaleWeightIfPossible(force: true)
            securityBridge.webPageDidFinishLoading()
            notificationBridge.webPageDidFinishLoading()
            nfcBridge.sendStatus()
            biometricLoginBridge.sendStatus()
        }
        func sendLatestScaleWeightIfPossible(force: Bool = false) {
            guard pageReady,
                  scaleConnected,
                  let webView,
                  let weight = latestNativeScaleWeight,
                  weight.isFinite else { return }
            // Avoid sending duplicate packets if SwiftUI redraws for another reason.
            if !force, let lastSentWeight, abs(lastSentWeight - weight) < 0.0001 {
                return
            }
            lastSentWeight = weight
            let jsWeight = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), weight)
            let script = "window.wrestlingManagerSetScaleWeight?.(\(jsWeight));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
        func sendScaleConnectionStatus(force: Bool = false) {
            guard pageReady, let webView else { return }
            let battery: Int? = scaleConnected && scaleBatteryPercent?.isFinite == true
                ? Int(min(100, max(0, scaleBatteryPercent ?? 0)).rounded()) : nil
            let connectionChanged = force || lastSentScaleConnected != scaleConnected
            guard connectionChanged || battery != lastSentBatteryPercent else { return }
            lastSentScaleConnected = scaleConnected
            lastSentBatteryPercent = battery
            if !scaleConnected { lastSentWeight = nil }
            let ready = scaleConnected ? "true" : "false"
            let percent = battery.map { String($0) } ?? "null"
            if connectionChanged {
                webView.evaluateJavaScript("window.wrestlingManagerScaleConnectionChanged?.(\(ready));", completionHandler: nil)
            }
            webView.evaluateJavaScript("window.wrestlingManagerScaleStatusChanged?.({connected:\(ready),batteryPercent:\(percent)});", completionHandler: nil)
        }
        // MARK: - External calendar / share links
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "wrestlingmanager" {
                securityBridge.forwardAuthURL(url)
                decisionHandler(.cancel)
                return
            }
            let isExternalScheme = ["webcal", "mailto", "sms", "tel"].contains(scheme)
            let isWrestlingManagerCalendarFile =
                scheme == "https" &&
                (url.host?.hasSuffix("supabase.co") == true) &&
                url.path.contains("/functions/v1/team-calendar")
            if isExternalScheme || isWrestlingManagerCalendarFile {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        // MARK: - Wrestling Manager native bridge
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "offlineMatMode" {
                guard message.frameInfo.isMainFrame,
                      isWrestlingManagerPage(message.frameInfo.request.url),
                      let webView, isWrestlingManagerPage(webView.url),
                      let body = message.body as? [String: Any],
                      body["command"] as? String == "open" else { return }
                purchaseActivation?.stop()
                videoPilotBridge.reset()
                offlineMatOpen.wrappedValue = true
                return
            }
            if message.name == "officialWeighInExport" {
                guard message.frameInfo.isMainFrame,
                      isWrestlingManagerPage(message.frameInfo.request.url),
                      let webView, isWrestlingManagerPage(webView.url),
                      !isSharingOfficialPDF,
                      let body = message.body as? [String: Any],
                      let encoded = body["base64"] as? String,
                      encoded.utf8.count <= 28_000_000,
                      let data = Data(base64Encoded: encoded),
                      data.count <= 20_000_000,
                      data.starts(with: Data("%PDF-".utf8)) else { return }
                guard let presenter = topViewController(from: webView.window?.rootViewController),
                      presenter.viewIfLoaded?.window != nil else {
                    webView.evaluateJavaScript("window.wrestlingManagerOfficialPdfError?.('The share window is not ready. Try Share / Save PDF again.');", completionHandler: nil)
                    return
                }
                let supplied = (body["filename"] as? String) ?? "Official-weigh-in.pdf"
                let stem = String(supplied.replacingOccurrences(of: ".pdf", with: "").prefix(100))
                let safe = stem.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "-" }.joined()
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WM-WeighIn-" + UUID().uuidString, isDirectory: true)
                let file = directory.appendingPathComponent((safe.isEmpty ? "Official-weigh-in" : safe) + ".pdf")
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
                    share.popoverPresentationController?.sourceView = webView
                    share.popoverPresentationController?.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 1, height: 1)
                    share.completionWithItemsHandler = { [weak self] _, _, _, _ in
                        Task { @MainActor in
                            self?.isSharingOfficialPDF = false
                            // Only this export's unique temporary copy is removed.
                            try? FileManager.default.removeItem(at: file)
                            try? FileManager.default.removeItem(at: directory)
                        }
                    }
                    isSharingOfficialPDF = true
                    presenter.present(share, animated: true)
                } catch {
                    try? FileManager.default.removeItem(at: file)
                    try? FileManager.default.removeItem(at: directory)
                    webView.evaluateJavaScript("window.wrestlingManagerOfficialPdfError?.('Could not prepare the PDF for sharing. Keep the sheet and try again.');", completionHandler: nil)
                }
                return
            }
            if message.name == "credentialScanner" {
                guard message.frameInfo.isMainFrame,
                      isWrestlingManagerPage(message.frameInfo.request.url),
                      let webView, isWrestlingManagerPage(webView.url) else {
                    #if DEBUG
                    print("Wrestling Manager scanner: ignored a request outside the app page.")
                    #endif
                    return
                }
                let body = message.body as? [String: Any]
                if body?["command"] as? String == "scan", videoPilotBridge.isCameraBusy {
                    webView.evaluateJavaScript("window.wrestlingManagerCredentialScannerError?.('Stop and save the video, then close the camera before scanning a credential.');", completionHandler: nil)
                    return
                }
                if body?["command"] as? String == "scan" {
                    let cameraUsage = ((Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cameraUsage.isEmpty else {
                        // Check the installed app's Info.plist before the scanner
                        // calls any protected camera API. An absent key makes iOS
                        // terminate the process before a permission prompt appears.
                        #if DEBUG
                        print("Wrestling Manager setup: NSCameraUsageDescription is missing or blank in the installed iPhone/iPad app. Check the iOS target's Info.plist build settings.")
                        #endif
                        webView.evaluateJavaScript("window.wrestlingManagerCredentialScanned?.(''); window.wrestlingManagerCredentialScannerError?.('Camera scanning is not configured in this app build. Please update the app.');", completionHandler: nil)
                        return
                    }
                }
                #if DEBUG
                print("Wrestling Manager scanner: forwarding request to camera scanner.")
                #endif
                credentialScannerBridge.userContentController(userContentController, didReceive: message)
                return
            }
            if message.name == "athleteScaleCheck" {
                guard message.frameInfo.isMainFrame,
                      isWrestlingManagerPage(message.frameInfo.request.url),
                      let body = message.body as? [String: Any],
                      let command = body["command"] as? String,
                      ["acquire", "release", "status"].contains(command) else { return }
                if command != "status" { onScaleCheckCommand(command) }
                sendScaleConnectionStatus(force: true)
                if command == "status" { sendLatestScaleWeightIfPossible(force: true) }
                return
            }
            guard message.name == "kioskState" else { return }
            if let body = message.body as? [String: Any],
               let locked = body["locked"] as? Bool {
                if locked { purchaseActivation?.stop(); videoPilotBridge.reset() }
                kioskLocked.wrappedValue = locked
                nfcBridge.sendStatus()
            }
        }
        // MARK: - JavaScript alert / confirm / prompt support
        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            let alert = UIAlertController(title: "Wrestling Manager", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler()
            })
            present(alert, from: webView, fallback: completionHandler)
        }
        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            let alert = UIAlertController(title: "Wrestling Manager", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completionHandler(false)
            })
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                completionHandler(true)
            })
            present(alert, from: webView) {
                completionHandler(false)
            }
        }
        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            let alert = UIAlertController(title: "Wrestling Manager", message: prompt, preferredStyle: .alert)
            alert.addTextField { field in
                field.text = defaultText
                field.clearButtonMode = .whileEditing
                let lowerPrompt = prompt.lowercased()
                if lowerPrompt.contains("pin") || lowerPrompt.contains("passcode") {
                    // Match the iPhone passcode experience for kiosk PIN entry.
                    field.keyboardType = .numberPad
                    field.isSecureTextEntry = true
                    field.textContentType = .oneTimeCode
                } else if lowerPrompt.contains("weight") {
                    field.keyboardType = .decimalPad
                }
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completionHandler(nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            present(alert, from: webView) {
                completionHandler(nil)
            }
        }
        private func present(
            _ alert: UIAlertController,
            from webView: WKWebView,
            fallback: @escaping () -> Void
        ) {
            guard let presenter = topViewController(from: webView.window?.rootViewController) else {
                fallback()
                return
            }
            presenter.present(alert, animated: true)
        }
        private func topViewController(from root: UIViewController?) -> UIViewController? {
            if let navigation = root as? UINavigationController {
                return topViewController(from: navigation.visibleViewController)
            }
            if let tab = root as? UITabBarController {
                return topViewController(from: tab.selectedViewController)
            }
            if let presented = root?.presentedViewController {
                return topViewController(from: presented)
            }
            return root
        }
    }
}
#Preview {
    ContentView()
}

// Physical NDEF athlete cards. Wallet card emulation is a separate Apple entitlement.
// NFCTagReaderSession uses the TAG entitlement and polls ISO 14443 / ISO 15693.
#if canImport(CoreNFC) && !targetEnvironment(macCatalyst)
@MainActor
final class WrestlingManagerBuiltInNfcBridge: NSObject, WKScriptMessageHandler, @preconcurrency NFCTagReaderSessionDelegate {
    private weak var webView: WKWebView?
    private var reader: NFCTagReaderSession?
    // Non-Sendable SDK objects are held only on MainActor. Callbacks return
    // simple values and a unique operation ID, never a session, tag or message.
    private var connectedTag: NFCNDEFTag?
    private var operationID: UUID?
    private var requestID: String?
    private var writeToken: String?
    private var readTimeoutTask: Task<Void, Never>?
    private var completed = false
    private var connecting = false
    private var backgroundObserver: NSObjectProtocol?

    func attach(to webView: WKWebView) {
        self.webView = webView
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
    func detach() {
        cancel()
        if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
        backgroundObserver = nil
        webView = nil
    }
    private func trusted(_ url: URL?) -> Bool {
        isWrestlingManagerPage(url)
    }
    private var hasUsageDescription: Bool {
        let usage = (Bundle.main.object(forInfoDictionaryKey: "NFCReaderUsageDescription") as? String) ?? ""
        return !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func sendStatus() {
        send(["event": "status", "timedRead": true, "available": hasUsageDescription && UIDevice.current.userInterfaceIdiom == .phone && NFCTagReaderSession.readingAvailable])
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, trusted(message.frameInfo.request.url), trusted(webView?.url),
              let body = message.body as? [String: Any], let command = body["command"] as? String else { return }
        if command == "status" { sendStatus(); return }
        if command == "shareCard" { shareCard(body); return }
        if command == "cancel" {
            if let id = body["requestId"] as? String, id == requestID { cancel() }
            return
        }
        guard ["read", "write"].contains(command), let id = body["requestId"] as? String,
              UUID(uuidString: id) != nil else { return }
        guard reader == nil else {
            send(["requestId": id, "ok": false, "message": "Finish or cancel the current NFC scan first."])
            return
        }
        guard hasUsageDescription else {
            send(["requestId": id, "ok": false, "message": "NFC is not enabled in this app build."])
            return
        }
        guard UIDevice.current.userInterfaceIdiom == .phone, NFCTagReaderSession.readingAvailable else {
            send(["requestId": id, "ok": false, "message": "This device cannot read NFC tags. Use Scan Code."])
            return
        }
        var token: String?
        if command == "write" {
            guard let value = body["token"] as? String, Self.validToken(value) else { return }
            token = value
        }
        guard let session = makeReaderSession() else {
            send(["requestId": id, "ok": false, "message": "Could not start NFC scanning on this device."])
            return
        }
        requestID = id
        writeToken = token
        completed = false
        connecting = false
        connectedTag = nil
        operationID = UUID()
        reader = session
        session.alertMessage = token == nil
            ? "Hold the athlete’s card or wristband against the top of this iPhone."
            : "Hold the card or wristband against the top of this iPhone to program it."
        // A requested kiosk scan is bounded even if the web timer is suspended.
        if command == "read", let seconds = body["timeoutSeconds"] as? Double, seconds.isFinite,
           let activeOperation = operationID {
            let duration = min(30, max(1, seconds))
            session.alertMessage += " Scan ends after \(Int(duration)) seconds."
            readTimeoutTask?.cancel()
            readTimeoutTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) }
                catch { return }
                guard !Task.isCancelled, let self,
                      self.operationID == activeOperation, !self.completed,
                      let reader = self.reader, let id = self.requestID else { return }
                self.completed = true
                self.writeToken = nil
                self.connectedTag = nil
                self.operationID = nil
                self.readTimeoutTask = nil
                self.send(["requestId": id, "ok": false, "timedOut": true,
                           "message": "No card found. Tap the screen to choose NFC or Capture / Scan Card."])
                reader.invalidate()
            }
        }
        session.begin()
    }
    private func makeReaderSession() -> NFCTagReaderSession? {
        // Xcode 26.4 / Swift 6.3 introduced the configuration initializer.
        // Retain the older initializer for builds with earlier SDKs and iOS.
        #if compiler(>=6.3)
        if #available(iOS 26.4, *) {
            let configuration = NFCTagReaderSession.Configuration(
                pollingOption: [.iso14443, .iso15693],
                iso7816SelectIdentifiers: [],
                feliCaSystemCodes: []
            )
            return NFCTagReaderSession(configuration: configuration, delegate: self, queue: .main)
        } else {
            return NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
        }
        #else
        return NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
        #endif
    }
    nonisolated private static func validToken(_ value: String) -> Bool {
        value.range(of: "^(WMC-[A-Za-z0-9_-]{22}|WMWC-[a-f0-9]{48})$", options: .regularExpression) != nil
    }
    nonisolated private static func token(in message: NFCNDEFMessage) -> String? {
        // Decode on the callback's queue. Only the resulting String crosses
        // into a Task; arbitrary tag URLs are never opened.
        for record in message.records {
            guard record.typeNameFormat == .nfcWellKnown, record.type == Data([0x54]),
                  let value = record.wellKnownTypeTextPayload().0, validToken(value) else { continue }
            return value
        }
        return nil
    }
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // All delegate calls run on the .main queue supplied at creation.
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard reader === session, !completed, !connecting, let operationID else { return }
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "Hold only one card or wristband near the iPhone."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, let reader = self.activeReader(for: operationID), !self.connecting else { return }
                reader.restartPolling()
            }
            return
        }
        switch tag {
        case .miFare(let ndefTag): connectedTag = ndefTag
        case .iso15693(let ndefTag): connectedTag = ndefTag
        case .iso7816(let ndefTag): connectedTag = ndefTag
        case .feliCa:
            finish(session, ok: false, message: "Use a writable NTAG or ISO 15693 NDEF card or wristband.")
            return
        @unknown default:
            finish(session, ok: false, message: "This NFC tag type is not supported.")
            return
        }
        connecting = true
        session.connect(to: tag) { [weak self] error in
            let connected = error == nil
            Task { @MainActor [weak self] in
                guard let self, let reader = self.activeReader(for: operationID) else { return }
                if !connected { self.finish(reader, ok: false, message: "Could not connect to the tag. Hold it still and try again."); return }
                self.handleConnectedTag(operationID: operationID)
            }
        }
    }
    private func activeReader(for operationID: UUID) -> NFCTagReaderSession? {
        guard self.operationID == operationID, !completed else { return nil }
        return reader
    }
    private func handleConnectedTag(operationID: UUID) {
        guard activeReader(for: operationID) != nil, let tag = connectedTag else { return }
        tag.queryNDEFStatus { [weak self] status, capacity, error in
            let supported = error == nil && status != .notSupported
            let writable = status == .readWrite
            Task { @MainActor [weak self] in
                self?.handleTagStatus(operationID: operationID, supported: supported, writable: writable, capacity: capacity)
            }
        }
    }
    private func handleTagStatus(operationID: UUID, supported: Bool, writable: Bool, capacity: Int) {
        guard let reader = activeReader(for: operationID), let tag = connectedTag else { return }
        guard supported else {
            finish(reader, ok: false, message: "Use an NDEF-compatible NFC card or wristband."); return
        }
        guard let token = writeToken else {
            readTag(operationID: operationID, expectedToken: nil)
            return
        }
        guard writable else { finish(reader, ok: false, message: "This NFC tag is locked. Use a writable card or wristband."); return }
        guard let record = NFCNDEFPayload.wellKnownTypeTextPayload(string: token, locale: Locale(identifier: "en")) else {
            finish(reader, ok: false, message: "Could not prepare the athlete card."); return
        }
        let payload = NFCNDEFMessage(records: [record])
        guard payload.length <= capacity else { finish(reader, ok: false, message: "This tag does not have enough space for the athlete card."); return }
        tag.writeNDEF(payload) { [weak self] error in
            let written = error == nil
            Task { @MainActor [weak self] in
                guard let self, let reader = self.activeReader(for: operationID) else { return }
                if !written { self.finish(reader, ok: false, message: "The card was not written. Hold the tag still and try again."); return }
                self.readTag(operationID: operationID, expectedToken: token)
            }
        }
    }
    private func readTag(operationID: UUID, expectedToken: String?) {
        guard activeReader(for: operationID) != nil, let tag = connectedTag else { return }
        tag.readNDEF { [weak self] message, error in
            let token = error == nil ? message.flatMap { Self.token(in: $0) } : nil
            Task { @MainActor [weak self] in
                guard let self, let reader = self.activeReader(for: operationID) else { return }
                guard let token else {
                    self.finish(reader, ok: false, message: expectedToken == nil ? "This tag does not contain a Wrestling Manager athlete card." : "The write could not be verified. Keep the tag still and program it again."); return
                }
                if let expectedToken {
                    guard token == expectedToken else { self.finish(reader, ok: false, message: "Card verification failed. Program it again."); return }
                    self.finish(reader, ok: true, message: "Athlete card programmed and verified.")
                } else {
                    self.finish(reader, ok: true, message: "Athlete card read.", token: token)
                }
            }
        }
    }
    private func finish(_ session: NFCTagReaderSession, ok: Bool, message: String, token: String? = nil) {
        guard reader === session, !completed, let id = requestID else { return }
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
        completed = true
        writeToken = nil
        connectedTag = nil
        operationID = nil
        var result: [String: Any] = ["requestId": id, "ok": ok, "message": message]
        if let token { result["token"] = token }
        send(result)
        if ok { session.alertMessage = message; session.invalidate() }
        else { session.invalidate(errorMessage: message) }
    }
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        guard reader === session else { return }
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
        if !completed, let id = requestID {
            let code = (error as? NFCReaderError)?.code
            let cancelled = code == .readerSessionInvalidationErrorUserCanceled
            send(["requestId": id, "ok": false, "cancelled": cancelled,
                  "message": cancelled ? "NFC cancelled." : "NFC scan ended: \(error.localizedDescription)"])
        }
        reader = nil
        requestID = nil
        writeToken = nil
        completed = false
        connecting = false
        connectedTag = nil
        operationID = nil
    }
    func cancel() {
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
        guard let reader else { return }
        if !completed, let id = requestID {
            send(["requestId": id, "ok": false, "cancelled": true])
        }
        completed = true
        writeToken = nil
        connectedTag = nil
        operationID = nil
        reader.invalidate()
    }
    private func send(_ result: [String: Any]) {
        guard let webView, trusted(webView.url), let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.wrestlingManagerNfcResult && window.wrestlingManagerNfcResult(\(json));", completionHandler: nil)
    }
    private func shareCard(_ body: [String: Any]) {
        guard let webView, let source = body["dataUrl"] as? String, source.hasPrefix("data:image/png;base64,"),
              source.count < 3_000_000, let data = Data(base64Encoded: String(source.dropFirst(22))),
              let image = UIImage(data: data) else { return }
        var controller = webView.window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let controller else { return }
        let share = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = webView
        share.popoverPresentationController?.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 1, height: 1)
        controller.present(share, animated: true)
    }
}


#else
@MainActor
final class WrestlingManagerBuiltInNfcBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    func attach(to webView: WKWebView) { self.webView = webView }
    func detach() { webView = nil }
    func cancel() {}
    private func trusted(_ url: URL?) -> Bool { isWrestlingManagerPage(url) }
    func sendStatus() { send(["event": "status", "available": false]) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              trusted(message.frameInfo.request.url), trusted(webView?.url),
              let body = message.body as? [String: Any],
              let command = body["command"] as? String else { return }
        if command == "status" { sendStatus(); return }
        if command == "shareCard" { shareCard(body); return }
        guard ["read", "write"].contains(command),
              let id = body["requestId"] as? String, UUID(uuidString: id) != nil else { return }
        send(["requestId": id, "ok": false,
              "message": "Built-in NFC scanning is unavailable on this Mac. Use Scan Code or enter the athlete code."])
    }
    private func send(_ result: [String: Any]) {
        guard let webView, trusted(webView.url), let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.wrestlingManagerNfcResult && window.wrestlingManagerNfcResult(\(json));", completionHandler: nil)
    }
    private func shareCard(_ body: [String: Any]) {
        guard let webView, let source = body["dataUrl"] as? String, source.hasPrefix("data:image/png;base64,"),
              source.count < 3_000_000, let data = Data(base64Encoded: String(source.dropFirst(22))),
              let image = UIImage(data: data) else { return }
        var controller = webView.window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        guard let controller else { return }
        let share = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = webView
        share.popoverPresentationController?.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 1, height: 1)
        controller.present(share, animated: true)
    }
}

#endif
