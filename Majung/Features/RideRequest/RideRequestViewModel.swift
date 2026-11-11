import Foundation
import Observation

@MainActor
@Observable
final class RideRequestViewModel {
    private let account: AccountViewModel
    private let api = RideRequestAPI()

    private(set) var requests: [RideRequestItem] = []
    private var requestFetchedAt: [UUID: ContinuousClock.Instant] = [:]
    private var trackedRequestId: UUID?
    private(set) var activeStreamConnected = false
    let tracking = PickupTracker()

    private(set) var busy = false
    private(set) var loading = false
    var error: String?
    var notice: String?

    var sortedRequests: [RideRequestItem] {
        requests.sorted { lhs, rhs in
            if lhs.status.sortRank != rhs.status.sortRank {
                return lhs.status.sortRank < rhs.status.sortRank
            }
            return lhs.expiresAt < rhs.expiresAt
        }
    }

    var activeRequest: RideRequestItem? {
        requests.first { $0.status == .active }
    }

    var invitedRequests: [RideRequestItem] {
        sortedRequests.filter { $0.status == .invited }
    }

    var waitingRequests: [RideRequestItem] {
        sortedRequests.filter { $0.status.isWaiting }
    }

    var pendingOrInvitedRequests: [RideRequestItem] {
        sortedRequests.filter { $0.status == .invited || $0.status == .pending }
    }

    var queuedRequests: [RideRequestItem] {
        sortedRequests.filter { $0.status == .queued }
    }

    var terminalRequests: [RideRequestItem] {
        sortedRequests.filter { !$0.status.isOpen }
    }

    var invitedCount: Int {
        invitedRequests.count
    }

    init(account: AccountViewModel) {
        self.account = account
        let missingError = AccountAPI.Failure(status: 404, code: "RIDE_REQUEST_NOT_FOUND", message: "진행 중인 픽업이 없어요.")
        tracking.configure(
            PickupTracker.Backend(
                refresh: { [weak self] in
                    guard let self, let id = self.activeRequest?.id else { throw missingError }
                    do {
                        let response = try await self.account.performAuthorized { cookie in
                            try await self.api.tracking(id: id, cookie: cookie)
                        }
                        return (response.pickup, response.vehicle)
                    } catch let failure as AccountAPI.Failure where [403, 404, 410].contains(failure.status) {
                        if let items = try? await self.account.performAuthorized({ cookie in
                            try await self.api.list(cookie: cookie)
                        }), let ended = items.first(where: { $0.id == id })?.terminalPickupSnapshot(
                            lastPlace: self.tracking.lastPlace,
                            lastVehicleName: self.tracking.lastVehicleName
                        ) {
                            return (ended, nil)
                        }
                        throw failure
                    }
                },
                setReady: { [weak self] ready, sequence in
                    guard let self, let id = self.activeRequest?.id else { throw missingError }
                    return try await self.account.performAuthorizedMutation { cookie, csrfToken in
                        try await self.api.updateReadiness(id: id, ready: ready, sequence: sequence, cookie: cookie, csrfToken: csrfToken)
                    }
                },
                propose: { [weak self] place in
                    guard let self, let id = self.activeRequest?.id else { throw missingError }
                    return try await self.account.performAuthorizedMutation { cookie, csrfToken in
                        try await self.api.proposePlace(id: id, place: place, cookie: cookie, csrfToken: csrfToken)
                    }
                },
                withdraw: { [weak self] in
                    guard let self, let id = self.activeRequest?.id else { throw missingError }
                    return try await self.account.performAuthorizedMutation { cookie, csrfToken in
                        try await self.api.withdrawPlaceProposal(id: id, cookie: cookie, csrfToken: csrfToken)
                    }
                },
                sendMessage: { [weak self] text in
                    guard let self, let id = self.activeRequest?.id else { throw missingError }
                    return try await self.account.performAuthorizedMutation { cookie, csrfToken in
                        try await self.api.sendQuickMessage(id: id, text: text, cookie: cookie, csrfToken: csrfToken)
                    }
                },
                isSessionLost: { error in
                    guard let failure = error as? AccountAPI.Failure else { return false }
                    return [401, 403, 404, 410].contains(failure.status) && !failure.isCsrfRejected
                },
                onSessionLost: { [weak self] in
                    Task { await self?.refresh(silent: true) }
                },
                onTerminal: { [weak self] in
                    Task { await self?.refresh(silent: true) }
                },
                formatError: { [weak account] error in
                    account?.displayError(error) ?? "연결이 원활하지 않아요. 잠시 후 다시 시도해주세요."
                },
                lostMessage: "픽업이 종료됐거나 상태를 확인할 수 없어요."
            )
        )
    }

    func reset() {
        requests = []
        requestFetchedAt = [:]
        trackedRequestId = nil
        activeStreamConnected = false
        tracking.resetState()
        error = nil
        notice = nil
    }

    func clearEndedTrackingIfNeeded() {
        if activeRequest == nil, tracking.snapshot?.status.ended == true {
            trackedRequestId = nil
            tracking.resetState()
        }
    }

