import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var accountModel: AccountViewModel
    @State private var peopleModel: PeopleViewModel
    @State private var rideRequestModel: RideRequestViewModel
    @State private var pickupModel = PickupViewModel()
    @State private var link = ""

    init() {
        let account = AccountViewModel()
        _accountModel = State(initialValue: account)
        _peopleModel = State(initialValue: PeopleViewModel(account: account))
        _rideRequestModel = State(initialValue: RideRequestViewModel(account: account))
    }

    private var activeSession: PickupSession? { scenePhase == .active ? pickupModel.session : nil }
    private var activeGuestStreamKey: String {
        "\(activeSession?.id.uuidString ?? "none")-\(scenePhase == .active)"
    }
    private var accountPollingKey: String { "\(accountModel.isReady)-\(scenePhase == .active)" }
    private var activeRideStreamKey: String {
        "\(rideRequestModel.activeRequest?.id.uuidString ?? "none")-\(scenePhase == .active)"
    }

    var body: some View {
        Group {
            if pickupModel.page != .entry {
                NavigationStack {
                    switch pickupModel.page {
                    case .invitation:
                        invitation
                    case .pickup:
                        PickupView(tracker: pickupModel.tracker, resetLabel: "처음으로") {
                            pickupModel.reset()
                        }
                    case .entry:
                        EmptyView()
                    }
                }
            } else if accountModel.isReady {
                MainTabView(
                    account: accountModel,
                    people: peopleModel,
                    rideRequests: rideRequestModel,
                    pickup: pickupModel,
                    inviteLink: $link
                )
            } else if accountModel.needsNicknameSetup {
                NavigationStack {
                    NicknameSetupView(account: accountModel)
                }
            } else {
                NavigationStack {
                    LoginEntryView(account: accountModel, pickup: pickupModel, inviteLink: $link)
                }
            }
        }
        .tint(Color(red: 0.10, green: 0.39, blue: 0.85))
        .task {
            await accountModel.restore()
            if accountModel.isReady {
                await rideRequestModel.refresh(silent: true)
            }
        }
        .onChange(of: accountModel.isReady) { _, ready in
            if ready {
                Task { await rideRequestModel.refresh(silent: true) }
            } else {
                peopleModel.reset()
                rideRequestModel.reset()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await accountModel.restore()
                    if accountModel.isReady {
                        await rideRequestModel.refresh(silent: true)
                    }
                }
            } else {
                pickupModel.tracker.clearVehicle()
                rideRequestModel.handleSceneInactive()
            }
        }
        .onOpenURL { url in
            if url.scheme?.lowercased() == "majung", url.host?.lowercased() == "auth" { return }
            Task { await pickupModel.openLink(url.absoluteString) }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            Task { await pickupModel.openLink(url.absoluteString) }
        }
        .task(id: activeSession) {
            guard activeSession != nil else { return }
            await refreshUntilInactive()
        }
        .task(id: activeGuestStreamKey) {
            guard let session = activeSession else { return }
            await pickupModel.runEventStream(for: session.id)
        }
        .task(id: accountPollingKey) {
            guard accountModel.isReady && scenePhase == .active else { return }
            await pollAccountRequestsUntilInactive()
        }
        .task(id: activeRideStreamKey) {
            guard scenePhase == .active, let requestId = rideRequestModel.activeRequest?.id else { return }
            await rideRequestModel.runEventStream(for: requestId)
        }
    }

    private func refreshUntilInactive() async {
        while !Task.isCancelled && pickupModel.session != nil {
            if scenePhase == .active { await pickupModel.refresh() }
            let interval = pickupModel.streamConnected ? 30 : 3
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
        }
    }

    private func pollAccountRequestsUntilInactive() async {
        while !Task.isCancelled && accountModel.isReady && scenePhase == .active {
            let interval: Int = if rideRequestModel.activeRequest != nil {
                rideRequestModel.activeStreamConnected ? 30 : 3
            } else {
                10
            }
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            if !Task.isCancelled && accountModel.isReady && scenePhase == .active {
                await rideRequestModel.refresh(silent: true)
            }
        }
    }

    private var invitation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let place = pickupModel.placeLabel, !pickupModel.linkUnavailable {
                    Text("마중에 초대받았어요").font(.title2.bold())
                    Label(place, systemImage: "mappin.circle.fill").font(.headline)
                    Text("참여하면 차량 위치와 도착 예정 시간을 확인하고, 준비 상태를 운전자에게 알릴 수 있어요.")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await pickupModel.join() }
                    } label: {
                        Text(pickupModel.busy ? "연결 중…" : "약속에 참여하기")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pickupModel.busy)
                } else if pickupModel.busy {
                    ProgressView("초대를 확인하고 있어요")
                } else {
                    Text(pickupModel.linkUnavailable ? "초대를 사용할 수 없어요" : "초대를 확인하지 못했어요")
                        .font(.title2.bold())
                    if !pickupModel.linkUnavailable {
                        Button("다시 확인") { Task { await pickupModel.preview() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if let error = pickupModel.error { Text(error).foregroundStyle(.red) }
                if !pickupModel.busy {
                    Button("다른 초대 열기") {
                        link = ""
                        pickupModel.reset()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("마중 초대 확인")
        .navigationBarTitleDisplayMode(.inline)
    }
}
