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

        var etaSummaryText: String {
            switch phase {
            case .arrived:
                return "만날 장소에 차량이 도착했어요"
            case .approaching:
                guard let seconds = durationSeconds else {
                    return "도착 시간을 확인 중이에요"
                }
                return seconds < 60 ? "1분 이내 도착 예정" : "약 \((seconds + 59) / 60)분 후 도착 예정"
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

        func activeTimerRange(at now: Date = Date()) -> ClosedRange<Date>? {
            guard phase == .approaching,
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
