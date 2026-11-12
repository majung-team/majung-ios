import CoreLocation
import Foundation
import XCTest
@testable import Majung

final class MajungCoreTests: XCTestCase {
    private let validUUIDString = "11111111-2222-4333-8444-555555555555"
    private let validCode43 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm0123"

    // MARK: - PickupInvitation

    func testPickupInvitationParsesHTTPSAndCustomScheme() {
        let httpsURL = URL(string: "https://majung.cloud/#join/\(validUUIDString)/\(validCode43)")!
        let httpsRootSlash = URL(string: "https://majung.cloud/#join/\(validUUIDString)/\(validCode43)")!
        let customURL = URL(string: "majung://join/\(validUUIDString)/\(validCode43)")!

        let parsedHTTPS = PickupInvitation(url: httpsURL)
        XCTAssertEqual(parsedHTTPS?.id, UUID(uuidString: validUUIDString))
        XCTAssertEqual(parsedHTTPS?.token, validCode43)
        XCTAssertEqual(PickupInvitation(url: httpsRootSlash), parsedHTTPS)

        let parsedCustom = PickupInvitation(url: customURL)
        XCTAssertEqual(parsedCustom, parsedHTTPS)
    }

    func testPickupInvitationRejectsMalformedURLs() {
        let cases = [
            "https://example.com/#join/\(validUUIDString)/\(validCode43)",
            "https://majung.cloud/other/#join/\(validUUIDString)/\(validCode43)",
            "https://majung.cloud/#vehicle/\(validUUIDString)/\(validCode43)",
            "https://majung.cloud/#join/not-a-uuid/\(validCode43)",
            "https://majung.cloud/#join/\(validUUIDString)/too-short",
            "https://majung.cloud/#join/\(validUUIDString)/\(String(repeating: "A", count: 44))",
            "https://majung.cloud/#join/\(validUUIDString)/\(String(repeating: "+", count: 43))",
            "majung://enroll/\(validUUIDString)/\(validCode43)"
        ]
        for raw in cases {
            let url = URL(string: raw)!
            XCTAssertNil(PickupInvitation(url: url), "Expected nil for \(raw)")
        }
    }

    // MARK: - VehiclePairingTarget

    func testVehiclePairingTargetParsesSupportedSchemesAndBareFragments() {
        let vehicleHTTP = URL(string: "https://majung.cloud/#vehicle/\(validUUIDString)/\(validCode43)")!
        let enrollLocalhost = URL(string: "http://localhost/#enroll/\(validUUIDString)/\(validCode43)")!
        let vehicleLoopback = URL(string: "http://127.0.0.1/#vehicle/\(validUUIDString)/\(validCode43)")!
        let vehicleCustom = URL(string: "majung://vehicle/\(validUUIDString)/\(validCode43)")!
        let enrollCustom = URL(string: "majung://enroll/\(validUUIDString)/\(validCode43)")!

        let target = VehiclePairingTarget(url: vehicleHTTP)
        XCTAssertEqual(target?.kind, .vehicle)
        XCTAssertEqual(target?.id, UUID(uuidString: validUUIDString))
        XCTAssertEqual(target?.code, validCode43)
        XCTAssertEqual(VehiclePairingTarget(url: vehicleLoopback), target)
        XCTAssertEqual(VehiclePairingTarget(url: vehicleCustom), target)

        let enrollTarget = VehiclePairingTarget(url: enrollLocalhost)
        XCTAssertEqual(enrollTarget?.kind, .enroll)
        XCTAssertEqual(VehiclePairingTarget(url: enrollCustom), enrollTarget)

        XCTAssertEqual(
            VehiclePairingTarget(rawText: "  #vehicle/\(validUUIDString)/\(validCode43) \n"),
            target
        )
        XCTAssertEqual(
            VehiclePairingTarget(rawText: "#enroll/\(validUUIDString)/\(validCode43)"),
            enrollTarget
        )
    }

