import Foundation
import Observation

@MainActor
@Observable
final class PickupViewModel {
    enum Page: Equatable {
        case entry, invitation, pickup
    }

    private let api = PickupAPI()
    private var invitation: PickupInvitation?
    private(set) var session = PickupSessionStore.load()
    private var revision = 0
    private var refreshing = false
    private var vehicleExpiresAt: ContinuousClock.Instant?

    var page: Page { session != nil || snapshot != nil ? .pickup : invitation == nil ? .entry : .invitation }
    private(set) var placeLabel: String?
    private(set) var snapshot: PickupSnapshot?
    private(set) var vehicle: PickupVehicle?
    private(set) var busy = false
    private(set) var linkUnavailable = false
    private(set) var connectionProblem = false
    private(set) var messageSent = false
    var messageDraft = "" {
        didSet { if messageDraft != oldValue { messageSent = false } }
    }
    var error: String?

    func openLink(_ text: String) async {
        guard !busy else { return }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let invite = PickupInvitation(url: url) else {
            error = "마중 초대 링크를 확인해주세요."
            return
        }
        if let current = session {
            if current.id == invite.id {
                await refresh()
                return
            }
            guard await canOpenAnotherInvitation(current) else { return }
        }
        reset()
        invitation = invite
        await preview()
    }

    private func canOpenAnotherInvitation(_ current: PickupSession) async -> Bool {
        busy = true
        revision += 1
        defer { busy = false }
        do {
            apply(try await api.snapshot(current))
            if session != nil {
                error = "진행 중인 픽업이 있어요. 픽업이 끝난 뒤 새 초대를 열어주세요."
                return false
            }
            return true
        } catch {
            if handleLostSession(error) { return true }
            self.error = "진행 중인 픽업을 확인하지 못했어요. 연결을 확인한 뒤 다시 열어주세요."
            return false
        }
    }

    func preview() async {
        guard let invite = invitation, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            placeLabel = try await api.preview(invite)
        } catch {
            showInviteError(error)
        }
    }

    func join() async {
        guard let invite = invitation, placeLabel != nil, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let joined = try await api.join(invite)
            // Save as soon as the single-use invitation is consumed.
            session = joined
            invitation = nil
            do {
                try PickupSessionStore.save(joined)
            } catch {
                self.error = "연결됐어요. 앱을 닫으면 이 픽업으로 돌아오지 못할 수 있어요."
            }
        } catch {
            showInviteError(error)
        }
    }

    func refresh() async {
        guard let session, !refreshing, !busy else { return }
        refreshing = true
        let revisionAtStart = revision
        defer { refreshing = false }
        do {
            let current = try await api.snapshot(session)
            guard !Task.isCancelled, self.session == session, revision == revisionAtStart else { return }
            apply(current)
            connectionProblem = false
            guard current.status == .active || current.status == .arrived else { return }

            let started = ContinuousClock.now
            let position = try? await api.vehicle(session)
            guard !Task.isCancelled, self.session == session, revision == revisionAtStart else { return }
            if let position, position.freshness == "FRESH", position.placeVersion == current.placeVersion,
               position.validForMillis > 0 {
                vehicle = position
                vehicleExpiresAt = started.advanced(by: .milliseconds(position.validForMillis))
            } else {
                vehicle = nil
                vehicleExpiresAt = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.session == session, revision == revisionAtStart else { return }
            if !handleLostSession(error) { connectionProblem = true }
        }
    }

    func currentVehicle(at now: ContinuousClock.Instant = .now) -> PickupVehicle? {
        guard let vehicleExpiresAt, now < vehicleExpiresAt else { return nil }
        return vehicle
    }

    func setReady(_ ready: Bool) async {
        guard let participant = snapshot?.participant, ready != participant.ready else { return }
        _ = await update { session in
            try await self.api.readiness(session, ready: ready, sequence: participant.readinessSequence + 1)
        }
    }

    func suggest(_ place: PickupPlace) async -> Bool {
        await update { try await self.api.propose($0, place: place) }
    }

    func withdrawProposal() async {
        _ = await update { try await self.api.withdraw($0) }
    }

    func sendMessage() async {
        let text = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 50 else { return }
        if await update({ try await self.api.message($0, text: text) }) {
            if messageDraft.trimmingCharacters(in: .whitespacesAndNewlines) == text {
                messageDraft = ""
                messageSent = true
            }
        }
    }

    func reset() {
        guard session == nil, !busy else { return }
        clearPage()
    }

    private func clearPage() {
        invitation = nil
        placeLabel = nil
        snapshot = nil
        vehicle = nil
        vehicleExpiresAt = nil
        error = nil
        linkUnavailable = false
        connectionProblem = false
        messageDraft = ""
        messageSent = false
    }

    private func update(_ operation: (PickupSession) async throws -> PickupSnapshot) async -> Bool {
        guard let session, !busy else { return false }
        revision += 1
        busy = true
        error = nil
        defer { busy = false }
        do {
            apply(try await operation(session))
            connectionProblem = false
            return true
        } catch {
            if !handleLostSession(error) { self.error = displayError(error) }
            return false
        }
    }

    private func apply(_ current: PickupSnapshot) {
        if snapshot?.placeVersion != current.placeVersion {
            vehicle = nil
            vehicleExpiresAt = nil
        }
        snapshot = current
        if current.status.ended {
            session = nil
            vehicle = nil
            vehicleExpiresAt = nil
            PickupSessionStore.clear()
        }
    }

    private func handleLostSession(_ error: Error) -> Bool {
        guard let failure = error as? PickupAPI.Failure,
              [401, 403, 404, 410].contains(failure.status),
              failure.code != "FORBIDDEN" || failure.message == "이 픽업에 접근할 수 없습니다." else { return false }
        session = nil
        PickupSessionStore.clear()
        clearPage()
        self.error = "이 픽업에 연결할 수 없어요. 새 초대 링크를 받아주세요."
        return true
    }

    private func showInviteError(_ error: Error) {
        if let failure = error as? PickupAPI.Failure, [403, 404, 409, 410].contains(failure.status) {
            linkUnavailable = true
            self.error = "이 초대 링크는 더 이상 사용할 수 없어요. 운전자에게 새 링크를 받아주세요."
        } else {
            self.error = displayError(error)
        }
    }

    private func displayError(_ error: Error) -> String {
        (error as? PickupAPI.Failure)?.errorDescription ?? "연결이 원활하지 않아요. 잠시 후 다시 시도해주세요."
    }
}
