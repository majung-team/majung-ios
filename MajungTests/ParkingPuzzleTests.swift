import XCTest
@testable import Majung

final class ParkingPuzzleTests: XCTestCase {
    private func finish(_ stage: ParkingStage, via points: [ParkingPoint]) -> ParkingRun {
        var run = ParkingRun(stage: stage)
        run.begin(at: stage.start)
        for point in points { run.extend(to: point) }
        run.drive()
        var ticks = 0
        while run.phase == .driving && ticks < 10_000 { run.step(); ticks += 1 }
        return run
    }

    func testAllEightStagesHaveCollisionFreeSolutions() {
        let routes: [[ParkingPoint]] = [
            [.init(x: 50, y: 22)],
            [.init(x: 24, y: 28), .init(x: 76, y: 28), .init(x: 76, y: 22)],
            [.init(x: 77, y: 24), .init(x: 23, y: 24), .init(x: 23, y: 22)],
            [.init(x: 76, y: 100), .init(x: 76, y: 22)],
            [.init(x: 23, y: 102), .init(x: 23, y: 59), .init(x: 76, y: 59), .init(x: 76, y: 20)],
            [.init(x: 50, y: 22)],
            [.init(x: 90, y: 100), .init(x: 90, y: 41), .init(x: 77, y: 41), .init(x: 77, y: 22)],
            [.init(x: 22, y: 60), .init(x: 77, y: 60), .init(x: 77, y: 20)]
        ]
        XCTAssertEqual(ParkingStage.all.count, 8)
        for (stage, route) in zip(ParkingStage.all, routes) {
            let run = finish(stage, via: route)
            XCTAssertEqual(run.phase, .parked, "Stage \(stage.id) is not solvable by its reference route")
            XCTAssertEqual(run.collisions, 0, "Stage \(stage.id)")
        }
    }

    func testFastDragCannotJumpThroughAnObstacle() {
        let stage = ParkingStage.all[3]
        let run = finish(stage, via: [.init(x: 23, y: 22)])
        XCTAssertEqual(run.phase, .collision)
        XCTAssertEqual(run.pose.center, stage.start)
        XCTAssertEqual(run.collisions, 1)
    }

    func testCarEdgeCollisionEvenWhenCenterIsOutsideObstacle() {
        let stage = ParkingStage.all[1]
        let pose = ParkingPose(center: .init(x: 39, y: 60))
        XCTAssertFalse(stage.obstacles[0].rect.contains(pose.center))
        XCTAssertTrue(ParkingGeometry.collides(pose, in: stage))
    }

    func testParkingRequiresWholeCarAndCorrectHeading() {
        let stage = ParkingStage.all[0]
        XCTAssertTrue(ParkingGeometry.isParked(.init(center: stage.destination), in: stage))
        XCTAssertFalse(ParkingGeometry.isParked(.init(center: .init(x: 57, y: 22)), in: stage))
        XCTAssertFalse(ParkingGeometry.isParked(.init(center: stage.destination, heading: 0), in: stage))
    }

    func testDrawingMustStartAtCarAndPauseCancelsFurtherMovement() {
        var run = ParkingRun(stage: ParkingStage.all[0])
        run.begin(at: .init(x: 10, y: 10))
        run.extend(to: run.stage.destination)
        run.drive()
        XCTAssertEqual(run.phase, .ready)
        run.begin(at: run.stage.start)
        run.extend(to: run.stage.destination)
        run.drive()
        run.step()
        run.pause()
        let stopped = run.pose
        for _ in 0..<20 { run.step() }
        XCTAssertEqual(run.pose, stopped)
        XCTAssertEqual(run.phase, .ready)
    }

    func testPartialRouteCanContinueFromStoppedCar() {
        let stage = ParkingStage.all[0]
        var run = finish(stage, via: [.init(x: 50, y: 60)])
        XCTAssertEqual(run.phase, .ready)
        run.begin(at: run.pose.center)
        run.extend(to: stage.destination)
        run.drive()
        while run.phase == .driving { run.step() }
        XCTAssertEqual(run.phase, .parked)
        XCTAssertEqual(run.strokes, 2)
    }

    @MainActor
    func testPausingAndChangingStageCancelQueuedMovement() async {
        let game = ParkingGame()
        game.draw(start: game.run.stage.start, point: game.run.stage.destination)
        game.drive()
        XCTAssertEqual(game.run.phase, .driving)
        game.pause()
        let stopped = game.run.pose
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(game.run.pose, stopped)
        XCTAssertEqual(game.run.phase, .ready)

        game.draw(start: game.run.pose.center, point: game.run.stage.destination)
        game.drive()
        game.select(ParkingStage.all[1])
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(game.run.stage.id, 2)
        XCTAssertEqual(game.run.pose.center, ParkingStage.all[1].start)
        XCTAssertEqual(game.run.phase, .ready)
    }

    func testCompletedStagesPersistAndIgnoreUnknownStages() throws {
        let suite = "ParkingPuzzleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ParkingProgressStore(defaults: defaults)
        store.complete(stageId: 2)
        store.complete(stageId: 2)
        store.complete(stageId: 999)
        XCTAssertEqual(ParkingProgressStore(defaults: defaults).load(), [2])
        defaults.set([1, -2, 900], forKey: "majung.parking.completed.v1")
        XCTAssertEqual(store.load(), [1])
    }
}