    func testVehiclePairingTargetRejectsInvalidInputs() {
        XCTAssertNil(VehiclePairingTarget(rawText: "   "))
        XCTAssertNil(VehiclePairingTarget(rawText: "not a url"))
        XCTAssertNil(VehiclePairingTarget(rawText: "https://majung.cloud/#join/\(validUUIDString)/\(validCode43)"))
        XCTAssertNil(VehiclePairingTarget(rawText: "#vehicle/invalid-uuid/\(validCode43)"))
        XCTAssertNil(VehiclePairingTarget(rawText: "#enroll/\(validUUIDString)/short"))
    }

    // MARK: - AccountValidation

    func testAccountValidationNicknameRules() {
        XCTAssertEqual(AccountValidation.normalizedNickname("  마중 탑승객 1  "), "마중 탑승객 1")
        XCTAssertEqual(AccountValidation.normalizedNickname("user_01-a.b"), "user_01-a.b")
        // Compatibility decomposition -> composed Hangul/ASCII check
        XCTAssertEqual(AccountValidation.normalizedNickname("ab"), "ab")
        XCTAssertEqual(AccountValidation.normalizedNickname(String(repeating: "가", count: 20)), String(repeating: "가", count: 20))

        XCTAssertNil(AccountValidation.normalizedNickname("가"))
        XCTAssertNil(AccountValidation.normalizedNickname("   "))
        XCTAssertNil(AccountValidation.normalizedNickname(String(repeating: "가", count: 21)))
        XCTAssertNil(AccountValidation.normalizedNickname("user@name!"))
    }

    func testAccountValidationSearchQueryBounds() {
        XCTAssertNil(AccountValidation.normalizedSearchQuery(" a "))
        XCTAssertEqual(AccountValidation.normalizedSearchQuery("  마중  "), "마중")
        XCTAssertEqual(
            AccountValidation.normalizedSearchQuery(String(repeating: "a", count: 32)),
            String(repeating: "a", count: 32)
        )
        XCTAssertNil(AccountValidation.normalizedSearchQuery(String(repeating: "a", count: 33)))
    }

    func testPKCEVerifierAndChallengeMatchRFC7636Vector() {
        // RFC 7636 Appendix B test vector
        let rfcVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(AccountValidation.pkceChallenge(for: rfcVerifier), expectedChallenge)

        let generated = AccountValidation.pkceVerifier()
        XCTAssertEqual(generated.count, 43)
        XCTAssertFalse(generated.contains("+"))
        XCTAssertFalse(generated.contains("/"))
        XCTAssertFalse(generated.contains("="))
    }

    // MARK: - Codec & Formatting

