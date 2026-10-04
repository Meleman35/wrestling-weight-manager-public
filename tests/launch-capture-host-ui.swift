#if REMOTE_SCALE_UI_TESTS
import UIKit

/// Actual production coordinator + photo UI + encrypted queue. Camera hardware
/// and incoming BLE packets are simulated; authorization remains an explicit port.
@main @MainActor final class LaunchCaptureHostTests: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = UIViewController()
        self.window = window; window.makeKeyAndVisible()
        Task { @MainActor in await run() }; return true
    }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func wait(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !predicate() { if Date() >= deadline { throw Failure(message:message) }; await pause(0.05) }
    }
    private func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
    private func button(_ title: String) -> UIButton? {
        guard let window else { return nil }
        return views(window).compactMap { $0 as? UIButton }.first { $0.currentTitle == title && $0.isEnabled }
    }
    private func tap(_ title: String) async throws { try await wait(title) { self.button(title) != nil }; button(title)?.sendActions(for: .touchUpInside) }
    private func run() async {
        do {
            guard let presenter = window?.rootViewController else { throw Failure(message:"No presenter") }
            let account = UUID(), club = UUID(), start = Date()
            let queue = try WrestlingManagerRemoteOutbox(accountID: account, clubID: club)
            var authorized = true, authorizationCount = 0
            let host = try WrestlingManagerRemoteCaptureHost(scope: .init(accountID:account,clubID:club,generation:"test-generation",
                programID:"host-test",windowID:"window",opensAt:start.addingTimeInterval(-60),closesAt:start.addingTimeInterval(120)),outbox:queue,authorize:{
                    authorizationCount += 1
                    try await Task.sleep(nanoseconds: 20_000_000)
                    if !authorized { throw Failure(message:"Authorization revoked") }
                })
            var setupResult: Result<Void, Error>?
            await host.prepareCamera(from:presenter) { setupResult = $0 }
            await pause(0.6); try await tap("Take setup test photo"); try await tap("Full athlete and scale are visible")
            try await wait("Camera setup did not finish") { setupResult != nil }; try setupResult!.get()
            var advances = 0;host.onReadyForNextScan = { advances += 1 }
            for (index,weight) in [120.0,119.0].enumerated() {
                guard host.readyForNextScan else { throw Failure(message:"Consecutive session required setup again") }
                var result: Result<UUID, Error>?
                let before = authorizationCount
                await host.beginCapture(athleteID:"athlete",method:"nfc",from:presenter,noticeAccepted:true) { result = $0 }
                guard authorizationCount == before + 1, presenter.presentedViewController != nil, host.settledWeight == nil else {
                    throw Failure(message:"Camera must open after one scan authorization, before stable weight")
                }
                do { _ = try await host.scan(athleteID:"other",method:"nfc"); throw Failure(message:"Duplicate scan accepted") }
                catch is WrestlingManagerRemoteCaptureHost.Failure { }
                await pause(0.6)
                for _ in 0..<3 { try host.receiveScalePacket(pounds:weight,observedAt:Date()); await pause(0.55) }
                try await wait("Stable weight did not queue its photo") { result != nil }
                let id = try result!.get(),saved = try await queue.capture(id)
                let envelope = try JSONDecoder().decode(WrestlingManagerRemoteCapture.Envelope.self,from:saved.payload)
                guard envelope.weight == weight, !saved.jpeg.isEmpty, saved.receipt == nil, !host.readyForNextScan else {
                    throw Failure(message:"Weight/photo/queued status mismatch")
                }
                try host.receiveScalePacket(pounds:0,observedAt:Date())
                try await wait("Fresh zero did not enable next scan") { host.readyForNextScan }
                guard advances == index + 1 else { throw Failure(message:"Duplicate or missed next-scan callback") }
            }
            authorized = false
            do { _ = try await host.scan(athleteID:"other",method:"nfc");throw Failure(message:"Revoked operator accepted") }
            catch let error as Failure { if error.message != "Authorization revoked" { throw error } }
            host.close();guard !host.readyForNextScan else { throw Failure(message:"Closed session remained ready") }
            finish("PASS: production host camera opens before stable weight; one scan authorization; automatic photo; two encrypted queued captures; fresh-zero next scan; duplicate and revoked operator rejected")
        } catch { finish("FAIL: \(error)") }
    }
    private func finish(_ message:String) {
        let url = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("result.txt")
        try? message.write(to:url,atomically:true,encoding:.utf8)
    }
    private struct Failure: Error { let message:String }
}
#endif
