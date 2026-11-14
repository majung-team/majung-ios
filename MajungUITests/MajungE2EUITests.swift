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

    func test00SplashLandsDirectlyOnLoginAndGuideIsOnDemand() throws {
        let server = try startServer()
        server.setAccountMode(.unauthenticated)

        // 1. Verify Splash renders cleanly on cold launch
        let app = launchApp(port: server.port, arguments: ["-UITestResetSessions", "-UITestHoldSplash"])
        XCTAssertTrue(app.descendants(matching: .any)["splash-screen"].waitForExistence(timeout: 6))
        attachScreenshot(named: "00-splash")

        // 2. Cold launch / fresh install skips blocking onboarding and lands straight on login entry
        terminateApp(app)
        app.launchArguments = ["-UITestResetSessions"]
        app.launch()

        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["guide-next-button"].exists)
        XCTAssertFalse(app.buttons["guide-done-button"].exists)
        attachScreenshot(named: "01-login-entry")

        // 3. Guide is accessible on-demand from the login navigation toolbar and walks through all 3 slides
        let loginGuideButton = app.buttons["login-guide-button"]
        XCTAssertTrue(loginGuideButton.waitForExistence(timeout: 5))
        loginGuideButton.tap()

        let nextBtn = app.buttons["guide-next-button"]
        XCTAssertTrue(nextBtn.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["실시간 위치 · ETA 공유"].exists)
        attachScreenshot(named: "02-guide-page1")

        nextBtn.tap()
        XCTAssertTrue(app.staticTexts["장소 조율 · 빠른 소통"].waitForExistence(timeout: 3))
        usleep(350_000)
        attachScreenshot(named: "03-guide-page2")

        nextBtn.tap()
        let doneBtn = app.buttons["guide-done-button"]
        XCTAssertTrue(doneBtn.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["guide-close-button"].exists)
        usleep(350_000)
        attachScreenshot(named: "04-guide-page3")
        doneBtn.tap()

        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 5))
    }

    private func submitInviteLink(_ inviteURL: String, in app: XCUIApplication) {
        let linkField = app.textFields["마중 초대 링크"]
        XCTAssertTrue(linkField.waitForExistence(timeout: 5))
        linkField.tap()
        linkField.typeText(inviteURL)
        let dismissKeyboard = app.buttons["키보드 닫기"]
        if dismissKeyboard.waitForExistence(timeout: 1.5) && dismissKeyboard.isHittable {
            dismissKeyboard.tap()
            assertKeyboardIsDismissed(in: app)
        }
        let openButton = app.buttons["초대 확인하기"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 3))
        if !openButton.isHittable { app.swipeUp() }
        XCTAssertTrue(openButton.isEnabled)
        openButton.tap()
    }

    private func assertKeyboardIsDismissed(in app: XCUIApplication) {
        let hidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.keyboards.firstMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["키보드 닫기"].exists)
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
        XCTAssertTrue(app.descendants(matching: .any)["pickup-live-activity-note"].waitForExistence(timeout: 5))

        // 3. Toggle readiness READY & test resend receipt
        app.buttons["pickup-readiness-ready-button"].tap()
        XCTAssertTrue(app.buttons["pickup-resend-readiness-button"].waitForExistence(timeout: 5))
        app.buttons["pickup-resend-readiness-button"].tap()
        XCTAssertEqual(server.requestsMatching(method: "PUT", pathPrefix: "/api/v1/pickups/\(server.pickupId)/readiness").count, 2)

        // Background to Home Screen so Dynamic Island Live Activity renders (compact + expanded), then tap Dynamic Island to return to app
        XCUIDevice.shared.press(.home)
        sleep(2)
        attachScreenshot(named: "pickup-dynamic-island-compact")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 0.9)
        sleep(1)
        attachScreenshot(named: "pickup-dynamic-island-expanded")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 6), "Dynamic Island tap must open the app")
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 8))

        // 4. Send quick message directly
        let messageField = app.textFields["직접 메시지 입력 (최대 50자)"]
        if !messageField.isHittable { app.swipeUp() }
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        messageField.tap()
        messageField.typeText("파란 우산 들고 있어요")
        app.buttons["pickup-message-send-button"].tap()
        XCTAssertTrue(app.staticTexts["보낸 메시지 · 파란 우산 들고 있어요"].waitForExistence(timeout: 5))
        let keyboardHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 5), .completed)

        // 5. Recover from SAME_PLACE without dismissing the form or losing the description.
        let proposeButton = app.buttons["pickup-propose-place-button"]
        for _ in 0..<3 where !proposeButton.isHittable { app.swipeDown() }
        XCTAssertTrue(proposeButton.isHittable)
        proposeButton.tap()
        XCTAssertTrue(app.navigationBars["다른 장소 제안"].waitForExistence(timeout: 5))
        app.buttons["proposal-place-map-select"].tap()
        let descField = app.textViews["proposal-place-label-field"].exists
            ? app.textViews["proposal-place-label-field"]
            : app.textFields["proposal-place-label-field"]
        XCTAssertTrue(descField.waitForExistence(timeout: 5))
        descField.tap()
        descField.typeText("의왕역 2번 출구")
        server.rejectNextProposalAsSamePlace()
        app.buttons["proposal-submit-button"].tap()
        XCTAssertTrue(app.staticTexts["현재 만날 장소와 같은 위치예요. 지도를 옮기거나 다른 장소를 검색해주세요."].waitForExistence(timeout: 8))
        XCTAssertEqual(descField.value as? String, "의왕역 2번 출구")
        attachScreenshot(named: "proposal-same-place-guidance")
        let searchField = app.textFields["proposal-place-search-field"]
        for _ in 0..<3 where !searchField.isHittable { app.swipeDown() }
        searchField.tap()
        searchField.typeText("강남역")
        app.buttons["proposal-place-search-button"].tap()
        let searchResult = app.buttons["proposal-place-result-0"]
        XCTAssertTrue(searchResult.waitForExistence(timeout: 8))
        searchResult.tap()
        let submitProposal = app.buttons["proposal-submit-button"]
        for _ in 0..<3 where !submitProposal.isHittable { app.swipeUp() }
        submitProposal.tap()
        XCTAssertTrue(app.buttons["pickup-withdraw-proposal-button"].waitForExistence(timeout: 8))
        XCTAssertEqual(server.requestsMatching(method: "PUT", pathPrefix: "/api/v1/pickups/\(server.pickupId)/place-proposal").count, 2)
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

    private func assertGuideOpensAndCloses(from trigger: XCUIElement, in app: XCUIApplication) {
        if !trigger.isHittable { app.swipeUp() }
        XCTAssertTrue(trigger.waitForExistence(timeout: 5))
        trigger.tap()
        XCTAssertTrue(app.staticTexts["실시간 위치 · ETA 공유"].waitForExistence(timeout: 4))
        let closeBtn = app.buttons["guide-close-button"]
        XCTAssertTrue(closeBtn.waitForExistence(timeout: 4))
        closeBtn.tap()
    }

    private func waitForKeyboardDismissed(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let keyboardGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.keyboards.firstMatch
        )
        let dismissGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.buttons["키보드 닫기"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone, dismissGone], timeout: 5), .completed, file: file, line: line)
    }

    private func revealElement(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<6 where !element.isHittable {
            if element.frame.minY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable)
    }

    func test09KeyboardGlassDismissAndCancelConsistency() throws {
        let server = try startServer()
        server.setAccountMode(.unauthenticated)

        let loginApp = launchApp(port: server.port)
        XCTAssertTrue(loginApp.buttons["kakao-login-button"].waitForExistence(timeout: 8))

        let dividerText = loginApp.staticTexts["또는 비로그인 초대 참여"]
        XCTAssertTrue(dividerText.waitForExistence(timeout: 5))
        XCTAssertLessThan(dividerText.frame.height, 26)
        attachScreenshot(named: "07-login-divider-single-line")

        let loginInviteField = loginApp.textFields["마중 초대 링크"]
        XCTAssertTrue(loginInviteField.waitForExistence(timeout: 5))
        loginInviteField.tap()
        XCTAssertTrue(loginApp.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(loginApp.buttons["키보드 닫기"].waitForExistence(timeout: 5))
        attachScreenshot(named: "07-login-keyboard-glass-dismiss")

        loginApp.staticTexts["전달받은 마중 초대 링크가 있나요?"].tap()
        waitForKeyboardDismissed(in: loginApp)

        loginInviteField.tap()
        XCTAssertTrue(loginApp.keyboards.firstMatch.waitForExistence(timeout: 5))
        loginInviteField.typeText("https://majung.cloud/#join/test")
        let loginClearBtn = loginApp.buttons["초대 링크 지우기"]
        XCTAssertTrue(loginClearBtn.waitForExistence(timeout: 3))
        loginClearBtn.tap()
        XCTAssertTrue(loginApp.keyboards.firstMatch.exists)
        loginInviteField.typeText("\n")
        waitForKeyboardDismissed(in: loginApp)

        server.setAccountMode(.ready)
        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["home-open-tracking-button"].waitForExistence(timeout: 8))

        app.tabBars.buttons["설정"].firstMatch.tap()
        let nicknameField = app.textFields["settings-nickname-field"]
        XCTAssertTrue(nicknameField.waitForExistence(timeout: 5))
        nicknameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["키보드 닫기"].waitForExistence(timeout: 5))
        attachScreenshot(named: "07-settings-keyboard-glass-dismiss")

        // Tap non-interactive profile label in Form -> dismisses keyboard
        app.staticTexts["이름"].firstMatch.tap()
        waitForKeyboardDismissed(in: app)

        // Clear button preserves active keyboard; empty Return dismisses cleanly
        nicknameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let clearNicknameBtn = app.buttons["닉네임 지우기"]
        XCTAssertTrue(clearNicknameBtn.waitForExistence(timeout: 3))
        clearNicknameBtn.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        nicknameField.typeText("\n")
        waitForKeyboardDismissed(in: app)

        // Scroll in Form immediately dismisses keyboard
        nicknameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.swipeDown()
        waitForKeyboardDismissed(in: app)

        // Switching tabs dismisses keyboard
        nicknameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["사람"].tap()
        waitForKeyboardDismissed(in: app)

        // People search: invalid 1-char Return still dismisses keyboard; Glass dismiss works too
        let peopleSearch = app.textFields["people-search-field"]
        XCTAssertTrue(peopleSearch.waitForExistence(timeout: 5))
        peopleSearch.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        peopleSearch.typeText("김\n")
        waitForKeyboardDismissed(in: app)

        peopleSearch.tap()
        XCTAssertTrue(app.buttons["키보드 닫기"].waitForExistence(timeout: 5))
        app.buttons["검색어 지우기"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        peopleSearch.typeText("김민수")
        app.buttons["키보드 닫기"].tap()
        waitForKeyboardDismissed(in: app)
        app.buttons["people-search-button"].tap()
        XCTAssertTrue(app.buttons["people-search-ride-minsu_car"].waitForExistence(timeout: 5))
        app.buttons["people-search-ride-minsu_car"].tap()
        XCTAssertTrue(app.navigationBars["만날 장소 선택"].waitForExistence(timeout: 5))

        // PlaceComposerView: search focus -> map select clears keyboard; multiline label gets Glass dismiss
        let placeSearch = app.textFields["ride-place-search-field"]
        XCTAssertTrue(placeSearch.waitForExistence(timeout: 5))
        placeSearch.tap()
        XCTAssertTrue(app.buttons["키보드 닫기"].waitForExistence(timeout: 5))
        app.buttons["ride-place-map-select"].tap()
        waitForKeyboardDismissed(in: app)

        let placeLabel = app.textFields["ride-place-label-field"]
        revealElement(placeLabel, in: app)
        placeLabel.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["키보드 닫기"].waitForExistence(timeout: 5))
        placeLabel.typeText("정문 앞")
        attachScreenshot(named: "07-place-label-keyboard-glass-dismiss")
        app.buttons["키보드 닫기"].tap()
        waitForKeyboardDismissed(in: app)
        app.buttons["닫기"].tap()

        // VehicleQRScannerSheet: unified Glass dismiss + outside tap
        app.tabBars.buttons["설정"].firstMatch.tap()
        let connectBtn = app.buttons["vehicle-connect-button"]
        revealElement(connectBtn, in: app)
        connectBtn.tap()
        XCTAssertTrue(app.navigationBars["차량 QR 연결"].waitForExistence(timeout: 5))
        let qrField = app.textFields["vehicle-qr-link-field"]
        revealElement(qrField, in: app)
        qrField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["키보드 닫기"].waitForExistence(timeout: 5))
        app.staticTexts["연결 링크 직접 입력"].tap()
        waitForKeyboardDismissed(in: app)
        app.buttons["닫기"].tap()
    }

    func test09bNicknameSetupAndPickupKeyboardConsistency() throws {
        let server = try startServer()
        server.setAccountMode(.needsNickname)

        let setupApp = launchApp(port: server.port)
        let setupField = setupApp.textFields["nickname-setup-field"]
        XCTAssertTrue(setupField.waitForExistence(timeout: 8))
        setupField.tap()
        XCTAssertTrue(setupApp.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(setupApp.buttons["키보드 닫기"].waitForExistence(timeout: 5))
        setupField.typeText("ㄱ\n")
        waitForKeyboardDismissed(in: setupApp)

        setupField.tap()
        XCTAssertTrue(setupApp.keyboards.firstMatch.waitForExistence(timeout: 5))
        setupField.typeText("테스터")
        let clearSetupBtn = setupApp.buttons["닉네임 지우기"]
        XCTAssertTrue(clearSetupBtn.waitForExistence(timeout: 3))
        clearSetupBtn.tap()
        XCTAssertTrue(setupApp.keyboards.firstMatch.exists)
        setupApp.buttons["키보드 닫기"].tap()
        waitForKeyboardDismissed(in: setupApp)

        server.setAccountMode(.ready)
        let app = launchApp(port: server.port)
        let trackingBtn = app.buttons["home-open-tracking-button"]
        XCTAssertTrue(trackingBtn.waitForExistence(timeout: 8))
        trackingBtn.tap()
        XCTAssertTrue(app.navigationBars["마중 픽업"].waitForExistence(timeout: 6))

        let msgField = app.textFields["직접 메시지 입력 (최대 50자)"]
        revealElement(msgField, in: app)
        msgField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["키보드 닫기"].waitForExistence(timeout: 5))

        // Quick preset chip clears focus; clear button preserves focus; Glass dismiss closes keyboard
        app.buttons["지금 내려가요"].tap()
        waitForKeyboardDismissed(in: app)

        msgField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["메시지 지우기"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["키보드 닫기"].tap()
        waitForKeyboardDismissed(in: app)
    }

    func test03SettingsVehicleQRPairingPollDetachAndLogout() throws {
        let server = try startServer()
        server.setAccountMode(.ready)

        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["home-open-tracking-button"].waitForExistence(timeout: 8))

        assertGuideOpensAndCloses(from: app.buttons["home-guide-button"], in: app)
        XCTAssertTrue(app.buttons["home-open-tracking-button"].waitForExistence(timeout: 5))

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

        assertGuideOpensAndCloses(from: app.buttons["settings-guide-button"], in: app)

        // Logout via 2-step alert -> back to login entry
        let logoutBtn = app.buttons["settings-logout-button"]
        if !logoutBtn.isHittable { app.swipeUp() }
        logoutBtn.tap()
        XCTAssertTrue(app.alerts["로그아웃할까요?"].waitForExistence(timeout: 5))
        app.alerts["로그아웃할까요?"].buttons["로그아웃"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 6))

        assertGuideOpensAndCloses(from: app.buttons["login-guide-button"], in: app)
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

    func test06GuestAndHomeInviteKeyboardRepeatedFocusDismissAndSubmit() throws {
        let server = try startServer()
        for mode in [LocalE2EServer.AccountMode.unauthenticated, .ready] {
            server.setAccountMode(mode)
            let app = launchApp(port: server.port)
            let field = app.textFields["마중 초대 링크"]
            XCTAssertTrue(field.waitForExistence(timeout: 8))
            for attempt in 0..<3 {
                if !field.isHittable { app.swipeUp() }
                field.tap()
                let dismiss = app.buttons["키보드 닫기"]
                XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                if attempt == 0 { attachScreenshot(named: "invite-keyboard-dismiss-\(mode)") }
                dismiss.tap()
                assertKeyboardIsDismissed(in: app)
            }
            let invite = "https://majung.cloud/#join/\(server.pickupId)/\(server.inviteCode)"
            submitInviteLink(invite, in: app)
            XCTAssertTrue(app.buttons["약속에 참여하기"].waitForExistence(timeout: 8))
            app.buttons["약속에 참여하기"].tap()
            XCTAssertTrue(app.buttons["pickup-waiting-refresh-button"].waitForExistence(timeout: 8))
            terminateApp(app)
            server.setGuestPhase(.none)
        }
    }


    func test07StaleLiveActivityShowsRefreshHintAndOpensPickup() throws {
        let server = try startServer()
        server.setAccountMode(.unauthenticated)
        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 8))
        submitInviteLink("https://majung.cloud/#join/\(server.pickupId)/\(server.inviteCode)", in: app)
        XCTAssertTrue(app.buttons["약속에 참여하기"].waitForExistence(timeout: 8))
        app.buttons["약속에 참여하기"].tap()
        XCTAssertTrue(app.buttons["pickup-waiting-refresh-button"].waitForExistence(timeout: 8))
        server.setGuestPhase(.active)
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 8))
        let eta = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "도착 예정")).firstMatch
        XCTAssertTrue(eta.waitForExistence(timeout: 8))
        server.setVehicleStale(true)
        XCTAssertTrue(app.buttons["pickup-retry-vehicle-button"].waitForExistence(timeout: 8))

        XCUIDevice.shared.press(.home)
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 0.9)
        let refreshHint = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "갱신 필요")).firstMatch
        let staleVisible = refreshHint.waitForExistence(timeout: 15)
        attachScreenshot(named: "pickup-live-activity-stale")
        XCTAssertTrue(staleVisible)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 6))
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 8))
        server.setGuestPhase(.completed)
        XCTAssertTrue(app.staticTexts["잘 만났어요!"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: refreshHint)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 8), .completed)
    }

    func test08InitialStaleLiveActivityShowsRefreshHintAndOpensPickup() throws {
        let server = try startServer()
        server.setAccountMode(.unauthenticated)
        let app = launchApp(port: server.port)
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 8))
        submitInviteLink("https://majung.cloud/#join/\(server.pickupId)/\(server.inviteCode)", in: app)
        XCTAssertTrue(app.buttons["약속에 참여하기"].waitForExistence(timeout: 8))
        app.buttons["약속에 참여하기"].tap()
        XCTAssertTrue(app.buttons["pickup-waiting-refresh-button"].waitForExistence(timeout: 8))
        server.setVehicleStale(true)
        server.setGuestPhase(.active)
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["pickup-retry-vehicle-button"].waitForExistence(timeout: 8))

        sleep(3)
        XCUIDevice.shared.press(.home)
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 0.9)
        let refreshHint = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "갱신 필요")).firstMatch
        let staleVisible = refreshHint.waitForExistence(timeout: 15)
        attachScreenshot(named: "pickup-live-activity-initial-stale")
        XCTAssertTrue(staleVisible)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 6))
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 8))
        server.setGuestPhase(.completed)
        XCTAssertTrue(app.staticTexts["잘 만났어요!"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: refreshHint)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 8), .completed)
    }

    /// Explicit production rehearsal only. CI uses the local-server scenarios above.
    func test10LiveVehicleRoundTrip() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("운영 연동 자동 검사는 iPhone 시뮬레이터에서만 실행")
        #else
        guard let invite = ProcessInfo.processInfo.environment["MAJUNG_LIVE_INVITE"],
              let url = URL(string: invite), url.scheme == "https", url.host == "majung.cloud",
              url.fragment?.hasPrefix("join/") == true else {
            throw XCTSkip("운영 시험 초대가 지정된 경우에만 실행")
        }
        let app = XCUIApplication()
        terminateApp(app)
        app.launchArguments = ["-UITestResetSessions"]
        app.launchEnvironment.removeValue(forKey: "MAJUNG_TEST_PORT")
        activeApp = app
        app.launch()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 12))
        submitInviteLink(invite, in: app)
        XCTAssertTrue(app.buttons["약속에 참여하기"].waitForExistence(timeout: 15))
        app.buttons["약속에 참여하기"].tap()
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 20))
        let eta = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "도착 예정")).firstMatch
        XCTAssertTrue(eta.waitForExistence(timeout: 20))
        attachScreenshot(named: "live-01-operating-pickup")

        func reveal(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            for _ in 0..<7 where !element.isHittable {
                if element.frame.minY < app.frame.minY { app.swipeDown() }
                else { app.swipeUp() }
            }
            XCTAssertTrue(element.isHittable)
        }
        func send(_ text: String) {
            let field = app.textFields["직접 메시지 입력 (최대 50자)"]
            reveal(field)
            field.tap()
            field.typeText(text)
            let send = app.buttons["pickup-message-send-button"]
            XCTAssertTrue(send.isEnabled)
            send.tap()
            XCTAssertTrue(app.staticTexts["보낸 메시지 · \(text)"].waitForExistence(timeout: 12))
        }
        send("ios-simulator-check")

        // Restore the same guest authority after terminating the app process.
        terminateApp(app)
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 20))
        attachScreenshot(named: "live-02-restored-pickup")

        let propose = app.buttons["pickup-propose-place-button"]
        reveal(propose)
        propose.tap()
        XCTAssertTrue(app.navigationBars["다른 장소 제안"].waitForExistence(timeout: 8))
        let select = app.buttons["proposal-place-map-select"]
        reveal(select)
        select.tap()
        let field = app.textViews["proposal-place-label-field"].exists
            ? app.textViews["proposal-place-label-field"] : app.textFields["proposal-place-label-field"]
        reveal(field)
        field.tap()
        field.typeText("시뮬레이터 장소 시험")
        let submit = app.buttons["proposal-submit-button"]
        reveal(submit)
        submit.tap()
        // The real server rejects an unchanged pin. Recover by choosing a different search result.
        XCTAssertTrue(app.staticTexts["현재 만날 장소와 같은 위치예요. 지도를 옮기거나 다른 장소를 검색해주세요."].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(named: "live-03a-same-place-guidance")
        let search = app.textFields["proposal-place-search-field"]
        reveal(search)
        search.tap()
        search.typeText("판교역")
        let searchButton = app.buttons["proposal-place-search-button"]
        reveal(searchButton)
        searchButton.tap()
        let candidate = app.buttons["proposal-place-result-0"]
        reveal(candidate)
        candidate.tap()
        reveal(submit)
        submit.tap()
        let withdraw = app.buttons["pickup-withdraw-proposal-button"]
        XCTAssertTrue(withdraw.waitForExistence(timeout: 15))
        attachScreenshot(named: "live-03-proposal-pending")
        // Keep the proposal open for at least two vehicle polling intervals.
        Thread.sleep(forTimeInterval: 7)
        reveal(withdraw)
        withdraw.tap()
        XCTAssertTrue(propose.waitForExistence(timeout: 12))

        let ready = app.buttons["pickup-readiness-ready-button"]
        reveal(ready)
        ready.tap()
        XCTAssertTrue(app.staticTexts["마중 차량이 도착했어요"].waitForExistence(timeout: 25))
        attachScreenshot(named: "live-04-arrived")
        send("ios-simulator-arrival-confirmed")
        XCTAssertTrue(app.staticTexts["잘 만났어요!"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.buttons["pickup-readiness-ready-button"].exists)
        attachScreenshot(named: "live-05-completed")
        app.buttons["처음으로"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 10))
        #endif
    }


    func test11LiveCancellationWhileTypingAndExpiredInvite() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("운영 연동 자동 검사는 iPhone 시뮬레이터에서만 실행")
        #else
        guard let invite = ProcessInfo.processInfo.environment["MAJUNG_LIVE_INVITE"],
              let url = URL(string: invite), url.scheme == "https", url.host == "majung.cloud",
              url.fragment?.hasPrefix("join/") == true else {
            throw XCTSkip("운영 시험 초대가 지정된 경우에만 실행")
        }
        let app = XCUIApplication()
        terminateApp(app)
        app.launchArguments = ["-UITestResetSessions"]
        app.launchEnvironment.removeValue(forKey: "MAJUNG_TEST_PORT")
        activeApp = app
        app.launch()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 12))
        submitInviteLink(invite, in: app)
        XCTAssertTrue(app.buttons["약속에 참여하기"].waitForExistence(timeout: 15))
        app.buttons["약속에 참여하기"].tap()
        let ready = app.buttons["pickup-readiness-ready-button"]
        XCTAssertTrue(ready.waitForExistence(timeout: 20))
        if !ready.isHittable { app.swipeUp() }
        ready.tap()

        let field = app.textFields["직접 메시지 입력 (최대 50자)"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<4 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.isHittable)
        field.tap()
        let draft = "취소 확인 중 작성하던 메모"
        field.typeText(draft)
        XCTAssertEqual(field.value as? String, draft)
        attachScreenshot(named: "live-cancel-01-typing")

        XCTAssertTrue(app.staticTexts["픽업이 취소됐어요"].waitForExistence(timeout: 25))
        XCTAssertFalse(field.exists)
        XCTAssertFalse(ready.exists)
        attachScreenshot(named: "live-cancel-02-terminal")
        terminateApp(app)
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["픽업이 취소됐어요"].exists)

        submitInviteLink(invite, in: app)
        XCTAssertTrue(app.staticTexts["초대를 사용할 수 없어요"].waitForExistence(timeout: 15))
        attachScreenshot(named: "live-cancel-03-expired-invite")
        app.buttons["다른 초대 열기"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 10))
        #endif
    }

}
