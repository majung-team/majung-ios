import SwiftUI
import UIKit

struct MainTabView: View {
    @Bindable var account: AccountViewModel
    @Bindable var people: PeopleViewModel
    @Bindable var rideRequests: RideRequestViewModel
    @Bindable var vehicleLinks: VehicleLinkViewModel
    @Bindable var pickup: PickupViewModel
    @Binding var inviteLink: String

    @State private var selectedTab: TabItem = .home
    @State private var rideTarget: RideTargetPerson?
    @State private var showingRideTracking = false

    private enum TabItem: Hashable {
        case home, requests, people, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeTabView(
                    account: account,
                    rideRequests: rideRequests,
                    pickup: pickup,
                    inviteLink: $inviteLink,
                    onOpenRequests: { selectedTab = .requests },
                    onOpenPeople: { selectedTab = .people },
                    onOpenTracking: { showingRideTracking = true }
                )
            }
            .tabItem {
                Label("홈", systemImage: "house.fill")
            }
            .tag(TabItem.home)

            NavigationStack {
                RequestsTabView(
                    rideModel: rideRequests,
                    onOpenPeople: { selectedTab = .people },
                    onOpenTracking: { showingRideTracking = true }
                )
            }
            .tabItem {
                Label("내 요청·초대", systemImage: "clock.fill")
            }
            .badge(rideRequests.invitedCount)
            .tag(TabItem.requests)

            NavigationStack {
                PeopleTabView(account: account, people: people) { target in
                    rideRequests.error = nil
                    rideTarget = target
                }
            }
            .tabItem {
                Label("사람", systemImage: "person.2.fill")
            }
            .tag(TabItem.people)

            NavigationStack {
                SettingsTabView(account: account, vehicleLinks: vehicleLinks)
            }
            .tabItem {
                Label("설정", systemImage: "gearshape.fill")
            }
            .tag(TabItem.settings)
        }
        .sheet(item: $rideTarget) { target in
            PlacePickerSheet(target: target, rideModel: rideRequests) {
                selectedTab = .requests
            }
        }
        .sheet(isPresented: $showingRideTracking) {
            NavigationStack {
                PickupView(tracker: rideRequests.tracking, resetLabel: "목록으로") {
                    showingRideTracking = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { showingRideTracking = false }
                    }
                }
            }
        }
        .onChange(of: rideRequests.activeRequest?.id) { _, activeId in
            if activeId == nil && rideRequests.tracking.snapshot == nil {
                showingRideTracking = false
            }
        }
        .onChange(of: vehicleLinks.navigationEventCount) { _, count in
            if count > 0 { selectedTab = .settings }
        }
        .onAppear {
            if vehicleLinks.hasPendingPairing || vehicleLinks.navigationEventCount > 0 {
                selectedTab = .settings
            }
        }
    }
}

private struct HomeTabView: View {
    @Bindable var account: AccountViewModel
    @Bindable var rideRequests: RideRequestViewModel
    @Bindable var pickup: PickupViewModel
    @Binding var inviteLink: String
    var onOpenRequests: () -> Void
    var onOpenPeople: () -> Void
    var onOpenTracking: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if rideRequests.invitedCount > 0 {
                    Button(action: onOpenRequests) {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("새 마중 초대 \(rideRequests.invitedCount)건을 확인해주세요")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("받은 초대 보기")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(14)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-invited-banner")
                }

                if let member = account.member {
                    MajungCard {
                        Text("안녕하세요, \(member.nickname) 님")
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("내 마중 ID · \(member.majungId)")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                }

                if let active = rideRequests.activeRequest {
                    activeRideCard(active)
                }

                if !rideRequests.waitingRequests.isEmpty {
                    waitingSummaryCard
                }

                MajungCard {
                    Label("운전자에게 마중 요청하기", systemImage: "person.badge.plus")
                        .font(.headline)
                    Text("사람 탭에서 닉네임·마중 ID로 지인을 찾고 만날 장소를 지정해 마중을 요청할 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("사람 찾아 마중 요청", action: onOpenPeople)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("home-open-people-button")
                }

                MajungCard {
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
        .refreshable {
            await rideRequests.refresh()
        }
    }

    private func activeRideCard(_ item: RideRequestItem) -> some View {
        MajungCard {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let vehicle = rideRequests.tracking.currentVehicle()
                let place = rideRequests.tracking.snapshot?.place ?? item.place
                let arrived = rideRequests.tracking.snapshot?.status == .arrived
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        MajungStatusPill(text: "실시간 마중 진행 중", tint: .green)
                        if let distance = MajungFormatting.distanceText(from: vehicle, to: place), !arrived {
                            MajungStatusPill(text: distance, tint: .accentColor)
                        }
                    }
                    let heading = arrived
                        ? "마중 차량이 도착했어요"
                        : MajungFormatting.etaText(vehicle)
                    Text(heading)
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Label(rideRequests.tracking.snapshot?.place?.label ?? item.place.label, systemImage: "mappin.circle.fill")
                .font(.subheadline.weight(.medium))
            if let vehicleName = rideRequests.tracking.snapshot?.vehicleName, !vehicleName.isEmpty {
                Label("\(item.nickname) 운전자 · \(vehicleName)", systemImage: "car.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                onOpenTracking()
            } label: {
                Text("픽업 보기")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("home-open-tracking-button")
        }
    }

    private var waitingSummaryCard: some View {
        MajungCard {
            HStack {
                Text("내 요청·초대 대기 목록")
                    .font(.headline)
                Spacer()
                Button("전체 보기", action: onOpenRequests)
                    .font(.footnote.weight(.semibold))
            }

            ForEach(rideRequests.waitingRequests.prefix(2)) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(item.nickname) · \(item.place.label)")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if item.status == .queued, let ahead = item.peopleAhead {
                            Text("내 앞 \(ahead)건 대기 중")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Spacer()
                    MajungStatusPill(
                        text: item.status == .invited ? "받은 초대" : item.status == .queued ? "내 차례 대기" : "수락 대기",
                        tint: item.status == .pending ? .orange : .accentColor
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct SettingsTabView: View {
    @Bindable var account: AccountViewModel
    @Bindable var vehicleLinks: VehicleLinkViewModel
    @State private var nicknameDraft = ""
    @State private var copiedId = false
    @State private var showingVehicleScanner = false
    @State private var detachingVehicle: VehicleLink?
    @State private var confirmingLogout = false

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
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section("내 차량") {
                if let active = vehicleLinks.activePairing {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            MajungStatusPill(text: "승인 대기", tint: .orange)
                            Spacer()
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = max(0, Int(active.expiresAt.timeIntervalSince(context.date)))
                                Text(String(format: "만료 %d:%02d", remaining / 60, remaining % 60))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(active.title)
                            .font(.subheadline.weight(.semibold))
                        Text(active.detailText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("요청 취소", role: .destructive) {
                            Task { await vehicleLinks.cancelActivePairing() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(vehicleLinks.busy)
                        .accessibilityIdentifier("vehicle-pairing-cancel-button")
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
            }

            if account.member != nil {
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
        .task {
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
    }
}
