import SwiftUI
import UserNotifications

@main
struct MajungApp: App {
    private let notificationDelegate = MajungNotificationDelegate()

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-UITestResetSessions") {
            AccountSessionStore.clear()
            PickupSessionStore.clear()
        }
        #endif
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private final class MajungNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
