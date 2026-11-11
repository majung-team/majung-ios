import Foundation
import Observation

@MainActor
@Observable
final class PickupTracker {
    struct Backend {
        let refresh: () async throws -> (PickupSnapshot, PickupVehicle?)
        let setReady: (_ ready: Bool, _ sequence: Int) async throws -> PickupSnapshot
        let propose: (_ place: PickupPlace) async throws -> PickupSnapshot
        let withdraw: () async throws -> PickupSnapshot
        let sendMessage: (_ text: String) async throws -> PickupSnapshot
        let isSessionLost: (_ error: Error) -> Bool
        let onSessionLost: () -> Void
        let onTerminal: () -> Void
        let formatError: (_ error: Error) -> String
        let lostMessage: String
    }

    private var backend: Backend?
    private var revision = 0
    private var refreshing = false
    private(set) var vehicle: PickupVehicle?
    private(set) var vehicleExpiresAt: ContinuousClock.Instant?
    private(set) var vehicleUpdatedAt: Date?

    private(set) var snapshot: PickupSnapshot?
    private(set) var lastPlace: PickupPlace?
    private(set) var lastVehicleName: String?
    private(set) var busy = false
    private(set) var connectionProblem = false
    private(set) var messageSent = false
    var messageDraft = "" {
        didSet { if messageDraft != oldValue { messageSent = false } }
    }
    var error: String?

    func configure(_ backend: Backend) {
        self.backend = backend
    }

    func refresh() async {
        guard let backend, !refreshing, !busy else { return }
        refreshing = true
        let revisionAtStart = revision
        defer { refreshing = false }

        do {
            let started = ContinuousClock.now
            let (current, position) = try await backend.refresh()
            guard !Task.isCancelled, revision == revisionAtStart else { return }
            apply(current)
            connectionProblem = false
            guard current.status == .active || current.status == .arrived else { return }
            applyVehicle(position, for: current, startedAt: started)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, revision == revisionAtStart else { return }
            if handleLostSession(error) { return }
            clearVehicle()
            connectionProblem = true
        }
    }

    func applyExternal(_ current: PickupSnapshot, vehicle position: PickupVehicle?, startedAt: ContinuousClock.Instant = .now) {
        apply(current)
        connectionProblem = false
        if current.status == .active || current.status == .arrived {
            applyVehicle(position, for: current, startedAt: startedAt)
        }
    }

    func clearVehicle() {
        vehicle = nil
        vehicleExpiresAt = nil
        vehicleUpdatedAt = nil
    }

    func currentVehicle(at now: ContinuousClock.Instant = .now) -> PickupVehicle? {
        guard let vehicleExpiresAt, now < vehicleExpiresAt else { return nil }
        return vehicle
    }

    func setReady(_ ready: Bool) async {
        guard let participant = snapshot?.participant, ready != participant.ready else { return }
        await submitReadiness(ready, sequence: participant.readinessSequence + 1)
    }

    func resendReady() async {
        guard let participant = snapshot?.participant, participant.ready else { return }
        await submitReadiness(true, sequence: participant.readinessSequence + 1)
    }

    private func submitReadiness(_ ready: Bool, sequence: Int) async {
        guard let backend else { return }
        _ = await update { try await backend.setReady(ready, sequence) }
    }

    func suggest(_ place: PickupPlace) async -> Bool {
        guard let backend else { return false }
        return await update { try await backend.propose(place) }
    }

    func withdrawProposal() async {
        guard let backend else { return }
        _ = await update { try await backend.withdraw() }
    }

    func sendMessage() async {
        guard let backend else { return }
        let text = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 50 else { return }
        if await update({ try await backend.sendMessage(text) }) {
            if messageDraft.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                messageDraft = ""
                messageSent = true
            }
        }
    }

    func resetState() {
        revision += 1
        snapshot = nil
        lastPlace = nil
        lastVehicleName = nil
        clearVehicle()
        error = nil
        connectionProblem = false
        messageDraft = ""
        messageSent = false
    }

    private func applyVehicle(_ position: PickupVehicle?, for current: PickupSnapshot, startedAt: ContinuousClock.Instant) {
        if let position, position.freshness == "FRESH", position.placeVersion == current.placeVersion,
           position.validForMillis > 0 {
            vehicle = position
            vehicleExpiresAt = startedAt.advanced(by: .milliseconds(position.validForMillis))
            vehicleUpdatedAt = Date()
        } else {
            clearVehicle()
        }
    }

    private func update(_ operation: () async throws -> PickupSnapshot) async -> Bool {
        guard let backend, !busy else { return false }
        revision += 1
        busy = true
        error = nil
        defer { busy = false }
        do {
            apply(try await operation())
            connectionProblem = false
            return true
        } catch {
            if !handleLostSession(error) {
                self.error = backend.formatError(error)
            }
            return false
        }
    }

    private func apply(_ current: PickupSnapshot) {
        if snapshot?.placeVersion != current.placeVersion {
            clearVehicle()
        }
        snapshot = current
        if let place = current.place {
            lastPlace = place
        }
        if let name = current.vehicleName, !name.isEmpty {
            lastVehicleName = name
        }
        if current.status.ended {
            clearVehicle()
            backend?.onTerminal()
        }
    }

    private func handleLostSession(_ error: Error) -> Bool {
        guard let backend, backend.isSessionLost(error) else { return false }
        resetState()
        backend.onSessionLost()
        self.error = backend.lostMessage
        return true
    }
}