    func testMajungCodecDecodesISO8601WithAndWithoutFractionalSeconds() throws {
        struct Stamp: Decodable { let createdAt: Date }
        let jsonWithFraction = Data(#"{"createdAt":"2026-11-11T04:00:00.123456Z"}"#.utf8)
        let jsonPlain = Data(#"{"createdAt":"2026-11-11T04:00:00Z"}"#.utf8)
        let badJSON = Data(#"{"createdAt":"not-a-date"}"#.utf8)

        let d1 = try MajungCodec.decoder.decode(Stamp.self, from: jsonWithFraction)
        let d2 = try MajungCodec.decoder.decode(Stamp.self, from: jsonPlain)
        XCTAssertEqual(d1.createdAt.timeIntervalSince1970, d2.createdAt.timeIntervalSince1970, accuracy: 0.2)

        XCTAssertThrowsError(try MajungCodec.decoder.decode(Stamp.self, from: badJSON))
    }

    func testMajungFormattingHelpers() {
        let place = PickupPlace(label: "왕십리역 1번 출구", latitude: 37.5612, longitude: 127.0370)
        XCTAssertEqual(MajungFormatting.etaText(nil), "도착 시간을 확인 중이에요")
        XCTAssertEqual(
            MajungFormatting.etaText(PickupVehicle(freshness: "FRESH", latitude: nil, longitude: nil, durationSeconds: 45, validForMillis: 15_000, ageMillis: 0, placeVersion: 1)),
            "1분 이내 도착 예정"
        )
        XCTAssertEqual(
            MajungFormatting.etaText(PickupVehicle(freshness: "FRESH", latitude: nil, longitude: nil, durationSeconds: 61, validForMillis: 15_000, ageMillis: 0, placeVersion: 1)),
            "약 2분 후 도착 예정"
        )
        XCTAssertEqual(MajungFormatting.minutesText(seconds: 59), "1분 이내")
        XCTAssertEqual(MajungFormatting.minutesText(seconds: 120), "약 2분")

        XCTAssertNil(MajungFormatting.distanceText(from: nil, to: place))
        let nearbyVehicle = PickupVehicle(
            freshness: "FRESH",
            latitude: 37.5612,
            longitude: 127.0370,
            durationSeconds: 30,
            validForMillis: 15_000,
            ageMillis: 1_000,
            placeVersion: 1
        )
        XCTAssertEqual(MajungFormatting.distanceText(from: nearbyVehicle, to: place), "1m 남음")

        let farVehicle = PickupVehicle(
            freshness: "FRESH",
            latitude: 37.5712,
            longitude: 127.0370,
            durationSeconds: 180,
            validForMillis: 15_000,
            ageMillis: 1_000,
            placeVersion: 1
        )
        let farText = MajungFormatting.distanceText(from: farVehicle, to: place)
        XCTAssertTrue(farText?.hasSuffix("km 남음") == true)

        let baseNow = Date(timeIntervalSince1970: 1_700_000_010)
        XCTAssertNil(MajungFormatting.freshnessText(for: nil, updatedAt: baseNow, now: baseNow))
        XCTAssertEqual(
            MajungFormatting.freshnessText(
                for: nearbyVehicle,
                updatedAt: baseNow.addingTimeInterval(-2),
                now: baseNow
            ),
            "실시간 갱신 중 · 방금 전"
        )
        XCTAssertEqual(
            MajungFormatting.freshnessText(
                for: nearbyVehicle,
                updatedAt: baseNow.addingTimeInterval(-6),
                now: baseNow
            ),
            "실시간 갱신 중 · 7초 전"
        )
    }

    // MARK: - Domain Status Helpers

    func testVehicleLinkModelsStateAndDisplayName() {
        let now = Date()
        let unnamed = VehicleLink(vehicleId: UUID(), vehicleName: "   ", linkedAt: now)
        let named = VehicleLink(vehicleId: UUID(), vehicleName: " 아이오닉 5 ", linkedAt: now)
        XCTAssertEqual(unnamed.displayName, "마중 차량")
        XCTAssertEqual(named.displayName, "아이오닉 5")

        let awaitingLink = VehicleLinkRequestState(
            challengeId: UUID(),
            vehicleId: nil,
            vehicleName: "레이 EV",
            status: "AWAITING_VEHICLE_CONFIRMATION",
            expiresAt: now
        )
        XCTAssertTrue(awaitingLink.isPending)
        XCTAssertFalse(awaitingLink.isLinked)

        let linked = VehicleLinkRequestState(
            challengeId: UUID(),
            vehicleId: UUID(),
            vehicleName: "레이 EV",
            status: "LINKED",
            expiresAt: now
        )
        XCTAssertFalse(linked.isPending)
        XCTAssertTrue(linked.isLinked)

        let enrollment = VehicleEnrollmentState(
            enrollmentId: UUID(),
            status: "CLAIMED",
            nickname: "마중",
            majungId: "majung-1",
            expiresAt: now
        )
        XCTAssertTrue(enrollment.isPending)
        XCTAssertFalse(enrollment.isConfirmed)
        XCTAssertFalse(enrollment.isCancelled)

        let pendingPairing = PendingVehiclePairing.linkRequest(awaitingLink)
        XCTAssertEqual(pendingPairing.title, "레이 EV 승인 대기 중")
        XCTAssertEqual(pendingPairing.id, awaitingLink.challengeId)
    }

    func testRideRequestItemStatusDecodingAndRanking() throws {
        let payload = """
        [
          {"requestId":"11111111-1111-4111-8111-111111111111","status":"PENDING","nickname":"김마중","majungId":"k","place":{"label":"출구","latitude":37.5,"longitude":127.0},"expiresAt":"2026-11-11T04:00:00Z","peopleAhead":null,"currentPickupRemainingSeconds":null,"currentPickupValidForMillis":0,"driverInvitation":false},
          {"requestId":"22222222-2222-4222-8222-222222222222","status":"ACTIVE","nickname":"김마중","majungId":"k","place":{"label":"출구","latitude":37.5,"longitude":127.0},"expiresAt":"2026-11-11T04:00:00Z","peopleAhead":0,"currentPickupRemainingSeconds":120,"currentPickupValidForMillis":15000,"driverInvitation":false},
          {"requestId":"33333333-3333-4333-8333-333333333333","status":"NEW_FUTURE_STATUS","nickname":"김마중","majungId":"k","place":{"label":"출구","latitude":37.5,"longitude":127.0},"expiresAt":"2026-11-11T04:00:00Z","peopleAhead":null,"currentPickupRemainingSeconds":null,"currentPickupValidForMillis":0,"driverInvitation":false}
        ]
        """.data(using: .utf8)!

        let items = try MajungCodec.decoder.decode([RideRequestItem].self, from: payload)
        XCTAssertEqual(items[0].status, .pending)
        XCTAssertTrue(items[0].status.isOpen)
        XCTAssertTrue(items[0].status.isWaiting)
        XCTAssertTrue(items[0].status.canCancel)

        XCTAssertEqual(items[1].status, .active)
        XCTAssertTrue(items[1].status.isOpen)
        XCTAssertFalse(items[1].status.isWaiting)
        XCTAssertFalse(items[1].status.canCancel)
        XCTAssertLessThan(items[1].status.sortRank, items[0].status.sortRank)

        XCTAssertEqual(items[2].status, .unknown)
        XCTAssertFalse(items[2].status.isOpen)
        XCTAssertEqual(items[2].status.label, "상태 확인 중")

        let place = PickupPlace(label: "왕십리역 1번 출구", latitude: 37.5612, longitude: 127.0370)
        let completedItem = RideRequestItem(
            requestId: UUID(),
            status: .completed,
            nickname: "김민수",
            majungId: "minsu",
            place: items[0].place,
            expiresAt: Date(),
            peopleAhead: nil,
            currentPickupRemainingSeconds: nil,
            currentPickupValidForMillis: 0,
            driverInvitation: false
        )
        let terminalSnap = completedItem.terminalPickupSnapshot(lastPlace: place, lastVehicleName: "아이오닉 5")
        XCTAssertEqual(terminalSnap?.status, .completed)
        XCTAssertEqual(terminalSnap?.place, place)
        XCTAssertEqual(terminalSnap?.vehicleName, "아이오닉 5")
        XCTAssertNil(items[0].terminalPickupSnapshot(lastPlace: place, lastVehicleName: nil))
    }

    func testVehicleLookupDecodingAndRideTargetPerson() throws {
        let json = """
        {
          "vehicles": [
            {
              "vehicleId": "11111111-2222-4333-8444-555555555555",
              "vehicleCode": "VEH-7K2M9A",
              "displayName": "초기 차량",
              "vehicleModel": "아이오닉 5",
              "licensePlate": "12가 3456",
              "ownerHint": "송*준 아빠",
              "directRequestEnabled": true,
              "linkedDriver": false,
              "trusted": true,
              "linkedDriverNickname": null,
              "linkedDriverMajungId": null
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try MajungCodec.decoder.decode(FavoriteVehicleListResponse.self, from: json)
        XCTAssertEqual(decoded.vehicles.count, 1)
        let vehicle = decoded.vehicles[0]
        XCTAssertEqual(vehicle.summaryTitle, "아이오닉 5 · 12가 3456")
        XCTAssertTrue(vehicle.trusted)
        XCTAssertFalse(vehicle.linkedDriver)

        let target = RideTargetPerson(vehicle: vehicle)
        XCTAssertNil(target.driverId)
        XCTAssertEqual(target.nickname, "아이오닉 5 · 12가 3456")
        XCTAssertEqual(target.majungId, "VEH-7K2M9A")
    }

    func testPickupSnapshotStatusAndProposalHelpers() throws {
        XCTAssertFalse(PickupSnapshot.Status.inviting.ended)
        XCTAssertFalse(PickupSnapshot.Status.waiting.ended)
        XCTAssertFalse(PickupSnapshot.Status.active.ended)
        XCTAssertFalse(PickupSnapshot.Status.arrived.ended)
        XCTAssertTrue(PickupSnapshot.Status.completed.ended)
        XCTAssertTrue(PickupSnapshot.Status.cancelled.ended)
        XCTAssertTrue(PickupSnapshot.Status.expired.ended)
        XCTAssertTrue(PickupSnapshot.Status.inviteExpired.ended)

        let payload = """
        {
          "pickupId": "11111111-2222-4333-8444-555555555555",
          "status": "ACTIVE",
          "place": {"label": "왕십리역 1번 출구", "latitude": 37.5612, "longitude": 127.0370},
          "placeVersion": 2,
          "participant": {"readiness": "READY", "readinessSequence": 4, "readinessReceivedSequence": 4},
          "placeProposal": {"place": {"label": "성수역 3번 출구", "latitude": 37.5445, "longitude": 127.0560}, "proposedBy": "PASSENGER"},
          "quickMessage": {"text": "잠시 후 도착해요"},
          "vehicleName": "아이오닉 5"
        }
        """.data(using: .utf8)!

        let snapshot = try MajungCodec.decoder.decode(PickupSnapshot.self, from: payload)
        XCTAssertEqual(snapshot.status, .active)
        XCTAssertTrue(snapshot.participant?.ready == true)
        XCTAssertTrue(snapshot.placeProposal?.isPassenger == true)
        XCTAssertEqual(snapshot.quickMessage?.text, "잠시 후 도착해요")
    }

    // MARK: - SSE Event Stream

    @MainActor
    func testMajungEventStreamParsesCRLFChangedAndAccessEnded() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        SSEStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream; charset=utf-8"]
            )!
            let payload = Data(
                (": ping\r\nevent: changed\r\ndata: refresh\r\n\r\n" +
                 "event: ignored\ndata: payload\n\n" +
                 "event: access-ended\ndata: ended\n\n").utf8
            )
            return (response, payload)
        }

        var states: [Bool] = []
        var refreshes = 0
        await MajungEventStream.listen(
            request: URLRequest(url: URL(string: "https://majung.cloud/api/v1/pickups/stream")!),
            session: session,
            onState: { states.append($0) },
            onRefresh: { refreshes += 1 }
        )

        XCTAssertEqual(states, [true, false])
        XCTAssertEqual(refreshes, 2)
    }

    @MainActor
    func testMajungEventStreamRejectsNonSSEOrErrorResponse() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        SSEStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data())
        }

        var states: [Bool] = []
        var refreshes = 0
        await MajungEventStream.listen(
            request: URLRequest(url: URL(string: "https://majung.cloud/api/v1/pickups/stream")!),
            session: session,
            onState: { states.append($0) },
            onRefresh: { refreshes += 1 }
        )

        XCTAssertEqual(states, [false])
        XCTAssertEqual(refreshes, 0)
    }

    // MARK: - OnboardingStore

    func testOnboardingStorePersistsAndResetsCompletionFlag() {
        let suiteName = "app.majung.tests.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(OnboardingStore.isCompleted(defaults: defaults))

        OnboardingStore.markCompleted(defaults: defaults)
        XCTAssertTrue(OnboardingStore.isCompleted(defaults: defaults))

        OnboardingStore.reset(defaults: defaults)
        XCTAssertFalse(OnboardingStore.isCompleted(defaults: defaults))
    }

    // MARK: - LocationService Authorization Action

    func testLocationAuthorizationActionNeverRequestsLocationWhileNotDetermined() {
        XCTAssertEqual(LocationService.authorizationAction(for: .notDetermined), .requestAuthorizationOnly)
        XCTAssertEqual(LocationService.authorizationAction(for: .authorizedWhenInUse), .requestLocationNow)
        XCTAssertEqual(LocationService.authorizationAction(for: .authorizedAlways), .requestLocationNow)
        XCTAssertEqual(LocationService.authorizationAction(for: .denied), .failDenied)
        XCTAssertEqual(LocationService.authorizationAction(for: .restricted), .failDenied)
    }

    // MARK: - PlaceSearchService

    func testPlaceSearchURLConstructionAndClamping() {
        let base = URL(string: "https://majung.cloud/api/v1")!
        let center = CLLocationCoordinate2D(latitude: 37.3208, longitude: 126.9482)
        let built = PlaceSearchService.searchURL(query: "  의왕역 1번출구  ", page: 99, near: center, baseURL: base)
        XCTAssertNotNil(built)
        let components = URLComponents(url: built!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.path, "/api/v1/places/search")
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(items["query"], "의왕역 1번출구")
        XCTAssertEqual(items["page"], "3")
        XCTAssertEqual(items["latitude"], "37.3208")
        XCTAssertEqual(items["longitude"], "126.9482")

        XCTAssertNil(PlaceSearchService.searchURL(query: "   ", page: 1, baseURL: base))
    }

    func testPlaceSearchServiceKakaoProxySuccessAndMapKitFallback() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEStubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let base = URL(string: "https://majung.cloud/api/v1")!

        // 1. Kakao search enabled -> returns rich Korean place candidates
        SSEStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
              "enabled": true,
              "hasNext": true,
              "items": [
                {"label": "강남역 2번 출구", "address": "서울 강남구 역삼동 858", "category": "지하철역", "latitude": 37.4979, "longitude": 127.0276}
              ]
            }
            """
            return (response, Data(json.utf8))
        }

        let kakaoPage = try await PlaceSearchService.search(
            query: "강남역",
            page: 1,
            near: nil,
            baseURL: base,
            session: session,
            mapKitFallback: { _, _ in
                XCTFail("MapKit fallback should not run when Kakao search succeeds")
                return []
            }
        )
        XCTAssertFalse(kakaoPage.usedFallback)
        XCTAssertTrue(kakaoPage.hasNext)
        XCTAssertEqual(kakaoPage.candidates.count, 1)
        XCTAssertEqual(kakaoPage.candidates[0].source, .kakao)
        XCTAssertEqual(kakaoPage.candidates[0].label, "강남역 2번 출구")
        XCTAssertEqual(kakaoPage.candidates[0].category, "지하철역")
        XCTAssertEqual(kakaoPage.candidates[0].detailText, "서울 강남구 역삼동 858")

        // 2. Kakao disabled or server HTTP 500 -> transparent fallback to MapKit
        SSEStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data())
        }

        let fallbackCandidate = PlaceSearchCandidate(
            id: "mk-1",
            label: "Apple Maps Place",
            address: "서울",
            category: nil,
            latitude: 37.5,
            longitude: 127.0,
            source: .mapKit
        )
        let fallbackPage = try await PlaceSearchService.search(
            query: "강남역",
            page: 1,
            near: nil,
            baseURL: base,
            session: session,
            mapKitFallback: { _, _ in [fallbackCandidate] }
        )
        XCTAssertTrue(fallbackPage.usedFallback)
        XCTAssertFalse(fallbackPage.hasNext)
        XCTAssertEqual(fallbackPage.candidates, [fallbackCandidate])
    }

