import Foundation
import Observation

@MainActor
@Observable
final class PeopleViewModel {
    private let account: AccountViewModel
    private let api = AccountAPI()
    private let pageSize = 20
    private let maxPage = 50

    private(set) var connections: [AccountConnection] = []
    private(set) var connectionPage = 0
    private(set) var connectionsHasNext = false

    private(set) var searchResults: [AccountSearchResult] = []
    private(set) var searchedQuery = ""
    private(set) var searchPage = 0
    private(set) var searchHasNext = false
    private(set) var searchDone = false

    private(set) var busy = false
    private(set) var loadingConnections = false
    var error: String?
    var notice: String?

    init(account: AccountViewModel) {
        self.account = account
    }

    func reset() {
        connections = []
        connectionPage = 0
        connectionsHasNext = false
        searchResults = []
        searchedQuery = ""
        searchPage = 0
        searchHasNext = false
        searchDone = false
        error = nil
        notice = nil
    }

    func loadConnections(page: Int? = nil, silent: Bool = false) async {
        guard !loadingConnections else { return }
        let targetPage = max(0, min(maxPage, page ?? connectionPage))
        loadingConnections = true
        if !silent {
            error = nil
        }
        defer { loadingConnections = false }

        do {
            let loaded = try await account.performAuthorized { cookie in
                try await self.api.connections(page: targetPage, cookie: cookie)
            }
            connectionPage = targetPage
            connections = loaded
            connectionsHasNext = loaded.count >= pageSize && targetPage < maxPage
        } catch {
            if !silent {
                self.error = account.displayError(error)
            }
        }
    }

    func search(_ rawQuery: String, page: Int = 0) async {
        guard !busy else { return }
        guard let normalized = AccountValidation.normalizedSearchQuery(rawQuery) else {
            error = "검색어는 2~32자로 입력해주세요."
            return
        }
        let targetPage = max(0, min(maxPage, page))
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            let results = try await account.performAuthorized { cookie in
                try await self.api.searchAccounts(query: normalized, page: targetPage, cookie: cookie)
            }
            searchedQuery = normalized
            searchPage = targetPage
            searchResults = results
            searchHasNext = results.count >= pageSize && targetPage < maxPage
            searchDone = true
        } catch {
            self.error = account.displayError(error)
        }
    }

    func changeSearchPage(delta: Int) async {
        guard searchDone, !searchedQuery.isEmpty else { return }
        let nextPage = searchPage + delta
        guard nextPage >= 0 && nextPage <= maxPage else { return }
        await search(searchedQuery, page: nextPage)
    }

    func requestConnection(memberId: UUID) async {
        guard !busy else { return }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            let result = try await account.performAuthorizedMutation { cookie, csrfToken in
                try await self.api.requestConnection(memberId: memberId, cookie: cookie, csrfToken: csrfToken)
            }
            await loadConnections(page: 0, silent: true)
            if result.isConnected {
                notice = "\(result.nickname) 님과 이미 연결돼 있어요."
            } else {
                notice = "\(result.nickname) 님에게 연결 요청을 보냈어요. 상대가 수락하면 연결돼요."
            }
        } catch {
            self.error = account.displayError(error)
        }
    }

    func perform(_ action: ConnectionAction, on connection: AccountConnection) async {
        guard !busy else { return }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }

        do {
            let updated = try await account.performAuthorizedMutation { cookie, csrfToken in
                try await self.api.updateConnection(id: connection.connectionId, action: action, cookie: cookie, csrfToken: csrfToken)
            }
            await loadConnections(page: connectionPage, silent: true)
            notice = switch action {
            case .accept:
                "\(updated.nickname) 님과 연결했어요."
            case .reject:
                "\(updated.nickname) 님의 연결 요청을 거절했어요."
            case .cancel:
                "보낸 연결 요청을 취소했어요."
            case .disconnect:
                "\(updated.nickname) 님과의 연결을 해제했어요."
            }
        } catch {
            self.error = account.displayError(error)
        }
    }

    func existingConnection(for majungId: String) -> AccountConnection? {
        connections.first { $0.majungId == majungId }
    }
}
