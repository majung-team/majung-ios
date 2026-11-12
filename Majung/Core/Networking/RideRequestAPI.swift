import Foundation

struct RideRequestAPI {
    private struct SubmitBody: Encodable {
        let driverId: UUID?
        let vehicleId: UUID?
        let place: PickupPlace
        let requestId: UUID
    }

    private struct ReadinessBody: Encodable {
        let readiness: String
        let sequence: Int
    }

    private struct PlaceBody: Encodable {
        let place: PickupPlace
    }

    private struct QuickMessageBody: Encodable {
        let message: String
    }

    private struct ArrivalPushBody: Encodable {
        let endpoint: String
    }

    private let client = AccountAPI()
    private let streamSession = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)

    func submit(driverId: UUID? = nil, vehicleId: UUID? = nil, place: PickupPlace, requestId: UUID, cookie: String, csrfToken: String) async throws -> RideRequestItem {
        try await client.requestWithResponse(
            "ride-requests",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken,
            body: SubmitBody(driverId: driverId, vehicleId: vehicleId, place: place, requestId: requestId)
        ).0
    }

    func lookupVehicle(code: String, cookie: String) async throws -> VehicleLookupItem {
        var components = URLComponents()
        components.path = "ride-requests/vehicles/lookup"
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        let path = components.string ?? "ride-requests/vehicles/lookup"
        return try await client.requestWithResponse(path, cookie: cookie).0
    }

    func favoriteVehicles(cookie: String) async throws -> [VehicleLookupItem] {
        let response: FavoriteVehicleListResponse = try await client.requestWithResponse(
            "ride-requests/favorite-vehicles",
            cookie: cookie
        ).0
        return response.vehicles
    }

    func removeFavoriteVehicle(vehicleId: UUID, cookie: String, csrfToken: String) async throws {
        try await client.requestEmpty(
            "ride-requests/favorite-vehicles/\(vehicleId.uuidString.lowercased())",
            method: "DELETE",
            cookie: cookie,
            csrfToken: csrfToken
        )
    }

    func list(cookie: String) async throws -> [RideRequestItem] {
        let response: RideRequestListResponse = try await client.requestWithResponse(
            "ride-requests",
            cookie: cookie
        ).0
        return response.requests
    }

    func answerInvitation(id: UUID, accept: Bool, cookie: String, csrfToken: String) async throws -> RideRequestItem {
        let action = accept ? "accept-invitation" : "reject-invitation"
        return try await client.requestWithResponse(
            "ride-requests/\(id.uuidString.lowercased())/\(action)",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken
        ).0
    }

    func cancel(id: UUID, cookie: String, csrfToken: String) async throws -> RideRequestItem {
        try await client.requestWithResponse(
            "ride-requests/\(id.uuidString.lowercased())/cancel",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken
        ).0
    }

    func tracking(id: UUID, cookie: String) async throws -> RideTrackingResponse {
        try await client.requestWithResponse(
            "ride-requests/\(id.uuidString.lowercased())/tracking",
            cookie: cookie
        ).0
    }

    func updateReadiness(id: UUID, ready: Bool, sequence: Int, cookie: String, csrfToken: String) async throws -> PickupSnapshot {
        try await client.requestWithResponse(
            "ride-requests/\(id.uuidString.lowercased())/readiness",
            method: "PUT",
            cookie: cookie,
            csrfToken: csrfToken,
            body: ReadinessBody(readiness: ready ? "READY" : "PREPARING", sequence: sequence)
        ).0
    }

    func proposePlace(id: UUID, place: PickupPlace, cookie: String, csrfToken: String) async throws -> PickupSnapshot {
        try await client.requestWithResponse(
            "ride-requests/\(id.uuidString.lowercased())/place-proposal",
            method: "PUT",
            cookie: cookie,
            csrfToken: csrfToken,
            body: PlaceBody(place: place)
        ).0
    }

    func withdrawPlaceProposal(id: UUID, cookie: String, csrfToken: String) async throws -> PickupSnapshot {
        try await client.requestWithResponse(
            "ride-requests/\(id.uuidString.lowercased())/place-proposal",
            method: "DELETE",
            cookie: cookie,
            csrfToken: csrfToken
        ).0
    }

    func sendQuickMessage(id: UUID, text: String, cookie: String, csrfToken: String) async throws -> PickupSnapshot {
        try await client.requestWithResponse(
            "ride-requests/\(id.uuidString.lowercased())/quick-message",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken,
            body: QuickMessageBody(message: text)
        ).0
    }

    func registerArrivalPush(id: UUID, endpoint: String, cookie: String, csrfToken: String) async throws {
        try await client.requestEmpty(
            "ride-requests/\(id.uuidString.lowercased())/arrival-push",
            method: "PUT",
            cookie: cookie,
            csrfToken: csrfToken,
            body: ArrivalPushBody(endpoint: endpoint)
        )
    }

    func streamListEvents(
        cookie: String,
        onState: @escaping @MainActor (Bool) -> Void,
        onRefresh: @escaping @MainActor () async -> Void
    ) async {
        let url = client.endpoint("ride-requests/events")
        var req = client.baseRequest(url: url, method: "GET", cookie: cookie, csrfToken: nil)
        req.timeoutInterval = 30
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        await MajungEventStream.listen(request: req, session: streamSession, onState: onState, onRefresh: onRefresh)
    }

    func streamEvents(
        id: UUID,
        cookie: String,
        onState: @escaping @MainActor (Bool) -> Void,
        onRefresh: @escaping @MainActor () async -> Void
    ) async {
        let url = client.endpoint("ride-requests/\(id.uuidString.lowercased())/events")
        var req = client.baseRequest(url: url, method: "GET", cookie: cookie, csrfToken: nil)
        req.timeoutInterval = 30
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        await MajungEventStream.listen(request: req, session: streamSession, onState: onState, onRefresh: onRefresh)
    }
}
