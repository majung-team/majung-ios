import SwiftUI
import UIKit

struct PeopleTabView: View {
    @Bindable var account: AccountViewModel
    @Bindable var people: PeopleViewModel

    @State private var queryDraft = ""
    @State private var copiedId = false
    @State private var pendingAction: PendingConnectionAction?
    @FocusState private var searchFocused: Bool

    private struct PendingConnectionAction: Identifiable {
        let connection: AccountConnection
        let action: ConnectionAction

        var id: String { "\(connection.id.uuidString)-\(action.rawValue)" }

        var title: String {
            switch action {
            case .reject: "연결 요청을 거절할까요?"
            case .cancel: "보낸 연결 요청을 취소할까요?"
            case .disconnect: "연결을 해제할까요?"
            case .accept: "연결 요청을 수락할까요?"
            }
        }

        var confirmLabel: String {
            switch action {
            case .reject: "요청 거절하기"
            case .cancel: "요청 취소하기"
            case .disconnect: "연결 해제하기"
            case .accept: "연결 수락"
            }
        }
    }

    private var canSearch: Bool {
        AccountValidation.normalizedSearchQuery(queryDraft) != nil && !people.busy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let notice = people.notice {
                    statusBanner(notice, tint: .green)
                }
                if let error = people.error {
                    statusBanner(error, tint: .red)
                }

                if let member = account.member {
                    myIdCard(member)
                }

                searchSection
                connectionsSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("사람")
        .refreshable {
            await people.loadConnections(page: people.connectionPage)
        }
        .task(id: account.member?.memberId) {
            await people.loadConnections(page: 0)
        }
        .alert(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            presenting: pendingAction
        ) { target in
            Button(target.confirmLabel, role: .destructive) {
                Task { await people.perform(target.action, on: target.connection) }
            }
            Button("돌아가기", role: .cancel) {}
        } message: { target in
            Text("\(target.connection.nickname) (\(target.connection.majungId))")
        }
    }

