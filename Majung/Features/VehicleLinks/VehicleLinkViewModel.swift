import Foundation
import Observation

@MainActor
@Observable
final class VehicleLinkViewModel {
    private let account: AccountViewModel
    private let api = VehicleLinkAPI()

    private(set) var links: [VehicleLink] = []
    private(set) var loaded = false
    private(set) var busy = false
    private var loadingLinks = false
    private var pollingStatus = false

    private(set) var activePairing: PendingVehiclePairing?
    private(set) var deferredTarget: VehiclePairingTarget?
    private(set) var notice: String?
    private(set) var error: String?
    private(set) var navigationEventCount = 0

    var hasPendingPairing: Bool { activePairing != nil }

    init(account: AccountViewModel) {
        self.account = account
    }

    func load(silent: Bool = false) async {
        guard account.isReady, !loadingLinks else { return }
        loadingLinks = true
        defer { loadingLinks = false }
        do {
            links = try await account.performAuthorized { cookie in
                try await self.api.links(cookie: cookie)
            }
            loaded = true
            if !silent { error = nil }
        } catch {
            loaded = true
            if !silent { self.error = account.displayError(error) }
        }
    }

    @discardableResult
    func handleIncoming(url: URL) async -> Bool {
        guard let target = VehiclePairingTarget(url: url) else { return false }
        return await handleTarget(target)
    }

    @discardableResult
    func handleTarget(_ target: VehiclePairingTarget) async -> Bool {
        notice = nil
        error = nil
        guard account.isReady else {
            deferredTarget = target
            notice = "로그인을 마치면 차량 연결을 이어서 진행할게요."
            return false
        }
        return await claim(target)
    }

    func resumeDeferredIfNeeded() async {
        guard account.isReady, let pending = deferredTarget else { return }
        deferredTarget = nil
        _ = await claim(pending)
    }

    func clearDeferred() {
        deferredTarget = nil
    }

    @discardableResult
    func claim(_ target: VehiclePairingTarget) async -> Bool {
        guard account.isReady, !busy else { return false }
        busy = true
        notice = nil
        error = nil
        defer { busy = false }

        do {
            switch target.kind {
            case .vehicle:
                let state = try await account.performAuthorizedMutation { cookie, csrfToken in
                    try await self.api.claimRequest(
                        challengeId: target.id,
                        code: target.code,
                        cookie: cookie,
                        csrfToken: csrfToken
                    )
                }
                applyLinkRequestState(state)
            case .enroll:
                let state = try await account.performAuthorizedMutation { cookie, csrfToken in
                    try await self.api.claimEnrollment(
                        id: target.id,
                        code: target.code,
                        cookie: cookie,
                        csrfToken: csrfToken
                    )
                }
                applyEnrollmentState(state)
            }
            if activePairing == nil {
                await load(silent: true)
            }
            navigationEventCount += 1
            return true
        } catch {
            self.error = account.displayError(error)
            navigationEventCount += 1
            return false
        }
    }

    func pollActivePairingOnce() async {
        guard account.isReady, let current = activePairing, !pollingStatus else { return }
        pollingStatus = true
        defer { pollingStatus = false }

        do {
            switch current {
            case .linkRequest(let state):
                let next = try await account.performAuthorized { cookie in
                    try await self.api.requestStatus(id: state.challengeId, cookie: cookie)
                }
                if next.isLinked {
                    await load(silent: true)
                }
                applyLinkRequestState(next)
            case .enrollment(let state):
                let next = try await account.performAuthorized { cookie in
                    try await self.api.enrollmentStatus(id: state.enrollmentId, cookie: cookie)
                }
                if next.isConfirmed {
                    await load(silent: true)
                }
                applyEnrollmentState(next)
            }
        } catch let failure as AccountAPI.Failure where [404, 410].contains(failure.status) {
            activePairing = nil
            error = failure.message ?? "차량 연결 요청이 만료되었거나 취소됐어요."
        } catch {
            // Transient poll failure resolves on the next interval.
        }
    }

    func cancelActivePairing() async {
        guard account.isReady, let current = activePairing, !busy else { return }
        busy = true
        notice = nil
        error = nil
        defer { busy = false }

        do {
            switch current {
            case .linkRequest(let state):
                try await account.performAuthorizedMutation { cookie, csrfToken in
                    try await self.api.cancelRequest(id: state.challengeId, cookie: cookie, csrfToken: csrfToken)
                }
            case .enrollment(let state):
                _ = try await account.performAuthorizedMutation { cookie, csrfToken in
                    try await self.api.cancelEnrollment(id: state.enrollmentId, cookie: cookie, csrfToken: csrfToken)
                }
            }
            activePairing = nil
            notice = "차량 연결 요청을 취소했어요."
        } catch {
            self.error = account.displayError(error)
        }
    }

    func detach(_ link: VehicleLink) async {
        guard account.isReady, !busy else { return }
        busy = true
        notice = nil
        error = nil
        defer { busy = false }

        do {
            try await account.performAuthorizedMutation { cookie, csrfToken in
                try await self.api.detach(vehicleId: link.vehicleId, cookie: cookie, csrfToken: csrfToken)
            }
            links.removeAll { $0.vehicleId == link.vehicleId }
            notice = "'\(link.displayName)' 연결을 해제했어요."
            await load(silent: true)
        } catch {
            self.error = account.displayError(error)
        }
    }

    func reset() {
        links = []
        loaded = false
        busy = false
        loadingLinks = false
        pollingStatus = false
        activePairing = nil
        notice = nil
        error = nil
    }

    private func applyLinkRequestState(_ state: VehicleLinkRequestState) {
        if state.isLinked {
            activePairing = nil
            error = nil
            let name = state.vehicleName?.trimmingCharacters(in: .whitespacesAndNewlines)
            notice = if let name, !name.isEmpty { "'\(name)' 차량을 연결했어요." } else { "차량 연결을 완료했어요." }
        } else if state.isPending {
            error = nil
            activePairing = .linkRequest(state)
        } else {
            activePairing = nil
            error = "차량 연결 요청이 만료되었거나 취소됐어요."
        }
    }

    private func applyEnrollmentState(_ state: VehicleEnrollmentState) {
        if state.isConfirmed {
            activePairing = nil
            error = nil
            notice = "새 차량 등록을 완료했어요."
        } else if state.isCancelled {
            activePairing = nil
            error = "차량 등록 요청이 취소됐어요."
        } else if state.isPending {
            error = nil
            activePairing = .enrollment(state)
        } else {
            activePairing = nil
            error = "차량 등록 요청이 만료됐어요."
        }
    }
}
