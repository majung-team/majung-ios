import Foundation

struct RideRequestAPI {
    private struct SubmitBody: Encodable {
        let driverId: UUID
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

    private let client = AccountAPI()
    private let streamSession = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)

    func submit(driverId: UUID, place: PickupPlace, requestId: UUID, cookie: String, csrfToken: String) async throws -> RideRequestItem {
        try await client.requestWithResponse(
            "ride-requests",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken,
            body: SubmitBody(driverId: driverId, place: place, requestId: requestId)
        ).0
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

        do {
            let (bytes, response) = try await streamSession.bytes(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
                  contentType.contains("text/event-stream") else {
                await onState(false)
                return
            }

            await onState(true)
            var currentEvent = "message"
            var dataLines: [String] = []

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                if line.isEmpty {
                    let payload = dataLines.joined(separator: "\n")
                    if currentEvent == "changed", payload == "refresh" {
                        await onRefresh()
                    } else if currentEvent == "access-ended" {
                        await onRefresh()
                        break
                    }
                    currentEvent = "message"
                    dataLines.removeAll()
                } else if line.hasPrefix("event:") {
                    currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    var value = String(line.dropFirst(5))
                    if value.hasPrefix(" ") { value.removeFirst() }
                    dataLines.append(value)
                }
            }
        } catch {
            // Polling handles transient SSE disconnects.
        }
        await onState(false)
    }
}
