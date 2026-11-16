import XCTest

final class ParkingGameUITests: XCTestCase {
    private var app: XCUIApplication!
    private var server: LocalE2EServer!

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = try LocalE2EServer()
        server.setAccountMode(.unauthenticated)
        app = XCUIApplication()
        app.launchArguments = ["-UITestResetSessions"]
        app.launchEnvironment["MAJUNG_TEST_PORT"] = String(server.port)
        app.launch()
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
        next.tap()
        XCTAssertTrue(app.staticTexts["작은 화단"].waitForExistence(timeout: 3))
        app.buttons["parking-stage-picker"].tap()
        app.buttons["parking-stage-8"].tap()
        XCTAssertTrue(app.staticTexts["오늘도 잘 주차"].waitForExistence(timeout: 3))
        app.buttons["parking-game-close"].tap()
        XCTAssertTrue(app.buttons["kakao-login-button"].waitForExistence(timeout: 3))
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
        app.buttons["parking-stage-picker"].tap()
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

}
