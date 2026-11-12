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
    private var inviteBusy = false
    private var inviteError: String?

    let tracker = PickupTracker()

    var page: Page { session != nil || tracker.snapshot != nil ? .pickup : invitation == nil ? .entry : .invitation }
    private(set) var placeLabel: String?
    var busy: Bool { inviteBusy || tracker.busy }
    private(set) var linkUnavailable = false
    private(set) var streamConnected = false
    var error: String? {
        get { tracker.error ?? inviteError }
        set {
            tracker.error = newValue
            inviteError = newValue
        }
    }

    init() {
        let missingSessionError = PickupAPI.Failure(status: 401, code: "SESSION_MISSING", message: "세션이 없어요.")
        tracker.configure(
            PickupTracker.Backend(
                refresh: { [weak self] in
                    guard let self, let current = self.session else { throw missingSessionError }
                    let snapshot = try await self.api.snapshot(current)
                    guard snapshot.status == .active || snapshot.status == .arrived else {
                        return (snapshot, nil)
                    }
                    let vehicle = try? await self.api.vehicle(current)
                    return (snapshot, vehicle)
                },
                setReady: { [weak self] ready, sequence in
                    guard let self, let current = self.session else { throw missingSessionError }
                    return try await self.api.readiness(current, ready: ready, sequence: sequence)
                },
                propose: { [weak self] place in
                    guard let self, let current = self.session else { throw missingSessionError }
                    return try await self.api.propose(current, place: place)
                },
                withdraw: { [weak self] in
                    guard let self, let current = self.session else { throw missingSessionError }
                    return try await self.api.withdraw(current)
                },
                sendMessage: { [weak self] text in
                    guard let self, let current = self.session else { throw missingSessionError }
                    return try await self.api.message(current, text: text)
                },
                isSessionLost: { error in
                    guard let failure = error as? PickupAPI.Failure,
                          [401, 403, 404, 410].contains(failure.status),
                          failure.code != "FORBIDDEN" || failure.message == "이 픽업에 접근할 수 없습니다." else {
                        return false
                    }
                    return true
                },
                onSessionLost: { [weak self] in self?.clearGuestSession() },
                onTerminal: { [weak self] in
                    self?.session = nil
                    PickupSessionStore.clear()
                },
                formatError: { error in
                    (error as? PickupAPI.Failure)?.errorDescription ?? "연결이 원활하지 않아요. 잠시 후 다시 시도해주세요."
                },
                lostMessage: "이 픽업에 연결할 수 없어요. 새 초대 링크를 받아주세요."
            )
        )
    }

    func openLink(_ text: String) async {
        guard !busy else { return }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let invite = PickupInvitation(url: url) else {
            inviteError = "마중 초대 링크를 확인해주세요."
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
        inviteBusy = true
        defer { inviteBusy = false }
        do {
            let currentSnapshot = try await api.snapshot(current)
            tracker.applyExternal(currentSnapshot, vehicle: nil)
            if session != nil {
                inviteError = "진행 중인 픽업이 있어요. 픽업이 끝난 뒤 새 초대를 열어주세요."
                return false
            }
            return true
        } catch {
            if let failure = error as? PickupAPI.Failure,
               [401, 403, 404, 410].contains(failure.status),
               failure.code != "FORBIDDEN" || failure.message == "이 픽업에 접근할 수 없습니다." {
                clearGuestSession()
                return true
            }
            inviteError = "진행 중인 픽업을 확인하지 못했어요. 연결을 확인한 뒤 다시 열어주세요."
            return false
        }
    }

    func preview() async {
        guard let invite = invitation, !busy else { return }
        inviteBusy = true
        inviteError = nil
        defer { inviteBusy = false }
        do {
            placeLabel = try await api.preview(invite)
        } catch {
            showInviteError(error)
        }
    }

    func join() async {
        guard let invite = invitation, placeLabel != nil, !busy else { return }
        inviteBusy = true
        inviteError = nil
        defer { inviteBusy = false }
        do {
            let joined = try await api.join(invite)
            session = joined
            invitation = nil
            do {
                try PickupSessionStore.save(joined)
            } catch {
                inviteError = "연결됐어요. 앱을 닫으면 이 픽업으로 돌아오지 못할 수 있어요."
            }
            if let endpoint = PickupNotificationService.apnsEndpoint {
                Task { try? await api.registerArrivalPush(joined, endpoint: endpoint) }
            }
        } catch {
            showInviteError(error)
        }
    }

    func refresh() async {
        guard session != nil else { return }
        await tracker.refresh()
    }

    func runEventStream(for sessionId: UUID) async {
        var delaySeconds = 1
        while !Task.isCancelled && session?.id == sessionId {
            guard let currentSession = session, currentSession.id == sessionId else { break }
            await api.streamEvents(
                session: currentSession,
                onState: { [weak self] connected in
                    self?.streamConnected = connected
                    if connected { delaySeconds = 1 }
                },
                onRefresh: { [weak self] in
                    await self?.refresh()
                }
            )
            streamConnected = false
            if Task.isCancelled || session?.id != sessionId { break }
            try? await Task.sleep(for: .seconds(delaySeconds))
            delaySeconds = min(delaySeconds * 2, 15)
        }
        streamConnected = false
    }

    func reset() {
        guard session == nil, !busy else { return }
        invitation = nil
        placeLabel = nil
        inviteError = nil
        linkUnavailable = false
        streamConnected = false
        tracker.resetState()
    }

    func leaveWaiting() async {
        guard let status = tracker.snapshot?.status, status == .inviting || status == .waiting else { return }
        if let active = session {
            try? await api.leaveWaiting(active)
        }
        clearGuestSession()
        inviteError = nil
        tracker.resetState()
    }

    private func clearGuestSession() {
        session = nil
        PickupSessionStore.clear()
        invitation = nil
        placeLabel = nil
        linkUnavailable = false
        streamConnected = false
    }

    private func showInviteError(_ error: Error) {
        if let failure = error as? PickupAPI.Failure, [403, 404, 409, 410].contains(failure.status) {
            linkUnavailable = true
            inviteError = "이 초대 링크는 더 이상 사용할 수 없어요. 운전자에게 새 링크를 받아주세요."
        } else {
            inviteError = (error as? PickupAPI.Failure)?.errorDescription ?? "연결이 원활하지 않아요. 잠시 후 다시 시도해주세요."
        }
    }
}
