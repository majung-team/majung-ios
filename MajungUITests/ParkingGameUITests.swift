import XCTest

final class ParkingGameUITests: XCTestCase {
    private var app: XCUIApplication!
    private var server: LocalE2EServer!

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = try LocalE2EServer()
        server.setAccountMode(.unauthenticated)
        app = XCUIApplication()
        app.launchArguments = ["-UITestResetSessions", "-UITestResetParking"]
        app.launchEnvironment["MAJUNG_TEST_PORT"] = String(server.port)
        app.launch()
        app.launchArguments = ["-UITestResetSessions"]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        server?.stop()
        try super.tearDownWithError()
    }

    func testPlayWithoutLoginCompleteAndSelectStage() throws {
        let entry = app.buttons["parking-game-open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        app.buttons["parking-chapter-0"].tap()
        app.buttons["parking-stage-1"].tap()
        app.buttons["parking-garage"].tap()
        app.buttons["parking-car-taxi"].tap()
        assertCarPreview("노란 택시")
        XCTAssertFalse(app.buttons["parking-car-apply"].isEnabled)
        let sound = app.switches["parking-sound"]
        sound.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: sound)
        waitForExpectations(timeout: 3)
        app.buttons["parking-garage-close"].tap()
        let board = app.descendants(matching: .any)["parking-board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(board.frame.width, 200)
        XCTAssertGreaterThan(board.frame.height, 240)
        let start = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 100.0 / 120))
        let end = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 22.0 / 120))
        start.press(forDuration: 0.1, thenDragTo: end)
        let next = app.buttons["parking-next-stage"]
        XCTAssertTrue(next.waitForExistence(timeout: 12))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "parking-stage-complete"
        attachment.lifetime = .keepAlways
        add(attachment)
        let awards = app.descendants(matching: .any)["parking-awards"].firstMatch
        XCTAssertTrue(awards.exists)
        XCTAssertTrue(awards.label.contains("3"))
        app.buttons["parking-garage"].tap()
        XCTAssertTrue(app.buttons["parking-car-taxi"].isEnabled)
        app.buttons["parking-car-mintVan"].tap()
        XCTAssertFalse(app.buttons["parking-car-apply"].isEnabled)
        app.buttons["parking-car-taxi"].tap()
        XCTAssertTrue(app.staticTexts["parking-current-car"].label.contains("파란 경차"))
        app.buttons["parking-car-apply"].tap()
        let selectedTaxi = app.buttons.matching(identifier: "parking-car-taxi")
            .matching(NSPredicate(format: "label CONTAINS %@", "타고 있어요")).firstMatch
        XCTAssertTrue(selectedTaxi.waitForExistence(timeout: 3))
        saveScreenshot("parking-garage-unlocked")
        app.buttons["parking-car-blue"].tap()
        XCTAssertTrue(app.buttons["parking-car-apply"].isEnabled)
        app.buttons["parking-garage-close"].tap()
        if !next.isHittable { app.swipeUp() }
        next.tap()
        XCTAssertTrue(app.staticTexts["작은 화단"].waitForExistence(timeout: 3))
        app.buttons["parking-stage-picker"].tap()
        app.buttons["parking-chapter-0"].tap()
        app.buttons["parking-stage-8"].tap()
        XCTAssertTrue(app.staticTexts["오늘도 잘 주차"].waitForExistence(timeout: 3))
        app.buttons["parking-game-close"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        openGame()
        app.buttons["parking-garage"].tap()
        XCTAssertTrue(app.buttons["parking-car-taxi"].label.contains("타고 있어요"))
        XCTAssertEqual(app.staticTexts["parking-car-preview-title"].label, "노란 택시")
        XCTAssertEqual(app.switches["parking-sound"].value as? String, "1")
    }
    func testHomeEntryObstacleCollisionAndRestart() throws {
        server.setAccountMode(.ready)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["home-open-people-button"].waitForExistence(timeout: 10))
        let entry = app.buttons["parking-game-open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        app.buttons["parking-chapter-0"].tap()
        app.buttons["parking-stage-4"].tap()
        let board = app.descendants(matching: .any)["parking-board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let start = board.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 100.0 / 120))
        let end = board.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 22.0 / 120))
        start.press(forDuration: 0.1, thenDragTo: end)
        let collision = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "앗, 닿았어요")).firstMatch
        XCTAssertTrue(collision.waitForExistence(timeout: 10))
        app.buttons["parking-restart"].tap()
        XCTAssertFalse(collision.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "parking-obstacles-and-restart"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["parking-game-close"].tap()
        XCTAssertTrue(app.buttons["home-open-people-button"].waitForExistence(timeout: 3))
    }

    func testChaptersLastStageAndDailyAreAvailableWithoutLogin() throws {
        openGame(chooseFirstStage: false)
        XCTAssertTrue(app.buttons["parking-chapter-0"].waitForExistence(timeout: 3))
        saveScreenshot("parking-chapters")
        let lastChapter = app.buttons["parking-chapter-3"]
        for _ in 0..<4 where !lastChapter.isHittable { app.swipeUp() }
        lastChapter.tap()
        let lastStage = app.buttons["parking-stage-48"]
        XCTAssertTrue(lastStage.waitForExistence(timeout: 3))
        for _ in 0..<3 where !lastStage.isHittable { app.swipeUp() }
        saveScreenshot("parking-chapter-stages")
        lastStage.tap()
        XCTAssertTrue(app.staticTexts["마지막 통로"].waitForExistence(timeout: 3))
        saveScreenshot("parking-night-theme")
        app.buttons["parking-stage-picker"].tap()
        app.buttons["parking-daily"].tap()
        XCTAssertTrue(app.staticTexts["오늘의 주차"].waitForExistence(timeout: 3))
        let daily = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "DAILY")).firstMatch
        let dateLabel = daily.label
        app.buttons["parking-restart"].tap()
        XCTAssertEqual(daily.label, dateLabel)
        saveScreenshot("parking-daily")
    }

    func testGarageShowsTenPreviewsWithoutChangingTheCurrentCar() throws {
        openGame()
        app.buttons["parking-garage"].tap()
        let list = app.scrollViews["parking-car-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        let cars = [("blue", "파란 경차"), ("taxi", "노란 택시"), ("mintVan", "민트 미니밴"),
                    ("pickup", "초록 픽업트럭"), ("suv", "보라 SUV"), ("coral", "산호빛 쿠페"),
                    ("camper", "작은 캠핑카"), ("classic", "크림 클래식카"),
                    ("roadster", "빨간 로드스터"), ("deliveryVan", "주황 배송밴")]
        for (id, title) in cars {
            let card = app.buttons["parking-car-\(id)"]
            for _ in 0..<5 where !card.isHittable { list.swipeUp() }
            XCTAssertTrue(card.isHittable)
            card.tap()
            assertCarPreview(title)
            XCTAssertFalse(app.buttons["parking-car-apply"].isEnabled)
            XCTAssertTrue(app.staticTexts["parking-current-car"].label.contains("파란 경차"))
            if id == "camper" { saveScreenshot("parking-garage-camper-preview") }
        }
        saveScreenshot("parking-garage-locked-preview")
        app.buttons["parking-garage-close"].tap()
        app.buttons["parking-garage"].tap()
        XCTAssertEqual(app.staticTexts["parking-car-preview-title"].label, "파란 경차")
        XCTAssertTrue(app.buttons["parking-car-blue"].isHittable)
        saveScreenshot("parking-garage-ten-cars")
    }

    func testMemberPickupGameKeepsTrackingAndArrivalClosesGarage() throws {
        server.setAccountMode(.ready)
        app.terminate()
        app.launch()
        let tracking = app.buttons["home-open-tracking-button"]
        XCTAssertTrue(tracking.waitForExistence(timeout: 10))
        tracking.tap()
        let play = app.buttons["pickup-parking-open"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        app.buttons["parking-chapter-0"].tap()
        app.buttons["parking-stage-1"].tap()
        app.buttons["parking-game-close"].tap()
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 3))
        play.tap()
        app.buttons["parking-chapter-0"].tap()
        app.buttons["parking-stage-1"].tap()
        app.buttons["parking-garage"].tap()
        let path = "/api/v1/ride-requests/\(server.activeRequestId)/tracking"
        let reads = server.requestsMatching(method: "GET", pathPrefix: path).count
        server.setMemberPickupPhase(.arrived)
        let notice = app.staticTexts["parking-pickup-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertEqual(notice.label, "차가 도착했어요")
        XCTAssertFalse(app.buttons["parking-garage-close"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["parking-board"].firstMatch.exists)
        XCTAssertGreaterThan(server.requestsMatching(method: "GET", pathPrefix: path).count, reads)
        saveScreenshot("parking-pickup-arrival")
        app.buttons["parking-return-to-pickup"].tap()
        XCTAssertTrue(app.staticTexts["마중 차량이 도착했어요"].waitForExistence(timeout: 3))
        XCTAssertTrue(server.requestsMatching(method: "POST", pathPrefix: "/api/v1/ride-requests/\(server.activeRequestId)/cancel").isEmpty)
    }

    func testGuestPickupCancellationInterruptsChapterSelection() throws {
        let field = app.textFields["마중 초대 링크"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<3 where !field.isHittable { app.swipeUp() }
        field.tap()
        field.typeText("https://majung.cloud/#join/\(server.pickupId)/\(server.inviteCode)\n")
        let join = app.buttons["약속에 참여하기"]
        XCTAssertTrue(join.waitForExistence(timeout: 8))
        join.tap()
        XCTAssertTrue(app.buttons["pickup-waiting-refresh-button"].waitForExistence(timeout: 8))
        server.setGuestPhase(.active)
        XCTAssertTrue(app.buttons["pickup-readiness-ready-button"].waitForExistence(timeout: 8))
        app.buttons["pickup-parking-open"].tap()
        XCTAssertTrue(app.buttons["parking-chapter-0"].waitForExistence(timeout: 3))
        server.setGuestPhase(.cancelled)
        let notice = app.staticTexts["parking-pickup-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertEqual(notice.label, "픽업 요청이 취소됐어요")
        saveScreenshot("parking-pickup-cancelled")
        app.buttons["parking-return-to-pickup"].tap()
        XCTAssertTrue(app.staticTexts["픽업이 취소됐어요"].waitForExistence(timeout: 3))
    }

    private func assertCarPreview(_ title: String) {
        let preview = app.staticTexts.matching(identifier: "parking-car-preview-title")
            .matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
    }

    private func openGame(chooseFirstStage: Bool = true) {
        let entry = app.buttons["parking-game-open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        entry.tap()
        XCTAssertTrue(app.buttons["parking-chapter-0"].waitForExistence(timeout: 3))
        if chooseFirstStage {
            app.buttons["parking-chapter-0"].tap()
            app.buttons["parking-stage-1"].tap()
            XCTAssertTrue(app.buttons["parking-stage-picker"].waitForExistence(timeout: 3))
        }
    }

    private func saveScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
