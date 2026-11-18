import SwiftUI

struct HomeTabView: View {
    @Bindable var account: AccountViewModel
    @Bindable var rideRequests: RideRequestViewModel
    @Bindable var pickup: PickupViewModel
    @Binding var inviteLink: String
    var onOpenRequests: () -> Void
    var onOpenPeople: () -> Void
    var onOpenTracking: () -> Void

    @FocusState private var inviteFieldFocused: Bool
    @State private var showingGuide = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if pickup.hasActivePickupScreen {
                    ActiveGuestPickupReturnCard(pickup: pickup)
                }
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
                    Text("먼저 사람 탭에서 운전자를 연결한 뒤, 만날 장소를 골라 요청해요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("사람 찾아 마중 요청") {
                        inviteFieldFocused = false
                        onOpenPeople()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("home-open-people-button")
                    Text("운전자라면 설정의 차량 연결에서 차량 화면의 QR을 연결해주세요. 초대받은 탑승자는 아래 링크로 참여하면 돼요.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                MajungCard {
                    Label("초대 링크로 참여하기", systemImage: "link")
                        .font(.headline)
                    Text("전달받은 초대 링크를 붙여넣어 만날 장소와 차량 도착 시간을 확인할 수 있어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("마중 초대 링크", text: $inviteLink)
                            .focused($inviteFieldFocused)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit {
                                inviteFieldFocused = false
                                if !inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !pickup.busy {
                                    Task { await pickup.openLink(inviteLink) }
                                }
                            }
                        MajungClearInputButton(text: $inviteLink, accessibilityLabel: "초대 링크 지우기")
                    }
                    .majungInputSurface()
                    HStack(spacing: 10) {
                        PasteButton(payloadType: String.self) { values in
                            guard let value = values.first else { return }
                            inviteFieldFocused = false
                            inviteLink = value
                            Task { await pickup.openLink(value) }
                        }
                        .disabled(pickup.busy)
                        Button {
                            inviteFieldFocused = false
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

                ParkingGameEntry()
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("홈")
        .majungGuideToolbar(isPresented: $showingGuide, accessibilityIdentifier: "home-guide-button")
        .majungKeyboardDismiss(isFocused: $inviteFieldFocused)
        .refreshable {
            await rideRequests.refresh()
        }
    }

    private func activeRideCard(_ item: RideRequestItem) -> some View {
        ActivePickupSummaryCard(
            item: item,
            tracking: rideRequests.tracking,
            ctaLabel: "픽업 보기",
            ctaIdentifier: "home-open-tracking-button",
            onOpen: onOpenTracking
        )
    }

    private var waitingSummaryCard: some View {
        let invitedCount = rideRequests.invitedRequests.count
        let requestCount = max(0, rideRequests.waitingRequests.count - invitedCount)
        return MajungCard {
            HStack(spacing: 8) {
                Text("내 요청·초대 대기 목록")
                    .font(.headline)
                Spacer()
                MajungStatusPill(text: "초대 \(invitedCount) · 요청 \(requestCount)", tint: .orange)
                Button("전체 보기", action: onOpenRequests)
                    .font(.footnote.weight(.semibold))
            }

            ForEach(rideRequests.waitingRequests.prefix(2)) { item in
                Button(action: onOpenRequests) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.nickname) · \(item.place.label)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
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
                .buttonStyle(.plain)
            }
        }
    }
}
