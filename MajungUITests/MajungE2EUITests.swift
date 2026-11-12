import XCTest

final class MajungE2EUITests: XCTestCase {
    private var activeApp: XCUIApplication?
    private var activeServer: LocalE2EServer?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        terminateApp(activeApp ?? XCUIApplication())
        activeApp = nil
        activeServer?.stop()
        activeServer = nil
        try super.tearDownWithError()
    }

    private func startServer() throws -> LocalE2EServer {
        let server = try LocalE2EServer()
        activeServer = server
        return server
    }

    private func terminateApp(_ app: XCUIApplication) {
        if app.state != .notRunning {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 10)
        }
    }

    private func launchApp(port: UInt16, arguments: [String] = ["-UITestResetSessions"]) -> XCUIApplication {
        let app = XCUIApplication()
        terminateApp(app)
        app.launchArguments = arguments
        app.launchEnvironment["MAJUNG_TEST_PORT"] = String(port)
        activeApp = app
        app.launch()
        return app
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test00FirstLaunchSplashAndOnboardingFlowAndPersistence() throws {
        let server = try startServer()
        server.setAccountMode(.unauthenticated)

        // 1. Verify Splash renders cleanly on cold launch
        let app = launchApp(port: server.port, arguments: ["-UITestResetSessions", "-UITestShowOnboarding", "-UITestHoldSplash"])
        XCTAssertTrue(app.descendants(matching: .any)["splash-screen"].waitForExistence(timeout: 6))
        attachScreenshot(named: "00-splash")

        // 2. Normal first launch auto-transitions from Splash to Onboarding and walks through all 3 slides
        terminateApp(app)
        app.launchArguments = ["-UITestResetSessions", "-UITestShowOnboarding"]
        app.launch()

        let nextBtn = app.buttons["onboarding-next-button"]
        XCTAssertTrue(nextBtn.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["실시간 위치 · ETA 공유"].exists)
        attachScreenshot(named: "01-onboarding-page1")

        nextBtn.tap()
        XCTAssertTrue(app.staticTexts["장소 조율 · 빠른 소통"].waitForExistence(timeout: 3))
        usleep(350_000)
        attachScreenshot(named: "02-onboarding-page2")

        nextBtn.tap()
        let startBtn = app.buttons["onboarding-start-button"]
        XCTAssertTrue(startBtn.waitForExistence(timeout: 3))
        usleep(350_000)
        attachScreenshot(named: "03-onboarding-page3")
        startBtn.tap()

        // 3. Completing onboarding lands on login entry
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 5))
        usleep(350_000)
        attachScreenshot(named: "04-login-entry")

        // 4. Subsequent cold launch skips onboarding straight to login entry after splash
        terminateApp(app)
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["onboarding-next-button"].exists)
        XCTAssertFalse(app.buttons["onboarding-start-button"].exists)
    }

    private func submitInviteLink(_ inviteURL: String, in app: XCUIApplication) {
        let linkField = app.textFields["마중 초대 링크"]
        XCTAssertTrue(linkField.waitForExistence(timeout: 5))
        linkField.tap()
        linkField.typeText(inviteURL)
        let dismissKeyboard = app.buttons["키보드 닫기"]
        if dismissKeyboard.waitForExistence(timeout: 1.5) && dismissKeyboard.isHittable {
            dismissKeyboard.tap()
        }
        let openButton = app.buttons["초대 확인하기"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 3))
        if !openButton.isHittable { app.swipeUp() }
        XCTAssertTrue(openButton.isEnabled)
        openButton.tap()
    }

    func test01GuestPickupLifecycleWaitingExitReadinessMessageProposalAndCompletion() throws {
        let server = try startServer()
        server.setAccountMode(.unauthenticated)

        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 8))

        // 1. Expired/unavailable invite preview shows clear error state & recovery
        server.setInvitePreviewStatus(410)
        let inviteURL = "https://majung.cloud/#join/\(server.pickupId)/\(server.inviteCode)"
        submitInviteLink(inviteURL, in: app)
        XCTAssertTrue(app.staticTexts["초대를 사용할 수 없어요"].waitForExistence(timeout: 8))
        app.buttons["다른 초대 열기"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 5))

        // 2. Valid invite -> join -> WAITING_APPROVAL -> 2-step leaveWaiting -> rejoin
        server.setInvitePreviewStatus(200)
        submitInviteLink(inviteURL, in: app)
        XCTAssertTrue(app.buttons["약속에 참여하기"].waitForExistence(timeout: 8))
        app.buttons["약속에 참여하기"].tap()

        XCTAssertTrue(app.buttons["pickup-waiting-refresh-button"].waitForExistence(timeout: 8))
        app.buttons["pickup-waiting-refresh-button"].tap()
        app.buttons["pickup-waiting-leave-button"].tap()
        XCTAssertTrue(app.alerts["초대 참여 대기를 나갈까요?"].waitForExistence(timeout: 5))
        app.alerts["초대 참여 대기를 나갈까요?"].buttons["나가기"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 5))
        XCTAssertEqual(server.requestsMatching(method: "POST", pathPrefix: "/api/v1/pickups/\(server.pickupId)/leave").count, 1)

        // Rejoin -> transition over SSE to ACTIVE
        submitInviteLink(inviteURL, in: app)
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
        let server = try startServer()
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

        // Account-level SSE pushes new invitation -> 대기·초대 (3) updates automatically
        server.pushExtraInvitationSSE()
        XCTAssertTrue(app.buttons["대기·초대 (3)"].waitForExistence(timeout: 6))

        // Accept first invitation -> auto-switches to 내 차례 대기 (2)
        app.buttons["requests-accept-invitation"].firstMatch.tap()
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

        // Kakao Korean place search & server pagination inside PlacePickerSheet
        let placeSearchField = app.textFields["ride-place-search-field"]
        XCTAssertTrue(placeSearchField.waitForExistence(timeout: 5))
        placeSearchField.tap()
        placeSearchField.typeText("강남역")
        app.buttons["ride-place-search-button"].tap()
        XCTAssertTrue(app.staticTexts["강남역 2번 출구"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["서울 강남구 역삼동 858"].exists)
        XCTAssertTrue(app.staticTexts["지하철역"].exists)

        app.buttons["ride-place-next-button"].tap()
        XCTAssertTrue(app.staticTexts["강남역 11번 출구"].waitForExistence(timeout: 5))
        app.buttons["ride-place-prev-button"].tap()
        XCTAssertTrue(app.buttons["ride-place-result-0"].waitForExistence(timeout: 5))
        app.buttons["ride-place-result-0"].tap()
        XCTAssertTrue(app.buttons["ride-submit-button"].isEnabled)
        attachScreenshot(named: "05-kakao-place-search")

        app.buttons["닫기"].tap()
    }

    func test03SettingsVehicleQRPairingPollDetachAndLogout() throws {
        let server = try startServer()
        server.setAccountMode(.ready)

        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["home-open-tracking-button"].waitForExistence(timeout: 8))

        app.tabBars.buttons["설정"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1대 연결됨"].waitForExistence(timeout: 5))

        // Automatic polling must finish linking without any refresh-button tap.
        app.buttons["vehicle-connect-button"].tap()
        XCTAssertTrue(app.navigationBars["차량 QR 연결"].waitForExistence(timeout: 5))
        let qrField = app.textFields["vehicle-qr-link-field"]
        qrField.tap()
        qrField.typeText("https://majung.cloud/#vehicle/\(server.newChallengeId)/\(server.inviteCode)")
        app.buttons["vehicle-qr-submit-button"].tap()

        XCTAssertTrue(app.buttons["vehicle-pairing-refresh-button"].waitForExistence(timeout: 6))
        server.approvePendingVehicleChallenge()
        XCTAssertTrue(app.staticTexts["2대 연결됨"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["vehicle-pairing-refresh-button"].exists)

        // Detach existing vehicle via 2-step alert
        let detachBtn = app.buttons["vehicle-detach-\(server.initialVehicleId)"]
        XCTAssertTrue(detachBtn.waitForExistence(timeout: 5))
        detachBtn.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["연결 해제"].tap()
        XCTAssertTrue(app.staticTexts["1대 연결됨"].waitForExistence(timeout: 6))

        // Replay onboarding from settings -> skip back to settings
        let replayBtn = app.buttons["settings-replay-onboarding-button"]
        if !replayBtn.isHittable { app.swipeUp() }
        XCTAssertTrue(replayBtn.waitForExistence(timeout: 5))
        replayBtn.tap()
        let skipBtn = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(skipBtn.waitForExistence(timeout: 4))
        skipBtn.tap()

        // Logout via 2-step alert -> back to login entry
        let logoutBtn = app.buttons["settings-logout-button"]
        if !logoutBtn.isHittable { app.swipeUp() }
        logoutBtn.tap()
        XCTAssertTrue(app.alerts["로그아웃할까요?"].waitForExistence(timeout: 5))
        app.alerts["로그아웃할까요?"].buttons["로그아웃"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 6))

        // Replay onboarding from logged-out entry -> skip back to login entry
        let loggedOutReplay = app.buttons["login-replay-onboarding-button"]
        if !loggedOutReplay.isHittable { app.swipeUp() }
        XCTAssertTrue(loggedOutReplay.waitForExistence(timeout: 5))
        loggedOutReplay.tap()
        let loggedOutSkip = app.buttons["onboarding-skip-button"]
        XCTAssertTrue(loggedOutSkip.waitForExistence(timeout: 4))
        loggedOutSkip.tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 5))
    }

    func test05VehiclePairingManualRefreshBeforeAndAfterApproval() throws {
        let server = try startServer()
        server.setAccountMode(.ready)

        let app = launchApp(port: server.port, arguments: ["-UITestResetSessions", "-UITestManualVehiclePairing"])
        XCTAssertTrue(app.buttons["home-open-tracking-button"].waitForExistence(timeout: 8))
        app.tabBars.buttons["설정"].firstMatch.tap()
        app.buttons["vehicle-connect-button"].tap()
        let field = app.textFields["vehicle-qr-link-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("https://majung.cloud/#vehicle/\(server.newChallengeId)/\(server.inviteCode)")
        app.buttons["vehicle-qr-submit-button"].tap()

        let refresh = app.buttons["vehicle-pairing-refresh-button"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 6))
        let statusPath = "/api/v1/vehicle-links/requests/\(server.newChallengeId)"
        let before = server.requestsMatching(method: "GET", pathPrefix: statusPath).count
        refresh.tap()
        let pendingPoll = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            server.requestsMatching(method: "GET", pathPrefix: statusPath).count > before
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pendingPoll], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["1대 연결됨"].exists)
        XCTAssertTrue(refresh.exists)

        server.approvePendingVehicleChallenge()
        refresh.tap()
        XCTAssertTrue(app.staticTexts["2대 연결됨"].waitForExistence(timeout: 6))
        XCTAssertFalse(refresh.exists)
        XCTAssertGreaterThanOrEqual(server.requestsMatching(method: "GET", pathPrefix: statusPath).count, before + 2)
    }

    func test04AccountWithdrawalClearsSessionAndCallsDeleteMe() throws {
        let server = try startServer()
        server.setAccountMode(.ready)

        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["home-open-tracking-button"].waitForExistence(timeout: 8))

        app.tabBars.buttons["설정"].firstMatch.tap()
        let deleteBtn = app.buttons["settings-delete-account-button"]
        if !deleteBtn.isHittable { app.swipeUp() }
        XCTAssertTrue(deleteBtn.waitForExistence(timeout: 5))
        attachScreenshot(named: "06-settings-account")
        deleteBtn.tap()

        XCTAssertTrue(app.alerts["정말 마중에서 탈퇴할까요?"].waitForExistence(timeout: 5))
        app.alerts["정말 마중에서 탈퇴할까요?"].buttons["탈퇴하기"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 6))
        XCTAssertEqual(server.requestsMatching(method: "DELETE", pathPrefix: "/api/v1/accounts/me").count, 1)
    }
}
