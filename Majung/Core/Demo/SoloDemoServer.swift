#if DEBUG
import Foundation
import Network

final class SoloDemoServer {
    static let shared = SoloDemoServer()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.majung.ios.SoloDemoServer")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var sseConnections: [NWConnection] = []

    var people: [DemoPerson] = []
    var connections: [DemoConnection] = []
    var requests: [DemoRequest] = []
    var pickups: [DemoPickup] = []
    var vehicleLinksByMember: [String: [DemoVehicleLink]] = [:]
    var pendingChallengeByMember: [String: DemoPendingChallenge] = [:]
    var sessions: [String: String] = [:] // cookie -> memberId

    let spareVehicleChallengeId = "30000000-0000-4000-8000-000000000099"
    let spareVehicleCode = "dev-spare-vehicle-qr-token-00000000000000001"
    let guestPickupId = "50000000-0000-4000-8000-000000000001"
    let guestInviteToken = "dev-guest-invite-token-00000000000000000001"
    let guestPollCounterLock = NSLock()
    var guestApprovalPolls = 0

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let placePresets: [PlacePreset] = [
        PlacePreset(label: "강남역 2번 출구", address: "서울 강남구 강남대로 396", category: "지하철역", lat: 37.4979, lng: 127.0276),
        PlacePreset(label: "강남역 11번 출구", address: "서울 강남구 테헤란로 101", category: "지하철역", lat: 37.4990, lng: 127.0272),
        PlacePreset(label: "광교중앙역 1번 출구", address: "경기 수원시 영통구 도청로 30", category: "지하철역", lat: 37.2886, lng: 127.0516),
        PlacePreset(label: "판교역 2번 출구", address: "경기 성남시 분당구 판교역로 160", category: "지하철역", lat: 37.3947, lng: 127.1112),
        PlacePreset(label: "정자역 3번 출구", address: "경기 성남시 분당구 성남대로 331", category: "지하철역", lat: 37.3670, lng: 127.1081),
        PlacePreset(label: "야탑역 1번 출구", address: "경기 성남시 분당구 성남대로 925", category: "지하철역", lat: 37.4114, lng: 127.1286),
        PlacePreset(label: "수원역 환승센터", address: "경기 수원시 팔달구 덕영대로 924", category: "기차/전철역", lat: 37.2660, lng: 127.0005),
        PlacePreset(label: "의왕역 1호선 1번 출구 앞", address: "경기 의왕시 철도박물관로 10", category: "지하철역", lat: 37.3208, lng: 126.9482),
        PlacePreset(label: "양재역 9번 출구", address: "서울 서초구 강남대로 202", category: "지하철역", lat: 37.4843, lng: 127.0346),
        PlacePreset(label: "선릉역 1번 출구", address: "서울 강남구 테헤란로 340", category: "지하철역", lat: 37.5045, lng: 127.0489),
        PlacePreset(label: "삼성역 6번 출구", address: "서울 강남구 테헤란로 538", category: "지하철역", lat: 37.5088, lng: 127.0631),
        PlacePreset(label: "서울역 1번 출구", address: "서울 중구 한강대로 405", category: "기차/전철역", lat: 37.5547, lng: 126.9707),
        PlacePreset(label: "홍대입구역 9번 출구", address: "서울 마포구 양화로 160", category: "지하철역", lat: 37.5572, lng: 126.9245),
        PlacePreset(label: "잠실역 8번 출구", address: "서울 송파구 올림픽로 265", category: "지하철역", lat: 37.5133, lng: 127.1001),
        PlacePreset(label: "여의도역 5번 출구", address: "서울 영등포구 여의나루로 42", category: "지하철역", lat: 37.5216, lng: 126.9243),
        PlacePreset(label: "사당역 10번 출구", address: "서울 동작구 동작대로 3", category: "지하철역", lat: 37.4765, lng: 126.9816),
        PlacePreset(label: "범계역 4번 출구", address: "경기 안양시 동안구 동안로 130", category: "지하철역", lat: 37.3897, lng: 126.9508),
        PlacePreset(label: "인덕원역 4번 출구", address: "경기 안양시 동안구 흥안대로 519", category: "지하철역", lat: 37.4017, lng: 126.9765),
        PlacePreset(label: "분당서울대학교병원 정문", address: "경기 성남시 분당구 구미로 173번길 82", category: "병원", lat: 37.3522, lng: 127.1235),
        PlacePreset(label: "코엑스 동문", address: "서울 강남구 영동대로 513", category: "복합문화공간", lat: 37.5116, lng: 127.0593),
        PlacePreset(label: "김포공항 국내선 3번 게이트", address: "서울 강서구 하늘길 112", category: "공항", lat: 37.5587, lng: 126.7945),
        PlacePreset(label: "인천공항 제1터미널 3층 7번", address: "인천 중구 공항로 272", category: "공항", lat: 37.4602, lng: 126.4407)
    ]