    // MARK: - PickupNotificationService APNs Token Formatting

    @MainActor
    func testVehiclePairingTargetSupportsVehicleAppAccountFragmentURLs() {
        let id = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let code = String(repeating: "A", count: 43)

        let enrollTarget = VehiclePairingTarget(rawText: "https://majung.cloud/account#enroll/\(id.uuidString.lowercased())/\(code)")
        XCTAssertEqual(enrollTarget?.kind, .enroll)
        XCTAssertEqual(enrollTarget?.id, id)
        XCTAssertEqual(enrollTarget?.code, code)

        let vehicleTarget = VehiclePairingTarget(rawText: "https://majung.cloud/account/#vehicle/\(id.uuidString.lowercased())/\(code)")
        XCTAssertEqual(vehicleTarget?.kind, .vehicle)
        XCTAssertEqual(vehicleTarget?.id, id)
        XCTAssertEqual(vehicleTarget?.code, code)

        let bareFragment = VehiclePairingTarget(rawText: "#enroll/\(id.uuidString.lowercased())/\(code)")
        XCTAssertEqual(bareFragment?.kind, .enroll)
    }

    @MainActor
    func testPickupNotificationServiceApnsTokenFormatting() {
        let validBytes = Data(repeating: 0xAB, count: 32)
        PickupNotificationService.updateApnsDeviceToken(validBytes)
        XCTAssertEqual(
            PickupNotificationService.apnsEndpoint,
            "apns://" + String(repeating: "ab", count: 32)
        )

        PickupNotificationService.updateApnsDeviceToken(Data([0x01, 0x02]))
        XCTAssertNil(PickupNotificationService.apnsEndpoint)
    }

