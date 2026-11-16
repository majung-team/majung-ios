import Foundation

struct ParkingPoint: Equatable, Codable {
    var x: Double
    var y: Double

    func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
}

struct ParkingRect: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    func contains(_ point: ParkingPoint) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }

    var corners: [ParkingPoint] {
        [.init(x: x, y: y), .init(x: x + width, y: y),
         .init(x: x + width, y: y + height), .init(x: x, y: y + height)]
    }
}

struct ParkingPose: Equatable {
    var center: ParkingPoint
    var heading: Double = -.pi / 2

    // Board coordinates are independent of the screen size. The car is 8 × 14 units.
    var corners: [ParkingPoint] {
        let forward = ParkingPoint(x: cos(heading) * 7, y: sin(heading) * 7)
        let side = ParkingPoint(x: -sin(heading) * 4, y: cos(heading) * 4)
        return [-1.0, 1.0].flatMap { a in
            [-1.0, 1.0].map { b in
                ParkingPoint(x: center.x + a * forward.x + b * side.x,
                             y: center.y + a * forward.y + b * side.y)
            }
        }
    }
}

struct ParkingObstacle: Identifiable {
    enum Kind { case car, island }
    let id: Int
    let rect: ParkingRect
    let kind: Kind
}

struct ParkingStage: Identifiable {
    let id: Int
    let title: String
    let hint: String
    let start: ParkingPoint
    let destination: ParkingPoint
    let obstacles: [ParkingObstacle]

    var bay: ParkingRect {
        .init(x: destination.x - 8, y: destination.y - 12, width: 16, height: 24)
    }

    static let all: [Self] = [
        .init(id: 1, title: "첫 주차", hint: "파란 차에서 P까지 선을 그려보세요.",
              start: .init(x: 50, y: 100), destination: .init(x: 50, y: 22), obstacles: []),
        .init(id: 2, title: "작은 화단", hint: "가운데 화단을 돌아서 들어가요.",
              start: .init(x: 24, y: 100), destination: .init(x: 76, y: 22), obstacles: [
                .init(id: 0, rect: .init(x: 42, y: 48, width: 16, height: 30), kind: .island)
              ]),
        .init(id: 3, title: "먼저 온 차들", hint: "주차된 차와 조금 여유를 두세요.",
              start: .init(x: 77, y: 101), destination: .init(x: 23, y: 22), obstacles: [
                .init(id: 0, rect: .init(x: 42, y: 47, width: 12, height: 23), kind: .car),
                .init(id: 1, rect: .init(x: 22, y: 63, width: 12, height: 23), kind: .car)
              ]),
        .init(id: 4, title: "한 번 꺾어서", hint: "화단 아래를 지나 오른쪽 길로 올라가요.",
              start: .init(x: 23, y: 100), destination: .init(x: 76, y: 22), obstacles: [
                .init(id: 0, rect: .init(x: 9, y: 47, width: 48, height: 16), kind: .island)
              ]),
        .init(id: 5, title: "지그재그", hint: "왼쪽으로, 다시 오른쪽으로. 차 폭도 생각해요.",
              start: .init(x: 76, y: 102), destination: .init(x: 76, y: 20), obstacles: [
                .init(id: 0, rect: .init(x: 43, y: 72, width: 47, height: 12), kind: .island),
                .init(id: 1, rect: .init(x: 10, y: 35, width: 47, height: 12), kind: .island)
              ]),
        .init(id: 6, title: "좁은 입구", hint: "두 차 사이로 천천히 들어가요.",
              start: .init(x: 50, y: 102), destination: .init(x: 50, y: 22), obstacles: [
                .init(id: 0, rect: .init(x: 21, y: 40, width: 19, height: 29), kind: .car),
                .init(id: 1, rect: .init(x: 60, y: 40, width: 19, height: 29), kind: .car)
              ]),
        .init(id: 7, title: "모퉁이 너머", hint: "아래쪽 길을 돌아 빈자리로 가요.",
              start: .init(x: 22, y: 100), destination: .init(x: 77, y: 22), obstacles: [
                .init(id: 0, rect: .init(x: 40, y: 12, width: 15, height: 65), kind: .island),
                .init(id: 1, rect: .init(x: 70, y: 60, width: 13, height: 22), kind: .car)
              ]),
        .init(id: 8, title: "오늘도 잘 주차", hint: "길을 크게 보고 마지막 방향을 맞춰보세요.",
              start: .init(x: 22, y: 102), destination: .init(x: 77, y: 20), obstacles: [
                .init(id: 0, rect: .init(x: 40, y: 72, width: 48, height: 12), kind: .island),
                .init(id: 1, rect: .init(x: 10, y: 36, width: 46, height: 12), kind: .island),
                .init(id: 2, rect: .init(x: 65, y: 98, width: 12, height: 17), kind: .car)
              ])
    ]
}