    private init() {
        resetState()
    }

    @discardableResult
    func ensureStarted() -> UInt16 {
        lock.lock()
        if port != 0, listener != nil {
            let current = port
            lock.unlock()
            return current
        }
        lock.unlock()

        do {
            let created = try NWListener(using: .tcp, on: .any)
            let ready = DispatchSemaphore(value: 0)
            var signalled = false
            created.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.lock.lock()
                    self?.port = created.port?.rawValue ?? 0
                    self?.lock.unlock()
                    if !signalled {
                        signalled = true
                        ready.signal()
                    }
                } else if case .failed = state {
                    if !signalled {
                        signalled = true
                        ready.signal()
                    }
                }
            }
            created.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            lock.lock()
            listener = created
            lock.unlock()
            created.start(queue: queue)
            _ = ready.wait(timeout: .now() + 8)
        } catch {
            // Keep port 0 if listener setup fails; callers will fall back cleanly.
        }
        lock.lock()
        let bound = port
        lock.unlock()
        return bound
    }

    var sampleVehicleQRString: String {
        "https://majung.cloud/#vehicle/\(spareVehicleChallengeId)/\(spareVehicleCode)"
    }

    var sampleGuestInviteString: String {
        "https://majung.cloud/#join/\(guestPickupId)/\(guestInviteToken)"
    }

    func resetState() {
        lock.lock()
        defer { lock.unlock() }
        sseConnections.forEach { $0.cancel() }
        sseConnections.removeAll()
        sessions.removeAll()
        guestPollCounterLock.lock()
        guestApprovalPolls = 0
        guestPollCounterLock.unlock()

        let selfId = "10000000-0000-4000-8000-000000000001"
        let minjunId = "10000000-0000-4000-8000-000000000002"
        let seoyeonId = "10000000-0000-4000-8000-000000000003"
        let dohyunId = "10000000-0000-4000-8000-000000000004"
        let woojinId = "10000000-0000-4000-8000-000000000005"
        let subinId = "10000000-0000-4000-8000-000000000006"
        let jiminId = "10000000-0000-4000-8000-000000000007"
        let jaehyukId = "10000000-0000-4000-8000-000000000008"
        let taeoId = "10000000-0000-4000-8000-000000000009"
        let chaewonId = "10000000-0000-4000-8000-000000000010"
        let hajunId = "10000000-0000-4000-8000-000000000011"
        let jiwooId = "10000000-0000-4000-8000-000000000012"
        let sujiId = "10000000-0000-4000-8000-000000000013"
        let yunaId = "10000000-0000-4000-8000-000000000014"
        let seonghunId = "10000000-0000-4000-8000-000000000015"
        let minjiId = "10000000-0000-4000-8000-000000000016"

        people = [
            DemoPerson(memberId: selfId, majungId: "MJ-DEMO001", nickname: "송승준", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000000", vehicleName: "승준 쏘나타"),
            DemoPerson(memberId: minjunId, majungId: "MJ-DRV001", nickname: "김민준 아이오닉5", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000001", vehicleName: "김민준 아이오닉5"),
            DemoPerson(memberId: seoyeonId, majungId: "MJ-DRV002", nickname: "이서연 카니발", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000002", vehicleName: "이서연 카니발"),
            DemoPerson(memberId: dohyunId, majungId: "MJ-DRV003", nickname: "박도현 쏘렌토", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000003", vehicleName: "박도현 쏘렌토"),
            DemoPerson(memberId: woojinId, majungId: "MJ-DRV004", nickname: "정우진 EV6", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000004", vehicleName: "정우진 EV6"),
            DemoPerson(memberId: subinId, majungId: "MJ-DRV005", nickname: "최수빈 카니발", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000005", vehicleName: "최수빈 카니발"),
            DemoPerson(memberId: jiminId, majungId: "MJ-DRV006", nickname: "한지민 아반떼", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000006", vehicleName: "한지민 아반떼"),
            DemoPerson(memberId: jaehyukId, majungId: "MJ-DRV007", nickname: "윤재혁 산타페", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000007", vehicleName: "윤재혁 산타페"),
            DemoPerson(memberId: taeoId, majungId: "MJ-DRV008", nickname: "강태오 모델3", driver: true,
                       vehicleId: "20000000-0000-4000-8000-000000000008", vehicleName: "강태오 모델3"),
            DemoPerson(memberId: chaewonId, majungId: "MJ-USR001", nickname: "오채원", driver: false, vehicleId: nil, vehicleName: nil),
            DemoPerson(memberId: hajunId, majungId: "MJ-USR002", nickname: "임하준", driver: false, vehicleId: nil, vehicleName: nil),
            DemoPerson(memberId: jiwooId, majungId: "MJ-USR003", nickname: "신지우", driver: false, vehicleId: nil, vehicleName: nil),
            DemoPerson(memberId: sujiId, majungId: "MJ-USR004", nickname: "배수지", driver: false, vehicleId: nil, vehicleName: nil),
            DemoPerson(memberId: yunaId, majungId: "MJ-USR005", nickname: "홍유나", driver: false, vehicleId: nil, vehicleName: nil),
            DemoPerson(memberId: seonghunId, majungId: "MJ-USR006", nickname: "조성훈", driver: false, vehicleId: nil, vehicleName: nil),
            DemoPerson(memberId: minjiId, majungId: "MJ-USR007", nickname: "장민지", driver: false, vehicleId: nil, vehicleName: nil)
        ]

        vehicleLinksByMember = [:]
        for p in people {
            if let vid = p.vehicleId, let vname = p.vehicleName {
                vehicleLinksByMember[p.memberId] = [
                    DemoVehicleLink(vehicleId: vid, vehicleName: vname, linkedAt: Self.isoFormatter.string(from: Date().addingTimeInterval(-3600)))
                ]
            } else {
                vehicleLinksByMember[p.memberId] = []
            }
        }
        pendingChallengeByMember = [:]

        connections = [
            DemoConnection(id: "60000000-0000-4000-8000-000000000001", status: "ACCEPTED", requesterId: selfId, recipientId: minjunId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000002", status: "ACCEPTED", requesterId: seoyeonId, recipientId: selfId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000003", status: "ACCEPTED", requesterId: subinId, recipientId: selfId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000004", status: "ACCEPTED", requesterId: jiminId, recipientId: selfId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000005", status: "ACCEPTED", requesterId: selfId, recipientId: chaewonId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000006", status: "PENDING", requesterId: dohyunId, recipientId: selfId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000007", status: "PENDING", requesterId: jiwooId, recipientId: selfId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000008", status: "PENDING", requesterId: selfId, recipientId: woojinId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000009", status: "PENDING", requesterId: selfId, recipientId: sujiId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000010", status: "ACCEPTED", requesterId: minjunId, recipientId: chaewonId),
            DemoConnection(id: "60000000-0000-4000-8000-000000000011", status: "ACCEPTED", requesterId: minjunId, recipientId: jiwooId)
        ]

        let selfPickupId = "50000000-0000-4000-8000-000000000010"
        let aheadPickupId = "50000000-0000-4000-8000-000000000011"
        pickups = [
            DemoPickup(
                id: selfPickupId,
                vehicleName: "최수빈 카니발",
                participantId: "70000000-0000-4000-8000-000000000001",
                participantName: "송승준",
                participantToken: nil,
                inviteToken: nil,
                status: "ACTIVE",
                placeLabel: "광교중앙역 1번 출구",
                lat: 37.2886,
                lng: 127.0516,
                carLat: 37.2820,
                carLng: 127.0460,
                durationSeconds: 240,
                placeVersion: 1,
                readiness: "PREPARING",
                readinessSeq: 1,
                readinessReceivedSeq: 1,
                proposalLabel: nil,
                proposalLat: nil,
                proposalLng: nil,
                proposalBy: nil,
                quickMessage: "잠시만요, 1번 출구로 가고 있어요!"
            ),
            DemoPickup(
                id: aheadPickupId,
                vehicleName: "김민준 아이오닉5",
                participantId: "70000000-0000-4000-8000-000000000002",
                participantName: "오채원",
                participantToken: nil,
                inviteToken: nil,
                status: "ACTIVE",
                placeLabel: "야탑역 1번 출구",
                lat: 37.4114,
                lng: 127.1286,
                carLat: 37.4050,
                carLng: 127.1210,
                durationSeconds: 360,
                placeVersion: 1,
                readiness: "READY",
                readinessSeq: 1,
                readinessReceivedSeq: 1,
                proposalLabel: nil,
                proposalLat: nil,
                proposalLng: nil,
                proposalBy: nil,
                quickMessage: "지금 1번 출구 앞이에요!"
            ),
            DemoPickup(
                id: guestPickupId,
                vehicleName: "강태오 모델3",
                participantId: nil,
                participantName: nil,
                participantToken: nil,
                inviteToken: guestInviteToken,
                status: "INVITING",
                placeLabel: "의왕역 1호선 1번 출구 앞",
                lat: 37.3208,
                lng: 126.9482,
                carLat: 37.3150,
                carLng: 126.9425,
                durationSeconds: 210,
                placeVersion: 1,
                readiness: "WAITING",
                readinessSeq: 0,
                readinessReceivedSeq: 0,
                proposalLabel: nil,
                proposalLat: nil,
                proposalLng: nil,
                proposalBy: nil,
                quickMessage: nil
            )
        ]

        let expiry = Date().addingTimeInterval(7200)
        requests = [
            DemoRequest(
                id: "40000000-0000-4000-8000-000000000001",
                status: "ACTIVE",
                driverId: subinId,
                passengerId: selfId,
                vehicleId: "20000000-0000-4000-8000-000000000005",
                pickupId: selfPickupId,
                placeLabel: "광교중앙역 1번 출구",
                lat: 37.2886,
                lng: 127.0516,
                driverInvitation: false,
                peopleAhead: 0,
                remainingSeconds: 240,
                expiresAt: expiry
            ),
            DemoRequest(
                id: "40000000-0000-4000-8000-000000000002",
                status: "INVITED",
                driverId: seoyeonId,
                passengerId: selfId,
                vehicleId: "20000000-0000-4000-8000-000000000002",
                pickupId: nil,
                placeLabel: "판교역 2번 출구",
                lat: 37.3947,
                lng: 127.1112,
                driverInvitation: true,
                peopleAhead: nil,
                remainingSeconds: nil,
                expiresAt: expiry
            ),
            DemoRequest(
                id: "40000000-0000-4000-8000-000000000003",
                status: "INVITED",
                driverId: jiminId,
                passengerId: selfId,
                vehicleId: "20000000-0000-4000-8000-000000000006",
                pickupId: nil,
                placeLabel: "정자역 3번 출구",
                lat: 37.3670,
                lng: 127.1081,
                driverInvitation: true,
                peopleAhead: nil,
                remainingSeconds: nil,
                expiresAt: expiry
            ),
            DemoRequest(
                id: "40000000-0000-4000-8000-000000000004",
                status: "PENDING",
                driverId: dohyunId,
                passengerId: selfId,
                vehicleId: "20000000-0000-4000-8000-000000000003",
                pickupId: nil,
                placeLabel: "강남역 11번 출구",
                lat: 37.4990,
                lng: 127.0272,
                driverInvitation: false,
                peopleAhead: nil,
                remainingSeconds: nil,
                expiresAt: expiry
            ),
            DemoRequest(
                id: "40000000-0000-4000-8000-000000000006",
                status: "QUEUED",
                driverId: minjunId,
                passengerId: selfId,
                vehicleId: "20000000-0000-4000-8000-000000000001",
                pickupId: nil,
                placeLabel: "수원역 환승센터",
                lat: 37.2660,
                lng: 127.0005,
                driverInvitation: false,
                peopleAhead: 1,
                remainingSeconds: 360,
                expiresAt: expiry
            )
        ]
    }

    // MARK: - Networking

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveHTTP(on: conn, buffer: Data())
    }

    private func receiveHTTP(on conn: NWConnection, buffer: Data) {
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
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    let kv = line.split(separator: ":", maxSplits: 1)
                    if kv.count == 2 {
                        headers[kv[0].trimmingCharacters(in: .whitespaces).lowercased()] = kv[1].trimmingCharacters(in: .whitespaces)
                    }
                }
                let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
                let bodyStart = headerRange.upperBound
                if next.count - bodyStart < contentLength && !isComplete {
                    self.receiveHTTP(on: conn, buffer: next)
                    return
                }
                let body = next.subdata(in: bodyStart..<min(next.count, bodyStart + contentLength))
                self.dispatch(method: method, target: target, headers: headers, body: body, conn: conn)
            } else if !isComplete {
                self.receiveHTTP(on: conn, buffer: next)
            } else {
                conn.cancel()
            }
        }
    }

    private func dispatch(method: String, target: String, headers: [String: String], body: Data, conn: NWConnection) {
        let split = target.components(separatedBy: "?")
        let path = split[0]
        let queryString = split.count > 1 ? split[1] : ""

        if path.hasSuffix("/events") {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n: ok\n\n"
            lock.lock()
            sseConnections.append(conn)
            lock.unlock()
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            return
        }

        lock.lock()
        let (status, payload, cookie) = buildResponse(method: method, path: path, queryString: queryString, headers: headers, body: body)
        lock.unlock()

        let bytes = Data(payload.utf8)
        var head = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n"
        if let cookie {
            head += "Set-Cookie: JSESSIONID=\(cookie); Path=/; HttpOnly\r\n"
        }
        head += "\r\n"
        var packet = Data(head.utf8)
        packet.append(bytes)
        conn.send(content: packet, completion: .contentProcessed { _ in conn.cancel() })
    }

    func notifySSE() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let targets = self.sseConnections
            self.lock.unlock()
            let msg = Data("event: changed\r\ndata: refresh\r\n\r\n".utf8)
            for conn in targets {
                conn.send(content: msg, completion: .contentProcessed { _ in })
            }
        }
    }

}
#endif