    private func myIdCard(_ member: AccountMember) -> some View {
        card {
            Text("내 마중 ID (지인 공유용)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text(member.majungId)
                    .font(.headline.monospaced())
                Spacer()
                Button(copiedId ? "복사됨" : "ID 복사") {
                    UIPasteboard.general.string = member.majungId
                    copiedId = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("people-copy-id-button")
            }
        }
    }

    private var searchSection: some View {
        card {
            Label("사람 찾기", systemImage: "magnifyingglass")
                .font(.headline)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("닉네임 또는 마중 ID (2~32자)", text: $queryDraft)
                        .focused($searchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            if canSearch {
                                searchFocused = false
                                Task { await people.search(queryDraft, page: 0) }
                            }
                        }
                        .accessibilityIdentifier("people-search-field")

                    if !queryDraft.isEmpty {
                        Button {
                            queryDraft = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("검색어 지우기")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                Button(people.busy ? "검색 중…" : "검색") {
                    searchFocused = false
                    Task { await people.search(queryDraft, page: 0) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSearch)
                .accessibilityIdentifier("people-search-button")
            }

            Text("동명이인은 아래 마중 ID로 구분해주세요. 이름과 마중 ID 외의 위치·차량 정보는 공개하지 않아요.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if people.searchDone {
                Divider()
                HStack {
                    Text("‘\(people.searchedQuery)’ 검색 결과")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(people.searchResults.count)명")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if people.searchResults.isEmpty {
                    Text("검색 결과가 없어요. 닉네임이나 마중 ID를 다시 확인해주세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 10) {
                        ForEach(people.searchResults) { person in
                            searchResultRow(person)
                        }
                    }
                }

                if people.searchPage > 0 || people.searchHasNext {
                    pager(
                        page: people.searchPage,
                        hasNext: people.searchHasNext,
                        onPrevious: { Task { await people.changeSearchPage(delta: -1) } },
                        onNext: { Task { await people.changeSearchPage(delta: 1) } }
                    )
                }
            }
        }
    }

    private func searchResultRow(_ person: AccountSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                monogram(for: person.nickname, tint: .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.nickname)
                        .font(.subheadline.weight(.semibold))
                    Text(person.majungId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let connection = people.existingConnection(for: person.majungId) {
                    connectionBadge(for: connection)
                } else {
                    Button("연결 요청") {
                        searchFocused = false
                        Task { await people.requestConnection(memberId: person.memberId) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(people.busy)
                    .accessibilityIdentifier("people-request-\(person.majungId)")
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectionsSection: some View {
        card {
            HStack {
                Label("내 연결 목록", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                Button(people.loadingConnections ? "확인 중…" : "새로 확인") {
                    searchFocused = false
                    Task { await people.loadConnections(page: people.connectionPage) }
                }
                .font(.footnote.weight(.semibold))
                .disabled(people.loadingConnections || people.busy)
                .accessibilityIdentifier("people-refresh-button")
            }

            Text("연결 요청은 상대가 수락해야 연결돼요. 연결을 수락해도 내 위치나 차량 정보는 공유되지 않아요.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if people.connections.isEmpty {
                Text("아직 연결된 사람이나 대기 중인 요청이 없어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(people.connections) { item in
                        connectionRow(item)
                    }
                }
            }

            if people.connectionPage > 0 || people.connectionsHasNext {
                pager(
                    page: people.connectionPage,
                    hasNext: people.connectionsHasNext,
                    onPrevious: { Task { await people.loadConnections(page: people.connectionPage - 1) } },
                    onNext: { Task { await people.loadConnections(page: people.connectionPage + 1) } }
                )
            }
        }
    }

    private func connectionRow(_ item: AccountConnection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                monogram(for: item.nickname, tint: item.isConnected ? .green : item.isIncomingPending ? .accentColor : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.nickname)
                        .font(.subheadline.weight(.semibold))
                    Text(item.majungId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                connectionBadge(for: item)
            }

            HStack(spacing: 8) {
                Spacer()
                if item.isConnected {
                    Button("연결 해제", role: .destructive) {
                        pendingAction = PendingConnectionAction(connection: item, action: .disconnect)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(people.busy)
                    .accessibilityIdentifier("people-disconnect-\(item.majungId)")
                } else if item.isIncomingPending {
                    Button("거절") {
                        pendingAction = PendingConnectionAction(connection: item, action: .reject)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(people.busy)
                    .accessibilityIdentifier("people-reject-\(item.majungId)")

                    Button("연결 수락") {
                        Task { await people.perform(.accept, on: item) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(people.busy)
                    .accessibilityIdentifier("people-accept-\(item.majungId)")
                } else {
                    Button("요청 취소") {
                        pendingAction = PendingConnectionAction(connection: item, action: .cancel)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(people.busy)
                    .accessibilityIdentifier("people-cancel-\(item.majungId)")
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func connectionBadge(for item: AccountConnection) -> some View {
        let (text, color): (String, Color) = if item.isConnected {
            ("연결됨", .green)
        } else if item.isIncomingPending {
            ("받은 연결 요청", .accentColor)
        } else {
            ("상대 확인 대기 중", .orange)
        }

        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func monogram(for name: String, tint: Color) -> some View {
        let letter = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1))
        return Text(letter.isEmpty ? "마" : letter)
            .font(.subheadline.bold())
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.14), in: Circle())
    }

    private func pager(page: Int, hasNext: Bool, onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        HStack {
            Button("이전", action: onPrevious)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(page == 0 || people.busy || people.loadingConnections)
            Spacer()
            Text("\(page + 1) 페이지")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("다음", action: onNext)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasNext || people.busy || people.loadingConnections)
        }
        .padding(.top, 4)
    }

    private func statusBanner(_ message: String, tint: Color) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
