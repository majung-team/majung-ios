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
        point.x >= x - 1e-8 && point.x <= x + width + 1e-8
            && point.y >= y - 1e-8 && point.y <= y + height + 1e-8
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

enum ParkingRouteFeedback: Equatable {
    case startAtCar, shortRoute, collision, boundary, outsideBay, wrongDirection, partialRoute

    var message: String {
        switch self {
        case .startAtCar: "차 위에서 손가락을 대고 선을 그려주세요."
        case .shortRoute: "선을 조금 더 길게 그린 뒤 손을 떼주세요."
        case .collision: "앗, 닿았어요. 표시된 장애물을 피해 차에서 다시 그려보세요."
        case .boundary: "주차장 밖으로 나갔어요. 테두리 안쪽으로 그려주세요."
        case .outsideBay: "차가 주차 칸에 걸쳐 있어요. 차 전체를 칸 안에 넣어주세요."
        case .wrongDirection: "칸에는 들어왔어요! 마지막 선을 위쪽 화살표 방향으로 그려주세요."
        case .partialRoute: "아직 주차 칸에 도착하지 않았어요. 지금 차 위치에서 선을 이어주세요."
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
    private(set) var feedback: ParkingRouteFeedback?
    private(set) var collisionPose: ParkingPose?
    private var cursor = 0

    var awards: ParkingAwards {
        guard phase == .parked else { return [] }
        var result: ParkingAwards = [.parked]
        if strokes == 1 { result.insert(.oneLine) }
        if collisions == 0 { result.insert(.noCollision) }
        return result
    }

    var isNearObstacle: Bool {
        guard phase == .driving else { return false }
        return stage.obstacles.contains { obstacle in
            let rect = obstacle.rect
            let expanded = ParkingRect(x: rect.x - 2, y: rect.y - 2,
                                       width: rect.width + 4, height: rect.height + 4)
            return pose.corners.contains(where: expanded.contains)
        }
    }

    init(stage: ParkingStage) {
        self.stage = stage
        pose = ParkingPose(center: stage.start)
    }

    mutating func begin(at point: ParkingPoint) {
        guard phase != .driving, phase != .parked else { return }
        guard point.distance(to: pose.center) <= 14 else {
            feedback = .startAtCar
            return
        }
        feedback = nil
        collisionPose = nil
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
        guard route.count > 2 else { phase = .ready; route = []; feedback = .shortRoute; return }
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
            collisionPose = proposed
            feedback = proposed.corners.allSatisfy(ParkingGeometry.bounds.contains) ? .collision : .boundary
            phase = .collision
            pose = ParkingPose(center: stage.start)
            return
        }
        pose = proposed
        cursor += 1
        if cursor == route.count {
            phase = ParkingGeometry.isParked(pose, in: stage) ? .parked : .ready
            if phase == .parked { feedback = nil }
            else if pose.corners.allSatisfy(stage.bay.contains) { feedback = .wrongDirection }
            else if stage.bay.contains(pose.center) { feedback = .outsideBay }
            else { feedback = .partialRoute }
        }
    }

    mutating func pause() {
        guard phase == .driving || phase == .drawing else { return }
        route = []
        phase = .ready
    }
}
