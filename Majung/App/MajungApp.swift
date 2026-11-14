import SwiftUI
import UIKit
import UserNotifications

@main
struct MajungApp: App {
    @UIApplicationDelegateAdaptor(MajungAppDelegate.self) private var appDelegate
    private let notificationDelegate = MajungNotificationDelegate()

    init() {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITestResetSessions") {
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
        // The foreground pickup screen already shows status; a system banner can outlive it.
        [.sound]
    }
}

final class MajungAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PickupNotificationService.updateApnsDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Ignore safely when APNs entitlement is absent on Personal Team / Simulator builds.
    }
}
