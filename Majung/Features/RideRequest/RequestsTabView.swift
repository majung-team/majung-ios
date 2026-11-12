import SwiftUI

struct RequestsTabView: View {
    @Bindable var rideModel: RideRequestViewModel
    var onOpenPeople: () -> Void
    var onOpenTracking: () -> Void

    @State private var filter: RequestFilter = .waiting
    @State private var pendingAction: PendingRideAction?

    private enum RequestFilter: String, CaseIterable {
        case waiting = "대기·초대"
        case queue = "내 차례 대기"
        case history = "지난 내역"
    }

    private struct PendingRideAction: Identifiable {
        let item: RideRequestItem
        let kind: Kind

        enum Kind {
            case acceptInvitation
            case rejectInvitation
            case cancelRequest
        }

        var id: String { "\(item.id.uuidString)-\(kind)" }

        var title: String {
            switch kind {
            case .acceptInvitation: "이 초대를 수락할까요?"
            case .rejectInvitation: "이 초대를 거절할까요?"
            case .cancelRequest: "정말 이 마중 요청을 취소할까요?"
            }
        }

        var message: String {
            switch kind {
            case .acceptInvitation:
                "수락하면 픽업 대기에 들어가요. 내 픽업이 시작되기 전에는 차량 위치가 공유되지 않아요."
            case .rejectInvitation:
                "\(item.nickname) 님의 초대를 거절하면 이 초대로 탑승할 수 없어요."
            case .cancelRequest:
                if item.status == .queued, let ahead = item.peopleAhead {
                    "취소하면 대기 순서(\(ahead + 1)번째)가 즉시 해제돼요."
                } else {
                    "\(item.nickname) 님께 보낸 마중 요청을 취소해요."
                }
            }
        }

        var confirmLabel: String {
            switch kind {
            case .acceptInvitation: "이 장소에서 탈게요"
            case .rejectInvitation: "초대 거절하기"
            case .cancelRequest: "요청 취소하기"
            }
        }

        var isDestructive: Bool {
            kind != .acceptInvitation
        }
    }

