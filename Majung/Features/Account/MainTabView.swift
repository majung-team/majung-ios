import SwiftUI
import UIKit

struct MainTabView: View {
    @Bindable var account: AccountViewModel
    @Bindable var people: PeopleViewModel
    @Bindable var pickup: PickupViewModel
    @Binding var inviteLink: String
    @State private var selectedTab: TabItem = .home

    private enum TabItem: Hashable {
        case home, requests, people, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeTabView(account: account, pickup: pickup, inviteLink: $inviteLink)
            }
            .tabItem {
                Label("홈", systemImage: "house.fill")
            }
            .tag(TabItem.home)

            NavigationStack {
                ContentUnavailableView(
                    "아직 받은 초대나 요청이 없어요",
                    systemImage: "clock",
                    description: Text("마중 요청·대기열 기능 연결 후 진행 중인 요청과 받은 초대를 확인할 수 있어요.")
                )
                .navigationTitle("내 요청·초대")
            }
            .tabItem {
                Label("내 요청·초대", systemImage: "clock.fill")
            }
            .tag(TabItem.requests)

            NavigationStack {
                PeopleTabView(account: account, people: people)
            }
            .tabItem {
                Label("사람", systemImage: "person.2.fill")
            }
            .tag(TabItem.people)

            NavigationStack {
                SettingsTabView(account: account)
            }
            .tabItem {
                Label("설정", systemImage: "gearshape.fill")
            }
            .tag(TabItem.settings)
        }
    }
}

private struct HomeTabView: View {
    @Bindable var account: AccountViewModel
    @Bindable var pickup: PickupViewModel
    @Binding var inviteLink: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let member = account.member {
                    card {
                        Text("안녕하세요, \(member.nickname) 님")
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("내 마중 ID · \(member.majungId)")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                }

                card {
                    Label("초대 링크로 참여하기", systemImage: "link")
                        .font(.headline)
                    Text("전달받은 초대 링크를 붙여넣어 만날 장소와 차량 도착 시간을 확인할 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("마중 초대 링크", text: $inviteLink, axis: .vertical)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 10) {
                        PasteButton(payloadType: String.self) { values in
                            guard let value = values.first else { return }
                            inviteLink = value
                            Task { await pickup.openLink(value) }
                        }
                        .disabled(pickup.busy)
                        Button {
                            Task { await pickup.openLink(inviteLink) }
                        } label: {
                            Text("초대 확인하기")
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pickup.busy)
                    }
                    if let error = pickup.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("홈")
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SettingsTabView: View {
    @Bindable var account: AccountViewModel
    @State private var nicknameDraft = ""
    @State private var copiedId = false
    @State private var confirmingLogout = false

    private var normalizedCount: Int {
        nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .count
    }

    private var canSaveNickname: Bool {
        guard let normalized = AccountValidation.normalizedNickname(nicknameDraft),
              let current = account.member else { return false }
        return normalized != current.nickname
    }

    var body: some View {
        Form {
            if let member = account.member {
                Section("내 프로필") {
                    LabeledContent("이름", value: member.nickname)
                    HStack {
                        Text("마중 ID")
                        Spacer()
                        Text(member.majungId)
                            .foregroundStyle(.secondary)
                        Button(copiedId ? "복사됨" : "복사") {
                            UIPasteboard.general.string = member.majungId
                            copiedId = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Section("내 이름(닉네임) 변경") {
                    TextField("새 닉네임 (2~20자)", text: $nicknameDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings-nickname-field")
                    HStack {
                        Text("\(normalizedCount)/20자")
                            .font(.footnote)
                            .foregroundStyle(normalizedCount > 20 ? Color.red : Color.secondary)
                        Spacer()
                        Button(account.busy ? "저장 중…" : "닉네임 저장") {
                            Task { _ = await account.saveNickname(nicknameDraft) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!canSaveNickname || account.busy)
                        .accessibilityIdentifier("settings-nickname-save")
                    }
                    if let notice = account.notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if let error = account.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("위치 및 개인정보 안내") {
                Text("위치 권한은 만날 장소를 고를 때만 사용하며, 픽업이 종료되면 실시간 위치 공유가 즉시 멈춰요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("계정") {
                Button("로그아웃", role: .destructive) {
                    confirmingLogout = true
                }
                .disabled(account.busy)
                .accessibilityIdentifier("settings-logout-button")
            }
        }
        .navigationTitle("설정")
        .onAppear {
            if nicknameDraft.isEmpty, let current = account.member?.nickname {
                nicknameDraft = current
            }
        }
        .onChange(of: account.member?.nickname) { _, newValue in
            if let newValue {
                nicknameDraft = newValue
            }
        }
        .confirmationDialog("로그아웃할까요?", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("로그아웃", role: .destructive) {
                Task { await account.logout() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("로그아웃하면 카카오 계정으로 다시 로그인해야 요청과 연결을 관리할 수 있어요.")
        }
    }
}
