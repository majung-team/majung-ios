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
        XCTAssertFalse(app.buttons["parking-car-taxi"].isEnabled)
        app.switches["parking-sound"].tap()
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
        XCTAssertFalse(app.buttons["parking-car-mintVan"].isEnabled)
        app.buttons["parking-car-taxi"].tap()
        let selectedTaxi = app.buttons.matching(identifier: "parking-car-taxi")
            .matching(NSPredicate(format: "label CONTAINS %@", "타고 있어요")).firstMatch
        XCTAssertTrue(selectedTaxi.waitForExistence(timeout: 3))
        saveScreenshot("parking-garage-unlocked")
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
