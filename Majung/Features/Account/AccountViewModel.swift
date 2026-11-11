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
}
