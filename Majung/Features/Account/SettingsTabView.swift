import SwiftUI
import UIKit

struct SettingsTabView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var account: AccountViewModel
    @Bindable var people: PeopleViewModel
    @Bindable var rideRequests: RideRequestViewModel
    @Bindable var vehicleLinks: VehicleLinkViewModel
    @State private var notifications = PickupNotificationService()
    @State private var nicknameDraft = ""
    @State private var copiedId = false
    @State private var showingVehicleScanner = false
    @State private var detachingVehicle: VehicleLink?
    @State private var showingGuide = false
    @State private var confirmingLogout = false
    @State private var confirmingDeleteAccount = false
    @FocusState private var nicknameFocused: Bool

    private var detachAlertPresented: Binding<Bool> {
        Binding(
            get: { detachingVehicle != nil },
            set: { if !$0 { detachingVehicle = nil } }
        )
    }

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
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copiedId = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section {
                if let active = vehicleLinks.activePairing {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            MajungStatusPill(text: "승인 대기", tint: .orange)
                            Spacer()
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = max(0, Int(active.expiresAt.timeIntervalSince(context.date)))
                                let formatted = remaining >= 3600
                                    ? String(format: "%d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
                                    : String(format: "%d:%02d", remaining / 60, remaining % 60)
                                Text("만료 \(formatted)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(active.title)
                            .font(.subheadline.weight(.semibold))
                        Text(active.detailText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("상태 확인") {
                                Task { await vehicleLinks.pollActivePairingOnce() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(vehicleLinks.busy)
                            .accessibilityIdentifier("vehicle-pairing-refresh-button")

                            Button("요청 취소", role: .destructive) {
                                Task { await vehicleLinks.cancelActivePairing() }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                            .disabled(vehicleLinks.busy)
                            .accessibilityIdentifier("vehicle-pairing-cancel-button")
                        }
                    }
                    .padding(.vertical, 4)
                }

                if vehicleLinks.links.isEmpty && vehicleLinks.loaded && vehicleLinks.activePairing == nil {
                    Text("연결된 차량이 없어요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(vehicleLinks.links) { link in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.displayName)
                                .font(.body.weight(.medium))
                            Text("연결 · \(MajungFormatting.shortDateTime(link.linkedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("해제", role: .destructive) {
                            detachingVehicle = link
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                        .disabled(vehicleLinks.busy)
                        .accessibilityIdentifier("vehicle-detach-\(link.vehicleId.uuidString.lowercased())")
                    }
                }

                Button {
                    showingVehicleScanner = true
                } label: {
                    Label("QR 또는 링크로 차량 연결", systemImage: "qrcode.viewfinder")
                }
                .disabled(vehicleLinks.busy)
                .accessibilityIdentifier("vehicle-connect-button")

                if let vNotice = vehicleLinks.notice {
                    Text(vNotice)
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let vError = vehicleLinks.error {
                    Text(vError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                HStack {
                    Text("내 차량")
                    Spacer()
                    if !vehicleLinks.links.isEmpty {
                        MajungStatusPill(text: "\(vehicleLinks.links.count)대 연결됨", tint: .green)
                    }
                }
            }

            if account.member != nil {
                Section("내 이름(닉네임) 변경") {
                    HStack(spacing: 8) {
                        TextField("새 닉네임 (2~20자)", text: $nicknameDraft)
                            .focused($nicknameFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                nicknameFocused = false
                                if canSaveNickname && !account.busy {
                                    Task { _ = await account.saveNickname(nicknameDraft) }
                                }
                            }
                            .accessibilityIdentifier("settings-nickname-field")

                        MajungClearInputButton(text: $nicknameDraft, accessibilityLabel: "닉네임 지우기")
                    }
                    .majungPreserveKeyboardOnTap()
                    HStack {
                        Text("\(normalizedCount)/20자")
                            .font(.footnote)
                            .foregroundStyle(normalizedCount > 20 ? Color.red : Color.secondary)
                        Spacer()
                        Button(account.busy ? "저장 중…" : "닉네임 저장") {
                            nicknameFocused = false
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

            Section("알림 및 개인정보 안내") {
                Toggle(isOn: Binding(
                    get: { notifications.enabled },
                    set: { value in Task { await notifications.setEnabled(value) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("도착 전·차량 도착 알림")
                        Text("도착 약 3분 전과 차량 도착 시 알림을 받아요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings-arrival-alert-toggle")

                if notifications.permissionDenied {
                    HStack {
                        Text("iOS 설정에서 알림 권한이 꺼져 있어요.")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("설정 열기") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                openURL(settingsURL)
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                }

                Text("픽업 중에는 다이나믹 아일랜드와 잠금화면에 마지막 도착 정보가 표시돼요. 오래된 정보는 ‘갱신 필요’로 안내하며, 앱을 다시 열면 최신 상태를 확인해요. 도착 알림은 앱 실행 중 제공해요. 위치 권한은 만날 장소를 고를 때만 사용하며, 픽업이 종료되면 위치 공유가 멈춰요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("마중 안내") {
                Button {
                    nicknameFocused = false
                    showingGuide = true
                } label: {
                    Label("마중 이용 가이드", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("settings-guide-button")
            }

            Section("계정") {
                Button("로그아웃", role: .destructive) {
                    nicknameFocused = false
                    confirmingLogout = true
                }
                .disabled(account.busy)
                .accessibilityIdentifier("settings-logout-button")

                Button("회원 탈퇴", role: .destructive) {
                    nicknameFocused = false
                    confirmingDeleteAccount = true
                }
                .disabled(account.busy)
                .accessibilityIdentifier("settings-delete-account-button")
            }
        }
        .navigationTitle("설정")
        .majungKeyboardDismiss(isFocused: $nicknameFocused)
        .onChange(of: showingVehicleScanner) { _, isShowing in
            if isShowing {
                nicknameFocused = false
            }
        }
        .task {
            await notifications.refreshStatus()
            await vehicleLinks.load(silent: true)
        }
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
        .sheet(isPresented: $showingVehicleScanner) {
            VehicleQRScannerSheet(vehicleLinks: vehicleLinks) {}
        }
        .majungGuideSheet(isPresented: $showingGuide)
        .alert(
            "'\(detachingVehicle?.displayName ?? "차량")' 연결을 해제할까요?",
            isPresented: detachAlertPresented,
            presenting: detachingVehicle
        ) { link in
            Button("연결 해제", role: .destructive) {
                detachingVehicle = nil
                Task { await vehicleLinks.detach(link) }
            }
            Button("돌아가기", role: .cancel) {
                detachingVehicle = nil
            }
        } message: { _ in
            Text("연결을 해제하면 해당 차량에서 내 계정으로 마중을 시작할 수 없어요.")
        }
        .alert("로그아웃할까요?", isPresented: $confirmingLogout) {
            Button("로그아웃", role: .destructive) {
                Task { await account.logout() }
            }
            Button("돌아가기", role: .cancel) {}
        }
        .alert("정말 마중에서 탈퇴할까요?", isPresented: $confirmingDeleteAccount) {
            Button("탈퇴하기", role: .destructive) {
                Task { _ = await account.deleteAccount() }
            }
            Button("돌아가기", role: .cancel) {}
        } message: {
            Text("계정 정보, 지인 연결, 등록된 차량 연결 및 이용 기록이 모두 삭제되며 되돌릴 수 없어요.")
        }
    }
}
