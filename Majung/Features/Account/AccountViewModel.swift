import Foundation
import Observation

@MainActor
@Observable
final class AccountViewModel {
    private let api = AccountAPI()
    private let webAuth = NativeAuthSession()
    private(set) var storedSession = AccountSessionStore.load()

    private(set) var loginEnabled = true
    private(set) var member: AccountMember?
    private(set) var csrfToken: String?
    private(set) var busy = false
    private(set) var restoring = false
    var error: String?
    var notice: String?

    #if DEBUG
    var devAccounts: [DevAccountSummary] = []
    #endif

    var isAuthenticated: Bool { storedSession != nil && member != nil }
    var needsNicknameSetup: Bool { isAuthenticated && member?.profileReady == false }
    var isReady: Bool { isAuthenticated && member?.profileReady == true }

    func restore() async {
        guard !restoring else { return }
        restoring = true
        defer { restoring = false }
        do {
            let result = try await api.session(cookie: storedSession?.sessionCookie)
            loginEnabled = result.state.loginEnabled
            if result.state.authenticated, let current = result.state.member {
                if let updatedCookie = result.updatedCookie {
                    saveCookie(updatedCookie)
                }
                member = current
                csrfToken = result.state.csrfToken
                if current.profileReady {
                    error = nil
                }
            } else {
                clearLocalSession()
            }
        } catch {
            // Keep existing Keychain cookie on transient network issues when offline; only clear on 401.
            if let failure = error as? AccountAPI.Failure, failure.isUnauthorized {
                clearLocalSession()
            }
        }
    }

    func signInWithKakao() async {
        guard !busy else { return }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        let verifier = AccountValidation.pkceVerifier()
        let challenge = AccountValidation.pkceChallenge(for: verifier)
        do {
            let code = try await webAuth.authenticate(url: api.iosLoginURL(challenge: challenge))
            let exchanged = try await api.exchange(code: code, verifier: verifier)
            saveCookie(exchanged.cookie)
            member = exchanged.profile

            let sessionResult = try await api.session(cookie: exchanged.cookie)
            loginEnabled = sessionResult.state.loginEnabled
            if let freshMember = sessionResult.state.member {
                member = freshMember
            }
            csrfToken = sessionResult.state.csrfToken
            if member?.profileReady == true {
                error = nil
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = displayError(error)
        }
    }

    func saveNickname(_ raw: String) async -> Bool {
        guard !busy else { return false }
        guard let normalized = AccountValidation.normalizedNickname(raw) else {
            error = "닉네임은 문자·숫자·공백·밑줄·점·하이픈으로 2~20자 입력해주세요."
            return false
        }
        guard let cookie = storedSession?.sessionCookie else {
            clearLocalSession()
            error = "다시 로그인해주세요."
            return false
        }

        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            let updated = try await performAuthorizedMutation { cookie, token in
                try await self.api.updateNickname(normalized, cookie: cookie, csrfToken: token)
            }
            member = updated
            notice = "이름을 저장했어요."
            return true
        } catch {
            handleAccountError(error)
            return false
        }
    }

    func performAuthorized<Response>(_ work: (_ cookie: String) async throws -> Response) async throws -> Response {
        guard let cookie = storedSession?.sessionCookie else {
            clearLocalSession()
            throw AccountAPI.Failure(status: 401, code: "LOGIN_REQUIRED", message: "다시 로그인해주세요.")
        }
        do {
            return try await work(cookie)
        } catch let failure as AccountAPI.Failure where failure.isUnauthorized {
            clearLocalSession()
            throw AccountAPI.Failure(status: 401, code: failure.code ?? "LOGIN_REQUIRED", message: "로그인 세션이 만료됐어요. 다시 로그인해주세요.")
        }
    }

    func performAuthorizedMutation<Response>(
        _ work: (_ cookie: String, _ csrfToken: String) async throws -> Response
    ) async throws -> Response {
        try await performAuthorized { cookie in
            let token = try await self.ensureCsrfToken(cookie: cookie)
            do {
                return try await work(cookie, token)
            } catch let failure as AccountAPI.Failure where failure.isCsrfRejected {
                let refreshed = try await self.refreshCsrfToken(cookie: cookie)
                return try await work(cookie, refreshed)
            }
        }
    }

    func logout() async {
        guard !busy else { return }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        if let cookie = storedSession?.sessionCookie {
            if let token = try? await ensureCsrfToken(cookie: cookie) {
                try? await api.logout(cookie: cookie, csrfToken: token)
            }
        }
        clearLocalSession()
    }

