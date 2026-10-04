#if REMOTE_SCALE_UI_TESTS
import SwiftUI
import UIKit

/// Runs the real device controller and photo presentation inside the same
/// SwiftUI NavigationStack + sheet used by the hardware test app. Only camera
/// hardware and BLE transport are simulated; no athlete data is used.
@main @MainActor final class RemoteDeviceUITests: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    static var receive: (@MainActor (Double, Date) -> Void)?
    static var connected = true
    static var reading = false
    static var installs = 0

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: HarnessHome())
        self.window = window; window.makeKeyAndVisible()
        Task { @MainActor in await self.run() }
        return true
    }
    private func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { allViews($0) } }
    private var views: [UIView] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).flatMap { allViews($0) }
    }
    private func button(_ text: String) -> UIButton? {
        views.compactMap { $0 as? UIButton }.first { $0.currentTitle == text && $0.window != nil }
    }
    private func label(_ text: String) -> Bool {
        views.compactMap { $0 as? UILabel }.contains { $0.text?.contains(text) == true }
    }
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    private func wait(_ description: String, timeout: Double = 5, until: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !until() {
            if Date() >= deadline { throw TestFailure(message: description) }
            await pause(0.05)
        }
    }
    private func tap(_ title: String) async throws {
        try await wait("Button unavailable: \(title)") { self.button(title)?.isEnabled == true }
        button(title)?.sendActions(for: .touchUpInside)
    }
    private func packet(_ weights: [Double]) {
        let at = Date()
        for weight in weights { Self.receive?(weight, at) }
    }
    private func run() async {
        do {
            try await tap("Check / recheck camera setup")
            try await tap("Take setup test photo")
            try await tap("Full athlete and scale are visible")
            try await tap("Start continuous test")
            for attempt in 1...3 {
                try await wait("Camera did not open for athlete \(attempt)") {
                    self.label("Test athlete \(attempt) •")
                }
                // Near-zero drift cannot take a picture of the empty platform.
                packet([0.2]); await pause(0.6); packet([0]); await pause(0.6); packet([0])
                guard !label("Test \(attempt) complete:") else { throw TestFailure(message: "Empty scale captured") }
                let weight = 120 + Double(attempt)
                packet([weight]); await pause(0.6); packet([weight]); await pause(0.6)
                let stableAt = Date(); packet([weight, weight])
                try await wait("No immediate photo for athlete \(attempt)", timeout: 1.5) {
                    self.label("Test \(attempt) complete:")
                }
                print("Athlete \(attempt): photo complete \(Date().timeIntervalSince(stableAt)) seconds after stability")
                guard Self.reading else { throw TestFailure(message: "Reader stopped between athletes") }
                packet([weight]); await pause(0.6); packet([weight]); await pause(0.2)
                guard label("Test \(attempt) complete:") else { throw TestFailure(message: "Advanced while occupied") }
                if attempt < 3 {
                    // Last zero in a mixed response must not hide an occupied scale.
                    packet([0, weight, 0]); await pause(0.3)
                    guard label("Test \(attempt) complete:") else { throw TestFailure(message: "Mixed packet advanced") }
                    // Regression: exactly ONE fresh zero; no later packet or tap.
                    packet([0])
                }
            }
            guard Self.installs == 1 else { throw TestFailure(message: "Session controller was recreated") }
            try await tap("End test session — keep setup")
            guard !Self.reading else { throw TestFailure(message: "Reader remained enabled after end") }
            try await tap("Start continuous test")
            try await wait("Retained setup did not reopen camera") { self.label("Test athlete 1 •") }
            Self.connected = false
            try await wait("Disconnect did not stop session") { self.label("Reconnect before starting again.") }
            guard !Self.reading else { throw TestFailure(message: "Reader remained enabled after disconnect") }
            finish("PASS: three immediate captures, one-zero automatic handoff, occupied/mixed-packet rejection, retained setup and disconnect.")
        } catch {
            let labels = views.compactMap { ($0 as? UILabel)?.text }.joined(separator: " | ")
            finish("FAIL: \(error)\n\(labels)")
        }
    }
    private func finish(_ result: String) {
        print(result)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.txt")
        try? result.write(to: url, atomically: true, encoding: .utf8)
    }
    struct TestFailure: Error { let message: String }
}

@MainActor private struct HarnessHome: View {
    @State private var show = false
    var body: some View {
        NavigationStack {
            Text("UI regression harness").onAppear { show = true }
                .sheet(isPresented: $show) {
                    NavigationStack {
                        WrestlingManagerRemoteDeviceCheck(
                            installScaleObserver: { RemoteDeviceUITests.receive = $0; RemoteDeviceUITests.installs += 1 },
                            removeScaleObserver: { RemoteDeviceUITests.receive = nil },
                            isScaleConnected: { RemoteDeviceUITests.connected },
                            setScaleReadingEnabled: { RemoteDeviceUITests.reading = $0 },
                            scaleReadStatus: { "Simulated BLE transport" })
                            .navigationTitle("Local device check")
                    }.interactiveDismissDisabled()
                }
        }
    }
}
#endif