    private var displayedItems: [RideRequestItem] {
        switch filter {
        case .waiting: rideModel.pendingOrInvitedRequests
        case .queue: rideModel.queuedRequests
        case .history: rideModel.terminalRequests
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let notice = rideModel.notice {
                    MajungStatusBanner(message: notice, tint: .green)
                }
                if let error = rideModel.error {
                    MajungStatusBanner(message: error, tint: .red)
                }

                if let active = rideModel.activeRequest {
                    activeRideCard(active)
                }

                Picker("요청 필터", selection: $filter) {
                    Text("대기·초대 (\(rideModel.pendingOrInvitedRequests.count))").tag(RequestFilter.waiting)
                    Text("내 차례 대기 (\(rideModel.queuedRequests.count))").tag(RequestFilter.queue)
                    Text("지난 내역 (\(rideModel.terminalRequests.count))").tag(RequestFilter.history)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("requests-filter-picker")

                if displayedItems.isEmpty {
                    emptyCard
                } else {
                    ForEach(displayedItems) { item in
                        rideCard(item)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("내 요청·초대")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(rideModel.loading ? "확인 중" : "새로 확인") {
                    Task { await rideModel.refresh() }
                }
                .disabled(rideModel.loading || rideModel.busy)
                .accessibilityIdentifier("requests-refresh-button")
            }
        }
        .refreshable {
            await rideModel.refresh()
        }
        .task {
            await rideModel.refresh(silent: true)
        }
        .alert(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            presenting: pendingAction
        ) { target in
            Button(target.confirmLabel, role: target.isDestructive ? .destructive : nil) {
                Task {
                    switch target.kind {
                    case .acceptInvitation:
                        let nextStatus = await rideModel.answerInvitation(target.item, accept: true)
                        if nextStatus == .queued {
                            filter = .queue
                        }
                    case .rejectInvitation:
                        await rideModel.answerInvitation(target.item, accept: false)
                    case .cancelRequest:
                        await rideModel.cancelRequest(target.item)
                    }
                }
            }
            Button("돌아가기", role: .cancel) {}
        } message: { target in
            Text(target.message)
        }
    }

    private func activeRideCard(_ item: RideRequestItem) -> some View {
        ActivePickupSummaryCard(
            item: item,
            tracking: rideModel.tracking,
            ctaLabel: "실시간 픽업 보기",
            ctaIdentifier: "requests-open-tracking",
            trailingMeta: item.majungId,
            onOpen: onOpenTracking
        )
    }

    private func rideCard(_ item: RideRequestItem) -> some View {
        MajungCard {
            HStack {
                MajungStatusPill(text: item.status.label, tint: statusTint(item.status))
                Spacer()
                if item.status == .invited {
                    Text("\(MajungFormatting.shortTime(item.expiresAt))까지 응답")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if item.status == .pending {
                    Text("\(MajungFormatting.shortTime(item.expiresAt)) 만료")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                MajungMonogram(name: item.nickname, tint: statusTint(item.status))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headingText(for: item))
                        .font(.subheadline.weight(.semibold))
                    if let summary = item.vehicleDisplaySummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let majungId = item.majungId {
                        Text(majungId)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.driverInvitation ? "운전자가 제안한 장소" : "내가 요청한 장소")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(item.place.label, systemImage: "mappin.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            if item.status == .invited {
                Text("수락해도 내 픽업이 시작되기 전에는 차량 위치가 공유되지 않아요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        pendingAction = PendingRideAction(item: item, kind: .acceptInvitation)
                    } label: {
                        Text("이 장소에서 탈게요")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(rideModel.busy)
                    .accessibilityIdentifier("requests-accept-invitation")

                    Button("초대 거절") {
                        pendingAction = PendingRideAction(item: item, kind: .rejectInvitation)
                    }
                    .buttonStyle(.bordered)
                    .disabled(rideModel.busy)
                    .accessibilityIdentifier("requests-reject-invitation")
                }
            } else if item.status == .pending {
                Text("내 픽업이 시작돼야 차량 위치와 도착 예정 시간이 공개돼요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if item.status == .queued {
                queueSummaryBox(item)
            }

            if item.status.canCancel {
                Button("마중 요청 취소", role: .destructive) {
                    pendingAction = PendingRideAction(item: item, kind: .cancelRequest)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .disabled(rideModel.busy)
                .accessibilityIdentifier("requests-cancel-button")
            }
        }
    }

    private func queueSummaryBox(_ item: RideRequestItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let ahead = item.peopleAhead ?? 0
            Text("내 앞에 \(ahead)건 진행 중 · 순번 #\(ahead + 1)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let remaining = rideModel.remainingSeconds(for: item, at: .now) {
                    Text("앞선 픽업 장소까지 \(MajungFormatting.minutesText(seconds: remaining)) (내 도착 시간 아님)")
                        .font(.footnote)
                } else {
                    Text("앞선 픽업의 남은 시간을 확인하지 못했어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text("다른 탑승자의 위치와 장소는 비공개로 보호돼요. 앞선 픽업이 끝나면 내 픽업을 시작해요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyCard: some View {
        MajungCard {
            switch filter {
            case .waiting:
                Text("대기 중인 초대나 요청이 없어요")
                    .font(.headline)
                Text("운전자를 찾고 만날 장소를 보내면 여기에 실시간 대기 상태가 표시돼요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("운전자 찾아 마중 요청", action: onOpenPeople)
                    .buttonStyle(.borderedProminent)
            case .queue:
                Text("내 차례 대기 중인 요청이 없어요")
                    .font(.headline)
                Text("운전자가 요청을 수락하면 내 앞 대기 순번을 확인할 수 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .history:
                Text("완료되거나 종료된 요청이 없어요")
                    .font(.headline)
            }
        }
    }

    private func headingText(for item: RideRequestItem) -> String {
        switch item.status {
        case .invited: "\(item.nickname) 님이 마중에 초대했어요"
        case .pending: "\(item.nickname) 님의 수락을 기다리고 있어요"
        case .queued: "\(item.nickname) 님이 요청을 수락했어요"
        case .active: "\(item.nickname) 님과 픽업 진행 중"
        case .completed, .cancelled, .rejected, .expired, .unknown: item.nickname
        }
    }

    private func statusTint(_ status: RideRequestItem.Status) -> Color {
        switch status {
        case .active, .completed: .green
        case .invited, .queued: .accentColor
        case .pending: .orange
        case .cancelled, .rejected, .expired, .unknown: .secondary
        }
    }
}
