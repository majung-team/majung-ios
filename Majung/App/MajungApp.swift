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
            RecentPlaceStore().clear()
        }
        if args.contains("-UITestResetParking") {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("majung.parking.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
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
        let identifier = notification.request.identifier
        return await MainActor.run {
            PickupNotificationService.shared.foregroundPresentationOptions(for: identifier)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let identifier = response.notification.request.identifier
        await MainActor.run {
            PickupNotificationService.shared.handleNotificationTap(userInfo: userInfo, identifier: identifier)
        }
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
