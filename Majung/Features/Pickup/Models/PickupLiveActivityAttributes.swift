import ActivityKit
import Foundation

struct PickupLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case approaching = "ACTIVE"
            case arrived = "ARRIVED"

            var title: String {
                switch self {
                case .approaching: "마중 이동 중"
                case .arrived: "차량 도착 완료"
                }
            }

            var shortBadgeText: String {
                switch self {
                case .approaching: "이동 중"
                case .arrived: "도착 완료"
                }
            }
        }

        let phase: Phase
        let placeLabel: String
        let vehicleName: String
        let placeVersion: Int
        let durationSeconds: Int?
        let countdownStartDate: Date?
        let estimatedArrivalDate: Date?
        let vehicleFreshUntil: Date?
        let passengerReady: Bool
        let updatedAt: Date
        var isReconnecting: Bool = false
        var lastCheckedAt: Date? = nil

        var etaSummaryText: String {
            switch phase {
            case .arrived:
                return "만날 장소에 차량이 도착했어요"
            case .approaching:
                guard let seconds = durationSeconds else {
                    return "도착 시간을 확인 중이에요"
                }
                if seconds < 60 { return "1분 이내 도착 예정" }
                let totalMinutes = (seconds + 59) / 60
                if totalMinutes >= 60 {
                    let hours = totalMinutes / 60
                    let minutes = totalMinutes % 60
                    return minutes == 0 ? "약 \(hours)시간 후 도착 예정" : "약 \(hours)시간 \(minutes)분 후 도착 예정"
                }
                return "약 \(totalMinutes)분 후 도착 예정"
            }
        }

        var compactTrailingLabel: String {
            switch phase {
            case .arrived:
                return "도착"
            case .approaching:
                guard let seconds = durationSeconds else {
                    return "확인 중"
                }
                return seconds < 60 ? "1분 내" : "\((seconds + 59) / 60)분"
            }
        }

        func compactTimerRange(at now: Date = Date()) -> ClosedRange<Date>? {
            guard let range = activeTimerRange(at: now),
                  range.upperBound.timeIntervalSince(now) < 3600 else {
                return nil
            }
            return range
        }

        func reliabilityText(isStale: Bool = false, now: Date = Date()) -> String {
            let referenceDate = lastCheckedAt ?? updatedAt
            let elapsed = max(0, Int(now.timeIntervalSince(referenceDate)))
            let relative = elapsed < 15 ? "방금 전" : (elapsed < 60 ? "\(elapsed)초 전" : "\(max(1, elapsed / 60))분 전")
            if isStale || isReconnecting || (phase == .approaching && vehicleFreshUntil == nil) {
                return "연결 확인 중 · 마지막 확인 \(relative)"
            }
            return "마지막 확인 \(relative)"
        }

        func activeTimerRange(at now: Date = Date()) -> ClosedRange<Date>? {
            guard phase == .approaching,
                  !isReconnecting,
                  let start = countdownStartDate,
                  let end = estimatedArrivalDate,
                  let freshUntil = vehicleFreshUntil,
                  freshUntil > now,
                  end > now,
                  start < end else {
                return nil
            }
            return start...end
        }
    }

    let pickupId: String

    static func deepLinkURL(pickupId: String) -> URL? {
        let encoded = pickupId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pickupId
        return URL(string: "majung://pickup/\(encoded)")
    }
}
