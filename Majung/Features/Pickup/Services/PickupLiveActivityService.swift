import ActivityKit
import Foundation

@MainActor
final class PickupLiveActivityService {
    static let shared = PickupLiveActivityService()

    private(set) var currentState: PickupLiveActivityAttributes.ContentState?
    private(set) var currentPickupKey: String?
    private var pendingTask: Task<Void, Never>?

    private let isEnabled: () -> Bool
    private let upsertHandler: (String, PickupLiveActivityAttributes.ContentState) async -> Void
    private let endAllHandler: () async -> Void

    init(
        isEnabled: @escaping () -> Bool = {
            ActivityAuthorizationInfo().areActivitiesEnabled
        },
        upsertHandler: @escaping (String, PickupLiveActivityAttributes.ContentState) async -> Void = { pickupKey, state in
            await PickupLiveActivityService.performSystemUpsert(pickupKey: pickupKey, state: state)
        },
        endAllHandler: @escaping () async -> Void = {
            await PickupLiveActivityService.performSystemEndAll()
        }
    ) {
        self.isEnabled = isEnabled
        self.upsertHandler = upsertHandler
        self.endAllHandler = endAllHandler
    }

    static func makeState(
        snapshot: PickupSnapshot,
        vehicle: PickupVehicle?,
        vehicleUpdatedAt: Date?,
        previousState: PickupLiveActivityAttributes.ContentState?,
        now: Date = Date()
    ) -> PickupLiveActivityAttributes.ContentState? {
        let phase: PickupLiveActivityAttributes.ContentState.Phase
        switch snapshot.status {
        case .active:
            phase = .approaching
        case .arrived:
            phase = .arrived
        case .inviting, .waiting, .inviteExpired, .completed, .cancelled, .expired:
            return nil
        }

        let rawPlace = snapshot.place?.label.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeLabel = !rawPlace.isEmpty ? rawPlace : (previousState?.placeLabel ?? "만날 장소")

        let rawVehicle = snapshot.vehicleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let vehicleName = !rawVehicle.isEmpty ? rawVehicle : (previousState?.vehicleName ?? "마중 차량")

        let passengerReady = snapshot.participant?.ready ?? false

        if phase == .arrived {
            return PickupLiveActivityAttributes.ContentState(
                phase: .arrived,
                placeLabel: placeLabel,
                vehicleName: vehicleName,
                placeVersion: snapshot.placeVersion,
                durationSeconds: 0,
                countdownStartDate: nil,
                estimatedArrivalDate: nil,
                vehicleFreshUntil: now.addingTimeInterval(30),
                passengerReady: passengerReady,
                updatedAt: now
            )
        }

        var durationSeconds: Int?
        var countdownStartDate: Date?
        var estimatedArrivalDate: Date?
        var vehicleFreshUntil: Date?

        if let vehicle,
           vehicle.freshness == "FRESH",
           vehicle.placeVersion == snapshot.placeVersion,
           vehicle.validForMillis > 0,
           (vehicleUpdatedAt ?? now).addingTimeInterval(Double(vehicle.validForMillis) / 1000) > now {
            vehicleFreshUntil = (vehicleUpdatedAt ?? now).addingTimeInterval(Double(vehicle.validForMillis) / 1000)
        }

        if let vehicle, vehicleFreshUntil != nil,
           let seconds = vehicle.durationSeconds,
           seconds >= 0 {
            let start = vehicleUpdatedAt ?? now
            let arrival = start.addingTimeInterval(TimeInterval(max(1, seconds)))
            if arrival > now {
                durationSeconds = seconds
                countdownStartDate = min(start, now)
                estimatedArrivalDate = arrival
            } else {
                durationSeconds = 0
            }
        } else if vehicle == nil, let previousState,
                  previousState.phase == .approaching,
                  previousState.placeVersion == snapshot.placeVersion,
                  let freshUntil = previousState.vehicleFreshUntil,
                  freshUntil > now,
                  let prevStart = previousState.countdownStartDate,
                  let prevArrival = previousState.estimatedArrivalDate,
                  prevArrival > now {
            durationSeconds = max(1, Int(prevArrival.timeIntervalSince(now).rounded()))
            countdownStartDate = prevStart
            estimatedArrivalDate = prevArrival
            vehicleFreshUntil = freshUntil
        }

        return PickupLiveActivityAttributes.ContentState(
            phase: .approaching,
            placeLabel: placeLabel,
            vehicleName: vehicleName,
            placeVersion: snapshot.placeVersion,
            durationSeconds: durationSeconds,
            countdownStartDate: countdownStartDate,
            estimatedArrivalDate: estimatedArrivalDate,
            vehicleFreshUntil: vehicleFreshUntil,
            passengerReady: passengerReady,
            updatedAt: now
        )
    }