    func deleteAccount() async -> Bool {
        guard !busy else { return false }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            try await performAuthorizedMutation { cookie, csrfToken in
                try await self.api.deleteAccount(cookie: cookie, csrfToken: csrfToken)
            }
            clearLocalSession()
            return true
        } catch {
            handleAccountError(error)
            return false
        }
    }

    private func ensureCsrfToken(cookie: String) async throws -> String {
        if let csrfToken, !csrfToken.isEmpty {
            return csrfToken
        }
        return try await refreshCsrfToken(cookie: cookie)
    }

    private func refreshCsrfToken(cookie: String) async throws -> String {
        let result = try await api.session(cookie: cookie)
        guard result.state.authenticated, let token = result.state.csrfToken, !token.isEmpty else {
            throw AccountAPI.Failure(status: 401, code: "LOGIN_REQUIRED", message: "다시 로그인해주세요.")
        }
        if let freshMember = result.state.member {
            member = freshMember
        }
        csrfToken = token
        return token
    }

    private func saveCookie(_ cookie: String) {
        let next = AccountStoredSession(sessionCookie: cookie)
        storedSession = next
        do {
            try AccountSessionStore.save(next)
        } catch {
            self.error = "로그인은 완료됐지만 기기 보안 저장소에 세션을 저장하지 못했어요."
        }
    }

    private func handleAccountError(_ error: Error) {
        if let failure = error as? AccountAPI.Failure, failure.isUnauthorized {
            clearLocalSession()
            self.error = "로그인 세션이 만료됐어요. 다시 로그인해주세요."
        } else {
            self.error = displayError(error)
        }
    }

    private func clearLocalSession() {
        storedSession = nil
        member = nil
        csrfToken = nil
        AccountSessionStore.clear()
    }

    func displayError(_ error: Error) -> String {
        if let native = error as? NativeAuthError, let msg = native.errorDescription {
            return msg
        }
        if let apiError = error as? AccountAPI.Failure, let msg = apiError.errorDescription {
            return msg
        }
        return "연결이 원활하지 않아요. 잠시 후 다시 시도해주세요."
    }

    #if DEBUG
    private struct DevLoginRequest: Encodable {
        let memberId: UUID?
    }

    private struct DevActionRequest: Encodable {
        let action: String
        let pickupId: UUID?
    }

    func setDevServerMode(_ mode: DevServerMode) async {
        guard DevServerConfig.shared.mode != mode else { return }
        DevServerConfig.shared.mode = mode
        clearLocalSession()
        error = nil
        notice = nil
        devAccounts = []
        loginEnabled = true
        if mode != .production {
            await loadDevAccounts()
        } else {
            await restore()
        }
    }

    func loadDevAccounts() async {
        guard DevServerConfig.shared.mode != .production else {
            devAccounts = []
            return
        }
        do {
            let (accounts, _): ([DevAccountSummary], HTTPURLResponse) = try await api.requestWithResponse("dev/accounts")
            devAccounts = accounts
        } catch {
            self.error = "테스트 서버(\(APIBaseURL.root.absoluteString))에서 더미 계정을 불러오지 못했어요."
        }
    }

    func signInWithDevAccount(memberId: UUID? = nil) async -> Bool {
        guard !busy else { return false }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            let (_, http): (AccountMember, HTTPURLResponse) = try await api.requestWithResponse(
                "dev/login",
                method: "POST",
                body: DevLoginRequest(memberId: memberId)
            )
            guard let url = http.url else {
                self.error = "테스트 로그인 응답 URL을 확인하지 못했어요."
                return false
            }
            var fields: [String: String] = [:]
            for (rawKey, rawValue) in http.allHeaderFields {
                if let k = rawKey as? String, let v = rawValue as? String {
                    fields[k] = v
                }
            }
            guard let cookie = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
                .first(where: { $0.name == "JSESSIONID" && !$0.value.isEmpty })?.value else {
                self.error = "테스트 세션을 저장하지 못했어요."
                return false
            }
            saveCookie(cookie)
            let sessionResult = try await api.session(cookie: cookie)
            loginEnabled = sessionResult.state.loginEnabled
            member = sessionResult.state.member
            csrfToken = sessionResult.state.csrfToken
            notice = "\(member?.nickname ?? "데모 계정")으로 전환했어요."
            return true
        } catch {
            self.error = displayError(error)
            return false
        }
    }

    func fetchDevGuestInviteLink() async -> String? {
        if DevServerConfig.shared.mode == .demo {
            _ = SoloDemoServer.shared.ensureStarted()
            return SoloDemoServer.shared.sampleGuestInviteString
        }
        guard DevServerConfig.shared.mode == .local else { return nil }
        struct GuestInviteRes: Decodable { let link: String }
        do {
            let (res, _): (GuestInviteRes, HTTPURLResponse) = try await api.requestWithResponse("dev/simulate/guest-invite", method: "POST")
            return res.link
        } catch {
            self.error = displayError(error)
            return nil
        }
    }

    func resetDevData() async -> Bool {
        guard DevServerConfig.shared.mode != .production, !busy else { return false }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        let previousId = member?.memberId
        do {
            try await api.requestEmpty("dev/reset", method: "POST")
            if let previousId {
                busy = false
                let ok = await signInWithDevAccount(memberId: previousId)
                if ok { notice = "더미 데이터를 처음 상태로 초기화했어요." }
                return ok
            }
            notice = "더미 데이터를 초기화했어요."
            return true
        } catch {
            self.error = displayError(error)
            return false
        }
    }

    func triggerDevSimulation(path: String, action: String? = nil) async -> Bool {
        guard DevServerConfig.shared.mode != .production else { return false }
        error = nil
        do {
            if let action {
                var targetPickupId: UUID? = nil
                if DevServerConfig.shared.mode == .local, path == "dev/simulate/vehicle-tick" {
                    struct DevStateRes: Decodable {
                        struct P: Decodable { let pickupId: UUID; let status: String }
                        let pickups: [P]
                    }
                    if let (state, _): (DevStateRes, HTTPURLResponse) = try? await api.requestWithResponse("dev/state"),
                       let active = state.pickups.first(where: { $0.status == "ACTIVE" || $0.status == "ARRIVED" }) {
                        targetPickupId = active.pickupId
                    }
                }
                try await api.requestEmpty(path, method: "POST", body: DevActionRequest(action: action, pickupId: targetPickupId))
            } else {
                try await api.requestEmpty(path, method: "POST")
            }
            notice = "데모 시뮬레이션을 실행했어요."
            return true
        } catch {
            self.error = displayError(error)
            return false
        }
    }
    #endif
}
