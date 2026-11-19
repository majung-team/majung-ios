import SwiftUI

struct PickupView: View {
    @Bindable var tracker: PickupTracker
    var resetLabel = "처음으로"
    var onReset: () -> Void
    var isLeavingWaiting = false
    var onLeaveWaiting: (() -> Void)? = nil

    @State private var notifications = PickupNotificationService.shared
    @State private var editingPlace = false
    @State private var showArrivalMap = false
    @State private var confirmingLeaveWaiting = false
    @FocusState private var messageFocused: Bool

    private var alertToggleBinding: Binding<Bool> {
        Binding(
            get: { notifications.enabled },
            set: { newValue in
                Task {
                    await notifications.setEnabled(newValue)
                    notifications.evaluate(snapshot: tracker.snapshot, vehicle: tracker.currentVehicle())
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = tracker.error { Text(error).foregroundStyle(.red) }
                if let snapshot = tracker.snapshot, !snapshot.status.ended { connectionStatus }

                if let snapshot = tracker.snapshot {
                    switch snapshot.status {
                    case .active:
                        if let place = snapshot.place { active(snapshot, place: place) }
                        else { PickupLoadingCard(message: "만날 장소를 확인하고 있어요") }
                    case .arrived:
                        if let place = snapshot.place { arrival(snapshot, place: place) }
                        else {
                            MajungCard {
                                Text("마중 차량이 도착했어요")
                                    .font(.title2.bold())
                            }
                        }
                        messages(snapshot)
                    case .completed, .cancelled, .expired, .inviteExpired:
                        PickupFinishedCard(
                            status: snapshot.status,
                            summaryPlace: snapshot.place ?? tracker.lastPlace,
                            summaryVehicle: (snapshot.vehicleName?.isEmpty == false ? snapshot.vehicleName : nil) ?? tracker.lastVehicleName,
                            resetLabel: resetLabel,
                            onReset: onReset
                        )
                    case .inviting, .waiting:
                        PickupWaitingCard(
                            snapshot: snapshot,
                            busy: tracker.busy || isLeavingWaiting,
                            isRefreshing: tracker.isRefreshing,
                            connectionProblem: tracker.connectionProblem,
                            onRefresh: { Task { await tracker.refresh() } },
                            onRequestLeave: onLeaveWaiting == nil ? nil : { confirmingLeaveWaiting = true }
                        )
                    }
                } else if tracker.connectionProblem {
                    MajungCard {
                        Text("픽업 상태를 아직 확인하지 못했어요")
                            .font(.headline)
                        Text("네트워크 연결을 확인한 뒤 다시 시도해주세요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await tracker.refresh() }
                        } label: {
                            Text("다시 확인")
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    PickupLoadingCard(message: "픽업을 불러오고 있어요")
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .majungKeyboardDismiss(isFocused: $messageFocused)
        .refreshable { await tracker.refresh() }
        .navigationTitle("마중 픽업")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ParkingGameEntry(tracker: tracker, compact: true)
            }
        }
        .sheet(isPresented: $editingPlace) {
            if let place = tracker.snapshot?.place {
                PlaceProposalView(
                    meetingPlace: place,
                    activeProposal: tracker.snapshot?.placeProposal,
                    tracker: tracker
                )
            }
        }
        .alert("초대 참여 대기를 나갈까요?", isPresented: $confirmingLeaveWaiting) {
            Button("나가기", role: .destructive) {
                onLeaveWaiting?()
            }
            Button("계속 기다리기", role: .cancel) {}
        } message: {
            Text("대기 화면을 나가도 운전자가 아직 승인하지 않았다면 새 초대 링크로 다시 열 수 있어요.")
        }
        .task {
            await notifications.refreshStatus()
            notifications.evaluate(snapshot: tracker.snapshot, vehicle: tracker.currentVehicle())
        }
        .onChange(of: tracker.snapshot?.status) { _, status in
            if status != .active { editingPlace = false }
            if status != .active && status != .arrived { messageFocused = false }
            notifications.evaluate(snapshot: tracker.snapshot, vehicle: tracker.currentVehicle())
        }
        .onChange(of: tracker.vehicle?.durationSeconds) { _, _ in
            notifications.evaluate(snapshot: tracker.snapshot, vehicle: tracker.currentVehicle())
        }
    }

    private func active(_ snapshot: PickupSnapshot, place: PickupPlace) -> some View {
        Group {
            pickupOverview(snapshot)
            if let participant = snapshot.participant {
                MajungCard {
                    HStack {
                        Text("내 탑승 준비 상태").font(.headline)
                        Spacer()
                        if participant.ready && participant.readinessReceivedSequence >= participant.readinessSequence {
                            Label(
                                "차량에 전달됐어요",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await tracker.setReady(false) }
                        } label: {
                            Text("준비 중")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(participant.ready ? Color(.tertiarySystemFill) : Color.accentColor)
                        .foregroundStyle(participant.ready ? Color.secondary : Color.white)
                        .disabled(tracker.busy || tracker.connectionProblem)
                        .accessibilityIdentifier("pickup-readiness-preparing-button")

                        Button {
                            Task { await tracker.setReady(true) }
                        } label: {
                            Text("탑승 준비 완료")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(participant.ready ? .green : Color(.tertiarySystemFill))
                        .foregroundStyle(participant.ready ? Color.white : Color.secondary)
                        .disabled(tracker.busy || tracker.connectionProblem)
                        .accessibilityIdentifier("pickup-readiness-ready-button")
                    }

                    if participant.ready && participant.readinessReceivedSequence < participant.readinessSequence {
                        HStack(spacing: 8) {
                            Text("차량 앱에서 확인 중이에요.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("다시 보내기") {
                                Task { await tracker.resendReady() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(tracker.busy || tracker.connectionProblem)
                            .accessibilityIdentifier("pickup-resend-readiness-button")
                        }
                    }
                }
            }
            messages(snapshot)
            meetingPlace(snapshot, place: place)
            MajungCard {
                DisclosureGroup("지도에서 만날 장소와 차량 보기") {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        PickupMapView(place: place, vehicle: tracker.currentVehicle())
                    }
                }
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("pickup-map-disclosure")
            }
            notificationCard
        }
    }

    private func meetingPlace(_ snapshot: PickupSnapshot, place: PickupPlace) -> some View {
        MajungCard {
            HStack {
                Text("현재 확정된 만날 장소")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot.placeProposal?.isPassenger != true {
                    Button("다른 장소 제안") {
                        messageFocused = false
                        editingPlace = true
                    }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(tracker.busy || tracker.connectionProblem)
                        .accessibilityIdentifier("pickup-propose-place-button")
                }
            }
            Label(place.label, systemImage: "mappin.circle.fill").font(.headline)
            if let proposal = snapshot.placeProposal {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(proposal.isPassenger ? "내가 제안한 장소" : "운전자가 제안한 장소")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        MajungStatusPill(
                            text: proposal.isPassenger ? "운전자 확인 대기" : "운전자 제안",
                            tint: proposal.isPassenger ? .orange : .accentColor
                        )
                    }
                    Text(proposal.place.label).font(.headline)
                    Text("새 장소가 확정될 때까지 위에 표시된 장소에서 만나요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if proposal.isPassenger {
                        HStack {
                            Button("제안 취소", role: .destructive) {
                                Task { await tracker.withdrawProposal() }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                            .disabled(tracker.busy || tracker.connectionProblem)
                            .accessibilityIdentifier("pickup-withdraw-proposal-button")
                            Spacer()
                        }
                    }
                }
                .padding(10)
                .background(
                    (proposal.isPassenger ? Color.orange : Color.accentColor).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
    }

    private func pickupOverview(_ snapshot: PickupSnapshot) -> some View {
        MajungCard {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let vehicle = tracker.currentVehicle()
                let approachingSoon = MajungFormatting.isApproachingSoon(vehicle)
                let resolvedVehicleName = (snapshot.vehicleName?.isEmpty == false ? snapshot.vehicleName : nil) ?? tracker.lastVehicleName
                let checkedText = MajungFormatting.lastCheckedText(
                    updatedAt: tracker.vehicleUpdatedAt,
                    refreshedAt: tracker.lastRefreshedAt,
                    now: context.date
                )
                VStack(alignment: .leading, spacing: 12) {
                    MajungStatusPill(
                        text: vehicle == nil ? "차량 정보 갱신 대기" : (approachingSoon ? "도착 직전 · 차량·장소 확인" : "픽업 진행 중"),
                        tint: vehicle == nil ? .orange : (approachingSoon ? .green : .accentColor)
                    )
                    Text(MajungFormatting.etaText(vehicle))
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("pickup-eta-summary")
                    if approachingSoon, let place = snapshot.place {
                        PickupPlaceSummaryBox(
                            caption: "곧 만날 장소 · 탑승할 차량",
                            placeName: place.label,
                            vehicleName: resolvedVehicleName ?? "연결된 마중 차량",
                            prominent: true,
                            lastCheckedText: checkedText,
                            place: place,
                            showPlaceActions: true
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("pickup-approaching-card")
                    } else {
                        if let name = resolvedVehicleName, !name.isEmpty {
                            Label(name, systemImage: "car.fill").foregroundStyle(.secondary)
                        }
                        if let place = snapshot.place {
                            Label(place.label, systemImage: "mappin.circle.fill").font(.subheadline.weight(.medium))
                        }
                        if let checkedText {
                            Label(checkedText, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("pickup-last-checked-time")
                        }
                    }
                    Text(nextAction(for: snapshot, hasVehicle: vehicle != nil))
                        .font(.subheadline)
                        .accessibilityIdentifier("pickup-next-action")
                    if let place = snapshot.place, let distance = MajungFormatting.distanceText(from: vehicle, to: place) {
                        Text(distance).font(.caption).foregroundStyle(.secondary)
                    }
                    if let freshness = MajungFormatting.freshnessText(for: vehicle, updatedAt: tracker.vehicleUpdatedAt, now: context.date) {
                        Text(freshness).font(.caption).foregroundStyle(.secondary)
                    }
                    if vehicle == nil && !tracker.connectionProblem {
                        Button("차량 정보 다시 확인") { Task { await tracker.refresh() } }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(tracker.isRefreshing)
                            .accessibilityIdentifier("pickup-retry-vehicle-button")
                    }
                }
            }
        }
    }

    private func nextAction(for snapshot: PickupSnapshot, hasVehicle: Bool) -> String {
        guard hasVehicle else { return "도착 시간이 확인되면 여기에 표시돼요. 만날 장소와 차량을 먼저 확인해주세요." }
        guard let participant = snapshot.participant, participant.ready else {
            return "탑승 준비를 마치면 아래에서 ‘탑승 준비 완료’를 눌러주세요."
        }
        return participant.readinessReceivedSequence >= participant.readinessSequence
            ? "준비 완료가 차량에 전달됐어요. 약속 장소를 확인하며 기다려주세요."
            : "준비 완료를 보냈어요. 차량에 전달됐는지 확인하고 있어요."
    }

    private var connectionStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if tracker.connectionProblem {
                MajungCard {
                    Label("최신 정보를 확인하지 못했어요", systemImage: "wifi.slash")
                        .font(.headline).foregroundStyle(.orange)
                    Text("자동으로 다시 확인하고 있어요. 아래 내용은 마지막으로 확인한 픽업 상태예요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let date = tracker.lastRefreshedAt {
                        Text("픽업 상태 마지막 확인 · \(MajungFormatting.shortTime(date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(tracker.isRefreshing ? "확인 중…" : "지금 다시 확인") {
                        Task { await tracker.refresh() }
                    }
                    .buttonStyle(.bordered).disabled(tracker.isRefreshing)
                    .accessibilityIdentifier("pickup-reconnect-button")
                }
            } else if let recovered = tracker.reconnectedAt, context.date.timeIntervalSince(recovered) < 5 {
                Label("다시 연결됐어요. 최신 픽업 상태를 확인했어요.", systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
                    .accessibilityIdentifier("pickup-reconnected-status")
            }
        }
    }

    private var notificationCard: some View {
        MajungCard {
            Toggle(isOn: alertToggleBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("도착 전·차량 도착 알림", systemImage: "bell.badge.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("도착 약 3분 전과 차량 도착 시 알림으로 알려드려요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("pickup-arrival-alert-toggle")

            if let statusNote = notifications.statusNote {
                Text(statusNote)
                    .font(.footnote)
                    .foregroundStyle(notifications.permissionDenied ? .red : .secondary)
            }

            Label(
                "앱 밖에서는 다이나믹 아일랜드와 잠금화면에 마지막 도착 정보가 표시돼요. 갱신이 필요하면 앱을 다시 열어주세요.",
                systemImage: "platter.filled.top.iphone"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("pickup-live-activity-note")
        }
    }

    private func arrival(_ snapshot: PickupSnapshot, place: PickupPlace) -> some View {
        MajungCard {
            PickupStatusHeroHeader(
                symbol: "checkmark.circle.fill",
                tint: .green,
                pillText: "차량 도착 완료",
                title: "마중 차량이 도착했어요",
                subtitle: "약속 장소에서 차량 번호와 차종을 확인하고 탑승해주세요."
            )

            let resolvedVehicleName = (snapshot.vehicleName?.isEmpty == false ? snapshot.vehicleName : nil) ?? tracker.lastVehicleName
            PickupPlaceSummaryBox(
                caption: "만날 약속 장소",
                placeName: place.label,
                vehicleName: resolvedVehicleName ?? "연결된 마중 차량",
                prominent: true,
                lastCheckedText: MajungFormatting.lastCheckedText(
                    updatedAt: tracker.vehicleUpdatedAt,
                    refreshedAt: tracker.lastRefreshedAt
                ),
                place: place,
                showPlaceActions: true
            )

            if tracker.arrivalBoardingNotified || snapshot.quickMessage?.text == "차량 확인했어요, 지금 탑승해요" {
                Label("차량 확인을 운전자에게 알렸어요. 탑승 후 차량에서 완료하면 위치 공유가 바로 종료돼요.", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("pickup-arrival-boarded-note")
            } else {
                Button {
                    messageFocused = false
                    Task { await tracker.notifyArrivalBoarding() }
                } label: {
                    Label("차량 확인 · 지금 탑승할게요", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(tracker.busy || tracker.connectionProblem)
                .accessibilityIdentifier("pickup-arrival-board-button")
            }

            Button {
                showArrivalMap.toggle()
            } label: {
                Text(showArrivalMap ? "지도 닫기" : "지도에서 차량 보기")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered)

            if showArrivalMap {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let vehicle = tracker.currentVehicle()
                    PickupMapView(place: place, vehicle: vehicle)
                    if vehicle?.latitude == nil || vehicle?.longitude == nil {
                        Text("차량 위치를 확인할 수 없어요. 지도에 만날 장소를 표시했어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func messages(_ snapshot: PickupSnapshot) -> some View {
        MajungCard {
            HStack {
                Text("운전자에게 빠른 메시지").font(.headline)
                Spacer()
                Text("\(tracker.messageDraft.utf16.count)/50자")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(tracker.messageDraft.utf16.count > 50 ? Color.red : Color.secondary)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(["지금 내려가요", "입구 앞이에요", "곧 도착해요"], id: \.self) { text in
                        Button(text) {
                            dismissMajungKeyboard {
                                messageFocused = false
                            }
                            tracker.messageDraft = text
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(tracker.messageDraft == text ? .accentColor : .secondary)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("직접 메시지 입력 (최대 50자)", text: $tracker.messageDraft)
                        .submitLabel(.send)
                        .focused($messageFocused)
                        .onSubmit { sendMessage() }

                    MajungClearInputButton(text: $tracker.messageDraft, accessibilityLabel: "메시지 지우기")
                }
                .majungInputSurface(cornerRadius: 10)
                Button("전송") { sendMessage() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        tracker.busy || tracker.connectionProblem ||
                        tracker.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        tracker.messageDraft.utf16.count > 50
                    )
                    .accessibilityIdentifier("pickup-message-send-button")
            }
            if let recent = snapshot.quickMessage, !recent.text.isEmpty {
                Label("보낸 메시지 · \(recent.text)", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else if tracker.messageSent {
                Label("메시지를 보냈어요.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
    }

    private func sendMessage() {
        guard !tracker.busy, !tracker.connectionProblem else { return }
        dismissMajungKeyboard {
            messageFocused = false
        }
        Task { await tracker.sendMessage() }
    }

}
