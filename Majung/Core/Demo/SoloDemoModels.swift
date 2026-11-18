#if DEBUG
import Foundation

struct DevAccountSummary: Decodable, Identifiable, Equatable {
    let memberId: UUID
    let majungId: String
    let nickname: String
    let profileReady: Bool
    let driver: Bool
    let vehicleName: String?

    var id: UUID { memberId }
}

extension SoloDemoServer {
    struct DemoPerson {
        let memberId: String
        let majungId: String
        var nickname: String
        let driver: Bool
        let vehicleId: String?
        let vehicleName: String?
    }

    struct DemoConnection {
        let id: String
        var status: String
        let requesterId: String
        let recipientId: String
    }

    struct DemoRequest {
        let id: String
        var status: String
        let driverId: String
        let passengerId: String
        let vehicleId: String?
        var pickupId: String?
        let placeLabel: String
        let lat: Double
        let lng: Double
        let driverInvitation: Bool
        var peopleAhead: Int?
        var remainingSeconds: Int?
        let expiresAt: Date
    }

    struct DemoPickup {
        let id: String
        let vehicleName: String
        var participantId: String?
        var participantName: String?
        var participantToken: String?
        let inviteToken: String?
        var status: String
        var placeLabel: String
        var lat: Double
        var lng: Double
        var carLat: Double
        var carLng: Double
        var durationSeconds: Int
        var placeVersion: Int
        var readiness: String
        var readinessSeq: Int
        var readinessReceivedSeq: Int
        var proposalLabel: String?
        var proposalLat: Double?
        var proposalLng: Double?
        var proposalBy: String?
        var quickMessage: String?
    }

    struct DemoVehicleLink {
        let vehicleId: String
        let vehicleName: String
        let linkedAt: String
    }

    struct DemoPendingChallenge {
        let challengeId: String
        let vehicleId: String
        let vehicleName: String
        var status: String
        var pollCount: Int
        let expiresAt: Date
    }

    struct PlacePreset {
        let label: String
        let address: String
        let category: String
        let lat: Double
        let lng: Double
    }
}
#endif
