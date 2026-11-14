import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MajungLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        MajungPickupLiveActivityWidget()
    }
}

struct MajungPickupLiveActivityWidget: Widget {
    private let brandBlue = Color(red: 0.25, green: 0.60, blue: 1.0)
    private let arrivedGreen = Color(red: 0.20, green: 0.82, blue: 0.45)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PickupLiveActivityAttributes.self) { context in
            lockScreenView(context: context)
                .widgetURL(PickupLiveActivityAttributes.deepLinkURL(pickupId: context.attributes.pickupId))
                .activityBackgroundTint(Color.black.opacity(0.84))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let stale = context.isStale || context.state.vehicleFreshUntil == nil
            let accent = stale ? Color.secondary : (context.state.phase == .arrived ? arrivedGreen : brandBlue)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: context.state.phase == .arrived ? "checkmark.circle.fill" : "car.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(accent)
                        Text(stale ? "갱신 필요" : context.state.phase.shortBadgeText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if stale {
                            Text("앱 열어 확인")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        } else if context.state.phase == .arrived {
                            Text("정차 완료")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(arrivedGreen)
                        } else if let range = context.state.activeTimerRange() {
                            Text(timerInterval: range, countsDown: true)
                                .monospacedDigit()
                                .font(.title3.weight(.bold))
                                .foregroundStyle(brandBlue)
                                .multilineTextAlignment(.trailing)
                        } else {
                            Text(context.state.compactTrailingLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accent)
                            Text(context.state.placeLabel)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if context.state.passengerReady && context.state.phase == .approaching {
                                Text("곧 나감 전달됨")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(arrivedGreen)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(context.state.vehicleName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(stale ? "앱을 열어 최신 정보를 확인해주세요" : context.state.etaSummaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.state.phase == .arrived ? "checkmark.circle.fill" : "car.fill")
                        .foregroundStyle(accent)
                    Text("마중")
                        .font(.caption2.weight(.bold))
                }
            } compactTrailing: {
                if stale {
                    Text("갱신 필요")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if context.state.phase == .arrived {
                    Text("도착")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(arrivedGreen)
                } else if let range = context.state.activeTimerRange() {
                    Text(timerInterval: range, countsDown: true)
                        .monospacedDigit()
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(brandBlue)
                        .frame(maxWidth: 46)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(context.state.compactTrailingLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                Image(systemName: stale ? "arrow.clockwise" : (context.state.phase == .arrived ? "checkmark.circle.fill" : "car.fill"))
                    .foregroundStyle(accent)
            }
            .widgetURL(PickupLiveActivityAttributes.deepLinkURL(pickupId: context.attributes.pickupId))
            .keylineTint(accent)
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<PickupLiveActivityAttributes>) -> some View {
        let stale = context.isStale || context.state.vehicleFreshUntil == nil
        let accent = stale ? Color.secondary : (context.state.phase == .arrived ? arrivedGreen : brandBlue)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: context.state.phase == .arrived ? "checkmark.circle.fill" : "car.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent)
                Text(context.state.vehicleName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text(stale ? "갱신 필요" : context.state.phase.shortBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.18), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(accent)
                Text(context.state.placeLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if stale {
                    Text("앱 열어 확인")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if context.state.phase == .arrived {
                    Text("정차 완료")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(arrivedGreen)
                } else if let range = context.state.activeTimerRange() {
                    Text(timerInterval: range, countsDown: true)
                        .monospacedDigit()
                        .font(.title3.weight(.bold))
                        .foregroundStyle(brandBlue)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack(spacing: 8) {
                Text(stale ? "앱을 열어 최신 정보를 확인해주세요" : context.state.etaSummaryText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Spacer()
                if context.state.passengerReady && context.state.phase == .approaching {
                    Text("곧 나감 전달됨")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(arrivedGreen)
                }
            }
        }
        .padding(16)
    }
}