    func beginTrackingSession() {
        if let activeId = activeRequest?.id {
            trackedRequestId = activeId
        }
    }

    func handleSceneInactive() {
        tracking.clearVehicle()
        requestFetchedAt.removeAll()
        activeStreamConnected = false
    }

    func remainingSeconds(for item: RideRequestItem, at now: ContinuousClock.Instant) -> Int? {
        guard item.status == .queued,
              item.currentPickupValidForMillis > 0,
              let seconds = item.currentPickupRemainingSeconds,
              let fetchedAt = requestFetchedAt[item.id],
              now < fetchedAt.advanced(by: .milliseconds(item.currentPickupValidForMillis)) else {
            return nil
        }
        return seconds
    }

    func refresh(silent: Bool = false) async {
        guard account.isReady, !loading, !busy else { return }
        loading = true
        if !silent {
            error = nil
        }
        defer { loading = false }

        do {
            let fetchedAt = ContinuousClock.now
            let items = try await account.performAuthorized { cookie in
                try await self.api.list(cookie: cookie)
            }
            await applyLoadedRequests(items, fetchedAt: fetchedAt)
        } catch {
            requestFetchedAt.removeAll()
            tracking.clearVehicle()
            if !silent {
                self.error = account.displayError(error)
            }
        }
    }

    func submitRequest(driverId: UUID, place: PickupPlace, requestId: UUID) async -> Bool {
        guard !busy else { return false }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            _ = try await account.performAuthorizedMutation { cookie, csrfToken in
                try await self.api.submit(driverId: driverId, place: place, requestId: requestId, cookie: cookie, csrfToken: csrfToken)
            }
            await reloadAfterMutation()
            notice = "운전자에게 마중을 요청했어요. 수락하면 픽업 대기에 들어가요."
            return true
        } catch {
            self.error = account.displayError(error)
            return false
        }
    }

    @discardableResult
    func answerInvitation(_ item: RideRequestItem, accept: Bool) async -> RideRequestItem.Status? {
        guard !busy else { return nil }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            let updated = try await account.performAuthorizedMutation { cookie, csrfToken in
                try await self.api.answerInvitation(id: item.requestId, accept: accept, cookie: cookie, csrfToken: csrfToken)
            }
            await reloadAfterMutation()
            notice = accept
                ? "초대를 수락했어요. 운전자가 내 픽업을 시작하면 위치를 확인할 수 있어요."
                : "초대를 거절했어요."
            return updated.status
        } catch {
            self.error = account.displayError(error)
            return nil
        }
    }

    func cancelRequest(_ item: RideRequestItem) async {
        guard !busy else { return }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            _ = try await account.performAuthorizedMutation { cookie, csrfToken in
                try await self.api.cancel(id: item.requestId, cookie: cookie, csrfToken: csrfToken)
            }
            await reloadAfterMutation()
            notice = "마중 요청을 취소했어요."
        } catch {
            self.error = account.displayError(error)
        }
    }

    func runEventStream(for requestId: UUID) async {
        var delaySeconds = 1
        while !Task.isCancelled && account.isReady && activeRequest?.id == requestId {
            guard let cookie = account.storedSession?.sessionCookie else { break }
            await api.streamEvents(
                id: requestId,
                cookie: cookie,
                onState: { [weak self] connected in
                    self?.activeStreamConnected = connected
                    if connected { delaySeconds = 1 }
                },
                onRefresh: { [weak self] in
                    await self?.refresh(silent: true)
                }
            )
            activeStreamConnected = false
            if Task.isCancelled || activeRequest?.id != requestId { break }
            try? await Task.sleep(for: .seconds(delaySeconds))
            delaySeconds = min(delaySeconds * 2, 15)
        }
        activeStreamConnected = false
    }

    private func reloadAfterMutation() async {
        if let items = try? await account.performAuthorized({ cookie in
            try await self.api.list(cookie: cookie)
        }) {
            await applyLoadedRequests(items, fetchedAt: ContinuousClock.now)
        }
    }

    private func applyLoadedRequests(_ items: [RideRequestItem], fetchedAt: ContinuousClock.Instant) async {
        let previousActiveId = activeRequest?.id ?? trackedRequestId
        var timestamps: [UUID: ContinuousClock.Instant] = [:]
        for item in items { timestamps[item.id] = fetchedAt }
        requests = items
        requestFetchedAt = timestamps

        if let currentActive = activeRequest {
            trackedRequestId = currentActive.id
            await tracking.refresh()
        } else if let prevId = previousActiveId,
                  let currentSnapshot = tracking.snapshot,
                  !currentSnapshot.status.ended,
                  let endedItem = items.first(where: { $0.id == prevId }),
                  let terminal = endedItem.terminalPickupSnapshot(
                      lastPlace: tracking.lastPlace,
                      lastVehicleName: tracking.lastVehicleName
                  ) {
            tracking.applyExternal(terminal, vehicle: nil)
        } else if let status = tracking.snapshot?.status, !status.ended {
            trackedRequestId = nil
            tracking.resetState()
        }
    }
}
