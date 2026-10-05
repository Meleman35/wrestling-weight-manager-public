import SwiftUI
import AmericanScaleKit

@main
struct RemoteScaleCheckApp: App {
    var body: some Scene { WindowGroup { RemoteScaleCheckHome() } }
}

@MainActor
private struct RemoteScaleCheckHome: View {
    private enum ScanMode: String, CaseIterable {
        case simulated = "Tap to simulate NFC"
        case reader = "NFC reader"
        case automatic = "No scan (automatic)"
    }
    @StateObject private var scale = AmericanScaleClient()
    @State private var showScale = false
    @State private var showCheck = false
    @StateObject private var nfc = WrestlingManagerBluetoothNFC()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showReader = false
    @State private var scanMode: ScanMode = .simulated
    @State private var cardReader: WrestlingManagerRemoteCardReader?
    #if DEBUG
    private func readCard(_ completion: @escaping (Result<String, Error>) -> Void) {
        if cardReader == nil {
            let reader = nfc
            cardReader = WrestlingManagerRemoteCardReader(isAvailable: { reader.available },
                isCardPresent: { reader.cardPresent }, startRead: { reply in
                    reader.read(timeout: 30) { result in
                        switch result {
                        case .success(let token): reply(.success(token))
                        case .failure(let error): reply(.failure(error.timedOut
                            ? WrestlingManagerRemoteCardReader.Failure.timedOut
                            : WrestlingManagerRemoteCardReader.Failure.unavailable(error.message)))
                        }
                    }
                }, cancelRead: { reader.cancelRead() })
        }
        cardReader?.read(completion)
    }
    #endif

    @ViewBuilder private var identificationControls: some View {
        Picker("Athlete identification", selection: $scanMode) {
            ForEach(ScanMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
        }.pickerStyle(.menu)
        if scanMode == .reader {
            Button("Connect NFC reader") { showReader = true }.buttonStyle(.bordered)
            Text(nfc.available ? "NFC reader connected" : "Connect your NFC reader to test athlete cards.").font(.caption)
        } else if scanMode == .simulated {
            Text("No NFC reader needed. Choose a test athlete and tap Simulate NFC scan before stepping on.").font(.caption)
        }
    }
    private var homeContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    Text("Camera + American Scale").font(.largeTitle.bold())
                    Text("Device check • Build 7").font(.caption)
                    Text("Separate development test. Your Wrestling Manager app and athlete records are not used.")
                    Text("1. Connect the scale.\n2. Check the camera framing.\n3. Start the continuous test. Scan, step on, then step off after the photo.")
                }
                Button("Connect American Scale") { showScale = true }.buttonStyle(.borderedProminent)
                identificationControls
                #if DEBUG
                Button("Open camera & scale check") { showCheck = true }
                    .buttonStyle(.borderedProminent).disabled(scale.connectionState != .ready || (scanMode == .reader && !nfc.available))
                #else
                Text("Use a Debug build for this development test.")
                #endif
                Text(scale.connectionState == .ready ? "Scale connected" : "Connect the scale to continue.")
                Text("No sign-in, subscriptions, uploads, or saved photos. Use an adult test subject. Test pictures clear when you close or background this screen.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Remote Scale Check")
    }
    #if DEBUG
    private var athleteCardHandler: ((@escaping (Result<String, Error>) -> Void) -> Void)? {
        guard scanMode == .reader else { return nil }
        return { completion in readCard(completion) }
    }
    private var checkScreen: some View {
        NavigationStack {
            WrestlingManagerRemoteDeviceCheck(
                installScaleObserver: { handler in scale.onRemoteWeightPacket = handler },
                removeScaleObserver: { scale.setRemoteWeightReadingEnabled(false); scale.onRemoteWeightPacket = nil },
                isScaleConnected: { scale.connectionState == .ready },
                setScaleReadingEnabled: { scale.setRemoteWeightReadingEnabled($0) },
                scaleReadStatus: { scale.connectionState == .ready ? scale.remoteReadStatus : scale.lastError ?? "Scale disconnected." },
                readAthleteCard: athleteCardHandler,
                cancelCardRead: { cardReader?.cancel() },
                simulateNFCScans: scanMode == .simulated)
            .navigationTitle("Local device check")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showCheck = false } } }
        }.interactiveDismissDisabled()
    }
    #endif
    var body: some View {
        NavigationStack {
            homeContent
                .sheet(isPresented: $showScale) {
                    AmericanScaleView(client: scale)
                        .overlay(alignment: .bottom) { Button("Done") { showScale = false }.buttonStyle(.borderedProminent).padding() }
                }
                .sheet(isPresented: $showReader) { RemoteScaleCheckReaderSetup(reader: nfc) }
                #if DEBUG
                .sheet(isPresented: $showCheck) { checkScreen }
                #endif
        }
        .onChange(of: scenePhase) { _, phase in nfc.setForeground(phase == .active) }
    }

}

@MainActor private struct RemoteScaleCheckReaderSetup: View {
    @ObservedObject var reader: WrestlingManagerBluetoothNFC
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Text(reader.displayName ?? "GoToTags / ACS NFC reader")
                Text(reader.state.rawValue)
                if let battery = reader.batteryPercent { Text("Battery: \(battery)%") }
                if let message = reader.lastMessage { Text(message).font(.footnote) }
                Toggle("Auto-connect", isOn: $reader.autoConnect)
                if reader.available {
                    Text(reader.cardPresent ? "Remove the card until prompted to tap." : "Ready for athlete cards.")
                    Button("Disconnect") { reader.disconnect() }
                } else {
                    Button(reader.state == .scanning ? "Stop search" : "Find NFC reader") {
                        if reader.state == .scanning { reader.stopSearch() } else { reader.scan() }
                    }
                    if reader.hasRememberedReader { Button("Reconnect saved reader") { reader.reconnect() } }
                    ForEach(reader.devices) { device in
                        Button(reader.displayName(for: device)) { reader.connect(device) }
                    }
                }
                Text("Local test only. Programmed athlete cards are mapped to numbered test athletes in memory. No real profile is looked up and no card is written.").font(.footnote)
            }
            .navigationTitle("NFC reader setup")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { reader.stopSearch(); dismiss() } } }
        }
    }
}
