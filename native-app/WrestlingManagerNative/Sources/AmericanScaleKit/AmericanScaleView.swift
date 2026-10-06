#if canImport(SwiftUI) && canImport(CoreBluetooth) && canImport(Combine)
import SwiftUI

@MainActor
public struct AmericanScaleView: View {
    @StateObject private var client: AmericanScaleClient
    @State private var displayUnit: AmericanScaleDisplayUnit = .pounds
    @State private var renameText = ""
    @State private var showingRename = false
    @State private var renameError: String?

    private let onUseLockedWeight: ((Double) -> Void)?

    public init(
        client: AmericanScaleClient = AmericanScaleClient(),
        onUseLockedWeight: ((Double) -> Void)? = nil
    ) {
        _client = StateObject(wrappedValue: client)
        self.onUseLockedWeight = onUseLockedWeight
    }

    public var body: some View {
        NavigationStack {
            List {
                connectionSection

                if client.connectionState == .ready {
                    liveScaleSection
                    commandSection
                    statusSection
                } else {
                    discoveredDevicesSection
                }
            }
            .navigationTitle("American Scale")
            .toolbar {
                if client.connectionState == .ready {
                    ToolbarItem(placement: disconnectToolbarPlacement) {
                        Button("Disconnect") {
                            client.disconnect()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingRename) {
                renameSheet
                    .presentationDetents([.medium])
            }
        }
    }

    private var disconnectToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent("Status", value: connectionLabel)

            if let name = client.connectedAdvertisedName {
                LabeledContent("Scale", value: name)
            }


            if let error = client.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            if client.connectionState != .ready {
                HStack {
                    Button("Find Scale") { client.startScanning() }
                    Button("Reconnect Last") { client.reconnectLastScale() }
                }
            }
        }
    }

    private var discoveredDevicesSection: some View {
        Section("Nearby Scales") {
            if client.discoveredDevices.isEmpty {
                Text("Turn on your scale, then tap Find Scale.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(client.discoveredDevices) { device in
                    Button {
                        client.connect(to: device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.advertisedName)
                                    .foregroundStyle(.primary)

                            }
                            Spacer()

                        }
                    }
                }
            }
        }
    }

    private var liveScaleSection: some View {
        Section("Live Weight") {
            Picker("Display Unit", selection: $displayUnit) {
                ForEach(AmericanScaleDisplayUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 6) {
                Text(formattedLiveWeight)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Live stream")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            if let locked = client.session.lockedWeightLb {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Locked capture")
                        .font(.headline)
                    Text(formatWeight(locked))
                        .font(.title2.bold())
                        .monospacedDigit()

                    HStack {
                        if let onUseLockedWeight {
                            Button("Use This Weight") {
                                onUseLockedWeight(locked)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Clear") {
                            client.clearLockedWeight()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var commandSection: some View {
        Section("Scale Controls") {
            Button("Zero Scale") {
                client.zeroScale()
            }

            Button(client.session.pendingLockIn ? "Waiting for next weight…" : "Lock In Weight") {
                client.lockInWeight()
            }
            .disabled(client.session.pendingLockIn)

            Button("Rename Scale") {
                renameText = client.connectedAdvertisedName ?? ""
                renameError = nil
                showingRename = true
            }
        }
    }

    private var statusSection: some View {
        Section("Scale Status") {
            if let battery = client.session.batteryPercent {
                LabeledContent("Battery", value: String(format: "%.0f%%", battery))
            }
            if let capacity = client.session.capacityLb {
                LabeledContent("Capacity", value: String(format: "%.1f lb", capacity))
            }
            if let lockState = client.session.lockInState {
                LabeledContent("Lock-in State", value: String(format: "%.3f", lockState))
            }
            if let info = client.session.latestInfo, !info.isEmpty {
                LabeledContent("Info") {
                    Text(info)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Scale name", text: $renameText)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } footer: {
                    Text("Verified-safe limit: 1–8 printable ASCII characters and no # character. The scale is expected to disconnect after rename; Wrestling Manager reconnects by Bluetooth peripheral identifier.")
                }

                if let renameError {
                    Text(renameError)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Rename Scale")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRename = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        do {
                            try client.renameScale(to: renameText)
                            showingRename = false
                        } catch {
                            renameError = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private var connectionLabel: String {
        switch client.connectionState {
        case .idle: return "Disconnected"
        case .bluetoothUnavailable: return "Bluetooth unavailable"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .discovering: return "Preparing scale"
        case .ready: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .failed: return "Connection error"
        }
    }

    private var formattedLiveWeight: String {
        guard let pounds = client.session.liveWeightLb else {
            return "—"
        }
        return formatWeight(pounds)
    }

    private func formatWeight(_ pounds: Double) -> String {
        let value = AmericanScaleUnits.displayedWeight(pounds: pounds, unit: displayUnit)
        return String(format: "%.1f %@", value, displayUnit.rawValue)
    }
}
#endif

