@preconcurrency import AVFoundation
import UIKit

/// Camera-only snapshot presenter; timestamps are taken at exposure, not review.
@MainActor
final class WrestlingManagerRemotePhoto {
    enum Failure: Error { case unavailable, busy, invalidImage, cancelled }
    private var camera: RemoteSnapshotController?
    private var completion: ((UUID, Result<(Data, Date), Error>) -> Void)?
    private var token: UUID?

    func take(token: UUID, from presenter: UIViewController,
              completion: @escaping (UUID, Result<(Data, Date), Error>) -> Void) {
        guard camera == nil else { completion(token, .failure(Failure.busy)); return }
        guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else {
            completion(token, .failure(Failure.unavailable)); return
        }
        let controller = RemoteSnapshotController()
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
        camera.stop(); camera.dismiss(animated: false)
        callback?(token, result)
    }
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
    private var preview: AVCaptureVideoPreviewLayer?
    private lazy var capture = RemoteSnapshotCamera(onReady: { [weak self] in
        guard let self, !self.finished else { return }; self.shutter.isEnabled = true
    }, onResult: { [weak self] data, at in
        guard let self, !self.finished else { return }
        self.finished = true
        if let data, let at { self.onFinish?(.success((data, at))) }
        else { self.onFinish?(.failure(WrestlingManagerRemotePhoto.Failure.unavailable)) }
    })
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: capture.session); layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer); preview = layer
        let cancel = UIButton(type: .system); cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(cancelPhoto), for: .touchUpInside)
        shutter.setTitle("Take weigh-in photo", for: .normal); shutter.isEnabled = false
        shutter.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        let controls = UIStackView(arrangedSubviews: [cancel, shutter]); controls.axis = .horizontal
        controls.distribution = .fillEqually; controls.backgroundColor = .black; controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        NSLayoutConstraint.activate([controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
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
        super.viewDidLayoutSubviews(); preview?.frame = view.bounds
        if let connection = preview?.connection, connection.isVideoRotationAngleSupported(rotation) {
            connection.videoRotationAngle = rotation
        }
    }
    @objc private func takePhoto() { guard !finished else { return }; shutter.isEnabled = false; capture.shoot(angle: rotation) }
    @objc private func cancelPhoto() {
        guard !finished else { return }; finished = true; capture.stop()
        onFinish?(.failure(WrestlingManagerRemotePhoto.Failure.cancelled))
    }
    func stop() { finished = true; capture.stop() }
}
