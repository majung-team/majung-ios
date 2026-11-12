import Foundation

struct VehiclePairingTarget: Equatable {
    enum Kind: String {
        case vehicle
        case enroll
    }

    let kind: Kind
    let id: UUID
    let code: String

    init?(url: URL) {
        let parts: [String]
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()

        switch (scheme, host) {
        case ("https", "majung.cloud") where Self.isSupportedPairingPath(url.path),
             ("http", "localhost") where Self.isSupportedPairingPath(url.path),
             ("http", "127.0.0.1") where Self.isSupportedPairingPath(url.path):
            parts = (url.fragment ?? "").components(separatedBy: "/")
        case ("majung", "vehicle"):
            parts = ["vehicle"] + url.pathComponents.dropFirst()
        case ("majung", "enroll"):
            parts = ["enroll"] + url.pathComponents.dropFirst()
        default:
            return nil
        }

        guard parts.count == 3,
              let kind = Kind(rawValue: parts[0]),
              let id = UUID(uuidString: parts[1]),
              parts[2].range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            return nil
        }
        self.kind = kind
        self.id = id
        self.code = parts[2]
    }

    init?(rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized: String
        if trimmed.hasPrefix("#") {
            normalized = "https://majung.cloud/account\(trimmed)"
        } else if trimmed.hasPrefix("account#") {
            normalized = "https://majung.cloud/\(trimmed)"
        } else {
            normalized = trimmed
        }
        guard let url = URL(string: normalized) else { return nil }
        self.init(url: url)
    }

    private static func isSupportedPairingPath(_ path: String) -> Bool {
        path.isEmpty || path == "/" || path == "/account" || path == "/account/"
    }
}

struct VehicleLink: Decodable, Identifiable, Equatable {
    let vehicleId: UUID
    let vehicleName: String?
    let linkedAt: Date

    var id: UUID { vehicleId }

    var displayName: String {
        let trimmed = vehicleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "마중 차량" : trimmed
    }
}

struct VehicleLinkRequestState: Decodable, Equatable {
    let challengeId: UUID
    let vehicleId: UUID?
    let vehicleName: String?
    let status: String
    let expiresAt: Date

    var isPending: Bool {
        status == "AWAITING_VEHICLE_CONFIRMATION" || status == "AWAITING_CONFIRM"
    }

    var isLinked: Bool { status == "LINKED" }
}

struct VehicleEnrollmentState: Decodable, Equatable {
    let enrollmentId: UUID
    let status: String
    let nickname: String?
    let majungId: String?
    let expiresAt: Date

    var isPending: Bool {
        status == "AWAITING_VEHICLE_CONFIRMATION" || status == "AWAITING_CONFIRM"
            || status == "PENDING" || status == "CLAIMED"
    }

    var isConfirmed: Bool { status == "LINKED" || status == "CONFIRMED" }
    var isCancelled: Bool { status == "CANCELLED" }
}

enum PendingVehiclePairing: Equatable {
    case linkRequest(VehicleLinkRequestState)
    case enrollment(VehicleEnrollmentState)

    var id: UUID {
        switch self {
        case .linkRequest(let state): state.challengeId
        case .enrollment(let state): state.enrollmentId
        }
    }

    var title: String {
        switch self {
        case .linkRequest(let state):
            let name = state.vehicleName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty {
                return "\(name) 승인 대기 중"
            }
            return "차량 연결 승인 대기 중"
        case .enrollment:
            return "새 차량 등록 승인 대기 중"
        }
    }

    var detailText: String {
        switch self {
        case .linkRequest:
            return "차량 화면에서 연결 승인을 누르면 바로 목록에 추가돼요."
        case .enrollment:
            return "차량 화면에서 내 계정을 선택해 등록을 확정해주세요."
        }
    }

    var expiresAt: Date {
        switch self {
        case .linkRequest(let state): state.expiresAt
        case .enrollment(let state): state.expiresAt
        }
    }
}
