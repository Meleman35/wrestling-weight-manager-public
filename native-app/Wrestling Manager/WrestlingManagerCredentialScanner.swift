// Revision-20 scanner patch: rotating preview and safe-area-bounded landscape controls.
// Camera preference, serial capture lifecycle and credential callbacks are unchanged.
@preconcurrency import AVFoundation
import UIKit
import WebKit

@MainActor
final class WrestlingManagerCredentialScannerBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private var activeScanner: WrestlingManagerScannerViewController?

    func attach(to webView: WKWebView) { self.webView = webView }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "credentialScanner",
              let body = message.body as? [String: Any],
              body["command"] as? String == "scan" else { return }
        webView = message.webView ?? webView
        guard activeScanner == nil else { return }
        guard let presenter = topViewController(from: webView?.window?.rootViewController),
              presenter.viewIfLoaded?.window != nil,
              !presenter.isBeingDismissed, !presenter.isBeingPresented else {
            sendError("The camera scanner could not open. Close the current dialog and try again.")
            return
        }
        webView?.endEditing(true)
        let scanner = WrestlingManagerScannerViewController()
        activeScanner = scanner
        scanner.modalPresentationStyle = .fullScreen
        scanner.onFinish = { [weak self, weak scanner] token, kind, error in
            guard let self, let scanner, self.activeScanner === scanner else { return }
            scanner.dismiss(animated: true) { [weak self] in
                guard let self, self.activeScanner === scanner else { return }
                self.activeScanner = nil
                if let error { self.sendError(error) }
                else { self.sendResult(token: token ?? "", kind: kind ?? "qr") }
            }
        }
        presenter.present(scanner, animated: true)
    }

    func cancelForBackground() { activeScanner?.cancelScanning() }

    private func sendResult(token: String, kind: String) {
        guard let tokenJSON = jsonString(token), let kindJSON = jsonString(kind) else { return }
        webView?.evaluateJavaScript("window.wrestlingManagerCredentialScanned?.(\(tokenJSON),\(kindJSON));", completionHandler: nil)
    }
    private func sendError(_ reason: String) {
        guard let reasonJSON = jsonString(reason) else { return }
        webView?.evaluateJavaScript("window.wrestlingManagerCredentialScanned?.(''); window.wrestlingManagerCredentialScannerError?.(\(reasonJSON));", completionHandler: nil)
    }
    private func jsonString(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func topViewController(from root: UIViewController?) -> UIViewController? {
        if let presented = root?.presentedViewController { return topViewController(from: presented) }
        if let navigation = root as? UINavigationController { return topViewController(from: navigation.visibleViewController) }
        if let tab = root as? UITabBarController { return topViewController(from: tab.selectedViewController) }
        return root
    }
}

// AVFoundation objects and mutable state are confined to queue. The immutable
// session reference is also used by Apple's preview layer on the main thread.
// This wrapper is Sendable; UI callbacks transfer only strings and booleans.
private final class WrestlingCameraCapture: NSObject, @unchecked Sendable, AVCaptureMetadataOutputObjectsDelegate {
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated private let queue = DispatchQueue(label: "app.wrestlingmanager.camera", qos: .userInitiated)
    nonisolated(unsafe) private var input: AVCaptureDeviceInput?
    nonisolated(unsafe) private var output: AVCaptureMetadataOutput?
    nonisolated(unsafe) private var finished = false
    nonisolated private let onReady: @MainActor @Sendable (Bool, String) -> Void
    nonisolated private let onResult: @MainActor @Sendable (String, String) -> Void
    nonisolated private let onFailure: @MainActor @Sendable (String) -> Void

    nonisolated init(onReady: @escaping @MainActor @Sendable (Bool, String) -> Void,
                     onResult: @escaping @MainActor @Sendable (String, String) -> Void,
                     onFailure: @escaping @MainActor @Sendable (String) -> Void) {
        self.onReady = onReady; self.onResult = onResult; self.onFailure = onFailure
        super.init()
    }

    nonisolated func start(preferFront: Bool) {
        queue.async { [self] in
            guard !finished else { return }
            do {
                var notice = ""
                do { try configure(front: preferFront) }
                catch {
                    if input == nil {
                        try configure(front: !preferFront)
                        notice = "The requested camera cannot scan codes here. Using the other camera."
                    } else {
                        notice = "That camera cannot scan codes here. Keeping the current camera."
                    }
                }
                if !session.isRunning { session.startRunning() }
                guard session.isRunning else { throw CameraError.unavailable }
                let front = input?.device.position == .front
                if notice.isEmpty, front, output?.metadataObjectTypes.contains(.code128) != true {
                    notice = "Use a QR code with the front camera, or switch to the rear camera for barcodes."
                }
                let callback = onReady
                let message = notice
                Task { @MainActor in callback(front, message) }
            } catch {
                finished = true
                if session.isRunning { session.stopRunning() }
                let callback = onFailure
                let reason = "The camera could not start: \(error.localizedDescription)"
                Task { @MainActor in callback(reason) }
            }
        }
    }

