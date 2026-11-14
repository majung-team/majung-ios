import Foundation
import Network

final class LocalE2EServer {
    struct RequestRecord {
        let method: String
        let path: String
        let body: String
    }

    enum AccountMode {
        case unauthenticated
        case needsNickname
        case ready
    }

    enum GuestPhase {
        case none
        case waiting
        case active
        case arrived
        case completed
    }

    struct RequestItemModel {
        let id: String
        var status: String
        let nickname: String
        let majungId: String
        let placeLabel: String
        let lat: Double
        let lng: Double
        let peopleAhead: Int?
        let remainingSeconds: Int?
        let validForMillis: Int
        let driverInvitation: Bool
    }

    struct VehicleModel {
        let id: String
        let name: String
        let linkedAt: String
    }

    private let lock = NSLock()
    private let listener: NWListener
    private let queue = DispatchQueue(label: "MajungLocalE2EServer")
    private var sseConnections: [NWConnection] = []

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    // Mutable scenario state protected by lock
    private var accountMode: AccountMode = .unauthenticated
    private var nickname = "김탑승"
    private var memberId = "10101010-1010-4010-8010-101010101010"
    private var majungId = "passenger_kim"
    private var invitePreviewStatus = 200
    private var guestPhase: GuestPhase = .none
    private var guestReadiness = "WAITING"
    private var guestReadinessSeq = 0
    private var guestReadinessReceivedSeq = 0
    private var guestProposal: (label: String, lat: Double, lng: Double)?
    private var guestQuickMessage: String?
    private var rejectNextGuestProposal = false

    private var rideRequests: [RequestItemModel] = []
    private var memberPickupStatus = "ACTIVE"
    private var memberReadiness = "NOT_READY"
    private var memberReadinessSeq = 1
    private var memberReadinessReceivedSeq = 1
    private var memberQuickMessage: String?

    private var vehicles: [VehicleModel] = []
    private var pendingChallenge: (id: String, name: String, status: String)?
    private var recordedRequests: [RequestRecord] = []

