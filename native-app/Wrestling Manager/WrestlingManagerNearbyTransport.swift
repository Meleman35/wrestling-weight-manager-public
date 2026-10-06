import Foundation
import UIKit
@preconcurrency import MultipeerConnectivity

/// One encrypted, approved Chairman/Judge connection. Nothing from the signed-in app is shared.
@MainActor
final class WrestlingManagerNearbyTransport: NSObject {
    var onEvent: (([String: Any]) -> Void)?
    private let service = "wm-mat"
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCBrowserViewController?
    private var reconnectBrowser: MCNearbyServiceBrowser?
    private var role = ""
    private var code = ""
    private var approvedPeer: MCPeerID?
    private var authenticatedPeer: MCPeerID?
    private weak var presenter: UIViewController?
    private var approvalPending = false
    private var failures = 0
    private var lockedUntil = Date.distantPast
    private var handshakeTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var negotiatingPeer: MCPeerID?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func problem(_ text: String) -> NSError { NSError(domain: "WrestlingManager.Nearby", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func localPeer(role: String, label: String) throws -> MCPeerID {
        let key = "wm-nearby-peer-v1-" + role
        if UserDefaults.standard.string(forKey: key + "-code") == code,
           let bytes = UserDefaults.standard.data(forKey: key),
           let peer = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: bytes) { return peer }
        var title = role == "chair" ? String(label.prefix(30)) + " · Chairman" : "Wrestling Manager · Judge"
        while title.utf8.count > 63 { title.removeLast() }
        let peer = MCPeerID(displayName: title)
        let bytes = try NSKeyedArchiver.archivedData(withRootObject: peer, requiringSecureCoding: true)
        UserDefaults.standard.set(bytes, forKey: key)
        UserDefaults.standard.set(code, forKey: key + "-code")
        return peer
    }

    func start(role: String, code: String, label: String, presenting: UIViewController?) throws {
        guard ["chair", "judge"].contains(role), code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw problem("Use a six-digit pairing code.") }
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String ?? ""
        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String] ?? []
        guard !usage.isEmpty, services.contains("_wm-mat._tcp") else { throw problem("Nearby scoring needs the Local Network and Bonjour entries from the update instructions.") }
        if self.role == role, self.code == code, session != nil {
            self.presenter = presenting
            if role == "judge", authenticatedPeer == nil { approvedPeer == nil ? showBrowser() : beginReconnect() }
            if role == "chair" { advertiser?.startAdvertisingPeer() }
            return
        }
        stop()
        self.role = role; self.code = code; self.presenter = presenting
        let peer = try localPeer(role: role, label: label)
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self; self.session = session
        if role == "chair" {
            let ad = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["version": "1", "seat": "chair"], serviceType: service)
            ad.delegate = self; advertiser = ad; ad.startAdvertisingPeer()
        } else { showBrowser() }
        onEvent?(["type": "status", "connected": false])
    }
    private func approvedChairMatches(_ peer: MCPeerID) -> Bool {
        guard let approvedPeer else { return false }
        return peer == approvedPeer
    }
    private func beginReconnect() {
        guard UIApplication.shared.applicationState == .active, role == "judge", let session, approvedPeer != nil, authenticatedPeer == nil, session.connectedPeers.isEmpty else { return }
        reconnectTask?.cancel(); reconnectTask = nil
        negotiatingPeer = nil
        reconnectBrowser?.stopBrowsingForPeers()
        let browser = MCNearbyServiceBrowser(peer: session.myPeerID, serviceType: service)
        browser.delegate = self; reconnectBrowser = browser; browser.startBrowsingForPeers()
        onEvent?(["type": "status", "connected": false, "detail": "Reconnecting nearby"] )
    }
    private func showBrowser() {
        guard let session, let presenter, browser == nil, presenter.presentedViewController == nil else { return }
        let controller = MCBrowserViewController(serviceType: service, session: session)
        controller.delegate = self
        // Apple counts the local device: two total peers means exactly one remote device.
        controller.minimumNumberOfPeers = 2
        controller.maximumNumberOfPeers = 2
        browser = controller
        presenter.present(controller, animated: true)
    }
    func stop() {
        handshakeTask?.cancel(); handshakeTask = nil
        reconnectTask?.cancel(); reconnectTask = nil; negotiatingPeer = nil
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        reconnectBrowser?.stopBrowsingForPeers(); reconnectBrowser = nil
        browser?.dismiss(animated: false); browser = nil
        session?.disconnect(); session = nil
        authenticatedPeer = nil; approvedPeer = nil; approvalPending = false; role = ""; code = ""
        onEvent?(["type": "status", "connected": false])
    }
    func send(_ packet: [String: Any]) throws {
        guard let peer = authenticatedPeer, let session, session.connectedPeers.contains(peer) else { throw problem("The other device is not connected. Keep both apps open.") }
        guard let type = packet["type"] as? String,
              (role == "chair" ? ["snapshot", "reply"] : ["read", "request"]).contains(type) else { throw problem("Invalid message for this seat.") }
        try raw(["type": "app", "packet": packet], to: peer)
    }
    private func raw(_ object: [String: Any], to peer: MCPeerID) throws {
        guard let session else { throw problem("Nearby session is closed.") }
        let bytes = try JSONSerialization.data(withJSONObject: object)
        guard bytes.count <= 1024 * 1024 else { throw problem("This bout is too large to send. Export its history.") }
        try session.send(bytes, toPeers: [peer], with: .reliable)
    }
    private func authenticate(_ peer: MCPeerID) {
        approvedPeer = peer; authenticatedPeer = peer; failures = 0
        negotiatingPeer = nil
        handshakeTask?.cancel()
        try? raw(["type": "accepted"], to: peer)
        onEvent?(["type": "status", "connected": true, "detail": "Nearby connected"])
    }
    private func receive(_ bytes: Data, from peer: MCPeerID, in incoming: MCSession) {
        guard incoming === session, bytes.count <= 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let type = object["type"] as? String else { return }
        if type == "hello", role == "chair" {
            guard Date() >= lockedUntil, object["code"] as? String == code else {
                failures += 1
                if failures >= 5 { lockedUntil = Date().addingTimeInterval(60); failures = 0 }
                try? raw(["type": "rejected"], to: peer)
                session?.disconnect()
                onEvent?(["type": "error", "message": "A device entered the wrong nearby code. Check the code on both screens."])
                return
            }
            if peer == approvedPeer { authenticate(peer); return }
            guard !approvalPending, authenticatedPeer == nil, let presenter else { return }
            approvalPending = true
            let alert = UIAlertController(title: "Pair judge device?", message: "\(peer.displayName) entered this mat’s code. Allow it to use the Judge scorebook?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Deny", style: .cancel) { [weak self] _ in
                self?.approvalPending = false; self?.session?.disconnect()
            })
            alert.addAction(UIAlertAction(title: "Pair judge", style: .default) { [weak self] _ in
                guard let self else { return }; self.approvalPending = false
                if incoming === self.session, incoming.connectedPeers.contains(peer) { self.authenticate(peer) }
            })
            presenter.present(alert, animated: true)
            return
        }
        if type == "accepted", role == "judge", incoming.connectedPeers.contains(peer) {
            guard approvedPeer == nil || approvedChairMatches(peer) else {
                onEvent?(["type": "error", "message": "This is a different Chairman device. Exit and pair again using that mat’s code."])
                session?.disconnect(); return
            }
            approvedPeer = peer; authenticatedPeer = peer; handshakeTask?.cancel()
            reconnectTask?.cancel(); reconnectTask = nil; negotiatingPeer = nil
            reconnectBrowser?.stopBrowsingForPeers(); reconnectBrowser = nil
            browser?.dismiss(animated: true); browser = nil
            onEvent?(["type": "status", "connected": true, "detail": "Nearby connected"]); return
        }
        if type == "rejected", role == "judge" {
            onEvent?(["type": "error", "message": "Pairing code did not match. Choose the correct chairman’s device."])
            session?.disconnect(); return
        }
        guard type == "app", peer == authenticatedPeer, let packet = object["packet"] as? [String: Any], let kind = packet["type"] as? String,
              (role == "chair" ? ["read", "request"] : ["snapshot", "reply"]).contains(kind) else { return }
        onEvent?(["type": "packet", "packet": packet])
    }
    @objc private func background() {
        // Do not deliberately tear down an active mat link for a brief app interruption.
        // iOS may suspend transport in the background; if it actually drops, didChange(.notConnected)
        // records that state and foreground() resumes discovery when the app becomes active again.
        reconnectBrowser?.stopBrowsingForPeers(); reconnectBrowser = nil
        reconnectTask?.cancel(); reconnectTask = nil
    }
    @objc private func foreground() {
        guard UIApplication.shared.applicationState == .active else { return }
        if role == "chair" { advertiser?.startAdvertisingPeer() }
        guard role == "judge" else { return }
        if let session, let peer = authenticatedPeer, session.connectedPeers.contains(peer) {
            onEvent?(["type": "status", "connected": true, "detail": "Nearby connected"])
            return
        }
        if approvedPeer == nil { showBrowser() } else { beginReconnect() }
    }
}

extension WrestlingManagerNearbyTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self, session === self.session else { return }
            if state == .connected {
                if self.role == "judge" { try? self.raw(["type": "hello", "code": self.code], to: peerID) }
                self.handshakeTask?.cancel()
                self.handshakeTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    guard !Task.isCancelled, let self, self.authenticatedPeer == nil, self.session === session else { return }
                    session.disconnect()
                }
            } else if state == .notConnected {
                if self.negotiatingPeer == peerID { self.negotiatingPeer = nil }
                if self.authenticatedPeer == peerID { self.authenticatedPeer = nil }
                self.onEvent?(["type": "status", "connected": false, "detail": "Reconnecting nearby"])
                guard UIApplication.shared.applicationState == .active else { return }
                if self.role == "chair" { self.advertiser?.startAdvertisingPeer(); return }
                self.handshakeTask?.cancel()
                self.handshakeTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    guard !Task.isCancelled else { return }
                    self?.beginReconnect()
                }
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.receive(data, from: peerID, in: session) }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { progress.cancel() }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
extension WrestlingManagerNearbyTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, advertiser === self.advertiser, self.role == "chair", Date() >= self.lockedUntil,
                  let session = self.session, session.connectedPeers.isEmpty, self.negotiatingPeer == nil, !self.approvalPending else { invitationHandler(false, nil); return }
            self.negotiatingPeer = peerID
            invitationHandler(true, session)
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in self?.onEvent?(["type": "error", "message": "Nearby discovery could not start. Enable Local Network access in Settings."]) }
    }
}
extension WrestlingManagerNearbyTransport: MCBrowserViewControllerDelegate {
    nonisolated func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        Task { @MainActor [weak self] in browserViewController.dismiss(animated: true); self?.browser = nil }
    }
    nonisolated func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        Task { @MainActor [weak self] in browserViewController.dismiss(animated: true); self?.browser = nil; self?.onEvent?(["type": "error", "message": "Nearby search cancelled. Reopen Judge to try again."]) }
    }
    nonisolated func browserViewController(_ browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) -> Bool { info?["seat"] == "chair" && info?["version"] == "1" }
}
extension WrestlingManagerNearbyTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in
            guard let self, browser === self.reconnectBrowser, info?["seat"] == "chair", info?["version"] == "1", self.approvedChairMatches(peerID), let session = self.session, session.connectedPeers.isEmpty, self.negotiatingPeer == nil else { return }
            self.negotiatingPeer = peerID
            browser.stopBrowsingForPeers()
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
            // Retain the inviting browser and recover if an invitation expires without a callback.
            self.reconnectTask?.cancel()
            self.reconnectTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 22_000_000_000)
                guard !Task.isCancelled, let self, self.session === session, self.authenticatedPeer == nil, session.connectedPeers.isEmpty else { return }
                self.beginReconnect()
            }
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in self?.onEvent?(["type": "error", "message": "Could not reconnect nearby. Keep both devices open with Wi-Fi and Bluetooth enabled."]) }
    }
}
