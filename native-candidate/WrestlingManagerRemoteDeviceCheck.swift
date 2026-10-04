#if DEBUG
import SwiftUI
import UIKit

/// Development-only hardware acceptance. One fictional athlete; image/evidence
/// remain in memory. No Auth, network, upload, Photos library or protected queue.
@MainActor
struct WrestlingManagerRemoteDeviceCheck: UIViewControllerRepresentable {
    let installScaleObserver: (@escaping @MainActor (Double, Date) -> Void) -> Void
    let removeScaleObserver: () -> Void
    let isScaleConnected: () -> Bool
    let setScaleReadingEnabled: (Bool) -> Void
    let scaleReadStatus: () -> String
    func makeUIViewController(context: Context) -> WrestlingManagerRemoteDeviceCheckController {
        let controller = WrestlingManagerRemoteDeviceCheckController(onClose: removeScaleObserver,
            isScaleConnected: isScaleConnected, setScaleReadingEnabled: setScaleReadingEnabled, scaleReadStatus: scaleReadStatus)
        installScaleObserver { [weak controller] pounds, at in controller?.receive(pounds: pounds, at: at) }
        return controller
    }
    func updateUIViewController(_ uiViewController: WrestlingManagerRemoteDeviceCheckController, context: Context) {
        uiViewController.checkConnection()
    }
    static func dismantleUIViewController(_ uiViewController: WrestlingManagerRemoteDeviceCheckController, coordinator: ()) { uiViewController.close() }
}

