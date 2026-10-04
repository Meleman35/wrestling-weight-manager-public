#if DEBUG
import SwiftUI
import UIKit

/// Development-only hardware acceptance. Numbered fictional attempts; image/evidence
/// remain in memory. No Auth, network, upload, Photos library or protected queue.
@MainActor
struct WrestlingManagerRemoteDeviceCheck: UIViewControllerRepresentable {
    let installScaleObserver: (@escaping @MainActor (Double, Date) -> Void) -> Void
    let removeScaleObserver: () -> Void
    let isScaleConnected: () -> Bool
    let setScaleReadingEnabled: (Bool) -> Void
    let scaleReadStatus: () -> String
    var readAthleteCard: ((@escaping (Result<String, Error>) -> Void) -> Void)? = nil
    var cancelCardRead: (() -> Void)? = nil
    var simulateNFCScans = false
    func makeUIViewController(context: Context) -> WrestlingManagerRemoteDeviceCheckController {
        let controller = WrestlingManagerRemoteDeviceCheckController(onClose: removeScaleObserver,
            isScaleConnected: isScaleConnected, setScaleReadingEnabled: setScaleReadingEnabled, scaleReadStatus: scaleReadStatus,
            readAthleteCard: readAthleteCard, cancelCardRead: cancelCardRead, simulateNFCScans: simulateNFCScans)
        installScaleObserver { [weak controller] pounds, at in controller?.receive(pounds: pounds, at: at) }
        return controller
    }
    func updateUIViewController(_ uiViewController: WrestlingManagerRemoteDeviceCheckController, context: Context) {
        Task { @MainActor [weak uiViewController] in uiViewController?.checkConnection() }
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
    private let readAthleteCard: ((@escaping (Result<String, Error>) -> Void) -> Void)?
    private let cancelCardRead: (() -> Void)?
    private let simulateNFCScans: Bool
    private var usesCards: Bool { simulateNFCScans || readAthleteCard != nil }
    private let simulatedAthlete = UISegmentedControl(items: ["Athlete 1", "Athlete 2", "Athlete 3"])
    private let simulatedScan = UIButton(type: .system)
    private var simulatedCardReply: ((Result<String, Error>) -> Void)?
    private var awaitingCard = false
    private var cardAthletes: [String: Int] = [:]
    private var currentAthlete = 1
    private struct SelectedResult { let weight: Double; let capturedAt: String; let photoAt: String; let jpeg: Data }
    private var selectedResults: [Int: SelectedResult] = [:]
    private let status = UILabel()
    private let picture = UIImageView()
    private let setup = UIButton(type: .system)
    private let weigh = UIButton(type: .system)
    private let clear = UIButton(type: .system)
    private let pause = UIButton(type: .system)
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
    private var sessionRunning = false
    private var awaitingScaleClear = false
    private var scaleClear = WrestlingManagerRemoteScaleClear()
    private var advanceScheduled = false
    private var completedCount = 0
    private var attemptStartedAt: Date?
    private var lastResult = ""
    private var sessionTimer: Task<Void, Never>?
    init(onClose: @escaping () -> Void, isScaleConnected: @escaping () -> Bool,
         setScaleReadingEnabled: @escaping (Bool) -> Void, scaleReadStatus: @escaping () -> String,
         readAthleteCard: ((@escaping (Result<String, Error>) -> Void) -> Void)? = nil, cancelCardRead: (() -> Void)? = nil,
         simulateNFCScans: Bool = false) {
        self.simulateNFCScans = simulateNFCScans
        self.readAthleteCard = readAthleteCard; self.cancelCardRead = cancelCardRead
        self.onClose = onClose; self.isScaleConnected = isScaleConnected
        self.setScaleReadingEnabled = setScaleReadingEnabled; self.scaleReadStatus = scaleReadStatus
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(onClose:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let title = UILabel(); title.text = "Remote camera & scale check • Build 7"; title.font = .preferredFont(forTextStyle: .title2)
        let note = UILabel(); note.text = "Continuous development test • Numbered fictional athletes\nCheck framing once, then start the session. After each photo, step off to prepare the next test automatically. Use an adult test subject in athletic clothing. Nothing here is uploaded or saved. NFC test results clear when the session is cleared."
        for label in [title,note,status] { label.numberOfLines = 0; label.adjustsFontForContentSizeCategory = true }
        status.text = "1. Check the camera framing. 2. Start a test weigh-in and step on the scale."
        picture.contentMode = .scaleAspectFit; picture.accessibilityLabel = "Temporary test weigh-in photo"
        picture.heightAnchor.constraint(equalToConstant: 240).isActive = true
        setup.setTitle("Check / recheck camera setup", for: .normal)
        setup.addTarget(self, action: #selector(checkSetup), for: .touchUpInside)
        weigh.setTitle("Start continuous test", for: .normal); weigh.isEnabled = false
        weigh.addTarget(self, action: #selector(startWeighIn), for: .touchUpInside)
        clear.setTitle("Clear test photo and setup", for: .normal)
        clear.addTarget(self, action: #selector(clearTest), for: .touchUpInside)
        pause.setTitle("End test session — keep setup", for: .normal)
        pause.addTarget(self, action: #selector(endSession), for: .touchUpInside)
        simulatedAthlete.selectedSegmentIndex = 0
        simulatedAthlete.accessibilityIdentifier = "simulated-athlete"
        simulatedAthlete.isHidden = !simulateNFCScans
        simulatedScan.isHidden = !simulateNFCScans
        simulatedScan.setTitle("Simulate NFC scan", for: .normal)
        simulatedScan.addTarget(self, action: #selector(simulateScan), for: .touchUpInside)
        for button in [setup,weigh,pause,clear,simulatedScan] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.titleLabel?.numberOfLines = 0; button.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        let stack = UIStackView(arrangedSubviews: [title,note,setup,weigh,pause,clear,simulatedAthlete,simulatedScan,status,picture]); stack.axis = .vertical; stack.spacing = 12
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
        controls()
    }
    private func controls() {
        setup.isEnabled = active && !busy; weigh.isEnabled = active && !busy && setupConfirmed
        pause.isEnabled = active && sessionRunning
        simulatedScan.isEnabled = active && sessionRunning && awaitingCard
        simulatedAthlete.isEnabled = simulatedScan.isEnabled
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleAdvance()
    }
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
                    case .confirmed: self.setupConfirmed = true; self.status.text = "Framing confirmed for this session. Start the continuous test, then step on the scale."
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
        sessionRunning = true; busy = true; completedCount = 0; lastResult = ""
        cardAthletes.removeAll(); selectedResults.removeAll(); awaitingCard = false
        if simulateNFCScans { cardAthletes = ["simulated-card-1": 1, "simulated-card-2": 2, "simulated-card-3": 3] }
        picture.image = nil; closesAt = Date().addingTimeInterval(300)
        setScaleReadingEnabled(true); controls()
        startSessionTimer()
        prepareNextAttempt()
    }
    private func startSessionTimer() {
        sessionTimer?.cancel()
        sessionTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.active, self.sessionRunning else { return }
                if !self.isScaleConnected() {
                    self.stopSession(message: self.scaleReadStatus() + " Reconnect before starting again."); return
                }
                if let closesAt = self.closesAt, Date() >= closesAt {
                    self.stopSession(message: "Five-minute test session ended. Setup is retained; start another session when ready."); return
                }
                if self.awaitingScaleClear { self.updateStepOffStatus(); self.scheduleAdvance() }
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            }
        }
    }
    private func prepareNextAttempt() {
        guard active, sessionRunning else { return }
        awaitingScaleClear = false; scaleClear.reset(); advanceScheduled = false
        guard usesCards else { currentAthlete = completedCount + 1; beginAttempt(); return }
        operation = UUID(); let ticket = operation; awaitingCard = true
        status.text = simulateNFCScans
            ? "Ready for simulated NFC scan.\nChoose a test athlete above, tap Simulate NFC scan, then step on. Choose the same athlete for a repeat weigh-in. No reader or real athlete card is used."
            : "Tap NFC card for the next athlete.\nRemove the previous card before tapping again.\nTap the same card again to test a repeat weigh-in. The lowest valid result and its matching photo stay selected for that card."
        controls()
        let completion: (Result<String, Error>) -> Void = { [weak self] result in
            guard let self, self.active, self.sessionRunning, self.awaitingCard, self.operation == ticket else { return }
            switch result {
            case .success(let card):
                guard !card.isEmpty, card.utf8.count <= 160 else {
                    self.stopSession(message: "Card could not be read. Camera setup is retained."); return
                }
                if self.cardAthletes[card] == nil {
                    guard self.cardAthletes.count < 20 else {
                        self.stopSession(message: "Local test limit reached. Start a new session to clear the temporary card results."); return
                    }
                    self.cardAthletes[card] = self.cardAthletes.count + 1
                }
                self.currentAthlete = self.cardAthletes[card]!
                self.awaitingCard = false; self.beginAttempt()
            case .failure(let error):
                if let failure = error as? WrestlingManagerRemoteCardReader.Failure, case .timedOut = failure {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        guard let self, self.active, self.sessionRunning, self.operation == ticket else { return }
                        self.prepareNextAttempt()
                    }
                } else {
                    self.stopSession(message: "NFC reader unavailable. Reconnect it and start again. Camera setup is retained.")
                }
            }
        }
        if simulateNFCScans { simulatedCardReply = completion }
        else { readAthleteCard?(completion) }
    }
    @objc private func simulateScan() {
        guard simulateNFCScans, active, sessionRunning, awaitingCard, let reply = simulatedCardReply else { return }
        simulatedCardReply = nil
        reply(.success("simulated-card-\(simulatedAthlete.selectedSegmentIndex + 1)"))
    }
    private func beginAttempt() {
        guard active, sessionRunning, setupConfirmed, isScaleConnected(), let closesAt, Date() < closesAt else { return }
        capture?.close(); operation = UUID(); let ticket = operation
        awaitingScaleClear = false; scaleClear.reset(); advanceScheduled = false
        latestWeight = nil; latestUpdateAt = nil; updateCount = 0; attemptStartedAt = Date()
        picture.image = nil
        do {
            let now = Date()
            let model = try WrestlingManagerRemoteCapture(scope: .init(accountID: UUID(), clubID: UUID(),
                generation: "device-check", programID: "fictional-device-check", windowID: "five-minute-test",
                opensAt: now.addingTimeInterval(-5), closesAt: closesAt))
            let token = try model.scan(athleteID: "fictional-adult-test-\(currentAthlete)", method: usesCards ? "nfc" : "qr")
            capture = model; busy = true; controls()
            status.text = "Test athlete \(currentAthlete): step on and hold still."
            photos.take(token: token, from: self, readyToCapture: { [weak self] in
                guard let self, self.active, self.sessionRunning, self.operation == ticket else { return false }
                return self.isScaleConnected() && model.settledWeight != nil
            }, captureStatus: { [weak self] in self?.liveStatus() ?? "Test closed." }) { [weak self] photoToken, result in
                guard let self, self.active, self.sessionRunning, self.operation == ticket else { return }
                do {
                    let (jpeg, at) = try result.get()
                    guard self.isScaleConnected() else { throw WrestlingManagerRemoteCapture.Failure.unsettled }
                    try model.snapshot(token: photoToken, normalizedJPEG: jpeg, capturedAt: at, noticeAccepted: true)
                    let frozen = try model.freeze(token: photoToken)
                    let envelope = try JSONDecoder().decode(WrestlingManagerRemoteCapture.Envelope.self, from: frozen.payload)
                    self.completedCount += 1
                    let candidate = SelectedResult(weight: envelope.weight, capturedAt: envelope.capturedAt,
                        photoAt: envelope.photoCapturedAt, jpeg: jpeg)
                    if !self.usesCards { self.selectedResults.removeAll() }
                    let previous = self.selectedResults[self.currentAthlete]
                    let selected = previous.map { $0.weight <= candidate.weight ? $0 : candidate } ?? candidate
                    let bytes = self.selectedResults.filter { $0.key != self.currentAthlete }.values.reduce(0) { $0 + $1.jpeg.count } + selected.jpeg.count
                    guard bytes <= 20 * 1024 * 1024 else {
                        self.stopSession(message: "Temporary photo limit reached. Start a new local test session to clear its pictures."); return
                    }
                    self.selectedResults[self.currentAthlete] = selected
                    self.picture.image = UIImage(data: selected.jpeg)
                    self.lastResult = String(format: "Test %d complete: %.1f lb\n", self.completedCount, selected.weight)
                        + (!self.usesCards ? "" : String(format: "Local test athlete %d • latest attempt %.1f lb\nLowest valid result selected with its matching photo.\n", self.currentAthlete, candidate.weight))
                        + "Captured: \(selected.capturedAt)\nPhoto: \(selected.photoAt)"
                    model.close(); self.capture = nil
                    self.awaitingScaleClear = true; self.scaleClear.begin(after: Date())
                    self.updateStepOffStatus(); self.controls()
                } catch WrestlingManagerRemotePhoto.Failure.cancelled {
                    self.stopSession(message: "Session stopped. Camera setup is retained; start again when ready.")
                } catch {
                    self.stopSession(message: "Capture did not complete. Hold still until the success message. Setup is retained; start again when ready.")
                }
            }
        } catch { stopSession(message: "The test could not start. Camera setup is retained; start again when ready.") }
    }
    func receive(pounds: Double, at: Date) {
        guard active, sessionRunning else { return }
        guard !awaitingCard else { return }
        if latestUpdateAt != at { updateCount += 1 }
        latestWeight = pounds; latestUpdateAt = at
        if awaitingScaleClear {
            scaleClear.observe(pounds: pounds, at: at, now: Date(), connected: isScaleConnected())
            updateStepOffStatus()
            scheduleAdvance()
            return
        }
        guard let capture, let token = capture.captureToken else { return }
        try? capture.scaleReading(token: token, pounds: pounds, observedAt: at, connected: isScaleConnected())
        let ticket = operation
        Task { @MainActor [weak self] in
            guard let self, self.active, self.sessionRunning, self.operation == ticket else { return }
            self.photos.updateCaptureReadiness()
        }
    }
    private func scheduleAdvance() {
        guard active, sessionRunning, awaitingScaleClear, !advanceScheduled,
              scaleClear.isClear(at: Date()) else { return }
        advanceScheduled = true; let ticket = operation
        // Defer until the complete BLE batch has been checked. Retry from the
        // session timer and view appearance if UIKit is still dismissing.
        Task { @MainActor [weak self] in
            guard let self, self.active, self.operation == ticket else { return }
            self.advanceScheduled = false
            guard self.sessionRunning, self.awaitingScaleClear, self.isScaleConnected(),
                  self.scaleClear.isClear(at: Date()), self.photos.canTake(from: self) else { return }
            self.prepareNextAttempt()
        }
    }
    func checkConnection() {
        if !isScaleConnected() {
            capture?.scaleDisconnected(); scaleClear.invalidate()
            if sessionRunning { stopSession(message: scaleReadStatus() + " Reconnect before starting again.") }
        }
    }
    private func updateStepOffStatus() {
        let reading = latestWeight.flatMap { $0.isFinite ? String(format: "%.1f lb", $0) : nil } ?? "unavailable"
        let age = latestUpdateAt.map { String(format: "%.1fs ago", max(0, Date().timeIntervalSince($0))) } ?? "none"
        let next = scaleClear.isClear(at: Date()) ? "Scale empty — preparing next athlete." : "Waiting for a fresh empty-scale reading."
        status.text = lastResult + "\nPhoto complete — step off the scale.\n\(next)\nLive scale: \(reading) • last \(age) • \(updateCount) updates.\n\(scaleReadStatus())\nCompleted this session: \(completedCount)."
    }
    private func liveStatus() -> String {
        guard isScaleConnected() else { return scaleReadStatus() + "\nSession stopped. Reconnect the scale." }
        let elapsed = max(0, Date().timeIntervalSince(attemptStartedAt ?? Date()))
        let heading = String(format: "Test athlete %d • %.0fs elapsed", currentAthlete, elapsed)
        guard let latestUpdateAt, let latestWeight else {
            return heading + "\n" + scaleReadStatus() + "\nWaiting for a fresh reading. Step onto the scale."
        }
        let age = max(0, Date().timeIntervalSince(latestUpdateAt))
        let weight = latestWeight.isFinite ? String(format: "%.1f lb", latestWeight) : "Invalid weight"
        let details = heading + String(format: "\n%@ • %d updates • last %.1fs ago", weight, updateCount, age)
        if age > 1.5 { return details + "\nWeight updates paused. Waiting for fresh readings.\n" + scaleReadStatus() }
        if !latestWeight.isFinite || latestWeight <= WrestlingManagerRemoteCapture.emptyScaleMaximumPounds || latestWeight > 800 {
            return details + "\nReady for this test athlete to step on."
        }
        if capture?.settledWeight != nil { return details + "\nWeight stable — taking photo. Hold still." }
        let progress = capture?.settlingProgress ?? (samples: 0, seconds: 0)
        return details + String(format: "\nSettling: %d/3 readings • %.1f/1.0s steady. Hold still.", min(3, progress.samples), min(1, progress.seconds))
    }
    @objc private func endSession() {
        stopSession(message: "Session ended. Camera setup is retained; start again when ready.")
    }
    private func stopSession(message: String) {
        operation = UUID(); awaitingCard = false; simulatedCardReply = nil; cancelCardRead?(); sessionRunning = false; awaitingScaleClear = false; advanceScheduled = false
        scaleClear.reset(); capture?.close(); capture = nil; busy = false
        sessionTimer?.cancel(); sessionTimer = nil; setScaleReadingEnabled(false)
        photos.cancel(); status.text = message; controls()
    }
    @objc private func clearTest() {
        stopSession(message: "Temporary test data cleared. Recheck setup to begin.")
        setupConfirmed = false; latestWeight = nil; latestUpdateAt = nil; updateCount = 0
        cardAthletes.removeAll(); selectedResults.removeAll()
        closesAt = nil; attemptStartedAt = nil; completedCount = 0; lastResult = ""
        review?.cancel(); review = nil; picture.image = nil; controls()
    }
    func close() {
        guard active else { return }; active = false; clearTest(); onClose()
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
#endif
