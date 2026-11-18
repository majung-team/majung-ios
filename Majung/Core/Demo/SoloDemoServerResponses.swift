#if DEBUG
import Foundation

extension SoloDemoServer {
    // MARK: - Helpers

    private func extractSessionCookie(from headers: [String: String]) -> String? {
        guard let raw = headers["cookie"] else { return nil }
        for part in raw.components(separatedBy: ";") {
            let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0] == "JSESSIONID" {
                return String(kv[1])
            }
        }
        return nil
    }

    private func currentMember(from headers: [String: String]) -> DemoPerson? {
        guard let cookie = extractSessionCookie(from: headers),
              let mid = sessions[cookie] else {
            return nil
        }
        return people.first(where: { $0.memberId.caseInsensitiveCompare(mid) == .orderedSame })
    }

    private func memberJSON(_ person: DemoPerson) -> String {
        #"{"memberId":"\#(person.memberId)","majungId":"\#(person.majungId)","nickname":"\#(escapeJSON(person.nickname))","profileReady":true}"#
    }

    private func parseQuery(_ raw: String) -> [String: String] {
        var map: [String: String] = [:]
        for pair in raw.components(separatedBy: "&") where !pair.isEmpty {
            let kv = pair.components(separatedBy: "=")
            let k = kv[0].removingPercentEncoding ?? kv[0]
            let v = (kv.count > 1 ? kv[1] : "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            map[k] = v
        }
        return map
    }

    private func jsonBody(_ body: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }

    private func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func errorJSON(_ status: Int, _ code: String, _ message: String) -> (Int, String, String?) {
        (status, #"{"code":"\#(code)","message":"\#(escapeJSON(message))"}"#, nil)
    }

    // MARK: - Request Router

    func buildResponse(
        method: String,
        path: String,
        queryString: String,
        headers: [String: String],
        body: Data
    ) -> (Int, String, String?) {
        let query = parseQuery(queryString)
        let obj = jsonBody(body)

        // Dev Sandbox API compatible with majung-backend
        if path == "/api/v1/dev/accounts" && method == "GET" {
            let items = people.map { p in
                let vJson = p.vehicleName.map { "\"\(escapeJSON($0))\"" } ?? "null"
                return #"{"memberId":"\#(p.memberId)","majungId":"\#(p.majungId)","nickname":"\#(escapeJSON(p.nickname))","profileReady":true,"driver":\#(p.driver),"vehicleName":\#(vJson)}"#
            }.joined(separator: ",")
            return (200, "[\(items)]", nil)
        }

        if path == "/api/v1/dev/login" && method == "POST" {
            let requestedId = (obj["memberId"] as? String)
                ?? people.first?.memberId
            let target = people.first(where: { $0.memberId.caseInsensitiveCompare(requestedId ?? "") == .orderedSame }) ?? people[0]
            let newCookie = "demo-session-\(UUID().uuidString.lowercased())"
            sessions[newCookie] = target.memberId
            return (200, memberJSON(target), newCookie)
        }

        if path == "/api/v1/dev/reset" && method == "POST" {
            resetState()
            return (200, #"{"ok":true}"#, nil)
        }

        if path == "/api/v1/dev/simulate/vehicle-tick" && method == "POST" {
            let action = (obj["action"] as? String) ?? "approach"
            let targetPickupId = (obj["pickupId"] as? String)
            if let idx = pickups.firstIndex(where: { p in
                if let targetPickupId { return p.id.caseInsensitiveCompare(targetPickupId) == .orderedSame }
                return p.status == "ACTIVE" || p.status == "ARRIVED"
            }) {
                let p = applyVehicleTick(at: idx, action: action)
                notifySSE()
                return (200, snapshotJSON(p), nil)
            }
            return errorJSON(404, "PICKUP_NOT_FOUND", "진행 중인 픽업이 없어요.")
        }

        if path == "/api/v1/dev/simulate/driver-invite" && method == "POST" {
            let member = currentMember(from: headers) ?? people[0]
            let newReqId = UUID().uuidString.lowercased()
            let driver = people.first(where: { $0.memberId == "10000000-0000-4000-8000-000000000004" }) ?? people[1]
            let item = DemoRequest(
                id: newReqId,
                status: "INVITED",
                driverId: driver.memberId,
                passengerId: member.memberId,
                vehicleId: driver.vehicleId,
                pickupId: nil,
                placeLabel: "서울역 1번 출구",
                lat: 37.5547,
                lng: 126.9707,
                driverInvitation: true,
                peopleAhead: nil,
                remainingSeconds: nil,
                expiresAt: Date().addingTimeInterval(3600)
            )
            requests.insert(item, at: 0)
            notifySSE()
            return (200, requestJSON(item, viewerId: member.memberId), nil)
        }

        if path == "/api/v1/dev/simulate/guest-invite" && method == "POST" {
            let link = sampleGuestInviteString
            return (200, #"{"pickupId":"\#(guestPickupId)","inviteToken":"\#(guestInviteToken)","link":"\#(link)","placeLabel":"의왕역 1호선 1번 출구 앞"}"#, nil)
        }

        if path == "/api/v1/places/search" && method == "GET" {
            let q = (query["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                return (200, #"{"enabled":true,"items":[],"hasNext":false}"#, nil)
            }
            let matched = Self.placePresets.filter {
                $0.label.localizedCaseInsensitiveContains(q)
                    || $0.address.localizedCaseInsensitiveContains(q)
                    || $0.category.localizedCaseInsensitiveContains(q)
            }
            let items = matched.prefix(8).map {
                #"{"label":"\#(escapeJSON($0.label))","address":"\#(escapeJSON($0.address))","category":"\#(escapeJSON($0.category))","latitude":\#($0.lat),"longitude":\#($0.lng)}"#
            }.joined(separator: ",")
            return (200, #"{"enabled":true,"items":[\#(items)],"hasNext":false}"#, nil)
        }

        // Auth endpoints
        if path == "/api/v1/auth/session" && method == "GET" {
            if let me = currentMember(from: headers) {
                return (200, #"{"loginEnabled":true,"authenticated":true,"member":\#(memberJSON(me)),"csrfToken":"demo-csrf"}"#, nil)
            }
            return (200, #"{"loginEnabled":true,"authenticated":false,"member":null,"csrfToken":null}"#, nil)
        }

        if path == "/api/v1/auth/logout" && method == "POST" {
            if let cookie = extractSessionCookie(from: headers) {
                sessions.removeValue(forKey: cookie)
            }
            return (200, #"{"ok":true}"#, nil)
        }

        if path == "/api/v1/accounts/me" && method == "PATCH" {
            guard let me = currentMember(from: headers),
                  let idx = people.firstIndex(where: { $0.memberId == me.memberId }) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            if let next = obj["nickname"] as? String {
                people[idx].nickname = next
            }
            return (200, memberJSON(people[idx]), nil)
        }

        if path == "/api/v1/accounts/me" && method == "DELETE" {
            if let cookie = extractSessionCookie(from: headers) {
                sessions.removeValue(forKey: cookie)
            }
            return (204, "", nil)
        }

        if path == "/api/v1/accounts/search" && method == "GET" {
            guard let me = currentMember(from: headers) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            let q = (query["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = people.filter { p in
                p.memberId != me.memberId && (p.nickname.localizedCaseInsensitiveContains(q) || p.majungId.localizedCaseInsensitiveContains(q))
            }
            let items = matches.map {
                #"{"memberId":"\#($0.memberId)","majungId":"\#($0.majungId)","nickname":"\#(escapeJSON($0.nickname))"}"#
            }.joined(separator: ",")
            return (200, "[\(items)]", nil)
        }

        // Connections
        if path == "/api/v1/connections" && method == "GET" {
            guard let me = currentMember(from: headers) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            let selfId = me.memberId
            let items = connections.compactMap { c -> String? in
                guard c.requesterId == selfId || c.recipientId == selfId else { return nil }
                let peerId = c.requesterId == selfId ? c.recipientId : c.requesterId
                guard let peer = people.first(where: { $0.memberId == peerId }) else { return nil }
                let direction = c.requesterId == selfId ? "OUTGOING" : "INCOMING"
                return #"{"connectionId":"\#(c.id)","majungId":"\#(peer.majungId)","nickname":"\#(escapeJSON(peer.nickname))","status":"\#(c.status)","direction":"\#(direction)"}"#
            }.joined(separator: ",")
            return (200, "[\(items)]", nil)
        }

        if path == "/api/v1/connections" && method == "POST" {
            guard let me = currentMember(from: headers) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            let targetId = obj["memberId"] as? String ?? ""
            guard let peer = people.first(where: { $0.memberId.caseInsensitiveCompare(targetId) == .orderedSame }) else {
                return errorJSON(404, "MEMBER_NOT_FOUND", "회원을 찾을 수 없어요.")
            }
            let conn = DemoConnection(id: UUID().uuidString.lowercased(), status: "ACCEPTED", requesterId: me.memberId, recipientId: peer.memberId)
            connections.removeAll {
                ($0.requesterId == me.memberId && $0.recipientId == peer.memberId)
                    || ($0.recipientId == me.memberId && $0.requesterId == peer.memberId)
            }
            connections.insert(conn, at: 0)
            return (200, #"{"connectionId":"\#(conn.id)","majungId":"\#(peer.majungId)","nickname":"\#(escapeJSON(peer.nickname))","status":"ACCEPTED","direction":"OUTGOING"}"#, nil)
        }

        if path.hasPrefix("/api/v1/connections/") && method == "POST" {
            let comps = path.split(separator: "/")
            if comps.count == 5 {
                let cid = String(comps[3])
                let action = String(comps[4])
                if let idx = connections.firstIndex(where: { $0.id.caseInsensitiveCompare(cid) == .orderedSame }) {
                    let conn = connections[idx]
                    let viewerId = currentMember(from: headers)?.memberId ?? people[0].memberId
                    let peerId = conn.requesterId == viewerId ? conn.recipientId : conn.requesterId
                    let peer = people.first(where: { $0.memberId == peerId })
                    switch action {
                    case "accept":
                        connections[idx].status = "ACCEPTED"
                        return (200, #"{"connectionId":"\#(conn.id)","majungId":"\#(peer?.majungId ?? "")","nickname":"\#(escapeJSON(peer?.nickname ?? ""))","status":"ACCEPTED","direction":"INCOMING"}"#, nil)
                    case "reject", "cancel", "disconnect":
                        connections.remove(at: idx)
                        return (200, #"{"connectionId":"\#(conn.id)","majungId":"\#(peer?.majungId ?? "")","nickname":"\#(escapeJSON(peer?.nickname ?? ""))","status":"CANCELLED","direction":"OUTGOING"}"#, nil)
                    default:
                        break
                    }
                }
            }
            return errorJSON(404, "CONNECTION_NOT_FOUND", "연결을 찾을 수 없어요.")
        }

        // Vehicle Links
        if path == "/api/v1/vehicle-links" && method == "GET" {
            guard let me = currentMember(from: headers) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            let list = vehicleLinksByMember[me.memberId] ?? []
            let items = list.map {
                #"{"vehicleId":"\#($0.vehicleId)","vehicleName":"\#(escapeJSON($0.vehicleName))","linkedAt":"\#($0.linkedAt)"}"#
            }.joined(separator: ",")
            return (200, "[\(items)]", nil)
        }

        if path.hasPrefix("/api/v1/vehicle-links/") && method == "DELETE" {
            guard let me = currentMember(from: headers) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            let vid = String(path.split(separator: "/").last ?? "")
            vehicleLinksByMember[me.memberId]?.removeAll { $0.vehicleId.caseInsensitiveCompare(vid) == .orderedSame }
            return (204, "", nil)
        }

        if path == "/api/v1/vehicle-links/requests" && method == "POST" {
            guard let me = currentMember(from: headers) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            let challengeId = (obj["challengeId"] as? String) ?? spareVehicleChallengeId
            let pending = DemoPendingChallenge(
                challengeId: challengeId,
                vehicleId: "20000000-0000-4000-8000-000000000099",
                vehicleName: "전시용 쏘나타",
                status: "AWAITING_VEHICLE_CONFIRMATION",
                pollCount: 0,
                expiresAt: Date().addingTimeInterval(600)
            )
            pendingChallengeByMember[me.memberId] = pending
            return (200, challengeJSON(pending), nil)
        }

        if path.hasPrefix("/api/v1/vehicle-links/requests/") && method == "GET" {
            guard let me = currentMember(from: headers),
                  var pending = pendingChallengeByMember[me.memberId] else {
                return errorJSON(404, "NOT_FOUND", "연결 요청을 찾을 수 없어요.")
            }
            pending.pollCount += 1
            if pending.pollCount >= 2 && pending.status != "LINKED" {
                pending.status = "LINKED"
                var list = vehicleLinksByMember[me.memberId] ?? []
                if !list.contains(where: { $0.vehicleId == pending.vehicleId }) {
                    list.append(DemoVehicleLink(vehicleId: pending.vehicleId, vehicleName: pending.vehicleName, linkedAt: Self.isoFormatter.string(from: Date())))
                    vehicleLinksByMember[me.memberId] = list
                }
            }
            pendingChallengeByMember[me.memberId] = pending
            return (200, challengeJSON(pending), nil)
        }

        if path.hasPrefix("/api/v1/vehicle-links/requests/") && path.hasSuffix("/cancel") && method == "POST" {
            if let me = currentMember(from: headers) {
                pendingChallengeByMember.removeValue(forKey: me.memberId)
            }
            return (204, "", nil)
        }

        // Ride Requests
        if path == "/api/v1/ride-requests" && method == "GET" {
            guard let me = currentMember(from: headers) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            let items = requests.filter { $0.passengerId == me.memberId || $0.driverId == me.memberId }
                .map { requestJSON($0, viewerId: me.memberId) }.joined(separator: ",")
            return (200, #"{"requests":[\#(items)]}"#, nil)
        }

        if path == "/api/v1/ride-requests" && method == "POST" {
            guard let me = currentMember(from: headers) else {
                return errorJSON(401, "LOGIN_REQUIRED", "다시 로그인해주세요.")
            }
            let driverId = (obj["driverId"] as? String) ?? people[1].memberId
            let reqId = (obj["requestId"] as? String) ?? UUID().uuidString.lowercased()
            let place = obj["place"] as? [String: Any] ?? [:]
            let label = (place["label"] as? String) ?? "강남역 2번 출구"
            let lat = (place["latitude"] as? Double) ?? 37.4979
            let lng = (place["longitude"] as? Double) ?? 127.0276
            let driver = people.first(where: { $0.memberId.caseInsensitiveCompare(driverId) == .orderedSame }) ?? people[1]

            let newPickupId = UUID().uuidString.lowercased()
            let newPickup = DemoPickup(
                id: newPickupId,
                vehicleName: driver.vehicleName ?? driver.nickname,
                participantId: UUID().uuidString.lowercased(),
                participantName: me.nickname,
                participantToken: nil,
                inviteToken: nil,
                status: "ACTIVE",
                placeLabel: label,
                lat: lat,
                lng: lng,
                carLat: lat - 0.009,
                carLng: lng - 0.007,
                durationSeconds: 300,
                placeVersion: 1,
                readiness: "NOT_READY",
                readinessSeq: 1,
                readinessReceivedSeq: 1,
                proposalLabel: nil,
                proposalLat: nil,
                proposalLng: nil,
                proposalBy: nil,
                quickMessage: nil
            )
            pickups.insert(newPickup, at: 0)
            let created = DemoRequest(
                id: reqId,
                status: "ACTIVE",
                driverId: driver.memberId,
                passengerId: me.memberId,
                vehicleId: driver.vehicleId,
                pickupId: newPickupId,
                placeLabel: label,
                lat: lat,
                lng: lng,
                driverInvitation: false,
                peopleAhead: 0,
                remainingSeconds: 300,
                expiresAt: Date().addingTimeInterval(7200)
            )
            requests.insert(created, at: 0)
            return (200, requestJSON(created, viewerId: me.memberId), nil)
        }

        if path.hasPrefix("/api/v1/ride-requests/") {
            let comps = path.split(separator: "/").map(String.init)
            if comps.count >= 5 {
                let rid = comps[3]
                let op = comps[4]
                guard let reqIdx = requests.firstIndex(where: { $0.id.caseInsensitiveCompare(rid) == .orderedSame }) else {
                    return errorJSON(404, "NOT_FOUND", "요청을 찾을 수 없어요.")
                }
                var req = requests[reqIdx]
                let viewerId = currentMember(from: headers)?.memberId ?? req.passengerId
                switch (method, op) {
                case ("POST", "accept-invitation"):
                    let newPid = UUID().uuidString.lowercased()
                    let drv = people.first(where: { $0.memberId == req.driverId })
                    let pas = people.first(where: { $0.memberId == req.passengerId })
                    pickups.insert(DemoPickup(
                        id: newPid, vehicleName: drv?.vehicleName ?? "마중 차량",
                        participantId: UUID().uuidString.lowercased(), participantName: pas?.nickname ?? "탑승자",
                        participantToken: nil, inviteToken: nil, status: "ACTIVE",
                        placeLabel: req.placeLabel, lat: req.lat, lng: req.lng,
                        carLat: req.lat - 0.008, carLng: req.lng - 0.006, durationSeconds: 240,
                        placeVersion: 1, readiness: "NOT_READY", readinessSeq: 1, readinessReceivedSeq: 1,
                        proposalLabel: nil, proposalLat: nil, proposalLng: nil, proposalBy: nil, quickMessage: nil
                    ), at: 0)
                    req.status = "ACTIVE"
                    req.pickupId = newPid
                    req.peopleAhead = 0
                    req.remainingSeconds = 240
                    requests[reqIdx] = req
                    return (200, requestJSON(req, viewerId: viewerId), nil)
                case ("POST", "reject-invitation"):
                    req.status = "REJECTED"
                    requests[reqIdx] = req
                    return (200, requestJSON(req, viewerId: viewerId), nil)
                case ("POST", "cancel"):
                    req.status = "CANCELLED"
                    requests[reqIdx] = req
                    return (200, requestJSON(req, viewerId: viewerId), nil)
                case ("GET", "tracking"):
                    guard let pid = req.pickupId,
                          let pIdx = pickups.firstIndex(where: { $0.id == pid }) else {
                        return errorJSON(409, "NOT_ACTIVE", "아직 픽업이 시작되지 않았어요.")
                    }
                    let p = pickups[pIdx]
                    return (200, #"{"pickup":\#(snapshotJSON(p)),"vehicle":\#(vehicleJSON(p))}"#, nil)
                case ("PUT", "readiness"):
                    if let pid = req.pickupId, let pIdx = pickups.firstIndex(where: { $0.id == pid }) {
                        pickups[pIdx].readiness = (obj["readiness"] as? String) ?? "READY"
                        pickups[pIdx].readinessSeq = (obj["sequence"] as? Int) ?? (pickups[pIdx].readinessSeq + 1)
                        pickups[pIdx].readinessReceivedSeq = pickups[pIdx].readinessSeq
                        return (200, snapshotJSON(pickups[pIdx]), nil)
                    }
                case ("PUT", "place-proposal"):
                    if let pid = req.pickupId, let pIdx = pickups.firstIndex(where: { $0.id == pid }),
                       let place = obj["place"] as? [String: Any] {
                        pickups[pIdx].proposalLabel = place["label"] as? String
                        pickups[pIdx].proposalLat = place["latitude"] as? Double
                        pickups[pIdx].proposalLng = place["longitude"] as? Double
                        pickups[pIdx].proposalBy = "PASSENGER"
                        return (200, snapshotJSON(pickups[pIdx]), nil)
                    }
                case ("DELETE", "place-proposal"):
                    if let pid = req.pickupId, let pIdx = pickups.firstIndex(where: { $0.id == pid }) {
                        pickups[pIdx].proposalLabel = nil
                        pickups[pIdx].proposalLat = nil
                        pickups[pIdx].proposalLng = nil
                        pickups[pIdx].proposalBy = nil
                        return (200, snapshotJSON(pickups[pIdx]), nil)
                    }
                case ("POST", "quick-message"):
                    if let pid = req.pickupId, let pIdx = pickups.firstIndex(where: { $0.id == pid }) {
                        pickups[pIdx].quickMessage = (obj["message"] as? String)
                        return (200, snapshotJSON(pickups[pIdx]), nil)
                    }
                case ("PUT", "arrival-push"):
                    return (204, "", nil)
                default:
                    break
                }
            }
        }

        // Guest Pickup endpoints
        if path.hasPrefix("/api/v1/pickups/") {
            let comps = path.split(separator: "/").map(String.init)
            let pid = comps.count >= 4 ? comps[3] : ""
            guard let pIdx = pickups.firstIndex(where: { $0.id.caseInsensitiveCompare(pid) == .orderedSame }) else {
                return errorJSON(404, "PICKUP_NOT_FOUND", "초대를 찾을 수 없어요.")
            }
            if comps.count == 4 && method == "GET" {
                var p = pickups[pIdx]
                if p.status == "WAITING_APPROVAL" {
                    guestPollCounterLock.lock()
                    guestApprovalPolls += 1
                    let polls = guestApprovalPolls
                    guestPollCounterLock.unlock()
                    if polls >= 2 {
                        p.status = "ACTIVE"
                        pickups[pIdx] = p
                    }
                }
                return (200, snapshotJSON(p), nil)
            }
            let op = comps.count >= 5 ? comps[4] : ""
            switch (method, op) {
            case ("POST", "invitation-preview"):
                return (200, #"{"placeLabel":"\#(escapeJSON(pickups[pIdx].placeLabel))"}"#, nil)
            case ("POST", "participants"):
                let pToken = "demo-guest-\(UUID().uuidString.lowercased())"
                pickups[pIdx].participantId = UUID().uuidString.lowercased()
                pickups[pIdx].participantName = "게스트"
                pickups[pIdx].participantToken = pToken
                pickups[pIdx].status = "WAITING_APPROVAL"
                guestPollCounterLock.lock()
                guestApprovalPolls = 0
                guestPollCounterLock.unlock()
                return (200, #"{"participantId":"\#(pickups[pIdx].participantId!)","participantToken":"\#(pToken)","status":"WAITING_APPROVAL"}"#, nil)
            case ("GET", "vehicle-state"):
                return (200, vehicleJSON(pickups[pIdx]), nil)
            case ("PUT", "readiness"):
                pickups[pIdx].readiness = (obj["readiness"] as? String) ?? "READY"
                pickups[pIdx].readinessSeq = (obj["sequence"] as? Int) ?? (pickups[pIdx].readinessSeq + 1)
                pickups[pIdx].readinessReceivedSeq = pickups[pIdx].readinessSeq
                return (200, snapshotJSON(pickups[pIdx]), nil)
            case ("PUT", "place-proposal"):
                if let place = obj["place"] as? [String: Any] {
                    pickups[pIdx].proposalLabel = place["label"] as? String
                    pickups[pIdx].proposalLat = place["latitude"] as? Double
                    pickups[pIdx].proposalLng = place["longitude"] as? Double
                    pickups[pIdx].proposalBy = "PASSENGER"
                }
                return (200, snapshotJSON(pickups[pIdx]), nil)
            case ("DELETE", "place-proposal"):
                pickups[pIdx].proposalLabel = nil
                pickups[pIdx].proposalLat = nil
                pickups[pIdx].proposalLng = nil
                pickups[pIdx].proposalBy = nil
                return (200, snapshotJSON(pickups[pIdx]), nil)
            case ("POST", "quick-message"):
                pickups[pIdx].quickMessage = obj["message"] as? String
                return (200, snapshotJSON(pickups[pIdx]), nil)
            case ("POST", "leave"):
                pickups[pIdx].status = "INVITING"
                pickups[pIdx].participantId = nil
                pickups[pIdx].participantName = nil
                pickups[pIdx].participantToken = nil
                return (204, "", nil)
            case ("PUT", "arrival-push"):
                return (204, "", nil)
            default:
                break
            }
        }

        return errorJSON(404, "NOT_FOUND", "요청한 데모 경로를 찾지 못했어요.")
    }

    private func applyVehicleTick(at idx: Int, action: String) -> DemoPickup {
        var p = pickups[idx]
        switch action {
        case "approach":
            p.carLat += (p.lat - p.carLat) * 0.4
            p.carLng += (p.lng - p.carLng) * 0.4
            p.durationSeconds = max(30, p.durationSeconds - 60)
            p.status = "ACTIVE"
        case "arrive":
            p.carLat = p.lat
            p.carLng = p.lng
            p.durationSeconds = 0
            p.status = "ARRIVED"
        case "complete":
            p.carLat = p.lat
            p.carLng = p.lng
            p.durationSeconds = 0
            p.status = "COMPLETED"
            for rIdx in requests.indices where requests[rIdx].pickupId == p.id {
                requests[rIdx].status = "COMPLETED"
            }
        default:
            break
        }
        pickups[idx] = p
        return p
    }

    private func challengeJSON(_ c: DemoPendingChallenge) -> String {
        let vidJson = c.status == "LINKED" ? "\"\(c.vehicleId)\"" : "null"
        return #"{"challengeId":"\#(c.challengeId)","vehicleId":\#(vidJson),"vehicleName":"\#(escapeJSON(c.vehicleName))","status":"\#(c.status)","expiresAt":"\#(Self.isoFormatter.string(from: c.expiresAt))"}"#
    }

    private func requestJSON(_ r: DemoRequest, viewerId: String) -> String {
        let driver = people.first(where: { $0.memberId == r.driverId })
        let passenger = people.first(where: { $0.memberId == r.passengerId })
        let displayPerson = viewerId == r.driverId ? passenger : driver
        let aheadJson = r.peopleAhead.map(String.init) ?? "null"
        let remJson = r.remainingSeconds.map(String.init) ?? "null"
        return """
        {"requestId":"\(r.id)","status":"\(r.status)","nickname":"\(escapeJSON(displayPerson?.nickname ?? "마중 회원"))","majungId":"\(displayPerson?.majungId ?? "MJ-DEMO")","place":{"label":"\(escapeJSON(r.placeLabel))","latitude":\(r.lat),"longitude":\(r.lng)},"expiresAt":"\(Self.isoFormatter.string(from: r.expiresAt))","peopleAhead":\(aheadJson),"currentPickupRemainingSeconds":\(remJson),"currentPickupValidForMillis":\(r.status == "ACTIVE" || r.status == "QUEUED" ? 15000 : 0),"driverInvitation":\(r.driverInvitation)}
        """
    }

    private func snapshotJSON(_ p: DemoPickup) -> String {
        let ended = p.status == "COMPLETED" || p.status == "CANCELLED"
        let placeJSON = ended ? "null" : #"{"label":"\#(escapeJSON(p.placeLabel))","latitude":\#(p.lat),"longitude":\#(p.lng)}"#
        let vehicleNameJSON = ended ? "null" : "\"\(escapeJSON(p.vehicleName))\""
        let participantJSON = p.participantId == nil ? "null" : """
        {"readiness":"\(p.readiness)","readinessSequence":\(p.readinessSeq),"readinessReceivedSequence":\(p.readinessReceivedSeq)}
        """
        let propJSON = (!ended && p.proposalLabel != nil && p.proposalLat != nil && p.proposalLng != nil)
            ? #"{"place":{"label":"\#(escapeJSON(p.proposalLabel!))","latitude":\#(p.proposalLat!),"longitude":\#(p.proposalLng!)},"proposedBy":"\#(p.proposalBy ?? "PASSENGER")"}"#
            : "null"
        let msgJSON = (!ended && p.quickMessage != nil) ? #"{"text":"\#(escapeJSON(p.quickMessage!))"}"# : "null"
        return """
        {"pickupId":"\(p.id)","status":"\(p.status)","place":\(placeJSON),"placeVersion":\(p.placeVersion),"participant":\(participantJSON),"placeProposal":\(propJSON),"quickMessage":\(msgJSON),"vehicleName":\(vehicleNameJSON)}
        """
    }

    private func vehicleJSON(_ p: DemoPickup) -> String {
        #"{"freshness":"FRESH","latitude":\#(p.carLat),"longitude":\#(p.carLng),"durationSeconds":\#(p.durationSeconds),"validForMillis":15000,"ageMillis":0,"placeVersion":\#(p.placeVersion)}"#
    }
}
#endif
