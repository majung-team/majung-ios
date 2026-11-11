import Foundation

struct PickupAPI {
    struct Failure: LocalizedError {
        let status: Int
        let code: String?
        let message: String?
        var errorDescription: String? { message ?? "잠시 후 다시 시도해주세요." }
    }

    private struct ErrorBody: Decodable {
        let code: String?
        let message: String?
    }

    private struct InvitationBody: Encodable { let inviteToken: String }
    private struct Preview: Decodable { let placeLabel: String }
    private struct Joined: Decodable { let participantToken: String }
    private struct ReadinessBody: Encodable {
        let readiness: String
        let sequence: Int
    }
    private struct PlaceBody: Encodable { let place: PickupPlace }
    private struct MessageBody: Encodable { let message: String }

    private let origin = APIBaseURL.root.appendingPathComponent("pickups")
    private let network = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)

    func preview(_ invite: PickupInvitation) async throws -> String {
        let response: Preview = try await request(invite.id, "invitation-preview", method: "POST",
                                                   body: InvitationBody(inviteToken: invite.token))
        return response.placeLabel
    }

    func join(_ invite: PickupInvitation) async throws -> PickupSession {
        let joined: Joined = try await request(invite.id, "participants", method: "POST",
                                                body: InvitationBody(inviteToken: invite.token))
        return PickupSession(id: invite.id, token: joined.participantToken)
    }

    func snapshot(_ session: PickupSession) async throws -> PickupSnapshot {
        try await request(session.id, token: session.token)
    }

    func vehicle(_ session: PickupSession) async throws -> PickupVehicle {
        try await request(session.id, "vehicle-state", token: session.token)
    }

    func readiness(_ session: PickupSession, ready: Bool, sequence: Int) async throws -> PickupSnapshot {
        try await request(session.id, "readiness", method: "PUT", token: session.token,
                          body: ReadinessBody(readiness: ready ? "READY" : "PREPARING", sequence: sequence))
    }

    func propose(_ session: PickupSession, place: PickupPlace) async throws -> PickupSnapshot {
        try await request(session.id, "place-proposal", method: "PUT", token: session.token,
                          body: PlaceBody(place: place))
    }

    func withdraw(_ session: PickupSession) async throws -> PickupSnapshot {
        try await request(session.id, "place-proposal", method: "DELETE", token: session.token)
    }

    func message(_ session: PickupSession, text: String) async throws -> PickupSnapshot {
        try await request(session.id, "quick-message", method: "POST", token: session.token,
                          body: MessageBody(message: text))
    }

    private func request<Response: Decodable>(
        _ id: UUID, _ endpoint: String? = nil, method: String = "GET",
        token: String? = nil, body: (any Encodable)? = nil
    ) async throws -> Response {
        var url = origin.appendingPathComponent(id.uuidString.lowercased())
        if let endpoint { url.appendPathComponent(endpoint) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await network.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw Failure(status: http.statusCode, code: body?.code, message: body?.message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
