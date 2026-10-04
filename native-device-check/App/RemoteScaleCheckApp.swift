import SwiftUI
import AmericanScaleKit

@main
struct RemoteScaleCheckApp: App {
    var body: some Scene { WindowGroup { RemoteScaleCheckHome() } }
}

@MainActor
private struct RemoteScaleCheckHome: View {
    @StateObject private var scale = AmericanScaleClient()
    @State private var showScale = false
    @State private var showCheck = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Camera + American Scale").font(.largeTitle.bold())
                Text("Device check • Build 3").font(.caption)
                Text("Separate development test. Your Wrestling Manager app and athlete records are not used.")
                Text("1. Connect the scale.\n2. Check the camera framing.\n3. Try an automatic test photo while standing on the scale.")
                Button("Connect American Scale") { showScale = true }.buttonStyle(.borderedProminent)
                #if DEBUG
                Button("Open camera & scale check") { showCheck = true }
                    .buttonStyle(.borderedProminent).disabled(scale.connectionState != .ready)
                #else
                Text("Use a Debug build for this development test.")
                #endif
                Text(scale.connectionState == .ready ? "Scale connected" : "Connect the scale to continue.")
                Text("No sign-in, subscriptions, uploads, or saved photos. Use an adult test subject. Test pictures clear when you close or background this screen.")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }.padding().navigationTitle("Remote Scale Check")
                .sheet(isPresented: $showScale) {
                    AmericanScaleView(client: scale)
                        .overlay(alignment: .bottom) { Button("Done") { showScale = false }.buttonStyle(.borderedProminent).padding() }
                }
                #if DEBUG
                .sheet(isPresented: $showCheck) {
                    NavigationStack {
                        WrestlingManagerRemoteDeviceCheck(
                            installScaleObserver: { handler in scale.onRemoteWeightPacket = handler },
                            removeScaleObserver: { scale.setRemoteWeightReadingEnabled(false); scale.onRemoteWeightPacket = nil },
                            isScaleConnected: { scale.connectionState == .ready },
                            setScaleReadingEnabled: { scale.setRemoteWeightReadingEnabled($0) },
                            scaleReadStatus: { scale.connectionState == .ready ? scale.remoteReadStatus : scale.lastError ?? "Scale disconnected." })
                        .navigationTitle("Local device check")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showCheck = false } } }
                    }.interactiveDismissDisabled()
                }
                #endif
        }
    }
}