    let pickupId = "11111111-2222-4333-8444-555555555555"
    let inviteCode = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm0123"
    let activeRequestId = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    let invitedRequestId = "bbbbbbbb-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    let pendingRequestId = "cccccccc-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    let queuedRequestId = "dddddddd-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    let initialVehicleId = "77777777-6666-4555-8444-333333333333"
    let newChallengeId = "66666666-5555-4444-8333-222222222222"
    let newVehicleId = "55555555-4444-4333-8222-111111111111"
    private let pairingExpiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))

    init() throws {
        let created = try NWListener(using: .tcp, on: .any)
        listener = created
        let ready = DispatchSemaphore(value: 0)
        created.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        created.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        created.start(queue: queue)
        ready.wait()
        resetDefaultData()
    }

    func stop() {
        queue.async { [weak self] in
            self?.sseConnections.forEach { $0.cancel() }
            self?.sseConnections.removeAll()
        }
        listener.cancel()
    }

    func resetDefaultData() {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.removeAll()
        invitePreviewStatus = 200
        guestPhase = .none
        guestReadiness = "WAITING"
        guestReadinessSeq = 0
        guestReadinessReceivedSeq = 0
        guestProposal = nil
        guestQuickMessage = nil
        rejectNextGuestProposal = false

        memberPickupStatus = "ACTIVE"
        memberReadiness = "NOT_READY"
        memberReadinessSeq = 1
        memberReadinessReceivedSeq = 1
        memberQuickMessage = nil

        rideRequests = [
            RequestItemModel(
                id: activeRequestId,
                status: "ACTIVE",
                nickname: "김민수",
                majungId: "minsu_car",
                placeLabel: "의왕역 1호선 1번 출구 앞",
                lat: 37.3208,
                lng: 126.9482,
                peopleAhead: 0,
                remainingSeconds: 240,
                validForMillis: 15_000,
                driverInvitation: false
            ),
            RequestItemModel(
                id: invitedRequestId,
                status: "INVITED",
                nickname: "이수진",
                majungId: "sujin_lee",
                placeLabel: "범계역 4번 출구 앞",
                lat: 37.3897,
                lng: 126.9508,
                peopleAhead: nil,
                remainingSeconds: nil,
                validForMillis: 0,
                driverInvitation: true
            ),
            RequestItemModel(
                id: pendingRequestId,
                status: "PENDING",
                nickname: "박지훈",
                majungId: "jihun_drive",
                placeLabel: "의왕역 1번 출구 앞",
                lat: 37.3208,
                lng: 126.9482,
                peopleAhead: nil,
                remainingSeconds: nil,
                validForMillis: 0,
                driverInvitation: false
            ),
            RequestItemModel(
                id: queuedRequestId,
                status: "QUEUED",
                nickname: "박지훈",
                majungId: "jihun_drive",
                placeLabel: "인덕원역 4번 출구",
                lat: 37.4017,
                lng: 126.9765,
                peopleAhead: 1,
                remainingSeconds: 480,
                validForMillis: 15_000,
                driverInvitation: false
            )
        ]

        vehicles = [
            VehicleModel(
                id: initialVehicleId,
                name: "흰색 아이오닉 5 · 12가 3456",
                linkedAt: "2026-11-11T01:00:00Z"
            )
        ]
        pendingChallenge = nil
    }

    func setAccountMode(_ mode: AccountMode, nickname: String = "김탑승") {
        lock.lock()
        self.accountMode = mode
        self.nickname = nickname
        lock.unlock()
    }

    func setInvitePreviewStatus(_ status: Int) {
        lock.lock()
        invitePreviewStatus = status
        lock.unlock()
    }

    func rejectNextProposalAsSamePlace() {
        lock.lock()
        rejectNextGuestProposal = true
        lock.unlock()
    }

    func setGuestPhase(_ phase: GuestPhase) {
        lock.lock()
        guestPhase = phase
        lock.unlock()
        pushSSEChanged()
    }

    func completeMemberRide() {
        lock.lock()
        memberPickupStatus = "COMPLETED"
        if let idx = rideRequests.firstIndex(where: { $0.id == activeRequestId }) {
            rideRequests[idx].status = "COMPLETED"
        }
        lock.unlock()
        pushSSEChanged()
    }

    func pushExtraInvitationSSE() {
        lock.lock()
        let extraId = "eeeeeeee-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        if !rideRequests.contains(where: { $0.id == extraId }) {
            rideRequests.append(
                RequestItemModel(
                    id: extraId,
                    status: "INVITED",
                    nickname: "최민준",
                    majungId: "minjun_choi",
                    placeLabel: "판교역 1번 출구",
                    lat: 37.3948,
                    lng: 127.1112,
                    peopleAhead: nil,
                    remainingSeconds: nil,
                    validForMillis: 0,
                    driverInvitation: true
                )
            )
        }
        lock.unlock()
        pushSSEChanged()
    }

    func approvePendingVehicleChallenge() {
        lock.lock()
        if let pending = pendingChallenge {
            pendingChallenge = (pending.id, pending.name, "LINKED")
            if !vehicles.contains(where: { $0.id == newVehicleId }) {
                vehicles.append(
                    VehicleModel(
                        id: newVehicleId,
                        name: pending.name,
                        linkedAt: "2026-11-11T05:00:00Z"
                    )
                )
            }
        }
        lock.unlock()
    }

    func requestsMatching(method: String, pathPrefix: String) -> [RequestRecord] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests.filter { $0.method == method && $0.path.hasPrefix(pathPrefix) }
    }

    func pushSSEChanged() {
        queue.async { [weak self] in
            guard let self else { return }
            let event = Data("event: changed\r\ndata: refresh\r\n\r\n".utf8)
            for conn in self.sseConnections {
                conn.send(content: event, completion: .contentProcessed { _ in })
            }
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(on: conn, buffer: Data())
    }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            var next = buffer
            if let data { next.append(data) }
            if let headerRange = next.range(of: Data("\r\n\r\n".utf8)) {
                let headerText = String(decoding: next[..<headerRange.lowerBound], as: UTF8.self)
                let lines = headerText.components(separatedBy: "\r\n")
                let parts = (lines.first ?? "").components(separatedBy: " ")
                let method = parts.count > 0 ? parts[0] : "GET"
                let target = parts.count > 1 ? parts[1] : "/"
                let contentLength = lines.compactMap { line -> Int? in
                    let kv = line.split(separator: ":", maxSplits: 1)
                    guard kv.count == 2, kv[0].lowercased() == "content-length" else { return nil }
                    return Int(kv[1].trimmingCharacters(in: .whitespaces))
                }.first ?? 0
                let bodyStart = headerRange.upperBound
                if next.count - bodyStart < contentLength && !isComplete {
                    self.receive(on: conn, buffer: next)
                    return
                }
                let bodyData = next.subdata(in: bodyStart..<min(next.count, bodyStart + contentLength))
                self.dispatch(method: method, target: target, body: bodyData, conn: conn)
            } else if !isComplete {
                self.receive(on: conn, buffer: next)
            } else {
                conn.cancel()
            }
        }
    }

    private func dispatch(method: String, target: String, body: Data, conn: NWConnection) {
        let parts = target.components(separatedBy: "?")
        let path = parts[0]
        let query = parts.count > 1 ? parts[1] : ""

        if path.hasSuffix("/events") {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n: ok\n\n"
            sseConnections.append(conn)
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            return
        }

        let bodyText = String(decoding: body, as: UTF8.self)
        lock.lock()
        recordedRequests.append(RequestRecord(method: method, path: path, body: bodyText))
        let (status, json, cookie) = buildResponse(method: method, path: path, query: query, body: body)
        lock.unlock()

        let bytes = Data(json.utf8)
        var head = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n"
        if let cookie {
            head += "Set-Cookie: \(cookie); Path=/; HttpOnly\r\n"
        }
        head += "\r\n"
        var packet = Data(head.utf8)
        packet.append(bytes)
        conn.send(content: packet, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func buildResponse(method: String, path: String, query: String, body: Data) -> (Int, String, String?) {
        switch (method, path) {
        case ("GET", "/api/v1/auth/session"):
            switch accountMode {
            case .unauthenticated:
                return (200, #"{"loginEnabled":true,"authenticated":false,"member":null,"csrfToken":null}"#, nil)
            case .needsNickname:
                return (200, #"{"loginEnabled":true,"authenticated":true,"member":{"memberId":"\#(memberId)","majungId":"\#(majungId)","nickname":"\#(nickname)","profileReady":false},"csrfToken":"csrf-e2e"}"#, "JSESSIONID=e2e-session")
            case .ready:
                return (200, #"{"loginEnabled":true,"authenticated":true,"member":{"memberId":"\#(memberId)","majungId":"\#(majungId)","nickname":"\#(nickname)","profileReady":true},"csrfToken":"csrf-e2e"}"#, "JSESSIONID=e2e-session")
            }

        case ("PATCH", "/api/v1/accounts/me"):
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let nextNick = obj["nickname"] as? String {
                nickname = nextNick
            }
            accountMode = .ready
            return (200, #"{"memberId":"\#(memberId)","majungId":"\#(majungId)","nickname":"\#(nickname)","profileReady":true}"#, nil)

        case ("POST", "/api/v1/auth/logout"):
            accountMode = .unauthenticated
            return (200, #"{"ok":true}"#, nil)

        case ("DELETE", "/api/v1/accounts/me"):
            accountMode = .unauthenticated
            rideRequests.removeAll()
            vehicles.removeAll()
            return (204, "", nil)

        case ("GET", "/api/v1/places/search"):
            let components = URLComponents(string: "http://localhost/search?\(query)")
            let page = components?.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) ?? 1
            if page <= 1 {
                return (200, """
                {
                  "enabled": true,
                  "hasNext": true,
                  "items": [
                    {"label": "강남역 2번 출구", "address": "서울 강남구 역삼동 858", "category": "지하철역", "latitude": 37.4979, "longitude": 127.0276},
                    {"label": "강남역 2호선", "address": "서울 강남구 강남대로 지하 396", "category": "지하철역", "latitude": 37.4981, "longitude": 127.0279},
                    {"label": "강남역 신분당선", "address": "서울 강남구 강남대로 지하 396", "category": "지하철역", "latitude": 37.4969, "longitude": 127.0281},
                    {"label": "강남역 1번 출구", "address": "서울 강남구 역삼동 825", "category": "지하철역", "latitude": 37.4977, "longitude": 127.0285},
                    {"label": "강남역 10번 출구", "address": "서울 서초구 서초동 1317-20", "category": "지하철역", "latitude": 37.4984, "longitude": 127.0268}
                  ]
                }
                """, nil)
            }
            return (200, """
            {
              "enabled": true,
              "hasNext": false,
              "items": [
                {"label": "강남역 11번 출구", "address": "서울 강남구 역삼동 820", "category": "지하철역", "latitude": 37.4990, "longitude": 127.0272}
              ]
            }
            """, nil)

        case ("POST", "/api/v1/pickups/\(pickupId)/invitation-preview"):
            if invitePreviewStatus != 200 {
                return (invitePreviewStatus, #"{"code":"INVITE_EXPIRED","message":"만료된 초대입니다."}"#, nil)
            }
            return (200, #"{"placeLabel":"의왕역 1호선 1번 출구 앞"}"#, nil)

        case ("POST", "/api/v1/pickups/\(pickupId)/participants"):
            guestPhase = .waiting
            return (201, #"{"participantToken":"guest-token-e2e"}"#, nil)

        case ("GET", "/api/v1/pickups/\(pickupId)"):
            return (200, guestSnapshotJSON(), nil)

        case ("GET", "/api/v1/pickups/\(pickupId)/vehicle-state"):
            return (200, vehicleJSON(), nil)

        case ("PUT", "/api/v1/pickups/\(pickupId)/readiness"):
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                if let r = obj["readiness"] as? String { guestReadiness = r }
                if let seq = obj["sequence"] as? Int { guestReadinessSeq = seq }
            }
            return (200, guestSnapshotJSON(), nil)

        case ("PUT", "/api/v1/pickups/\(pickupId)/place-proposal"):
            if rejectNextGuestProposal {
                rejectNextGuestProposal = false
                return (409, #"{"code":"SAME_PLACE","message":"현재 장소와 같은 위치입니다."}"#, nil)
            }
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let place = obj["place"] as? [String: Any],
               let label = place["label"] as? String,
               let lat = place["latitude"] as? Double,
               let lng = place["longitude"] as? Double {
                guestProposal = (label, lat, lng)
            }
            return (200, guestSnapshotJSON(), nil)

        case ("DELETE", "/api/v1/pickups/\(pickupId)/place-proposal"):
            guestProposal = nil
            return (200, guestSnapshotJSON(), nil)

        case ("POST", "/api/v1/pickups/\(pickupId)/quick-message"):
            if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let message = obj["message"] as? String {
                guestQuickMessage = message
            }
            return (200, guestSnapshotJSON(), nil)

        case ("POST", "/api/v1/pickups/\(pickupId)/leave"):
            guestPhase = .none
            return (204, "", nil)

        case ("GET", "/api/v1/ride-requests"):
            let encoded = rideRequests.map { item in
                let ahead = item.peopleAhead.map(String.init) ?? "null"
                let rem = item.remainingSeconds.map(String.init) ?? "null"
                return """
                {"requestId":"\(item.id)","status":"\(item.status)","nickname":"\(item.nickname)","majungId":"\(item.majungId)","place":{"label":"\(item.placeLabel)","latitude":\(item.lat),"longitude":\(item.lng)},"expiresAt":"2026-11-11T10:30:00Z","peopleAhead":\(ahead),"currentPickupRemainingSeconds":\(rem),"currentPickupValidForMillis":\(item.validForMillis),"driverInvitation":\(item.driverInvitation)}
                """
            }.joined(separator: ",")
            return (200, "{\"requests\":[\(encoded)]}", nil)

        case ("GET", "/api/v1/ride-requests/\(activeRequestId)/tracking"):
            if memberPickupStatus != "ACTIVE" {
                return (403, #"{"code":"PICKUP_NOT_STARTED","message":"내 픽업이 시작된 뒤 확인할 수 있어요."}"#, nil)
            }
            return (200, "{\"pickup\":\(memberSnapshotJSON()),\"vehicle\":\(vehicleJSON())}", nil)

        case ("POST", "/api/v1/ride-requests/\(invitedRequestId)/accept-invitation"):
            if let idx = rideRequests.firstIndex(where: { $0.id == invitedRequestId }) {
                rideRequests[idx] = RequestItemModel(
                    id: invitedRequestId,
                    status: "QUEUED",
                    nickname: rideRequests[idx].nickname,
                    majungId: rideRequests[idx].majungId,
                    placeLabel: rideRequests[idx].placeLabel,
                    lat: rideRequests[idx].lat,
                    lng: rideRequests[idx].lng,
                    peopleAhead: 2,
                    remainingSeconds: 600,
                    validForMillis: 15_000,
                    driverInvitation: true
                )
                return (200, """
                {"requestId":"\(invitedRequestId)","status":"QUEUED","nickname":"이수진","majungId":"sujin_lee","place":{"label":"범계역 4번 출구 앞","latitude":37.3897,"longitude":126.9508},"expiresAt":"2026-11-11T10:30:00Z","peopleAhead":2,"currentPickupRemainingSeconds":600,"currentPickupValidForMillis":15000,"driverInvitation":true}
                """, nil)
            }
            return (404, #"{"code":"NOT_FOUND"}"#, nil)

        case ("POST", _) where path.hasPrefix("/api/v1/ride-requests/") && path.hasSuffix("/cancel"):
            let id = String(path.dropFirst("/api/v1/ride-requests/".count).dropLast("/cancel".count))
            if let idx = rideRequests.firstIndex(where: { $0.id == id }) {
                rideRequests[idx].status = "CANCELLED"
                let item = rideRequests[idx]
                return (200, """
                {"requestId":"\(item.id)","status":"CANCELLED","nickname":"\(item.nickname)","majungId":"\(item.majungId)","place":{"label":"\(item.placeLabel)","latitude":\(item.lat),"longitude":\(item.lng)},"expiresAt":"2026-11-11T10:30:00Z","peopleAhead":null,"currentPickupRemainingSeconds":null,"currentPickupValidForMillis":0,"driverInvitation":\(item.driverInvitation)}
                """, nil)
            }
            return (404, #"{"code":"NOT_FOUND"}"#, nil)

        case ("GET", "/api/v1/accounts/search"):
            let _ = query
            return (200, """
            [
              {"memberId":"99999999-8888-4777-8666-555555555555","majungId":"minsu_car","nickname":"김민수"},
              {"memberId":"88888888-7777-4666-8555-444444444444","majungId":"minsu_kim","nickname":"김민수"}
            ]
            """, nil)

        case ("GET", "/api/v1/connections"):
            return (200, """
            [
              {"connectionId":"11111111-1111-4111-8111-111111111111","majungId":"minsu_car","nickname":"김민수","status":"ACCEPTED","direction":"OUTGOING"}
            ]
            """, nil)

        case ("GET", "/api/v1/vehicle-links"):
            let items = vehicles.map {
                #"{"vehicleId":"\#($0.id)","vehicleName":"\#($0.name)","linkedAt":"\#($0.linkedAt)"}"#
            }.joined(separator: ",")
            return (200, "[\(items)]", nil)

        case ("DELETE", "/api/v1/vehicle-links/\(initialVehicleId)"):
            vehicles.removeAll { $0.id == initialVehicleId }
            return (204, "", nil)

        case ("POST", "/api/v1/vehicle-links/requests"):
            pendingChallenge = (newChallengeId, "쏘렌토 하이브리드", "AWAITING_VEHICLE_CONFIRMATION")
            return (200, """
            {"challengeId":"\(newChallengeId)","vehicleId":null,"vehicleName":"쏘렌토 하이브리드","status":"AWAITING_VEHICLE_CONFIRMATION","expiresAt":"\(pairingExpiresAt)"}
            """, nil)

        case ("GET", "/api/v1/vehicle-links/requests/\(newChallengeId)"):
            let status = pendingChallenge?.status ?? "AWAITING_VEHICLE_CONFIRMATION"
            let vid = status == "LINKED" ? "\"\(newVehicleId)\"" : "null"
            return (200, """
            {"challengeId":"\(newChallengeId)","vehicleId":\(vid),"vehicleName":"쏘렌토 하이브리드","status":"\(status)","expiresAt":"\(pairingExpiresAt)"}
            """, nil)

        default:
            return (404, #"{"code":"NOT_FOUND","message":"Not found"}"#, nil)
        }
    }

    private func guestSnapshotJSON() -> String {
        let statusStr = switch guestPhase {
        case .none, .waiting: "WAITING_APPROVAL"
        case .active: "ACTIVE"
        case .arrived: "ARRIVED"
        case .completed: "COMPLETED"
        }
        let completed = guestPhase == .completed
        let placeJSON = completed ? "null" : #"{"label":"의왕역 1호선 1번 출구 앞","latitude":37.3208,"longitude":126.9482}"#
        let vehicleNameJSON = completed ? "null" : #""흰색 아이오닉 5 · 12가 3456""#
        let proposalJSON = (!completed && guestPhase == .active && guestProposal != nil)
            ? #"{"place":{"label":"\#(guestProposal!.label)","latitude":\#(guestProposal!.lat),"longitude":\#(guestProposal!.lng)},"proposedBy":"PASSENGER"}"#
            : "null"
        let msgJSON = (!completed && guestQuickMessage != nil)
            ? #"{"text":"\#(guestQuickMessage!)"}"#
            : "null"
        return """
        {
          "pickupId": "\(pickupId)",
          "status": "\(statusStr)",
          "place": \(placeJSON),
          "placeVersion": 1,
          "participant": {
            "readiness": "\(guestReadiness)",
            "readinessSequence": \(guestReadinessSeq),
            "readinessReceivedSequence": \(guestReadinessReceivedSeq)
          },
          "placeProposal": \(proposalJSON),
          "quickMessage": \(msgJSON),
          "vehicleName": \(vehicleNameJSON)
        }
        """
    }

    private func memberSnapshotJSON() -> String {
        """
        {
          "pickupId": "\(pickupId)",
          "status": "\(memberPickupStatus)",
          "place": {"label":"의왕역 1호선 1번 출구 앞","latitude":37.3208,"longitude":126.9482},
          "placeVersion": 1,
          "participant": {
            "readiness": "\(memberReadiness)",
            "readinessSequence": \(memberReadinessSeq),
            "readinessReceivedSequence": \(memberReadinessReceivedSeq)
          },
          "placeProposal": null,
          "quickMessage": \(memberQuickMessage.map { #"{"text":"\#($0)"}"# } ?? "null"),
          "vehicleName": "흰색 아이오닉 5 · 12가 3456"
        }
        """
    }

    private func vehicleJSON() -> String {
        """
        {
          "freshness": "FRESH",
          "latitude": 37.3120,
          "longitude": 126.9410,
          "durationSeconds": 240,
          "validForMillis": 15000,
          "ageMillis": 2000,
          "placeVersion": 1
        }
        """
    }
}
