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

    private func solution(for stage: ParkingStage) -> [ParkingPoint] {
        let original: [[ParkingPoint]] = [
            [.init(x: 50, y: 22)],
            [.init(x: 24, y: 28), .init(x: 76, y: 28), .init(x: 76, y: 22)],
            [.init(x: 77, y: 24), .init(x: 23, y: 24), .init(x: 23, y: 22)],
            [.init(x: 76, y: 100), .init(x: 76, y: 22)],
            [.init(x: 23, y: 102), .init(x: 23, y: 59), .init(x: 76, y: 59), .init(x: 76, y: 20)],
            [.init(x: 50, y: 22)],
            [.init(x: 90, y: 100), .init(x: 90, y: 41), .init(x: 77, y: 41), .init(x: 77, y: 22)],
            [.init(x: 22, y: 60), .init(x: 77, y: 60), .init(x: 77, y: 20)]
        ]
        if stage.id <= 8 { return original[stage.id - 1] }
        let routes: [[ParkingPoint]] = [
            [.init(x: 22, y: 28), .init(x: 78, y: 28), .init(x: 78, y: 20)],
            [.init(x: 50, y: 20)],
            [.init(x: 90, y: 102), .init(x: 90, y: 28), .init(x: 78, y: 28), .init(x: 78, y: 20)],
            [.init(x: 23, y: 102), .init(x: 23, y: 60), .init(x: 78, y: 60), .init(x: 78, y: 20)],
            [.init(x: 90, y: 102), .init(x: 90, y: 28), .init(x: 78, y: 28), .init(x: 78, y: 20)],
            [.init(x: 22, y: 102), .init(x: 22, y: 20)],
            [.init(x: 22, y: 28), .init(x: 78, y: 28), .init(x: 78, y: 20)],
            [.init(x: 50, y: 20)]
        ]
        let index = stage.id - 9
        return routes[index % 8].map { .init(x: (index / 8) % 2 == 1 ? 100 - $0.x : $0.x, y: $0.y) }
    }

    func testAll48StagesHaveCollisionFreeSolutionsAndChaptersPartitionThem() {
        XCTAssertEqual(ParkingStage.all.count, 48)
        XCTAssertEqual(Set(ParkingStage.all.map(\.id)).count, 48)
        XCTAssertEqual(ParkingChapter.all.flatMap(\.stages).map(\.id), Array(1...48))
        XCTAssertTrue(ParkingChapter.all.allSatisfy { $0.stages.count == 12 })
        for stage in ParkingStage.all {
            let run = finish(stage, via: solution(for: stage))
            XCTAssertEqual(run.phase, .parked, "Stage \(stage.id) is not solvable")
            XCTAssertEqual(run.awards, .all, "Stage \(stage.id)")
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
        XCTAssertEqual(store.load(), [1, 2])
    }

    func testAwardsRequireCompletionAndRecordBestWithoutFarmingStars() throws {
        let suite = "ParkingAwards.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ParkingProgressStore(defaults: defaults)
        let stage = ParkingStage.all[0]
        var run = ParkingRun(stage: stage)
        XCTAssertEqual(run.awards, [])
        run.begin(at: stage.start); run.extend(to: .init(x: 50, y: 60)); run.drive()
        while run.phase == .driving { run.step() }
        run.begin(at: run.pose.center); run.extend(to: stage.destination); run.drive()
        while run.phase == .driving { run.step() }
        XCTAssertEqual(run.awards, [.parked, .noCollision])
        store.save(run.awards, for: stage)
        XCTAssertEqual(store.totalStars, 2)
        for _ in 0..<10 { store.save(.all, for: stage) }
        store.save([.parked], for: stage)
        XCTAssertEqual(store.totalStars, 3)
        XCTAssertEqual(store.awards(for: stage), .all)
    }

    func testLegacyCompletionMigratesWithoutInventingBonusStars() throws {
        let suite = "ParkingLegacy.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([1, 2, -1, 999], forKey: "majung.parking.completed.v1")
        let store = ParkingProgressStore(defaults: defaults)
        XCTAssertEqual(store.totalStars, 2)
        store.save(.all, for: ParkingStage.all[0])
        XCTAssertEqual(store.totalStars, 4)
        XCTAssertEqual(store.load(), [1, 2])
    }

    func testCarUnlockSelectionAndSoundSurviveReload() throws {
        let suite = "ParkingGarage.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ParkingProgressStore(defaults: defaults)
        store.select(car: .coral)
        XCTAssertEqual(store.selectedCar, .blue)
        XCTAssertFalse(store.soundEnabled)
        for stage in ParkingStage.all.prefix(10) { store.save(.all, for: stage) }
        XCTAssertEqual(store.totalStars, 30)
        store.select(car: .coral)
        store.soundEnabled = true
        let restored = ParkingProgressStore(defaults: defaults)
        XCTAssertEqual(restored.selectedCar, .coral)
        XCTAssertEqual(restored.totalStars, 30)
        XCTAssertTrue(restored.soundEnabled)
    }

    func testDailyIsStableForLocalDateAndEveryDayIsSolvable() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3600))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16)))
        let morning = ParkingDaily.stage(on: date.addingTimeInterval(3600), timeZone: zone)
        let evening = ParkingDaily.stage(on: date.addingTimeInterval(23 * 3600), timeZone: zone)
        XCTAssertEqual(morning.dailyKey, "2026-11-16")
        XCTAssertEqual(morning.start, evening.start)
        XCTAssertEqual(morning.destination, evening.destination)
        XCTAssertEqual(morning.id, evening.id)
        let yesterday = ParkingDaily.stage(on: date.addingTimeInterval(-1), timeZone: zone)
        XCTAssertEqual(yesterday.dailyKey, "2026-11-15")
        for day in 0..<366 {
            let daily = ParkingDaily.stage(on: date.addingTimeInterval(Double(day) * 86400), timeZone: zone)
            let base = ParkingStage.all[daily.id - 1]
            let flipped = daily.start != base.start || daily.destination != base.destination
            let route = solution(for: base).map { ParkingPoint(x: flipped ? 100 - $0.x : $0.x, y: $0.y) }
            XCTAssertEqual(finish(daily, via: route).phase, .parked, "Daily \(daily.dailyKey ?? "")")
        }
    }

    func testDailyResultsDoNotUnlockCarsAndKeepOnly30Days() throws {
        let suite = "ParkingDaily.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ParkingProgressStore(defaults: defaults)
        for day in 0..<40 {
            let daily = ParkingDaily.stage(on: Date(timeIntervalSince1970: 1_795_000_000 + Double(day) * 86400))
            store.save(.all, for: daily)
        }
        XCTAssertEqual(store.totalStars, 0)
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(defaults.dictionary(forKey: "majung.parking.daily.v1")?.count, 30)
        let today = ParkingDaily.stage(on: Date())
        store.save(.all, for: today)
        store.save([.parked], for: today)
        XCTAssertEqual(store.awards(for: today), .all)
    }

    func testNearObstacleReactionOccursBeforeCollision() {
        var run = ParkingRun(stage: ParkingStage.all[1])
        run.begin(at: run.stage.start)
        run.extend(to: .init(x: 36, y: 100))
        run.extend(to: .init(x: 36, y: 60))
        run.drive()
        var approached = false
        while run.phase == .driving {
            run.step()
            if run.isNearObstacle { approached = true; XCTAssertFalse(ParkingGeometry.collides(run.pose, in: run.stage)) }
        }
        XCTAssertTrue(approached)
        XCTAssertEqual(run.collisions, 0)
    }

}
