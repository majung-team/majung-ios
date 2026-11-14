import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accountModel: AccountViewModel
    @State private var peopleModel: PeopleViewModel
    @State private var rideRequestModel: RideRequestViewModel
    @State private var vehicleLinkModel: VehicleLinkViewModel
    @State private var pickupModel = PickupViewModel()
    @State private var link = ""
    @State private var showingSplash = true
    @State private var pickupNavigationEventCount = 0
    @State private var backgroundGraceActive = false
    @State private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    @State private var backgroundGraceTimerTask: Task<Void, Never>?

    init() {
        let account = AccountViewModel()
        _accountModel = State(initialValue: account)
        _peopleModel = State(initialValue: PeopleViewModel(account: account))
        _rideRequestModel = State(initialValue: RideRequestViewModel(account: account))
        _vehicleLinkModel = State(initialValue: VehicleLinkViewModel(account: account))
    }

    private var isPickupSceneRunning: Bool { scenePhase == .active || backgroundGraceActive }
    private var activeSession: PickupSession? { isPickupSceneRunning ? pickupModel.session : nil }
    private var activeGuestStreamKey: String {
        "\(activeSession?.id.uuidString ?? "none")-\(isPickupSceneRunning)"
    }
    private var accountPollingKey: String { "\(accountModel.isReady)-\(isPickupSceneRunning)" }
    private var activeRideStreamKey: String {
        "\(rideRequestModel.activeRequest?.id.uuidString ?? "none")-\(isPickupSceneRunning)"
    }
    private var pendingVehiclePollingKey: String {
        "\(accountModel.isReady)-\(scenePhase == .active)-\(vehicleLinkModel.hasPendingPairing)"
    }

    var body: some View {
        Group {
            if showingSplash {
                SplashView()
            } else if pickupModel.page != .entry {
                NavigationStack {
                    switch pickupModel.page {
                    case .invitation:
                        invitation
                    case .pickup:
                        PickupView(
                            tracker: pickupModel.tracker,
                            resetLabel: "처음으로",
                            onReset: {
                                pickupModel.reset()
                            },
                            onLeaveWaiting: {
                                Task {
                                    await pickupModel.leaveWaiting()
                                    link = ""
                                }
                            }
                        )
                    case .entry:
                        EmptyView()
                    }
                }
            } else if accountModel.isReady {
                MainTabView(
                    account: accountModel,
                    people: peopleModel,
                    rideRequests: rideRequestModel,
                    vehicleLinks: vehicleLinkModel,
                    pickup: pickupModel,
                    inviteLink: $link,
                    pickupNavigationEventCount: pickupNavigationEventCount
                )
            } else if accountModel.needsNicknameSetup {
                NavigationStack {
                    NicknameSetupView(account: accountModel)
                }
            } else {
                NavigationStack {
                    LoginEntryView(
                        account: accountModel,
                        pickup: pickupModel,
                        inviteLink: $link,
                        vehiclePendingMessage: vehicleLinkModel.deferredTarget != nil
                            ? "로그인을 마치면 차량 연결을 이어서 진행할게요."
                            : nil
                    )
                }
            }
        }
        .tint(MajungBrand.blue)
        .task {
            await runLaunchSequence()
        }
        .onChange(of: accountModel.isReady) { wasReady, ready in
            if ready {
                Task {
                    await rideRequestModel.refresh(silent: true)
                    await vehicleLinkModel.load(silent: true)
                    await vehicleLinkModel.resumeDeferredIfNeeded()
                }
            } else {
                peopleModel.reset()
                rideRequestModel.reset()
                vehicleLinkModel.reset()
                if wasReady {
                    vehicleLinkModel.clearDeferred()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                endPickupBackgroundGrace()
                guard !showingSplash else { return }
                Task {
                    await restoreAccountAndLinkedState()
                    await pickupModel.refresh()
                }
            } else if phase == .background {
                if pickupModel.session != nil || rideRequestModel.activeRequest != nil {
                    beginPickupBackgroundGrace()
                } else {
                    pickupModel.tracker.clearVehicle()
                    rideRequestModel.handleSceneInactive()
                }
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            handleIncomingURL(url)
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
            guard accountModel.isReady && isPickupSceneRunning else { return }
            await pollAccountRequestsUntilInactive()
        }
        .task(id: "\(accountPollingKey)-stream") {
            guard accountModel.isReady && isPickupSceneRunning else { return }
            await rideRequestModel.runListEventStream()
        }
        .task(id: activeRideStreamKey) {
            guard isPickupSceneRunning, let requestId = rideRequestModel.activeRequest?.id else { return }
            await rideRequestModel.runEventStream(for: requestId)
        }
        .task(id: pendingVehiclePollingKey) {
            guard accountModel.isReady && scenePhase == .active && vehicleLinkModel.hasPendingPairing else { return }
            await pollPendingVehicleUntilDone()
        }
    }

    private var minimumSplashDuration: Duration {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-UITestHoldSplash") {
            return .seconds(8)
        }
        if args.contains("-UITestResetSessions") {
            return .milliseconds(150)
        }
        #endif
        return .milliseconds(1050)
    }

    private func runLaunchSequence() async {
        let shouldWaitForRestoreGrace = accountModel.storedSession != nil
            || ProcessInfo.processInfo.environment["MAJUNG_TEST_PORT"] != nil

        let restoreTask = Task {
            await restoreAccountAndLinkedState()
        }

        try? await Task.sleep(for: minimumSplashDuration)

        if shouldWaitForRestoreGrace {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { _ = await restoreTask.value }
                group.addTask { try? await Task.sleep(for: .milliseconds(800)) }
                _ = await group.next()
                group.cancelAll()
            }
        }

        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.28)) {
            showingSplash = false
        }
    }

    private func restoreAccountAndLinkedState() async {
        await accountModel.restore()
        if accountModel.isReady {
            async let rides: Void = rideRequestModel.refresh(silent: true)
            async let vehicles: Void = vehicleLinkModel.load(silent: true)
            _ = await (rides, vehicles)
            await vehicleLinkModel.resumeDeferredIfNeeded()
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme?.lowercased() == "majung", url.host?.lowercased() == "auth" { return }
        if url.scheme?.lowercased() == "majung", url.host?.lowercased() == "pickup" {
            pickupNavigationEventCount += 1
            Task {
                if pickupModel.session != nil {
                    await pickupModel.refresh()
                } else if accountModel.isReady {
                    await rideRequestModel.refresh(silent: true)
                }
            }
            return
        }
        if VehiclePairingTarget(url: url) != nil {
            Task { await vehicleLinkModel.handleIncoming(url: url) }
            return
        }
        Task { await pickupModel.openLink(url.absoluteString) }
    }

    private func beginPickupBackgroundGrace() {
        endPickupBackgroundGrace()
        backgroundGraceActive = true
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "majung.pickup.liveactivity") {
            Task { @MainActor in
                suspendPickupAfterBackgroundGrace()
            }
        }
        backgroundGraceTimerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            suspendPickupAfterBackgroundGrace()
        }
    }

    private func suspendPickupAfterBackgroundGrace() {
        guard backgroundGraceActive else { return }
        endPickupBackgroundGrace()
        if scenePhase != .active {
            pickupModel.tracker.clearVehicle()
            rideRequestModel.handleSceneInactive()
        }
    }

    private func endPickupBackgroundGrace() {
        backgroundGraceTimerTask?.cancel()
        backgroundGraceTimerTask = nil
        backgroundGraceActive = false
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }

    private func pollPendingVehicleUntilDone() async {
        #if DEBUG && targetEnvironment(simulator)
        // Keep manual-refresh UI tests independent from the automatic polling timer.
        if APIBaseURL.root.host == "localhost",
           ProcessInfo.processInfo.arguments.contains("-UITestManualVehiclePairing") {
            return
        }
        #endif
        while !Task.isCancelled && accountModel.isReady && scenePhase == .active && vehicleLinkModel.hasPendingPairing {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if !Task.isCancelled && accountModel.isReady && scenePhase == .active && vehicleLinkModel.hasPendingPairing {
                await vehicleLinkModel.pollActivePairingOnce()
            }
        }
    }

    private func refreshUntilInactive() async {
        while !Task.isCancelled && pickupModel.session != nil {
            if isPickupSceneRunning { await pickupModel.refresh() }
            let interval = pickupModel.streamConnected ? 30 : 3
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
        }
    }

    private func pollAccountRequestsUntilInactive() async {
        while !Task.isCancelled && accountModel.isReady && isPickupSceneRunning {
            let interval: Int = if rideRequestModel.activeRequest != nil {
                rideRequestModel.activeStreamConnected ? 30 : 3
            } else {
                rideRequestModel.listStreamConnected ? 30 : 10
            }
            do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            if !Task.isCancelled && accountModel.isReady && isPickupSceneRunning {
                await rideRequestModel.refresh(silent: true)
            }
        }
    }

    private var invitation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let place = pickupModel.placeLabel, !pickupModel.linkUnavailable {
                    MajungStatusPill(text: "마중 탑승 초대", tint: .accentColor)
                    Text("마중에 초대받았어요")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("만날 약속 장소")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(place, systemImage: "mappin.circle.fill")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 1)
                        Text("참여하기 전에는 개인정보 보호를 위해 차량의 현재 위치나 도착 예정 시간이 표시되지 않아요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    Button {
                        Task { await pickupModel.join() }
                    } label: {
                        Text(pickupModel.busy ? "연결 중…" : "약속에 참여하기")
                            .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pickupModel.busy)
                } else if pickupModel.busy {
                    ProgressView("초대를 확인하고 있어요")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        MajungStatusPill(
                            text: pickupModel.linkUnavailable ? "사용 불가한 초대" : "확인 지연",
                            tint: .orange
                        )
                        Text(pickupModel.linkUnavailable ? "초대를 사용할 수 없어요" : "초대를 확인하지 못했어요")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        if !pickupModel.linkUnavailable {
                            Button("다시 확인") { Task { await pickupModel.preview() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                if let error = pickupModel.error {
                    MajungStatusBanner(message: error, tint: .red)
                }
                if !pickupModel.busy {
                    Button {
                        link = ""
                        pickupModel.reset()
                    } label: {
                        Text("다른 초대 열기")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
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