    func sync(
        snapshot: PickupSnapshot?,
        vehicle: PickupVehicle?,
        vehicleUpdatedAt: Date?,
        now: Date = Date()
    ) {
        guard let snapshot else {
            endAllImmediately()
            return
        }
        let pickupKey = Self.pickupKey(for: snapshot)
        let previousForSamePickup = currentPickupKey == pickupKey ? currentState : nil
        guard let nextState = Self.makeState(
            snapshot: snapshot,
            vehicle: vehicle,
            vehicleUpdatedAt: vehicleUpdatedAt,
            previousState: previousForSamePickup,
            now: now
        ) else {
            end(pickupKey: pickupKey)
            return
        }

        guard isEnabled() else {
            currentState = nil
            currentPickupKey = nil
            return
        }

        if currentPickupKey == pickupKey,
           let existing = currentState,
           Self.isEquivalentForDisplay(existing, nextState) {
            return
        }

        currentPickupKey = pickupKey
        currentState = nextState
        enqueue { [upsertHandler] in
            await upsertHandler(pickupKey, nextState)
        }
    }

    func end(pickupKey: String?) {
        if let pickupKey, let activeKey = currentPickupKey, activeKey != pickupKey {
            return
        }
        endAllImmediately()
    }

    func endAllImmediately() {
        currentState = nil
        currentPickupKey = nil
        enqueue { [endAllHandler] in
            await endAllHandler()
        }
    }

    static func pickupKey(for snapshot: PickupSnapshot) -> String {
        snapshot.pickupId?.uuidString.lowercased() ?? snapshot.place?.label ?? "active"
    }

    private func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        let previous = pendingTask
        pendingTask = Task {
            _ = await previous?.value
            await operation()
        }
    }

    private static func isEquivalentForDisplay(
        _ lhs: PickupLiveActivityAttributes.ContentState,
        _ rhs: PickupLiveActivityAttributes.ContentState
    ) -> Bool {
        guard lhs.phase == rhs.phase,
              lhs.placeLabel == rhs.placeLabel,
              lhs.vehicleName == rhs.vehicleName,
              lhs.placeVersion == rhs.placeVersion,
              lhs.passengerReady == rhs.passengerReady else {
            return false
        }
        switch (lhs.vehicleFreshUntil, rhs.vehicleFreshUntil) {
        case let (left?, right?):
            if abs(left.timeIntervalSince(right)) >= 2 { return false }
        case (nil, nil):
            break
        default:
            return false
        }
        switch (lhs.estimatedArrivalDate, rhs.estimatedArrivalDate) {
        case (nil, nil):
            return lhs.durationSeconds == rhs.durationSeconds
        case let (lDate?, rDate?):
            return abs(lDate.timeIntervalSince(rDate)) < 2
        default:
            return false
        }
    }

    private static func performSystemUpsert(
        pickupKey: String,
        state: PickupLiveActivityAttributes.ContentState
    ) async {
        // Missing vehicle data is shown as needing refresh by the widget itself.
        // Starting with a past staleDate can suppress the initial Dynamic Island view.
        let content = ActivityContent(state: state, staleDate: state.vehicleFreshUntil)

        var matchedExisting = false
        for activity in Activity<PickupLiveActivityAttributes>.activities {
            if activity.attributes.pickupId == pickupKey,
               activity.activityState == .active || activity.activityState == .stale {
                if !matchedExisting {
                    matchedExisting = true
                    await activity.update(content)
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        if !matchedExisting {
            let attributes = PickupLiveActivityAttributes(pickupId: pickupKey)
            _ = try? Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        }
    }

    private static func performSystemEndAll() async {
        for activity in Activity<PickupLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
