import SwiftUI

@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(WrestlingManagerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    NotificationCenter.default.post(
                        name: .wrestlingManagerAuthCallback,
                        object: url
                    )
                }
        }
    }
}