@MainActor
final class WrestlingManagerRemoteDeviceCheckController: UIViewController {
    private let photos = WrestlingManagerRemotePhoto()
    private let onClose: () -> Void
    private let isScaleConnected: () -> Bool
    private let setScaleReadingEnabled: (Bool) -> Void
    private let scaleReadStatus: () -> String
    private let status = UILabel()
    private let picture = UIImageView()
    private let setup = UIButton(type: .system)
    private let weigh = UIButton(type: .system)
    private let clear = UIButton(type: .system)
    private var capture: WrestlingManagerRemoteCapture?
    private var review: WrestlingManagerRemoteSetupReview?
    private var setupConfirmed = false
    private var active = true
    private var busy = false
    private var operation = UUID()
    private var observer: NSObjectProtocol?
    private var latestWeight: Double?
    private var latestUpdateAt: Date?
    private var updateCount = 0
    private var closesAt: Date?
    init(onClose: @escaping () -> Void, isScaleConnected: @escaping () -> Bool,
         setScaleReadingEnabled: @escaping (Bool) -> Void, scaleReadStatus: @escaping () -> String) {
        self.onClose = onClose; self.isScaleConnected = isScaleConnected
        self.setScaleReadingEnabled = setScaleReadingEnabled; self.scaleReadStatus = scaleReadStatus
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(onClose:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let title = UILabel(); title.text = "Remote camera & scale check • Build 3"; title.font = .preferredFont(forTextStyle: .title2)
        let note = UILabel(); note.text = "Development test • Fictional athlete\nConnect the American Scale first. Use an adult test subject in athletic clothing. Keep face, singlet, both feet and scale visible. Nothing here is uploaded or saved."
        for label in [title,note,status] { label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = true }
        status.text = "1. Check the camera framing. 2. Start a test weigh-in and step on the scale."
        picture.contentMode = .scaleAspectFit; picture.accessibilityLabel = "Temporary test weigh-in photo"
        picture.heightAnchor.constraint(equalToConstant: 240).isActive = true
        setup.setTitle("Check / recheck camera setup", for: .normal)
        setup.addTarget(self, action: #selector(checkSetup), for: .touchUpInside)
        weigh.setTitle("Start test weigh-in", for: .normal); weigh.isEnabled = false
        weigh.addTarget(self, action: #selector(startWeighIn), for: .touchUpInside)
        clear.setTitle("Clear test photo and setup", for: .normal)
        clear.addTarget(self, action: #selector(clearTest), for: .touchUpInside)
        for button in [setup,weigh,clear] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.titleLabel?.numberOfLines = 0; button.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        let stack = UIStackView(arrangedSubviews: [title,note,setup,weigh,clear,status,picture]); stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)])
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.clearTest() } }
    }
    private func controls() { setup.isEnabled = active && !busy; weigh.isEnabled = active && !busy && setupConfirmed }
    @objc private func checkSetup() {
        guard active, !busy else { return }; clearTest(); busy = true; controls()
        let ticket = operation
        photos.take(token: ticket, from: self, setup: true) { [weak self] _, result in
            guard let self, self.active, self.operation == ticket else { return }
            switch result {
            case .failure: self.busy = false; self.status.text = "Camera setup cancelled or unavailable. Check camera permission and try again."; self.controls()
            case .success(let (jpeg, _)):
                let review = WrestlingManagerRemoteSetupReview(jpeg: jpeg) { [weak self] decision in
                    guard let self, self.active, self.operation == ticket else { return }
                    self.review = nil; self.busy = false
                    switch decision {
                    case .confirmed: self.setupConfirmed = true; self.status.text = "Framing confirmed. Start a test weigh-in, then step on the scale."
                    case .cancelled: self.status.text = "Setup cancelled."
                    case .retake: self.checkSetup()
                    }
                    self.controls()
                }
                self.review = review; self.present(review, animated: false)
            }
        }
    }
    @objc private func startWeighIn() {
        guard active, !busy, setupConfirmed else { return }
        guard isScaleConnected() else { status.text = "Reconnect the scale, then start the test again."; return }
        picture.image = nil; capture?.close(); operation = UUID(); let ticket = operation
        latestWeight = nil; latestUpdateAt = nil; updateCount = 0
        do {
            let now = Date()
            closesAt = now.addingTimeInterval(300)
            let model = try WrestlingManagerRemoteCapture(scope: .init(accountID: UUID(), clubID: UUID(),
                generation: "device-check", programID: "fictional-device-check", windowID: "five-minute-test",
                opensAt: now.addingTimeInterval(-5), closesAt: now.addingTimeInterval(300)))
            let token = try model.scan(athleteID: "fictional-adult-test", method: "qr")
            capture = model; busy = true; controls(); status.text = "Waiting for fresh scale packets. The photo takes automatically after the scale stays stable."
            setScaleReadingEnabled(true)
            photos.take(token: token, from: self, readyToCapture: { [weak self] in
                guard let self, self.active, self.operation == ticket else { return false }
                self.checkConnection()
                return self.isScaleConnected() && model.settledWeight != nil
            }, captureStatus: { [weak self] in
                self?.liveStatus() ?? "Test closed."
            }) { [weak self] photoToken, result in
                guard let self, self.active, self.operation == ticket else { return }
                self.busy = false; self.controls()
                do {
                    let (jpeg, at) = try result.get()
                    self.checkConnection()
                    guard self.isScaleConnected() else { throw WrestlingManagerRemoteCapture.Failure.unsettled }
                    try model.snapshot(token: photoToken, normalizedJPEG: jpeg, capturedAt: at, noticeAccepted: true)
                    let frozen = try model.freeze(token: photoToken)
                    let envelope = try JSONDecoder().decode(WrestlingManagerRemoteCapture.Envelope.self, from: frozen.payload)
                    self.picture.image = UIImage(data: jpeg)
                    self.status.text = String(format: "Test capture: %.1f lb\n", envelope.weight) + "Captured: \(envelope.capturedAt)\nPhoto: \(envelope.photoCapturedAt)\nConfirm the whole athlete and scale are visible. This is a local test, not an accepted tournament weigh-in."
                } catch { self.status.text = "Test not captured. Keep the scale connected and the athlete still, then try again. No weigh-in was saved." }
                model.close(); self.capture = nil; self.setScaleReadingEnabled(false)
            }
        } catch { setScaleReadingEnabled(false); busy = false; controls(); status.text = "The test could not start. Close and reopen this check." }
    }
    func receive(pounds: Double, at: Date) {
        guard active, let capture, let token = capture.captureToken else { return }
        if latestUpdateAt != at { updateCount += 1 }
        latestWeight = pounds; latestUpdateAt = at
        // Invalid/unstable packets clear readiness in the same production model.
        try? capture.scaleReading(token: token, pounds: pounds, observedAt: at, connected: isScaleConnected())
    }
    func checkConnection() {
        if !isScaleConnected() { capture?.scaleDisconnected() }
    }
    private func liveStatus() -> String {
        guard isScaleConnected() else { return scaleReadStatus() + "\nCancel and reconnect the scale." }
        if let closesAt, Date() >= closesAt {
            setScaleReadingEnabled(false)
            return "Five-minute test ended. Cancel and start a new test."
        }
        guard let latestUpdateAt, let latestWeight else {
            return scaleReadStatus() + "\nNo weight received yet. Step on the scale after starting this test."
        }
        let age = max(0, Date().timeIntervalSince(latestUpdateAt))
        let weight = latestWeight.isFinite ? String(format: "%.1f lb", latestWeight) : "Invalid weight"
        let details = String(format: "%@ • %d updates • last %.1fs ago", weight, updateCount, age) + "\n" + scaleReadStatus()
        if age > 1.5 { return details + "\nWeight updates paused. Waiting for fresh readings." }
        if !latestWeight.isFinite || latestWeight <= 0 || latestWeight > 800 {
            return details + "\nWaiting for a valid weight. Step onto the scale."
        }
        return details + (capture?.settledWeight == nil ? "\nReceiving readings. Hold still while stability is checked." : "\nStable weight. Stay still through the countdown.")
    }
    @objc private func clearTest() {
        operation = UUID(); capture?.close(); capture = nil; setupConfirmed = false; busy = false
        setScaleReadingEnabled(false)
        latestWeight = nil; latestUpdateAt = nil; updateCount = 0; closesAt = nil
        photos.cancel(); review?.cancel(); review = nil; picture.image = nil
        status.text = "Temporary test data cleared. Recheck setup to begin."; controls()
    }
    func close() {
        guard active else { return }; active = false; clearTest(); onClose()
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
#endif
