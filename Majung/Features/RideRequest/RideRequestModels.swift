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
    let vehicleId: UUID?
    let vehicleCode: String?
    let vehicleModel: String?
    let licensePlate: String?
    let ownerHint: String?
    let trustStatus: String?

    init(
        requestId: UUID,
        status: Status,
        nickname: String,
        majungId: String?,
        place: PickupPlace,
        expiresAt: Date,
        peopleAhead: Int?,
        currentPickupRemainingSeconds: Int?,
        currentPickupValidForMillis: Int,
        driverInvitation: Bool,
        vehicleId: UUID? = nil,
        vehicleCode: String? = nil,
        vehicleModel: String? = nil,
        licensePlate: String? = nil,
        ownerHint: String? = nil,
        trustStatus: String? = nil
    ) {
        self.requestId = requestId
        self.status = status
        self.nickname = nickname
        self.majungId = majungId
        self.place = place
        self.expiresAt = expiresAt
        self.peopleAhead = peopleAhead
        self.currentPickupRemainingSeconds = currentPickupRemainingSeconds
        self.currentPickupValidForMillis = currentPickupValidForMillis
        self.driverInvitation = driverInvitation
        self.vehicleId = vehicleId
        self.vehicleCode = vehicleCode
        self.vehicleModel = vehicleModel
        self.licensePlate = licensePlate
        self.ownerHint = ownerHint
        self.trustStatus = trustStatus
    }

    var id: UUID { requestId }

    var vehicleDisplaySummary: String? {
        let model = vehicleModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plate = licensePlate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hint = ownerHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = []
        if !model.isEmpty && !plate.isEmpty {
            parts.append("\(model) · \(plate)")
        } else if !model.isEmpty {
            parts.append(model)
        } else if !plate.isEmpty {
            parts.append(plate)
        }
        if !hint.isEmpty {
            parts.append(hint)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

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

struct VehicleLookupItem: Decodable, Identifiable, Equatable {
    let vehicleId: UUID
    let vehicleCode: String
    let displayName: String?
    let vehicleModel: String?
    let licensePlate: String?
    let ownerHint: String?
    let directRequestEnabled: Bool
    let linkedDriver: Bool
    let trusted: Bool
    let linkedDriverNickname: String?
    let linkedDriverMajungId: String?

    var id: UUID { vehicleId }

    var summaryTitle: String {
        let model = vehicleModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plate = licensePlate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !model.isEmpty && !plate.isEmpty { return "\(model) · \(plate)" }
        if !model.isEmpty { return model }
        if !plate.isEmpty { return plate }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? vehicleCode : name
    }
}

struct FavoriteVehicleListResponse: Decodable {
    let vehicles: [VehicleLookupItem]
}

struct RideTargetPerson: Identifiable, Equatable {
    let driverId: UUID?
    let nickname: String
    let majungId: String
    let vehicle: VehicleLookupItem?

    var id: String {
        if let vehicle {
            return "vehicle-\(vehicle.vehicleId.uuidString)"
        }
        return "driver-\(driverId?.uuidString ?? majungId)"
    }

    init(driverId: UUID, nickname: String, majungId: String) {
        self.driverId = driverId
        self.nickname = nickname
        self.majungId = majungId
        self.vehicle = nil
    }

    init(vehicle: VehicleLookupItem) {
        self.driverId = nil
        self.nickname = vehicle.summaryTitle
        self.majungId = vehicle.vehicleCode
        self.vehicle = vehicle
    }
}