    // MARK: - Solo Demo Mode & Server Switching

    @MainActor
    func testSoloDemoServerSupportsAccountsLoginPlacesRequestsAndVehicleTick() async throws {
        let prevMode = DevServerConfig.shared.mode
        defer {
            DevServerConfig.shared.mode = prevMode
            SoloDemoServer.shared.resetState()
        }

        SoloDemoServer.shared.resetState()
        DevServerConfig.shared.mode = .demo

        let base = APIBaseURL.root
        XCTAssertEqual(base.host, "127.0.0.1")

        let accountAPI = AccountAPI()
        let (accounts, _): ([DevAccountSummary], HTTPURLResponse) = try await accountAPI.requestWithResponse("dev/accounts")
        XCTAssertGreaterThanOrEqual(accounts.count, 16)

        struct LoginBody: Encodable { let memberId: UUID? }
        let (me, loginHTTP): (AccountMember, HTTPURLResponse) = try await accountAPI.requestWithResponse(
            "dev/login",
            method: "POST",
            body: LoginBody(memberId: accounts[0].memberId)
        )
        XCTAssertEqual(me.majungId, "MJ-DEMO001")

        let cookieHeader = (loginHTTP.allHeaderFields["Set-Cookie"] as? String) ?? ""
        XCTAssertTrue(cookieHeader.contains("JSESSIONID="))
        let cookieValue = cookieHeader
            .components(separatedBy: ";").first?
            .replacingOccurrences(of: "JSESSIONID=", with: "") ?? ""
        XCTAssertFalse(cookieValue.isEmpty)

        let rides = try await RideRequestAPI().list(cookie: cookieValue)
        XCTAssertGreaterThanOrEqual(rides.count, 4)

        let search = try await PlaceSearchService.search(query: "강남", baseURL: base)
        XCTAssertFalse(search.usedFallback)
        XCTAssertFalse(search.candidates.isEmpty)

        struct TickBody: Encodable { let action: String }
        try await accountAPI.requestEmpty("dev/simulate/vehicle-tick", method: "POST", body: TickBody(action: "arrive"))
        if let active = rides.first(where: { $0.status == .active }) {
            let snap = try await RideRequestAPI().tracking(id: active.requestId, cookie: cookieValue)
            XCTAssertEqual(snap.pickup.status, .arrived)
        }
    }
}

private final class SSEStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            // Deliver in small chunks to verify byte-by-byte CR/LF boundary handling.
            let midpoint = data.count / 2
            client?.urlProtocol(self, didLoad: data.prefix(midpoint))
            client?.urlProtocol(self, didLoad: data.dropFirst(midpoint))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