    private enum CameraError: LocalizedError {
        case unavailable
        nonisolated var errorDescription: String? { "No available camera supports QR or barcode scanning." }
    }
    nonisolated private func configure(front: Bool) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back) else { throw CameraError.unavailable }
        let candidate = try AVCaptureDeviceInput(device: device)
        let previous = input
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        output?.metadataObjectTypes = []
        if let previous { session.removeInput(previous) }
        do {
            guard session.canAddInput(candidate) else { throw CameraError.unavailable }
            session.addInput(candidate)
            if output == nil {
                let metadata = AVCaptureMetadataOutput()
                guard session.canAddOutput(metadata) else { throw CameraError.unavailable }
                session.addOutput(metadata)
                metadata.setMetadataObjectsDelegate(self, queue: queue)
                output = metadata
            }
            guard let output else { throw CameraError.unavailable }
            let types = [AVMetadataObject.ObjectType.qr, .code128].filter { output.availableMetadataObjectTypes.contains($0) }
            guard !types.isEmpty else { throw CameraError.unavailable }
            output.metadataObjectTypes = types
            input = candidate
        } catch {
            if session.inputs.contains(where: { $0 === candidate }) { session.removeInput(candidate) }
            if let previous, session.canAddInput(previous) {
                session.addInput(previous)
                if let output { output.metadataObjectTypes = [.qr, .code128].filter { output.availableMetadataObjectTypes.contains($0) } }
                input = previous
            } else { input = nil }
            throw error
        }
    }

    nonisolated func stop() {
        queue.async { [self] in
            finished = true
            if session.isRunning { session.stopRunning() }
        }
    }
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished,
              let code = objects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = code.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        finished = true
        let kind = code.type == .qr ? "qr" : "barcode"
        let callback = onResult
        // Let the delegate return before synchronously stopping the pipeline.
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            Task { @MainActor in callback(value, kind) }
        }
    }
}

