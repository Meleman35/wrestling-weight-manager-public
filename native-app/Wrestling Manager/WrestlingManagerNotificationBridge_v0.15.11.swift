import UIKit
import UserNotifications
import WebKit

@MainActor
final class WrestlingManagerNotificationBridge: NSObject, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    static let shared = WrestlingManagerNotificationBridge()

    private weak var webView: WKWebView?
    private var pageReady = false
    private var deviceToken: String?
    private var pendingEvents: [[String: Any]] = []
    private var pendingOpenedKeys = Set<String>()

    private override init() {
        super.init()
    }

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        pageReady = false
    }

    func detach(from webView: WKWebView) {
        if self.webView === webView {
            self.webView = nil
            pageReady = false
        }
    }

    func webPageDidFinishLoading() {
        pageReady = true
        sendStatus()
        flushPendingEvents()
    }

    func registeredForRemoteNotifications(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        sendStatus()
    }

    func failedToRegisterForRemoteNotifications(_ error: Error) {
        emit([
            "type": "registrationError",
            "message": error.localizedDescription
        ])
    }

    func receivedLaunchNotification(_ userInfo: [AnyHashable: Any]) {
        queueOpenedNotification(userInfo)
    }

    private func queueOpenedNotification(_ userInfo: [AnyHashable: Any]) {
        var dictionary: [String: Any] = [:]
        for (key, value) in userInfo {
            if let stringKey = key as? String {
                dictionary[stringKey] = value
            }
        }
        let wm = dictionary["wm"] as? [String: Any]
        let notificationId = (wm?["notification_id"] as? String) ?? (dictionary["notification_id"] as? String) ?? ""
        let threadId = (wm?["thread_id"] as? String) ?? (dictionary["thread_id"] as? String) ?? ""
        let dedupeKey = !notificationId.isEmpty ? "notification:\(notificationId)" : "thread:\(threadId)"
        if !dedupeKey.hasSuffix(":"), pendingOpenedKeys.contains(dedupeKey) { return }
        if !dedupeKey.hasSuffix(":") { pendingOpenedKeys.insert(dedupeKey) }
        emit(["type": "opened", "payload": dictionary])
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let command = body["command"] as? String else { return }

        switch command {
        case "status":
            sendStatus()
        case "requestPermission":
            requestPermission()
        case "register":
            UIApplication.shared.registerForRemoteNotifications()
        case "setBadge":
            let count = max(0, body["count"] as? Int ?? 0)
            setBadge(count)
        case "openSettings":
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        default:
            emit(["type": "error", "message": "Unknown notification command."])
        }
    }

    private func requestPermission() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                sendStatus()
            } catch {
                emit(["type": "permissionError", "message": error.localizedDescription])
            }
        }
    }

    private func setBadge(_ count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }

    private func sendStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let authorization: String
            switch settings.authorizationStatus {
            case .authorized: authorization = "authorized"
            case .denied: authorization = "denied"
            case .provisional: authorization = "provisional"
            case .ephemeral: authorization = "ephemeral"
            case .notDetermined: authorization = "notDetermined"
            @unknown default: authorization = "unknown"
            }

            if (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional),
               deviceToken == nil {
                UIApplication.shared.registerForRemoteNotifications()
            }

            emit([
                "type": "status",
                "authorizationStatus": authorization,
                "alertsEnabled": settings.alertSetting == .enabled,
                "soundsEnabled": settings.soundSetting == .enabled,
                "badgesEnabled": settings.badgeSetting == .enabled,
                "token": deviceToken.map { $0 as Any } ?? NSNull(),
                "environment": Self.apnsEnvironment,
                "bundleId": Bundle.main.bundleIdentifier ?? "",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            ])
        }
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private func emit(_ payload: [String: Any]) {
        guard pageReady, let webView else {
            pendingEvents.append(payload)
            return
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.wrestlingManagerNotificationResponse?.(\(json));")
    }

    private func flushPendingEvents() {
        let events = pendingEvents
        pendingEvents.removeAll()
        events.forEach(emit)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            self.emit([
                "type": "received",
                "payload": notification.request.content.userInfo
            ])
        }
        completionHandler([.banner, .list, .badge, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            self.queueOpenedNotification(response.notification.request.content.userInfo)
        }
        completionHandler()
    }
}

@MainActor
final class WrestlingManagerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let bridge = WrestlingManagerNotificationBridge.shared
        bridge.install()
        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            bridge.receivedLaunchNotification(notification)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            WrestlingManagerNotificationBridge.shared.registeredForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            WrestlingManagerNotificationBridge.shared.failedToRegisterForRemoteNotifications(error)
        }
    }
}
