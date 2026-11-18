import SwiftUI

struct PickupWaitingCard: View {
    let snapshot: PickupSnapshot
    let busy: Bool
    let isRefreshing: Bool
    let connectionProblem: Bool
    let onRefresh: () -> Void
    let onRequestLeave: (() -> Void)?

    var body: some View {
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
                Button(action: onRefresh) {
                    Text("상태 새로고침")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || isRefreshing)
                .accessibilityIdentifier("pickup-waiting-refresh-button")

                if let onRequestLeave {
                    Button("다른 초대 열기", role: .destructive, action: onRequestLeave)
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(busy || connectionProblem)
                        .accessibilityIdentifier("pickup-waiting-leave-button")
                }
            }
        }
    }
}

struct PickupFinishedCard: View {
    let status: PickupSnapshot.Status
    let summaryPlace: PickupPlace?
    let summaryVehicle: String?
    let resetLabel: String
    let onReset: () -> Void

    private var display: (symbol: String, tint: Color, pillText: String, title: String, subtitle: String) {
        let subtitle = "개인정보 보호를 위해 차량 위치 공유가 즉시 종료됐어요."
        switch status {
        case .completed:
            return ("checkmark.circle.fill", .green, "위치 공유 종료", "잘 만났어요!", subtitle)
        case .cancelled:
            return ("xmark.circle.fill", .orange, "픽업 취소 · 공유 종료", "픽업이 취소됐어요", subtitle)
        default:
            return ("clock.badge.exclamationmark", .orange, "픽업 만료 · 공유 종료", "픽업 시간이 지났어요", subtitle)
        }
    }

    var body: some View {
        let state = display
        MajungCard {
            PickupStatusHeroHeader(
                symbol: state.symbol,
                tint: state.tint,
                pillText: state.pillText,
                title: state.title,
                subtitle: state.subtitle
            )

            if summaryPlace != nil || summaryVehicle != nil {
                PickupPlaceSummaryBox(
                    caption: summaryPlace != nil ? "약속했던 장소" : "이용한 차량",
                    placeName: summaryPlace?.label,
                    vehicleName: summaryVehicle
                )
            }

            Button(action: onReset) {
                Text(resetLabel)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct PickupStatusHeroHeader: View {
    let symbol: String
    let tint: Color
    let pillText: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            MajungStatusPill(text: pillText, tint: tint)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct PickupPlaceSummaryBox: View {
    let caption: String
    let placeName: String?
    let vehicleName: String?
    var prominent: Bool = false
    var lastCheckedText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 10 : 8) {
            Text(caption)
                .font(.caption.weight(prominent ? .semibold : .regular))
                .foregroundStyle(.secondary)
            if let placeName {
                Label(placeName, systemImage: "mappin.circle.fill")
                    .font(prominent ? .title3.bold() : .headline)
            }
            if let vehicleName, !vehicleName.isEmpty {
                if placeName != nil { Divider() }
                Label(vehicleName, systemImage: "car.fill")
                    .font(prominent ? .headline.weight(.bold) : .subheadline.weight(.bold))
                    .padding(.horizontal, prominent ? 12 : 10)
                    .padding(.vertical, prominent ? 8 : 6)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: prominent ? 10 : 8))
            }
            if let lastCheckedText, !lastCheckedText.isEmpty {
                Label(lastCheckedText, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pickup-last-checked-time")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(prominent ? 14 : 12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PickupLoadingCard: View {
    let message: String

    var body: some View {
        MajungCard {
            ProgressView(message)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }
}

struct ActiveGuestPickupReturnCard: View {
    @Bindable var pickup: PickupViewModel

    private var badge: (text: String, tint: Color) {
        switch pickup.tracker.snapshot?.status {
        case .arrived: ("차량 도착 완료", .green)
        case .waiting, .inviting: ("운전자 확인 대기", .orange)
        default: ("초대 픽업 진행 중", .accentColor)
        }
    }

    private var statusDetail: String {
        switch pickup.tracker.snapshot?.status {
        case .arrived:
            return "차량이 도착했어요. 차량 번호를 확인해주세요."
        case .waiting, .inviting:
            return "운전자가 확인하면 실시간 위치를 볼 수 있어요."
        default:
            return MajungFormatting.etaText(pickup.tracker.currentVehicle())
        }
    }

    var body: some View {
        MajungCard {
            let currentBadge = badge
            MajungStatusPill(text: currentBadge.text, tint: currentBadge.tint)
            Text(pickup.tracker.snapshot?.place?.label ?? pickup.tracker.lastPlace?.label ?? "만날 장소 확인 중")
                .font(.headline)
            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                pickup.reopenPickup()
            } label: {
                Text("픽업 화면으로 돌아가기")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reopen-guest-pickup-button")
        }
    }
}
