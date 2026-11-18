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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let placeName {
                Label(placeName, systemImage: "mappin.circle.fill")
                    .font(.headline)
            }
            if let vehicleName, !vehicleName.isEmpty {
                if placeName != nil { Divider() }
                Label(vehicleName, systemImage: "car.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
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
