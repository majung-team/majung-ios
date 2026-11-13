import SwiftUI

struct PickupView: View {
    @Bindable var tracker: PickupTracker
    var resetLabel = "처음으로"
    var onReset: () -> Void
    var onLeaveWaiting: (() -> Void)? = nil

    @State private var notifications = PickupNotificationService()
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
                if tracker.connectionProblem {
                    Label("연결이 끊겼어요. 다시 연결하고 있어요.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                }

                if let snapshot = tracker.snapshot {
                    switch snapshot.status {
                    case .active:
                        if let place = snapshot.place { active(snapshot, place: place) }
                        else { ProgressView("만날 장소를 확인하고 있어요") }
                    case .arrived:
                        if let place = snapshot.place { arrival(snapshot, place: place) }
                        else { Text("마중 차량이 도착했어요").font(.title2.bold()) }
                        messages(snapshot)
                    case .completed, .cancelled, .expired, .inviteExpired:
                        finished(snapshot)
                    case .inviting, .waiting:
                        waitingCard(snapshot)
                    }
                } else if tracker.connectionProblem {
                    Button("다시 확인") { Task { await tracker.refresh() } }
                } else {
                    ProgressView("픽업을 불러오고 있어요")
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await tracker.refresh() }
        .navigationTitle("마중 픽업")
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
            notifications.evaluate(snapshot: tracker.snapshot, vehicle: tracker.currentVehicle())
        }
        .onChange(of: tracker.vehicle?.durationSeconds) { _, _ in
            notifications.evaluate(snapshot: tracker.snapshot, vehicle: tracker.currentVehicle())
        }
    }

    private func active(_ snapshot: PickupSnapshot, place: PickupPlace) -> some View {
        Group {
            MajungCard {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let vehicle = tracker.currentVehicle()
                    let freshness = MajungFormatting.freshnessText(
                        for: vehicle,
                        updatedAt: tracker.vehicleUpdatedAt,
                        now: context.date
                    )
                    let distance = MajungFormatting.distanceText(from: vehicle, to: place)
                    VStack(alignment: .leading, spacing: 12) {
                        if freshness != nil || distance != nil {
                            HStack(spacing: 8) {
                                if let freshness {
                                    MajungStatusPill(text: freshness, tint: .green)
                                }
                                if let distance {
                                    MajungStatusPill(text: distance, tint: .accentColor)
                                }
                            }
                        }
                        Text(MajungFormatting.etaText(vehicle)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        if let name = snapshot.vehicleName, !name.isEmpty {
                            Label(name, systemImage: "car.fill").foregroundStyle(.secondary)
                        }
                        if vehicle == nil {
                            HStack(spacing: 10) {
                                Text("차량 위치 응답을 기다리고 있어요.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("다시 확인") {
                                    Task { await tracker.refresh() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityIdentifier("pickup-retry-vehicle-button")
                            }
                        }
                        PickupMapView(place: place, vehicle: vehicle)
                    }
                }
            }
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
                            .disabled(tracker.busy)
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
                                .disabled(tracker.busy)
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
            if let participant = snapshot.participant {
                MajungCard {
                    HStack {
                        Text("내 탑승 준비 상태").font(.headline)
                        Spacer()
                        if participant.ready && participant.readinessReceivedSequence >= participant.readinessSequence {
                            Label(
                                "차량 전달됨 · #\(participant.readinessReceivedSequence)",
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
                        .disabled(tracker.busy)
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
                        .disabled(tracker.busy)
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
                            .disabled(tracker.busy)
                            .accessibilityIdentifier("pickup-resend-readiness-button")
                        }
                    }
                }
            }
            notificationCard
            messages(snapshot)
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
        }
    }

    private func waitingCard(_ snapshot: PickupSnapshot) -> some View {
        MajungCard {
            MajungStatusPill(text: "참여 요청 완료 · 운전자 확인 대기", tint: .orange)
            Text("운전자가 확인하면 실시간 화면이 열려요")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("초대 참여 의사가 차량에 전달됐어요. 운전자가 픽업을 시작하면 실시간 차량 위치와 도착 예정 시간을 볼 수 있어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let place = snapshot.place {
                Label(place.label, systemImage: "mappin.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 10) {
                Button {
                    Task { await tracker.refresh() }
                } label: {
                    Text("상태 새로고침")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracker.busy)
                .accessibilityIdentifier("pickup-waiting-refresh-button")

                if onLeaveWaiting != nil {
                    Button("다른 초대 열기", role: .destructive) {
                        confirmingLeaveWaiting = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(tracker.busy)
                    .accessibilityIdentifier("pickup-waiting-leave-button")
                }
            }
        }
    }

    private func arrival(_ snapshot: PickupSnapshot, place: PickupPlace) -> some View {
        MajungCard {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                MajungStatusPill(text: "차량 도착 완료", tint: .green)
                Text("마중 차량이 도착했어요")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("약속 장소에서 차량 번호와 차종을 확인하고 탑승해주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("만날 약속 장소")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(place.label, systemImage: "mappin.circle.fill")
                    .font(.headline)
                if let name = snapshot.vehicleName, !name.isEmpty {
                    Divider()
                    Label(name, systemImage: "car.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            Button {
                showArrivalMap.toggle()
            } label: {
                Text(showArrivalMap ? "지도 닫기" : "지도에서 차량 보기")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)

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
                        Button(text) { tracker.messageDraft = text }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(tracker.messageDraft == text ? .accentColor : .secondary)
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                TextField("직접 메시지 입력 (최대 50자)", text: $tracker.messageDraft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.send)
                    .focused($messageFocused)
                    .onSubmit { sendMessage() }
                Button("전송") { sendMessage() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        tracker.busy ||
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
        messageFocused = false
        Task { await tracker.sendMessage() }
    }

    private func finished(_ snapshot: PickupSnapshot) -> some View {
        let summaryPlace = snapshot.place ?? tracker.lastPlace
        let summaryVehicle = (snapshot.vehicleName?.isEmpty == false ? snapshot.vehicleName : nil) ?? tracker.lastVehicleName
        let isCompleted = snapshot.status == .completed
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                MajungStatusPill(
                    text: isCompleted ? "방금 완료된 픽업" : snapshot.status == .cancelled ? "픽업 취소됨" : "픽업 만료됨",
                    tint: isCompleted ? .green : .orange
                )
                Spacer()
                Text("위치 공유 종료")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isCompleted ? .green : .secondary)
            }
            Text(
                isCompleted ? "잘 만났어요!" :
                snapshot.status == .cancelled ? "픽업이 취소됐어요" : "픽업 시간이 지났어요"
            )
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
            Text("개인정보 보호를 위해 차량 위치 공유가 즉시 종료됐어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if summaryPlace != nil || summaryVehicle != nil {
                Divider()
                if let summaryPlace {
                    Label(summaryPlace.label, systemImage: "mappin.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                if let summaryVehicle {
                    Label(summaryVehicle, systemImage: "car.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: onReset) {
                Text(resetLabel)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCompleted ? .green : .accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            isCompleted ? Color.green.opacity(0.08) : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            if isCompleted {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.green.opacity(0.28), lineWidth: 1)
            }
        }
    }
}
