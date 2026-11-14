import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class PickupNotificationService {
    private enum StorageKey {
        static let enabled = "majung.arrivalAlertEnabled"
    }

    static private(set) var apnsDeviceTokenHex: String?
    static var apnsEndpoint: String? {
        guard let hex = apnsDeviceTokenHex, (64...256).contains(hex.count) else { return nil }
        return "apns://\(hex)"
    }

    static func updateApnsDeviceToken(_ deviceToken: Data) {
        apnsDeviceTokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    private(set) var enabled: Bool
    private(set) var permissionDenied = false
    private(set) var statusNote: String?
    private var sentEventKeys: Set<String> = []
    private var trackedIdentifiers: Set<String> = []
    private var deliveryTasks: [String: Task<Void, Never>] = [:]
    private let defaults: UserDefaults
    private let addNotification: (UNNotificationRequest) async -> Void
    private let removeNotifications: ([String]) -> Void

    init(
        defaults: UserDefaults = .standard,
        addNotification: @escaping (UNNotificationRequest) async -> Void = {
            try? await UNUserNotificationCenter.current().add($0)
        },
        removeNotifications: @escaping ([String]) -> Void = {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: $0)
            center.removeDeliveredNotifications(withIdentifiers: $0)
        }
    ) {
        self.defaults = defaults
        self.addNotification = addNotification
        self.removeNotifications = removeNotifications
        enabled = defaults.bool(forKey: StorageKey.enabled)
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            permissionDenied = true
            enabled = false
            defaults.set(false, forKey: StorageKey.enabled)
            clearNotifications(identifiers: Array(trackedIdentifiers))
        case .authorized, .provisional, .ephemeral:
            permissionDenied = false
        case .notDetermined:
            permissionDenied = false
        @unknown default:
            break
        }
    }

    func setEnabled(_ wantOn: Bool) async {
        statusNote = nil
        if !wantOn {
            enabled = false
            defaults.set(false, forKey: StorageKey.enabled)
            clearNotifications(identifiers: Array(trackedIdentifiers))
            return
        }

        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            permissionDenied = false
            enabled = true
            defaults.set(true, forKey: StorageKey.enabled)
            UIApplication.shared.registerForRemoteNotifications()
            statusNote = Self.apnsEndpoint != nil
                ? "도착 약 3분 전과 차량 도착 시 푸시 및 로컬 알림으로 알려드려요."
                : "도착 약 3분 전과 차량 도착 시 앱 실행 중 로컬 알림으로 알려드려요."
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if granted {
                    permissionDenied = false
                    enabled = true
                    defaults.set(true, forKey: StorageKey.enabled)
                    UIApplication.shared.registerForRemoteNotifications()
                    statusNote = Self.apnsEndpoint != nil
                        ? "도착 약 3분 전과 차량 도착 시 푸시 및 로컬 알림으로 알려드려요."
                        : "도착 약 3분 전과 차량 도착 시 앱 실행 중 로컬 알림으로 알려드려요."
                } else {
                    markDenied()
                }
            } catch {
                markDenied()
            }
        case .denied:
            markDenied()
        @unknown default:
            markDenied()
        }
    }

    func evaluate(snapshot: PickupSnapshot?, vehicle: PickupVehicle?) {
        guard let snapshot else { return }
        let pickupKey = snapshot.pickupId?.uuidString.lowercased() ?? snapshot.place?.label ?? "active"
        let approachingIdentifier = "majung.approaching-\(pickupKey)"
        let arrivedIdentifier = "majung.arrived-\(pickupKey)"
        trackedIdentifiers.formUnion([approachingIdentifier, arrivedIdentifier])
        if snapshot.status.ended {
            clearNotifications(identifiers: Array(trackedIdentifiers))
            return
        }
        guard enabled else { return }
        let placeLabel = snapshot.place?.label ?? "만날 장소"
        let vehicleLabel: String = if let name = snapshot.vehicleName?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !name.isEmpty {
            name
        } else {
            "마중 차량"
        }

        switch snapshot.status {
        case .active:
            if let seconds = vehicle?.durationSeconds, seconds <= 180 {
                let key = "approaching-\(pickupKey)"
                guard !sentEventKeys.contains(key) else { return }
                sentEventKeys.insert(key)
                let etaLabel = MajungFormatting.minutesText(seconds: seconds)
                deliver(
                    id: key,
                    title: "곧 \(vehicleLabel)이 도착해요",
                    body: "\(etaLabel) 후 '\(placeLabel)' 도착 예정이에요."
                )
            }
        case .arrived:
            clearNotifications(identifiers: [approachingIdentifier])
            let key = "arrived-\(pickupKey)"
            guard !sentEventKeys.contains(key) else { return }
            sentEventKeys.insert(key)
            deliver(
                id: key,
                title: "마중 차량이 도착했어요",
                body: "\(vehicleLabel)이 '\(placeLabel)'에 정차했어요."
            )
        default:
            break
        }
    }

    private func markDenied() {
        permissionDenied = true
        enabled = false
        defaults.set(false, forKey: StorageKey.enabled)
        clearNotifications(identifiers: Array(trackedIdentifiers))
        statusNote = "알림 권한이 꺼져 있어요. 기기 설정에서 마중 알림을 허용해주세요."
    }

    private func deliver(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let identifier = "majung.\(id)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        deliveryTasks[identifier] = Task {
            await addNotification(request)
            // Registration can finish after a terminal event has already removed the alert.
            if Task.isCancelled { removeNotifications([identifier]) }
            deliveryTasks.removeValue(forKey: identifier)
        }
    }

    private func clearNotifications(identifiers: [String]) {
        for identifier in identifiers {
            deliveryTasks.removeValue(forKey: identifier)?.cancel()
        }
        trackedIdentifiers.subtract(identifiers)
        removeNotifications(identifiers)
    }

    #if DEBUG
    func sendDebugSampleNotification() async -> String {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral else {
            return "기기 설정에서 마중 알림 권한을 허용한 뒤 다시 눌러주세요."
        }
        let content = UNMutableNotificationContent()
        content.title = "마중 차량이 도착했어요"
        content.body = "최수빈 카니발이 '광교중앙역 1번 출구'에 정차했어요. (테스트 알림)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: "majung.debug.sample.\(UUID().uuidString)", content: content, trigger: trigger)
        try? await center.add(req)
        return "1초 뒤 테스트 알림 배너가 표시됩니다."
    }
    #endif
}
