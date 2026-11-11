import Foundation

struct PickupInvitation: Equatable {
    let id: UUID
    let token: String

    init?(url: URL) {
        let parts: [String]
        switch (url.scheme?.lowercased(), url.host?.lowercased()) {
        case ("https", "majung.cloud") where url.path.isEmpty || url.path == "/":
            parts = (url.fragment ?? "").components(separatedBy: "/")
        case ("majung", "join"):
            parts = ["join"] + url.pathComponents.dropFirst()
        default:
            return nil
        }
        guard parts.count == 3, parts[0] == "join", let id = UUID(uuidString: parts[1]),
              parts[2].range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { return nil }
        self.id = id
        token = parts[2]
    }
}

struct PickupSession: Codable, Equatable {
    let id: UUID
    let token: String
}

struct PickupPlace: Codable, Equatable {
    let label: String
    let latitude: Double
    let longitude: Double
}

struct PickupSnapshot: Decodable {
    enum Status: String, Decodable {
        case inviting = "INVITING"
        case waiting = "WAITING_APPROVAL"
        case inviteExpired = "INVITE_EXPIRED"
        case active = "ACTIVE"
        case arrived = "ARRIVED"
        case completed = "COMPLETED"
        case cancelled = "CANCELLED"
        case expired = "EXPIRED"

        var ended: Bool { self == .completed || self == .cancelled || self == .expired || self == .inviteExpired }
    }

    struct Participant: Decodable {
        let readiness: String
        let readinessSequence: Int
        let readinessReceivedSequence: Int
        var ready: Bool { readiness == "READY" }
    }

    struct Proposal: Decodable {
        let place: PickupPlace
        let proposedBy: String
        var isPassenger: Bool { proposedBy == "PASSENGER" }
    }

    struct QuickMessage: Decodable {
        let text: String
    }

    let status: Status
    let place: PickupPlace?
    let placeVersion: Int
    let participant: Participant?
    let placeProposal: Proposal?
    let quickMessage: QuickMessage?
    let vehicleName: String?
}

struct PickupVehicle: Decodable {
    let freshness: String
    let latitude: Double?
    let longitude: Double?
    let durationSeconds: Int?
    let validForMillis: Int
    let placeVersion: Int
}
