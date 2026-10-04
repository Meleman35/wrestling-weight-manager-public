@preconcurrency import AVFoundation
import UIKit

/// Camera-only snapshot presenter; timestamps are taken at exposure, not review.
@MainActor
final class WrestlingManagerRemotePhoto {
    enum Failure: Error { case unavailable, busy, invalidImage, cancelled }
    private var camera: RemoteSnapshotController?
    private var completion: ((UUID, Result<(Data, Date), Error>) -> Void)?
    private var token: UUID?

    func take(token: UUID, from presenter: UIViewController, setup: Bool = false,
              readyToCapture: (() -> Bool)? = nil,
              completion: @escaping (UUID, Result<(Data, Date), Error>) -> Void) {
        guard camera == nil else { completion(token, .failure(Failure.busy)); return }
        guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else {
            completion(token, .failure(Failure.unavailable)); return
        }
        let controller = RemoteSnapshotController(setup: setup, readyToCapture: readyToCapture)
        self.token = token; self.completion = completion; camera = controller
        controller.modalPresentationStyle = .fullScreen
        controller.onFinish = { [weak self, weak controller] result in
            guard let self, let controller, self.camera === controller else { return }
            self.finish(result.flatMap { data, at in
                guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0,
                      image.size.width.isFinite, image.size.height.isFinite else { return .failure(Failure.invalidImage) }
                // Render strips original metadata and applies image orientation.
                let factor = min(1, 1280 / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    UIColor.black.setFill(); UIRectFill(CGRect(origin: .zero, size: size))
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                guard let jpeg = normalized.jpegData(compressionQuality: 0.8), !jpeg.isEmpty,
                      jpeg.count <= 5 * 1024 * 1024 else { return .failure(Failure.invalidImage) }
                return .success((jpeg, at))
            })
        }
        presenter.present(controller, animated: true)
    }
    func cancel() { finish(.failure(Failure.cancelled)) }
    private func finish(_ result: Result<(Data, Date), Error>) {
        guard let camera, let token else { return }
        let callback = completion
        self.camera = nil; self.token = nil; completion = nil
        camera.stop(); camera.dismiss(animated: false) { callback?(token, result) }
    }
}

/// Local-only test photo review. No upload, album write, athlete binding or queue.
@MainActor final class WrestlingManagerRemoteSetupReview: UIViewController {
    enum Decision { case confirmed, retake, cancelled }
    private let picture = UIImageView()
    private let layout = UIStackView()
    private var completion: ((Decision) -> Void)?
    init(jpeg: Data, completion: @escaping (Decision) -> Void) {
        self.completion = completion; super.init(nibName: nil, bundle: nil)
        picture.image = UIImage(data: jpeg); modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("Use init(jpeg:completion:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let title = UILabel(); title.text = "Check the complete weigh-in view"; title.font = .preferredFont(forTextStyle: .headline)
        title.numberOfLines = 0; title.textAlignment = .center
        let note = UILabel(); note.text = "Confirm the athlete’s face, singlet, both feet and scale are visible. Keep other athletes out of the frame. This test photo will be discarded. Recheck setup after moving the device or scale."
        note.font = .preferredFont(forTextStyle: .body); note.numberOfLines = 0
        for label in [title,note] { label.adjustsFontForContentSizeCategory = true }
        picture.contentMode = .scaleAspectFit; picture.accessibilityLabel = "Temporary camera setup test photo"
        let confirm = UIButton(type: .system); confirm.setTitle("Full athlete and scale are visible", for: .normal)
        confirm.addTarget(self, action: #selector(confirmSetup), for: .touchUpInside); confirm.isEnabled = picture.image != nil
        let retake = UIButton(type: .system); retake.setTitle("Adjust camera and retake", for: .normal)
        retake.addTarget(self, action: #selector(retakeSetup), for: .touchUpInside)
        let cancel = UIButton(type: .system); cancel.setTitle("Cancel setup", for: .normal)
        cancel.addTarget(self, action: #selector(cancelSetup), for: .touchUpInside)
        for button in [confirm,retake,cancel] {
            button.titleLabel?.numberOfLines = 0; button.titleLabel?.textAlignment = .center
            button.titleLabel?.font = .preferredFont(forTextStyle: .body)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        // Keep the photo visible on landscape phones and at larger text sizes.
        // Instructions/buttons scroll independently instead of collapsing it.
        let panel = UIScrollView(); panel.alwaysBounceVertical = true
        let stack = UIStackView(arrangedSubviews: [title,note,confirm,retake,cancel]); stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(stack)
        layout.addArrangedSubview(picture); layout.addArrangedSubview(panel)
        layout.axis = .vertical; layout.distribution = .fillEqually; layout.spacing = 12
        layout.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(layout)
        picture.setContentHuggingPriority(.defaultLow, for: .vertical)
        picture.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        picture.setContentHuggingPriority(.defaultLow, for: .horizontal)
        picture.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([layout.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            layout.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            layout.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            layout.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: panel.frameLayoutGuide.widthAnchor)])
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout.axis = view.bounds.width > view.bounds.height ? .horizontal : .vertical
    }
    private func finish(_ decision: Decision) {
        guard let callback = completion else { return }; completion = nil; picture.image = nil
        dismiss(animated: false) { callback(decision) }
    }
    @objc private func confirmSetup() { finish(.confirmed) }
    @objc private func retakeSetup() { finish(.retake) }
    @objc private func cancelSetup() { cancel() }
    func cancel() { finish(.cancelled) }
}

// Mutable AVFoundation capture state is confined to a serial queue.
nonisolated private final class RemoteSnapshotCamera: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    nonisolated(unsafe) let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.wrestlingmanager.remote-photo", qos: .userInitiated)
    nonisolated(unsafe) private var output: AVCapturePhotoOutput?
    nonisolated(unsafe) private var finished = false
    nonisolated(unsafe) private var exposureAt: Date?
    nonisolated(unsafe) private var shooting = false
    private let onReady: @MainActor @Sendable () -> Void
    private let onResult: @MainActor @Sendable (Data?, Date?) -> Void
    init(onReady: @escaping @MainActor @Sendable () -> Void,
         onResult: @escaping @MainActor @Sendable (Data?, Date?) -> Void) {
        self.onReady = onReady; self.onResult = onResult; super.init()
    }
    func start() {
        queue.async { [self] in
            guard !finished else { return }
            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw WrestlingManagerRemotePhoto.Failure.unavailable
                }
                let input = try AVCaptureDeviceInput(device: device)
                let photo = AVCapturePhotoOutput()
                session.beginConfiguration()
                session.sessionPreset = .photo
                guard session.canAddInput(input), session.canAddOutput(photo) else {
                    session.commitConfiguration(); throw WrestlingManagerRemotePhoto.Failure.unavailable
                }
                session.addInput(input); session.addOutput(photo); session.commitConfiguration(); output = photo
                session.startRunning()
                guard session.isRunning else { throw WrestlingManagerRemotePhoto.Failure.unavailable }
                Task { @MainActor [onReady] in onReady() }
            } catch { fail() }
        }
    }
    func shoot(angle: CGFloat) {
        queue.async { [self] in
            guard !finished, !shooting, let output, session.isRunning else { return }
            shooting = true
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
        }
    }
    func stop() { queue.async { [self] in finished = true; if session.isRunning { session.stopRunning() } } }
    private func fail() {
        guard !finished else { return }; finished = true
        if session.isRunning { session.stopRunning() }
        Task { @MainActor [onResult] in onResult(nil, nil) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        let at = Date()
        queue.async { [self] in guard !finished else { return }; exposureAt = at }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [self] in
            guard !finished else { return }
            guard let data, let at = exposureAt else { fail(); return }
            finished = true; if session.isRunning { session.stopRunning() }
            Task { @MainActor [onResult] in onResult(data, at) }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error != nil { queue.async { [self] in fail() } }
    }
}

@MainActor private final class RemoteSnapshotController: UIViewController {
    var onFinish: ((Result<(Data, Date), Error>) -> Void)?
    private var finished = false
    private let shutter = UIButton(type: .system)
    private let setup: Bool
    private let readyToCapture: (() -> Bool)?
    private var countdown = WrestlingManagerRemoteReadiness()
    private var countdownTask: Task<Void, Never>?
    private let previewView = UIView()
    private let guide = CAShapeLayer()
    init(setup: Bool, readyToCapture: (() -> Bool)?) {
        self.setup = setup; self.readyToCapture = setup ? nil : readyToCapture
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(setup:)") }
    private var preview: AVCaptureVideoPreviewLayer?
    private lazy var capture = RemoteSnapshotCamera(onReady: { [weak self] in
        guard let self, !self.finished else { return }
        self.shutter.isEnabled = self.readyToCapture == nil; self.view.setNeedsLayout()
        if self.readyToCapture != nil { self.startCountdown() }
    }, onResult: { [weak self] data, at in
        guard let self, !self.finished else { return }
        self.finished = true
        if let data, let at { self.onFinish?(.success((data, at))) }
        else { self.onFinish?(.failure(WrestlingManagerRemotePhoto.Failure.unavailable)) }
    })
    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, !self.finished else { return }
                let seconds = self.countdown.remaining(ready: self.readyToCapture?() == true,
                                                       at: ProcessInfo.processInfo.systemUptime)
                self.shutter.setTitle(seconds.map { "Photo in \($0)… Stand still" } ?? "Waiting for a stable scale reading…", for: .normal)
                if seconds == 0 { self.takePhoto(); return }
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            }
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        previewView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(previewView)
        // Show the complete camera frame; a fill crop can conceal the athlete's
        // head or feet even when the captured JPEG includes a different area.
        let layer = AVCaptureVideoPreviewLayer(session: capture.session); layer.videoGravity = .resizeAspect
        previewView.layer.addSublayer(layer); preview = layer
        guide.fillColor = UIColor.clear.cgColor; guide.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        guide.lineWidth = 2; guide.lineDashPattern = [8, 6]; previewView.layer.addSublayer(guide)
        let instructions = UILabel(); instructions.textColor = .white; instructions.numberOfLines = 0
        instructions.font = .preferredFont(forTextStyle: .subheadline); instructions.adjustsFontForContentSizeCategory = true
        instructions.textAlignment = .center; instructions.translatesAutoresizingMaskIntoConstraints = false
        instructions.text = setup
            ? "Camera & scale setup\nShow the athlete’s face, singlet, both feet and the scale. Use a private area with nobody else in frame."
            : "Keep the athlete’s face, singlet, both feet and scale in view. Stand still for the verification photo."
        view.addSubview(instructions)
        let cancel = UIButton(type: .system); cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(cancelPhoto), for: .touchUpInside)
        shutter.setTitle(setup ? "Take setup test photo" : "Take weigh-in photo", for: .normal); shutter.isEnabled = false
        shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [cancel, shutter]); controls.axis = .horizontal
        controls.distribution = .fillEqually; controls.backgroundColor = .black; controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        NSLayoutConstraint.activate([instructions.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            instructions.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            instructions.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            previewView.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 12),
            previewView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), controls.heightAnchor.constraint(equalToConstant: 64)])
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: capture.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, !self.finished else { return }
                    if granted { self.capture.start() } else { self.cancelPhoto() }
                }
            }
        default: cancelPhoto()
        }
    }
    private var rotation: CGFloat {
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); preview?.frame = previewView.bounds
        if let connection = preview?.connection, connection.isVideoRotationAngleSupported(rotation) {
            connection.videoRotationAngle = rotation
        }
        if let preview {
            let frame = preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            guide.frame = previewView.bounds; guide.path = UIBezierPath(roundedRect: frame.insetBy(dx: 12, dy: 12), cornerRadius: 14).cgPath
        }
    }
    @objc private func takePhoto() {
        guard !finished, readyToCapture?() != false else { return }
        shutter.isEnabled = false; capture.shoot(angle: rotation)
    }
    @objc private func cancelPhoto() {
        guard !finished else { return }; finished = true; countdownTask?.cancel(); capture.stop()
        onFinish?(.failure(WrestlingManagerRemotePhoto.Failure.cancelled))
    }
    func stop() { finished = true; countdownTask?.cancel(); countdownTask = nil; capture.stop() }
}