@MainActor
final class WrestlingManagerScannerViewController: UIViewController {
    var onFinish: ((String?, String?, String?) -> Void)?
    private static let cameraPreferenceKey = "wm.scanner.preferFrontCamera"
    private var usingFront = (UserDefaults.standard.object(forKey: "wm.scanner.preferFrontCamera") as? Bool) ?? true
    private var didFinish = false
    private var started = false
    private let cameraSwitch = UIButton(type: .system)
    private let cameraHelp = UILabel()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var previewRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var previewVisible = false
    private lazy var capture = WrestlingCameraCapture(
        onReady: { [weak self] front, notice in
            guard let self, !self.didFinish else { return }
            self.usingFront = front
            UserDefaults.standard.set(front, forKey: Self.cameraPreferenceKey)
            self.cameraSwitch.isEnabled = true
            self.cameraSwitch.setTitle(front ? "Use Rear Camera" : "Use Front Camera", for: .normal)
            self.cameraHelp.text = notice.isEmpty ? "\(front ? "Front" : "Rear") camera · Center the athlete QR or barcode inside the frame." : notice
            // Configuration is committed and the camera has started before onReady.
            // The preview's current input identifies the real device, including fallback.
            self.configurePreviewRotation()
        },
        onResult: { [weak self] token, kind in self?.finish(token: token, kind: kind) },
        onFailure: { [weak self] reason in self?.finish(error: reason) }
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildOverlay()
        let preview = AVCaptureVideoPreviewLayer(session: capture.session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        previewVisible = true
        updatePreviewGeometry()
        guard !started else { return }
        started = true
        requestCameraAndStart()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreviewGeometry()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        previewVisible = false
        clearPreviewRotation()
        capture.stop()
    }

    private func configurePreviewRotation() {
        clearPreviewRotation()
        guard previewVisible, !didFinish,
              let preview = previewLayer,
              let port = preview.connection?.inputPorts.first(where: { $0.mediaType == .video }),
              let deviceInput = port.input as? AVCaptureDeviceInput else { return }
        // Use the actual camera and preview layer, rather than assuming every front
        // camera has the same native sensor orientation. iOS/Catalyst target is 17.6+.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: deviceInput.device, previewLayer: preview)
        previewRotationCoordinator = coordinator
        previewRotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) {
            [weak self, weak coordinator] _, _ in
            // AVFoundation documents this KVO callback on the main queue. Apply the
            // angle immediately so it stays synchronized with system rotation.
            MainActor.assumeIsolated {
                guard let self, let coordinator, self.previewVisible, !self.didFinish,
                      self.previewRotationCoordinator === coordinator else { return }
                self.applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        }
        // Handles opening the scanner while already in either landscape direction.
        updatePreviewGeometry()
    }

    private func updatePreviewGeometry() {
        guard let preview = previewLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = view.bounds
        CATransaction.commit()
        if let coordinator = previewRotationCoordinator {
            applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard previewVisible, !didFinish, angle.isFinite,
              let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
        // Preserve AVFoundation's existing front/rear mirroring behavior.
        // Metadata output and saved match-video orientation are not changed here.
    }

    private func clearPreviewRotation() {
        previewRotationObservation?.invalidate()
        previewRotationObservation = nil
        previewRotationCoordinator = nil
    }
    private func requestCameraAndStart() {
        let usage = (Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String) ?? ""
        guard !usage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finish(error: "Camera scanning is not configured in this app build. Please update the app.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: capture.start(preferFront: usingFront)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, !self.didFinish else { return }
                    if granted { self.capture.start(preferFront: self.usingFront) }
                    else { self.finish(error: "Camera access is required to scan an athlete code.") }
                }
            }
        case .denied, .restricted: finish(error: "Camera access is off. Enable it in Settings > Privacy & Security > Camera.")
        @unknown default: finish(error: "The camera is not available on this device.")
        }
    }
    @objc private func switchCamera() {
        guard !didFinish else { return }
        cameraSwitch.isEnabled = false
        cameraHelp.text = "Switching camera…"
        // The old camera must not continue applying angles during reconfiguration.
        // onReady installs a new coordinator for the selected camera or fallback.
        clearPreviewRotation()
        capture.start(preferFront: !usingFront)
    }
    @objc func cancelScanning() { finish() }
    private func finish(token: String? = nil, kind: String? = nil, error: String? = nil) {
        guard !didFinish else { return }
        didFinish = true
        clearPreviewRotation()
        capture.stop()
        if token != nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        onFinish?(token, kind, error)
    }
    private func buildOverlay() {
        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setTitle("Cancel", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        close.layer.cornerRadius = 15
        close.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        close.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        close.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)

        let frameGuide = UIView()
        frameGuide.translatesAutoresizingMaskIntoConstraints = false
        frameGuide.isUserInteractionEnabled = false
        frameGuide.layer.borderColor = UIColor.white.cgColor
        frameGuide.layer.borderWidth = 3
        frameGuide.layer.cornerRadius = 24
        frameGuide.backgroundColor = .clear

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Scan Athlete Code"
        title.textColor = .white
        title.font = .systemFont(ofSize: 25, weight: .heavy)
        title.textAlignment = .center
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.6

        let help = cameraHelp
        help.translatesAutoresizingMaskIntoConstraints = false
        help.text = "Center the athlete QR or barcode inside the frame."
        help.textColor = UIColor.white.withAlphaComponent(0.88)
        help.font = .systemFont(ofSize: 15, weight: .semibold)
        help.textAlignment = .center
        help.numberOfLines = 3
        // Shrink the scan frame before compressing its instructions on short screens.
        help.setContentCompressionResistancePriority(.required, for: .vertical)

        cameraSwitch.translatesAutoresizingMaskIntoConstraints = false
        cameraSwitch.setTitle("Switch Camera", for: .normal)
        cameraSwitch.setTitleColor(.white, for: .normal)
        cameraSwitch.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        cameraSwitch.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        cameraSwitch.layer.cornerRadius = 15
        cameraSwitch.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        cameraSwitch.isEnabled = false
        view.addSubview(cameraSwitch)
        view.addSubview(frameGuide)
        view.addSubview(title)
        view.addSubview(help)
        view.addSubview(close)

        let safe = view.safeAreaLayoutGuide
        let scanArea = UILayoutGuide()
        view.addLayoutGuide(scanArea)
        // Prefer the existing 78% width, but let height constrain the frame on a
        // landscape screen. Header/footer controls stay inside the safe area.
        let preferredGuideWidth = frameGuide.widthAnchor.constraint(equalTo: safe.widthAnchor, multiplier: 0.78)
        preferredGuideWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            cameraSwitch.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            cameraSwitch.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            cameraSwitch.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            cameraSwitch.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            cameraSwitch.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, constant: -32),
            close.topAnchor.constraint(equalTo: safe.topAnchor, constant: 10),
            close.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            title.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            title.heightAnchor.constraint(equalTo: close.heightAnchor),
            title.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -12),
            help.bottomAnchor.constraint(equalTo: cameraSwitch.topAnchor, constant: -12),
            help.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            help.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            scanArea.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 12),
            scanArea.bottomAnchor.constraint(equalTo: help.topAnchor, constant: -12),
            scanArea.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            scanArea.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            frameGuide.centerXAnchor.constraint(equalTo: scanArea.centerXAnchor),
            frameGuide.centerYAnchor.constraint(equalTo: scanArea.centerYAnchor),
            frameGuide.widthAnchor.constraint(lessThanOrEqualTo: scanArea.widthAnchor),
            frameGuide.heightAnchor.constraint(lessThanOrEqualTo: scanArea.heightAnchor),
            frameGuide.heightAnchor.constraint(equalTo: frameGuide.widthAnchor, multiplier: 0.72),
            preferredGuideWidth
        ])
    }
}

