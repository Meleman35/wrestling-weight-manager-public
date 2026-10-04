// Video Pilot 0.20.46. AVFoundation objects are confined to one serial queue.
@preconcurrency import AVFoundation
import UIKit

final class WrestlingManagerVideoCapture: NSObject, @unchecked Sendable, AVCaptureFileOutputRecordingDelegate {
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated private let queue = DispatchQueue(label: "app.wrestlingmanager.video.capture", qos: .userInitiated)
    nonisolated(unsafe) private let movie = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private var closed = false
    nonisolated(unsafe) private var pending = false
    nonisolated(unsafe) private var stopRequested = false
    nonisolated private let onStart: @MainActor @Sendable () -> Void
    nonisolated private let onFinish: @MainActor @Sendable (Bool, Bool) -> Void

    nonisolated init(onStart: @escaping @MainActor @Sendable () -> Void,
                     onFinish: @escaping @MainActor @Sendable (Bool, Bool) -> Void) {
        self.onStart = onStart; self.onFinish = onFinish
        super.init()
    }
    private enum CaptureError: Error { case unavailable }

    nonisolated func open(rotation: CGFloat) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard !closed else { throw CaptureError.unavailable }
                    session.beginConfiguration()
                    do {
                        guard session.canSetSessionPreset(.hd1280x720),
                              let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                              let microphone = AVCaptureDevice.default(for: .audio) else { throw CaptureError.unavailable }
                        session.sessionPreset = .hd1280x720
                        let videoInput = try AVCaptureDeviceInput(device: camera)
                        let audioInput = try AVCaptureDeviceInput(device: microphone)
                        guard session.canAddInput(videoInput) else { throw CaptureError.unavailable }
                        session.addInput(videoInput)
                        guard session.canAddInput(audioInput) else { throw CaptureError.unavailable }
                        session.addInput(audioInput)
                        guard session.canAddOutput(movie) else { throw CaptureError.unavailable }
                        session.addOutput(movie)
                        movie.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
                        movie.maxRecordedDuration = CMTime(seconds: 20 * 60, preferredTimescale: 600)
                        movie.minFreeDiskSpaceLimit = 256 * 1024 * 1024
                        if let connection = movie.connection(with: .video) {
                            if connection.isVideoRotationAngleSupported(rotation) { connection.videoRotationAngle = rotation }
                            if movie.availableVideoCodecTypes.contains(.h264) {
                                movie.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)
                            }
                        }
                        session.commitConfiguration()
                    } catch { session.commitConfiguration(); throw error }
                    session.startRunning()
                    guard session.isRunning else { throw CaptureError.unavailable }
                    continuation.resume()
                } catch {
                    closed = true
                    if session.isRunning { session.stopRunning() }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    // Set capture orientation on the same queue immediately before the movie begins.
    nonisolated func record(to url: URL, rotation: CGFloat) {
        queue.async { [self] in
            guard !closed, !pending, session.isRunning else {
                let callback = onFinish
                Task { @MainActor in callback(false, true) }; return
            }
            pending = true; stopRequested = false
            if let connection = movie.connection(with: .video), connection.isVideoRotationAngleSupported(rotation) {
                connection.videoRotationAngle = rotation
            }
            movie.startRecording(to: url, recordingDelegate: self)
        }
    }
    nonisolated func timestamp(_ callback: @escaping @MainActor @Sendable (Double) -> Void) {
        queue.async { [self] in
            let seconds = movie.recordedDuration.seconds
            let ms = seconds.isFinite ? max(0, seconds * 1000) : 0
            Task { @MainActor in callback(ms) }
        }
    }
    nonisolated func stop() {
        queue.async { [self] in
            stopRequested = true
            if movie.isRecording { movie.stopRecording() }
            else if !pending { closed = true; if session.isRunning { session.stopRunning() } }
        }
    }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async { [self] in
            let callback = onStart
            Task { @MainActor in callback() }
            if stopRequested, movie.isRecording { movie.stopRecording() }
        }
    }
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // A limit/interruption can supply an error even when a playable file was finalized.
        let success = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
        let interrupted = error != nil
        queue.async { [self] in
            pending = false; closed = true
            if session.isRunning { session.stopRunning() }
            let callback = onFinish
            Task { @MainActor in callback(success, interrupted) }
        }
    }
}

// This is a display of the existing scorer's snapshot, not another scoring engine.
@MainActor
final class WrestlingManagerVideoPreview: UIView {
    let preview: AVCaptureVideoPreviewLayer
    private let scoreboard = UILabel()
    init(session: AVCaptureSession, rotation: CGFloat) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        backgroundColor = .black; clipsToBounds = true; isUserInteractionEnabled = false
        preview.videoGravity = .resizeAspect
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(rotation) { connection.videoRotationAngle = rotation }
        layer.addSublayer(preview)
        scoreboard.textColor = .white; scoreboard.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        scoreboard.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        scoreboard.numberOfLines = 3; scoreboard.textAlignment = .center
        addSubview(scoreboard)
        accessibilityLabel = "Match camera preview"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews(); preview.frame = bounds
        scoreboard.frame = CGRect(x: 6, y: 6, width: max(0, bounds.width - 12), height: min(66, bounds.height))
    }
    func show(_ text: String) { scoreboard.text = String(text.prefix(500)) }
    func rotate(_ angle: CGFloat) {
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }
    func overlayControls(_ enabled: Bool) { scoreboard.isHidden = enabled }
}

// Keep the MOVIE's orientation selected at Record, not the entire interface.
// AVFoundation receives that angle once in record(to:rotation:); the preview and
// controls can rotate during the take and replay is never left with a stale lock.
@MainActor
enum WrestlingVideoOrientation {
    static var movieOrientation: UIInterfaceOrientation?
    static func angle(_ orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .landscapeRight: return 0
        case .landscapeLeft: return 180
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }
    static func recordingStarted(_ orientation: UIInterfaceOrientation, root: UIViewController?) {
        movieOrientation = orientation; refresh(root)
    }
    static func unlock(root: UIViewController?) { movieOrientation = nil; refresh(root) }
    static func refresh(_ root: UIViewController?) {
        root?.setNeedsUpdateOfSupportedInterfaceOrientations()
        root?.children.forEach { refresh($0) }
        if let presented = root?.presentedViewController { refresh(presented) }
    }
}

extension WrestlingManagerAppDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }
}
