import Foundation

struct VehicleLinkAPI {
    private struct RequestClaimBody: Encodable {
        let challengeId: UUID
        let code: String
    }

    private struct EnrollmentClaimBody: Encodable {
        let code: String
    }

    private let accountAPI = AccountAPI()

    func links(cookie: String) async throws -> [VehicleLink] {
        try await accountAPI.requestWithResponse("vehicle-links", cookie: cookie).0
    }

    func detach(vehicleId: UUID, cookie: String, csrfToken: String) async throws {
        try await accountAPI.requestEmpty(
            "vehicle-links/\(vehicleId.uuidString.lowercased())",
            method: "DELETE",
            cookie: cookie,
            csrfToken: csrfToken
        )
    }

    func claimRequest(
        challengeId: UUID,
        code: String,
        cookie: String,
        csrfToken: String
    ) async throws -> VehicleLinkRequestState {
        try await accountAPI.requestWithResponse(
            "vehicle-links/requests",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken,
            body: RequestClaimBody(challengeId: challengeId, code: code)
        ).0
    }

    func requestStatus(id: UUID, cookie: String) async throws -> VehicleLinkRequestState {
        try await accountAPI.requestWithResponse(
            "vehicle-links/requests/\(id.uuidString.lowercased())",
            cookie: cookie
        ).0
    }

    func cancelRequest(id: UUID, cookie: String, csrfToken: String) async throws {
        try await accountAPI.requestEmpty(
            "vehicle-links/requests/\(id.uuidString.lowercased())/cancel",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken
        )
    }

    func claimEnrollment(
        id: UUID,
        code: String,
        cookie: String,
        csrfToken: String
    ) async throws -> VehicleEnrollmentState {
        try await accountAPI.requestWithResponse(
            "vehicle-links/enrollments/\(id.uuidString.lowercased())",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken,
            body: EnrollmentClaimBody(code: code)
        ).0
    }

    func enrollmentStatus(id: UUID, cookie: String) async throws -> VehicleEnrollmentState {
        try await accountAPI.requestWithResponse(
            "vehicle-links/enrollments/\(id.uuidString.lowercased())",
            cookie: cookie
        ).0
    }

    func cancelEnrollment(
        id: UUID,
        cookie: String,
        csrfToken: String
    ) async throws -> VehicleEnrollmentState {
        try await accountAPI.requestWithResponse(
            "vehicle-links/enrollments/\(id.uuidString.lowercased())/cancel",
            method: "POST",
            cookie: cookie,
            csrfToken: csrfToken
        ).0
    }
}
