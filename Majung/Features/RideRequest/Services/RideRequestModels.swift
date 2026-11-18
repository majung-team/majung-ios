import Foundation

struct RideRequestItem: Decodable, Identifiable, Equatable {
    enum Status: String, Decodable, Equatable {
        case invited = "INVITED"
        case pending = "PENDING"
        case queued = "QUEUED"
        case active = "ACTIVE"
        case completed = "COMPLETED"
        case cancelled = "CANCELLED"
        case rejected = "REJECTED"
        case expired = "EXPIRED"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }

        var isOpen: Bool {
            switch self {
            case .invited, .pending, .queued, .active: true
            default: false
            }
        }

        var isWaiting: Bool {
            switch self {
            case .invited, .pending, .queued: true
            default: false
            }
        }

        var canCancel: Bool {
            self == .pending || self == .queued
        }

        var sortRank: Int {
            switch self {
            case .active: 0
            case .invited: 1
            case .queued: 2
            case .pending: 3
            case .completed: 4
            case .cancelled: 5
            case .rejected: 6
            case .expired: 7
            case .unknown: 8
            }
        }

        var label: String {
            switch self {
            case .invited: "운전자가 보낸 초대 · 응답 대기"
            case .pending: "운전자 응답 대기 중"
            case .queued: "수락됨 · 내 차례 대기 중"
            case .active: "내 픽업 진행 중"
            case .completed: "탑승 완료"
            case .cancelled: "취소됨"
            case .rejected: "거절됨"
            case .expired: "만료됨"
            case .unknown: "상태 확인 중"
            }
        }
    }

    let requestId: UUID
    let status: Status
    let nickname: String
    let majungId: String?
    let place: PickupPlace
    let expiresAt: Date
    let peopleAhead: Int?
    let currentPickupRemainingSeconds: Int?
    let currentPickupValidForMillis: Int
    let driverInvitation: Bool

    var id: UUID { requestId }

    func terminalPickupSnapshot(lastPlace: PickupPlace?, lastVehicleName: String?) -> PickupSnapshot? {
        let terminalStatus: PickupSnapshot.Status? = switch status {
        case .completed: .completed
        case .cancelled: .cancelled
        case .expired: .expired
        default: nil
        }
        guard let terminalStatus else { return nil }
        return PickupSnapshot(
            pickupId: nil,
            status: terminalStatus,
            place: lastPlace ?? place,
            placeVersion: 0,
            participant: nil,
            placeProposal: nil,
            quickMessage: nil,
            vehicleName: lastVehicleName
        )
    }
}

struct RideRequestListResponse: Decodable {
    let requests: [RideRequestItem]
}

struct RideTrackingResponse: Decodable {
    let pickup: PickupSnapshot
    let vehicle: PickupVehicle?
}

struct RideTargetPerson: Identifiable, Equatable {
    let driverId: UUID
    let nickname: String
    let majungId: String

    var id: UUID { driverId }
}
