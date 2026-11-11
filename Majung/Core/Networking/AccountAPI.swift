import Foundation

struct AccountAPI {
    struct Failure: LocalizedError {
        let status: Int
        let code: String?
        let message: String?

        var isUnauthorized: Bool { status == 401 }
        var isCsrfRejected: Bool { status == 403 }
        var errorDescription: String? { message ?? "잠시 후 다시 시도해주세요." }
    }

    private struct ErrorBody: Decodable {
        let code: String?
        let message: String?
    }

    private struct ExchangeBody: Encodable {
        let code: String
        let verifier: String
    }

    private struct NicknameBody: Encodable {
        let nickname: String
    }

    private struct ConnectionTargetBody: Encodable {
        let memberId: UUID
    }

    private let origin = APIBaseURL.root
    private let network = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)

    func iosLoginURL(challenge: String) -> URL {
        var components = URLComponents(url: origin.appendingPathComponent("auth/ios/login"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "challenge", value: challenge)]
        return components.url!
    }

    func exchange(code: String, verifier: String) async throws -> (profile: AccountMember, cookie: String) {
        let (profile, response): (AccountMember, HTTPURLResponse) = try await requestWithResponse(
            "auth/ios/exchange",
            method: "POST",
            body: ExchangeBody(code: code, verifier: verifier)
        )
        guard let cookie = extractSessionCookie(from: response) else {
            throw Failure(status: 0, code: "SESSION_COOKIE_MISSING", message: "로그인 세션을 저장하지 못했어요. 다시 시도해주세요.")
        }
        return (profile, cookie)
    }

    func session(cookie: String?) async throws -> (state: AccountSessionResponse, updatedCookie: String?) {
        let (state, response): (AccountSessionResponse, HTTPURLResponse) = try await requestWithResponse(
            "auth/session",
            cookie: cookie
        )
        return (state, extractSessionCookie(from: response))
    }

    func me(cookie: String) async throws -> AccountMember {
        try await requestWithResponse("accounts/me", cookie: cookie).0
    }

    func updateNickname(_ nickname: String, cookie: String, csrfToken: String) async throws -> AccountMember {
        try await requestWithResponse(
            "accounts/me",
            method: "PATCH",
            cookie: cookie,
            csrfToken: csrfToken,
            body: NicknameBody(nickname: nickname)
        ).0
    }

    func searchAccounts(query: String, page: Int, cookie: String) async throws -> [AccountSearchResult] {
        try await requestWithResponse(
            "accounts/search",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "page", value: String(page))
            ],
            cookie: cookie
        ).0
    }

    func connections(page: Int, cookie: String) async throws -> [AccountConnection] {
        try await requestWithResponse(
            "connections",
            queryItems: [URLQueryItem(name: "page", value: String(page))],
            cookie: cookie
        ).0
    }

    func requestConnection(memberId: UUID, cookie: String, csrfToken: String) async throws -> AccountConnection {
        try await requestWithResponse(
            "connections",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken,
            body: ConnectionTargetBody(memberId: memberId)
        ).0
    }

    func updateConnection(id: UUID, action: ConnectionAction, cookie: String, csrfToken: String) async throws -> AccountConnection {
        try await requestWithResponse(
            "connections/\(id.uuidString.lowercased())/\(action.rawValue)",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken
        ).0
    }

    func logout(cookie: String, csrfToken: String) async throws {
        let url = endpoint("auth/logout")
        var req = baseRequest(url: url, method: "POST", cookie: cookie, csrfToken: csrfToken)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await network.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 401 else {
            let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw Failure(status: http.statusCode, code: errorBody?.code, message: errorBody?.message)
        }
    }

    func requestWithResponse<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        cookie: String? = nil,
        csrfToken: String? = nil,
        body: (any Encodable)? = nil
    ) async throws -> (Response, HTTPURLResponse) {
        let (data, http) = try await performRequest(
            path,
            method: method,
            queryItems: queryItems,
            cookie: cookie,
            csrfToken: csrfToken,
            body: body
        )
        return (try MajungCodec.decoder.decode(Response.self, from: data), http)
    }

    func requestEmpty(
        _ path: String,
        method: String = "POST",
        queryItems: [URLQueryItem]? = nil,
        cookie: String? = nil,
        csrfToken: String? = nil,
        body: (any Encodable)? = nil
    ) async throws {
        _ = try await performRequest(
            path,
            method: method,
            queryItems: queryItems,
            cookie: cookie,
            csrfToken: csrfToken,
            body: body
        )
    }

    private func performRequest(
        _ path: String,
        method: String,
        queryItems: [URLQueryItem]?,
        cookie: String?,
        csrfToken: String?,
        body: (any Encodable)?
    ) async throws -> (Data, HTTPURLResponse) {
        let url = endpoint(path, queryItems: queryItems)
        var req = baseRequest(url: url, method: method, cookie: cookie, csrfToken: csrfToken)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try MajungCodec.encoder.encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await network.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let errorBody = try? MajungCodec.decoder.decode(ErrorBody.self, from: data)
            throw Failure(status: http.statusCode, code: errorBody?.code, message: errorBody?.message)
        }
        return (data, http)
    }

    func endpoint(_ path: String, queryItems: [URLQueryItem]? = nil) -> URL {
        var url = origin
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        guard let queryItems, !queryItems.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = queryItems
        return components.url ?? url
    }

    func baseRequest(url: URL, method: String, cookie: String?, csrfToken: String?) -> URLRequest {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.httpMethod = method
        req.httpShouldHandleCookies = false
        if let cookie, !cookie.isEmpty {
            req.setValue("JSESSIONID=\(cookie)", forHTTPHeaderField: "Cookie")
        }
        if let csrfToken, !csrfToken.isEmpty {
            req.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-TOKEN")
        }
        return req
    }

    private func extractSessionCookie(from response: HTTPURLResponse) -> String? {
        guard let url = response.url else { return nil }
        var fields: [String: String] = [:]
        for (rawKey, rawValue) in response.allHeaderFields {
            if let key = rawKey as? String, let value = rawValue as? String {
                fields[key] = value
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        return cookies.first(where: { $0.name == "JSESSIONID" && !$0.value.isEmpty })?.value
    }
}
