import UIKit
import AVKit

// AVPlayerViewController is a child, not subclassed. Our container owns rotation
// and the historical score badge; exported MP4s contain the same badge as pixels.
@MainActor
final class WrestlingManagerVideoReplay: UIViewController {
    private var row: [String: Any]
    private let store: WrestlingManagerVideoStore
    private let playerController = AVPlayerViewController()
    private let badge = UIImageView()
    private let note = UILabel()
    private let renderer = WrestlingManagerVideoScoreOverlay()
    private var renderTask: Task<Void, Never>?
    private var observer: Any?
    private var frames: [WrestlingVideoScoreTimeline.Entry] = []
    private var lastFrame: WrestlingVideoScoreFrame?
    private var burnedIn = false
    private var ended = false
    private var videoSize = CGSize(width: 1280, height: 720)
    var onClose: (() -> Void)?
    private var player: AVPlayer? { playerController.player }

    init(row: [String: Any], store: WrestlingManagerVideoStore) {
        self.row = row; self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown }
    override var shouldAutorotate: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        title = (row["label"] as? String) ?? "Match video"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "Export", style: .plain, target: self, action: #selector(exportMatchRecording)),
            UIBarButtonItem(title: "Events", style: .plain, target: self, action: #selector(events)),
            UIBarButtonItem(title: "Rotate", style: .plain, target: self, action: #selector(rotate))]
        addChild(playerController); view.addSubview(playerController.view); playerController.didMove(toParent: self)
        playerController.allowsPictureInPicturePlayback = false
        playerController.videoGravity = .resizeAspect
        playerController.entersFullScreenWhenPlaybackBegins = false
        badge.isUserInteractionEnabled = false; badge.accessibilityLabel = "Historical match score"
        // Keep the fallback badge with AVKit if it enters its own full-screen player.
        // A ready scored MP4 does not need this view; its scores are actual pixels.
        if let surface = playerController.contentOverlayView {
            badge.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(badge)
            let relativeWidth = badge.widthAnchor.constraint(equalTo: surface.widthAnchor, multiplier: 0.30)
            relativeWidth.priority = .defaultHigh
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.leadingAnchor, constant: 8),
                badge.topAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.topAnchor, constant: 8),
                relativeWidth, badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 145),
                badge.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
                badge.heightAnchor.constraint(equalTo: badge.widthAnchor, multiplier: 0.30)
            ])
        } else { view.addSubview(badge) }
        note.textColor = .white; note.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        note.font = .systemFont(ofSize: 12); note.numberOfLines = 2; note.textAlignment = .center
        note.isUserInteractionEnabled = false; view.addSubview(note)
        frames = WrestlingVideoScoreTimeline.entries(row, duration: max(0.001, ((row["durationMs"] as? NSNumber)?.doubleValue ?? 0) / 1000))
        do {
            guard let id = row["id"] as? String else { throw WrestlingManagerVideoStore.Failure.invalid }
            let scored = try WrestlingManagerVideoScoreOverlay.cachedURL(row: row, store: store)
            burnedIn = scored != nil
            let url = try scored ?? store.movie(id)
            playerController.player = AVPlayer(url: url)
            observer = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.10, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let owner = self else { return }
                Task { @MainActor in owner.paint(time.seconds) }
            }
            updateNote(); paint(0)
            Task { [weak self] in
                let asset = AVURLAsset(url: url)
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let size = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform), let self, !self.ended else { return }
                let box = CGRect(origin: .zero, size: size).applying(transform)
                self.videoSize = CGSize(width: abs(box.width), height: abs(box.height)); self.view.setNeedsLayout()
            }
        } catch { note.text = "The movie could not be opened. Original files were kept." }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerController.view.frame = view.bounds
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let scale = min(view.bounds.width / max(1, videoSize.width), view.bounds.height / max(1, videoSize.height))
        let content = CGRect(x: (view.bounds.width - videoSize.width * scale) / 2, y: (view.bounds.height - videoSize.height * scale) / 2, width: videoSize.width * scale, height: videoSize.height * scale)
        let width = min(280, max(145, content.width * 0.30))
        if badge.translatesAutoresizingMaskIntoConstraints {
            badge.frame = CGRect(x: max(safe.minX + 8, content.minX + 8), y: max(safe.minY + 8, content.minY + 8), width: width, height: width * 0.30)
        }
        note.frame = CGRect(x: safe.minX + 8, y: max(safe.minY, safe.maxY - 68), width: max(0, safe.width - 16), height: 36)
    }
    private func updateNote() {
        let partial = row["status"] as? String == "partial" ? "Partial recording · " : ""
        note.text = burnedIn ? partial + "Scores embedded in this video" : partial + "Original kept · Export creates a permanent scored copy"
    }
    private func paint(_ seconds: Double) {
        badge.isHidden = burnedIn
        guard !burnedIn, let frame = WrestlingVideoScoreTimeline.frame(frames, at: seconds) else {
            if !burnedIn { badge.isHidden = true; note.text = "Score history is unavailable at this time. Original footage is preserved." }
            return
        }
        if frame != lastFrame {
            lastFrame = frame
            badge.image = WrestlingManagerVideoScoreOverlay.image(frame, size: CGSize(width: 360, height: 108))
            badge.accessibilityValue = "Red \(frame.red), \(frame.otherIsGreen ? "Green" : "Blue") \(frame.other)"
        }
    }
    @objc private func rotate() {
        guard let scene = view.window?.windowScene else { return }
        let mask: UIInterfaceOrientationMask = scene.interfaceOrientation.isLandscape ? .portrait : .landscapeRight
        navigationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] _ in
            Task { @MainActor in self?.note.text = "Turn the phone sideways. Check the iPhone rotation lock if it stays upright." }
        }
    }
    func endPlayback() {
        guard !ended else { return }; ended = true
        renderer.cancel(); renderTask?.cancel(); renderTask = nil
        player?.pause()
        if let observer { player?.removeTimeObserver(observer); self.observer = nil }
        player?.replaceCurrentItem(with: nil)
    }
    @objc private func close() { endPlayback(); dismiss(animated: true) { [weak self] in self?.onClose?() } }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if navigationController?.isBeingDismissed == true || isBeingDismissed { endPlayback(); onClose?() }
    }
    @objc private func events() {
        let list = WrestlingManagerVideoEventList(events: (row["events"] as? [[String: Any]]) ?? []) { [weak self] ms in
            guard let self else { return }
            let maximum = max(0, ((self.row["durationMs"] as? NSNumber)?.doubleValue ?? 0) - 50)
            let target = min(maximum, max(0, ms + 3))
            self.player?.seek(to: CMTime(seconds: target / 1000, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            self.paint(target / 1000)
        }
        let navigation = WrestlingVideoNavigationController(rootViewController: list)
        present(navigation, animated: true)
    }
    @objc private func exportMatchRecording() {
        guard renderTask == nil else { return }
        player?.pause()
        let notice = UIAlertController(title: "Keep a copy", message: "The scored MP4 keeps the changing scores without scorer buttons. Share only with people permitted to receive this recording.", preferredStyle: .actionSheet)
        notice.addAction(UIAlertAction(title: "Export scored video", style: .default) { [weak self] _ in self?.exportScored() })
        notice.addAction(UIAlertAction(title: "Export original + score timeline", style: .default) { [weak self] _ in
            guard let self, let id = self.row["id"] as? String, let video = try? self.store.movie(id), let timeline = try? self.store.timeline(id) else { return }
            self.share([video, timeline])
        })
        notice.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        notice.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(notice, animated: true)
    }
    private func exportScored() {
        note.text = "Preparing permanent score overlay… Original video is safe."
        navigationItem.rightBarButtonItems?.first?.isEnabled = false
        renderTask = Task { [weak self] in
            guard let self else { return }
            defer { self.renderTask = nil; self.navigationItem.rightBarButtonItems?.first?.isEnabled = true }
            do {
                let completed = try await self.renderer.prepare(row: self.row, store: self.store)
                guard !self.ended, !Task.isCancelled, let url = try WrestlingManagerVideoScoreOverlay.cachedURL(row: completed, store: self.store) else { return }
                self.row = completed
                self.note.text = "Scored copy ready. Choose a destination, then open the saved file to confirm it."
                self.share([url])
            } catch {
                if !self.ended { self.note.text = error.localizedDescription }
            }
        }
    }
    private func share(_ urls: [URL]) {
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        // Opening the share sheet is not proof of a completed external download.
        present(sheet, animated: true)
    }
}

@MainActor
final class WrestlingVideoNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { topViewController?.supportedInterfaceOrientations ?? .allButUpsideDown }
    override var shouldAutorotate: Bool { true }
}

@MainActor
private final class WrestlingManagerVideoEventList: UITableViewController {
    private let events: [[String: Any]]
    private let seek: (Double) -> Void
    init(events: [[String: Any]], seek: @escaping (Double) -> Void) { self.events = events; self.seek = seek; super.init(style: .plain) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Jump to a scoring event"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
    }
    @objc private func close() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { events.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil), event = events[indexPath.row]
        let seconds = Int(((event["atMs"] as? NSNumber)?.doubleValue ?? 0) / 1000)
        cell.textLabel?.text = "\(seconds / 60):\(String(format: "%02d", seconds % 60)) · \((event["label"] as? String) ?? "Score updated")"
        cell.textLabel?.numberOfLines = 0
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let ms = (events[indexPath.row]["atMs"] as? NSNumber)?.doubleValue ?? 0
        dismiss(animated: true) { [seek] in seek(ms) }
    }
}