enum ParkingGeometry {
    static let bounds = ParkingRect(x: 3, y: 3, width: 94, height: 114)

    static func collides(_ pose: ParkingPose, in stage: ParkingStage) -> Bool {
        let corners = pose.corners
        guard corners.allSatisfy(bounds.contains) else { return true }
        let axes = [ParkingPoint(x: 1, y: 0), ParkingPoint(x: 0, y: 1),
                    ParkingPoint(x: cos(pose.heading), y: sin(pose.heading)),
                    ParkingPoint(x: -sin(pose.heading), y: cos(pose.heading))]
        return stage.obstacles.contains { obstacle in
            axes.allSatisfy { axis in
                let car = corners.map { $0.x * axis.x + $0.y * axis.y }
                let wall = obstacle.rect.corners.map { $0.x * axis.x + $0.y * axis.y }
                return car.min()! <= wall.max()! && wall.min()! <= car.max()!
            }
        }
    }

    static func isParked(_ pose: ParkingPose, in stage: ParkingStage) -> Bool {
        let angle = abs(atan2(sin(pose.heading + .pi / 2), cos(pose.heading + .pi / 2)))
        return !collides(pose, in: stage) && pose.corners.allSatisfy(stage.bay.contains)
            && angle < .pi / 8
    }

    // Subdivide every segment so even a fast drag cannot jump through an obstacle.
    static func samples(from start: ParkingPoint, to end: ParkingPoint) -> [ParkingPoint] {
        let count = max(1, Int(ceil(start.distance(to: end) / 0.6)))
        return (1...count).map { index in
            let t = Double(index) / Double(count)
            return .init(x: start.x + (end.x - start.x) * t,
                         y: start.y + (end.y - start.y) * t)
        }
    }
}

struct ParkingRun {
    enum Phase: Equatable { case ready, drawing, driving, collision, parked }
    let stage: ParkingStage
    private(set) var pose: ParkingPose
    private(set) var route: [ParkingPoint] = []
    private(set) var phase: Phase = .ready
    private(set) var strokes = 0
    private(set) var collisions = 0
    private var cursor = 0

    init(stage: ParkingStage) {
        self.stage = stage
        pose = ParkingPose(center: stage.start)
    }

    mutating func begin(at point: ParkingPoint) {
        guard phase != .driving, phase != .parked,
              point.distance(to: pose.center) <= 14 else { return }
        route = [pose.center]
        phase = .drawing
    }

    mutating func extend(to point: ParkingPoint) {
        guard phase == .drawing, point.x.isFinite, point.y.isFinite,
              route.count < 6_000, let previous = route.last,
              previous.distance(to: point) >= 0.8 else { return }
        let bounded = ParkingPoint(x: min(96, max(4, point.x)), y: min(116, max(4, point.y)))
        guard previous.distance(to: bounded) >= 0.8 else { return }
        route.append(contentsOf: ParkingGeometry.samples(from: previous, to: bounded))
    }

    mutating func drive() {
        guard phase == .drawing else { return }
        guard route.count > 2 else { phase = .ready; route = []; return }
        strokes += 1
        cursor = 1
        phase = .driving
    }

    mutating func step() {
        guard phase == .driving, cursor < route.count else { return }
        let next = route[cursor]
        let proposed = ParkingPose(center: next,
                                   heading: atan2(next.y - pose.center.y, next.x - pose.center.x))
        if ParkingGeometry.collides(proposed, in: stage) {
            collisions += 1
            phase = .collision
            pose = ParkingPose(center: stage.start)
            return
        }
        pose = proposed
        cursor += 1
        if cursor == route.count {
            phase = ParkingGeometry.isParked(pose, in: stage) ? .parked : .ready
        }
    }

    mutating func pause() {
        guard phase == .driving || phase == .drawing else { return }
        route = []
        phase = .ready
    }
}

struct ParkingProgressStore {
    private let defaults: UserDefaults
    private let key = "majung.parking.completed.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> Set<Int> {
        let ids = defaults.array(forKey: key) as? [Int] ?? []
        let valid = Set(ParkingStage.all.map(\.id))
        return Set(ids).intersection(valid)
    }

    func complete(stageId: Int) {
        guard ParkingStage.all.contains(where: { $0.id == stageId }) else { return }
        var ids = load()
        ids.insert(stageId)
        defaults.set(ids.sorted(), forKey: key)
    }
}
