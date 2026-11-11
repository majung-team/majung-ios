import SwiftUI
import UserNotifications

@main
struct MajungApp: App {
    private let notificationDelegate = MajungNotificationDelegate()

    init() {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITestResetSessions") {
            AccountSessionStore.clear()
            PickupSessionStore.clear()
            if args.contains("-UITestShowOnboarding") {
                OnboardingStore.reset()
            } else {
                OnboardingStore.markCompleted()
            }
        } else if args.contains("-UITestShowOnboarding") {
            OnboardingStore.reset()
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
