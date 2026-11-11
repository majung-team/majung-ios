import XCTest

final class MajungE2EUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(port: UInt16) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestResetSessions"]
        app.launchEnvironment["MAJUNG_TEST_PORT"] = String(port)
        app.launch()
        return app
    }

    func test01GuestPickupLifecycleWaitingExitReadinessMessageProposalAndCompletion() throws {
        let server = try LocalE2EServer()
        defer { server.stop() }
        server.setAccountMode(.unauthenticated)

        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 8))

        // 1. Expired/unavailable invite preview shows clear error state & recovery
        server.setInvitePreviewStatus(410)
        let inviteURL = "https://majung.cloud/#join/\(server.pickupId)/\(server.inviteCode)"
        let linkField = app.textFields["마중 초대 링크"]
        XCTAssertTrue(linkField.waitForExistence(timeout: 5))
        linkField.tap()
        linkField.typeText(inviteURL)
        app.buttons["초대 확인하기"].tap()
        XCTAssertTrue(app.staticTexts["초대를 사용할 수 없어요"].waitForExistence(timeout: 8))
        app.buttons["다른 초대 열기"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 5))

        // 2. Valid invite -> join -> WAITING_APPROVAL -> 2-step leaveWaiting -> rejoin
        server.setInvitePreviewStatus(200)
        linkField.tap()
        linkField.typeText(inviteURL)
        app.buttons["초대 확인하기"].tap()
        XCTAssertTrue(app.buttons["약속에 참여하기"].waitForExistence(timeout: 8))
        app.buttons["약속에 참여하기"].tap()

        XCTAssertTrue(app.buttons["pickup-waiting-refresh-button"].waitForExistence(timeout: 8))
        app.buttons["pickup-waiting-refresh-button"].tap()
        app.buttons["pickup-waiting-leave-button"].tap()
        XCTAssertTrue(app.alerts["초대 참여 대기를 나갈까요?"].waitForExistence(timeout: 5))
        app.alerts["초대 참여 대기를 나갈까요?"].buttons["나가기"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 5))

        // Rejoin -> transition over SSE to ACTIVE
        linkField.tap()
        linkField.typeText(inviteURL)
        app.buttons["초대 확인하기"].tap()
        XCTAssertTrue(app.buttons["약속에 참여하기"].waitForExistence(timeout: 8))
        app.buttons["약속에 참여하기"].tap()
        XCTAssertTrue(app.buttons["pickup-waiting-refresh-button"].waitForExistence(timeout: 8))

        server.setGuestPhase(.active)
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 8))

        // 3. Toggle readiness READY & test resend receipt
        app.buttons["pickup-readiness-ready-button"].tap()
        XCTAssertTrue(app.buttons["pickup-resend-readiness-button"].waitForExistence(timeout: 5))
        app.buttons["pickup-resend-readiness-button"].tap()
        XCTAssertEqual(server.requestsMatching(method: "PUT", pathPrefix: "/api/v1/pickups/\(server.pickupId)/readiness").count, 2)

        // 4. Send quick message directly
        let messageField = app.textFields["직접 메시지 입력 (최대 50자)"]
        if !messageField.isHittable { app.swipeUp() }
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        messageField.tap()
        messageField.typeText("파란 우산 들고 있어요")
        app.buttons["pickup-message-send-button"].tap()
        XCTAssertTrue(app.staticTexts["보낸 메시지 · 파란 우산 들고 있어요"].waitForExistence(timeout: 5))

        // 5. Open PlaceProposalView, select map center, submit & withdraw
        app.swipeDown()
        XCTAssertTrue(app.buttons["pickup-propose-place-button"].waitForExistence(timeout: 5))
        app.buttons["pickup-propose-place-button"].tap()
        XCTAssertTrue(app.navigationBars["다른 장소 제안"].waitForExistence(timeout: 5))
        app.buttons["proposal-place-map-select"].tap()
        let descField = app.textViews["proposal-place-label-field"].exists
            ? app.textViews["proposal-place-label-field"]
            : app.textFields["proposal-place-label-field"]
        XCTAssertTrue(descField.waitForExistence(timeout: 5))
        descField.tap()
        descField.typeText("의왕역 2번 출구")
        app.buttons["proposal-submit-button"].tap()
        XCTAssertTrue(app.buttons["pickup-withdraw-proposal-button"].waitForExistence(timeout: 8))
        app.buttons["pickup-withdraw-proposal-button"].tap()
        XCTAssertTrue(app.buttons["pickup-propose-place-button"].waitForExistence(timeout: 5))

        // 6. Arrived & Completed retain place + vehicle summary
        server.setGuestPhase(.arrived)
        XCTAssertTrue(app.staticTexts["마중 차량이 도착했어요"].waitForExistence(timeout: 8))

        server.setGuestPhase(.completed)
        XCTAssertTrue(app.staticTexts["잘 만났어요!"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["의왕역 1호선 1번 출구 앞"].exists)
        XCTAssertTrue(app.staticTexts["흰색 아이오닉 5 · 12가 3456"].exists)
        app.buttons["처음으로"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 5))
    }

    func test02MemberNicknameRequestsDeduplicationPeopleSearchAndCompletedSummary() throws {
        let server = try LocalE2EServer()
        defer { server.stop() }
        server.setAccountMode(.needsNickname, nickname: "이")

        let app = launchApp(port: server.port)
        let nickField = app.textFields["nickname-setup-field"]
        XCTAssertTrue(nickField.waitForExistence(timeout: 8))
        nickField.tap()
        nickField.typeText("김탑승")
        app.buttons["nickname-setup-submit"].tap()

        // Home screen with banner + active pickup card + waiting summary
        XCTAssertTrue(app.buttons["home-open-tracking-button"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["home-invited-banner"].exists)

        // Requests tab: separated 대기·초대 (2) and 내 차례 대기 (1)
        app.tabBars.buttons["내 요청·초대"].tap()
        XCTAssertTrue(app.buttons["대기·초대 (2)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["내 차례 대기 (1)"].exists)

        // Accept invitation -> auto-switches to 내 차례 대기 (2)
        app.buttons["requests-accept-invitation"].tap()
        XCTAssertTrue(app.alerts["이 초대를 수락할까요?"].waitForExistence(timeout: 5))
        app.alerts["이 초대를 수락할까요?"].buttons["이 장소에서 탈게요"].tap()
        XCTAssertTrue(app.buttons["내 차례 대기 (2)"].waitForExistence(timeout: 5))

        // Cancel one queued item with 2-step alert
        let cancelBtn = app.buttons["requests-cancel-button"].firstMatch
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: 5))
        cancelBtn.tap()
        XCTAssertTrue(app.alerts["정말 이 마중 요청을 취소할까요?"].waitForExistence(timeout: 5))
        app.alerts["정말 이 마중 요청을 취소할까요?"].buttons["요청 취소하기"].tap()
        XCTAssertTrue(app.buttons["내 차례 대기 (1)"].waitForExistence(timeout: 5))

        // Open tracking sheet -> SSE completion (403 on /tracking) keeps summary visible until user closes
        app.buttons["requests-open-tracking"].tap()
        XCTAssertTrue(app.navigationBars["마중 픽업"].waitForExistence(timeout: 6))
        server.completeMemberRide()
        XCTAssertTrue(app.staticTexts["잘 만났어요!"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["의왕역 1호선 1번 출구 앞"].exists)
        app.buttons["목록으로"].tap()
        XCTAssertTrue(app.buttons["지난 내역 (2)"].waitForExistence(timeout: 5))

        // People tab: 1-char hint + homonym search + PlacePickerSheet open/close
        app.tabBars.buttons["사람"].tap()
        let searchField = app.textFields["people-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("김")
        XCTAssertTrue(app.staticTexts["검색어는 2글자 이상 입력해주세요."].waitForExistence(timeout: 3))
        searchField.typeText("민수")
        app.buttons["people-search-button"].tap()
        XCTAssertTrue(app.buttons["people-search-ride-minsu_car"].waitForExistence(timeout: 5))
        app.buttons["people-search-ride-minsu_car"].tap()
        XCTAssertTrue(app.navigationBars["만날 장소 선택"].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
    }

    func test03SettingsVehicleQRPairingPollDetachAndLogout() throws {
        let server = try LocalE2EServer()
        defer { server.stop() }
        server.setAccountMode(.ready)

        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["home-open-tracking-button"].waitForExistence(timeout: 8))

        app.tabBars.buttons["설정"].tap()
        XCTAssertTrue(app.staticTexts["1대 연결됨"].waitForExistence(timeout: 5))

        // Connect vehicle via QR sheet manual URL -> pending -> manual poll transitions to linked
        app.buttons["vehicle-connect-button"].tap()
        XCTAssertTrue(app.navigationBars["차량 QR 연결"].waitForExistence(timeout: 5))
        let qrField = app.textFields["vehicle-qr-link-field"]
        qrField.tap()
        qrField.typeText("https://majung.cloud/#vehicle/\(server.newChallengeId)/\(server.inviteCode)")
        app.buttons["vehicle-qr-submit-button"].tap()

        XCTAssertTrue(app.buttons["vehicle-pairing-refresh-button"].waitForExistence(timeout: 6))
        server.approvePendingVehicleChallenge()
        app.buttons["vehicle-pairing-refresh-button"].tap()
        XCTAssertTrue(app.staticTexts["2대 연결됨"].waitForExistence(timeout: 6))

        // Detach existing vehicle via 2-step alert
        let detachBtn = app.buttons["vehicle-detach-\(server.initialVehicleId)"]
        XCTAssertTrue(detachBtn.waitForExistence(timeout: 5))
        detachBtn.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["연결 해제"].tap()
        XCTAssertTrue(app.staticTexts["1대 연결됨"].waitForExistence(timeout: 6))

        // Logout via 2-step alert -> back to login entry
        let logoutBtn = app.buttons["settings-logout-button"]
        if !logoutBtn.isHittable { app.swipeUp() }
        logoutBtn.tap()
        XCTAssertTrue(app.alerts["로그아웃할까요?"].waitForExistence(timeout: 5))
        app.alerts["로그아웃할까요?"].buttons["로그아웃"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 6))
    }
}
