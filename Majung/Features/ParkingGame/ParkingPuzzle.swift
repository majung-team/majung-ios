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

struct ParkingStage: Identifiable {
    let id: Int
    let title: String
    let hint: String
    let start: ParkingPoint
    let destination: ParkingPoint
    let obstacles: [ParkingObstacle]
    var dailyKey: String? = nil
    var themeOverride: ParkingTheme? = nil

    var theme: ParkingTheme { themeOverride ?? ParkingChapter.containing(stageId: id).theme }

    var bay: ParkingRect {
        .init(x: destination.x - 8, y: destination.y - 12, width: 16, height: 24)
    }

    private static let originals: [Self] = [
        .init(id: 1, title: "첫 주차", hint: "차에서 P까지 선을 그려보세요.",
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

    static let all: [Self] = originals + (9...48).map { id in
        let index = id - 9
        let shape = index % 8
        let variation = index / 8
        let offset = Double(variation - 2) * 2
        let mirrored = variation % 2 == 1
        func p(_ x: Double, _ y: Double) -> ParkingPoint {
            .init(x: mirrored ? 100 - x : x, y: y)
        }
        func obstacle(_ id: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                      _ kind: ParkingObstacle.Kind = .island) -> ParkingObstacle {
            .init(id: id, rect: .init(x: mirrored ? 100 - x - w : x, y: y, width: w, height: h), kind: kind)
        }
        let start: ParkingPoint
        let destination: ParkingPoint
        let obstacles: [ParkingObstacle]
        let title: String
        switch shape {
        case 0:
            start = p(22, 102); destination = p(78, 20); title = "큰 화단 옆으로"
            obstacles = [obstacle(0, 40, 50 + offset, 24, 28)]
        case 1:
            start = p(50, 102); destination = p(50, 20); title = "사이좋게 나란히"
            obstacles = [obstacle(0, 22, 48 + offset, 18, 26, .car),
                         obstacle(1, 60, 48 - offset, 18, 26, .car)]
        case 2:
            start = p(22, 102); destination = p(78, 20); title = "끝까지 돌아서"
            obstacles = [obstacle(0, 40, 38 + offset, 16, 50),
                         obstacle(1, 70, 65 + offset, 12, 20, .car)]
        case 3:
            start = p(78, 102); destination = p(78, 20); title = "두 번 꺾는 길"
            obstacles = [obstacle(0, 43, 74 + offset, 47, 10),
                         obstacle(1, 10, 36 + offset, 47, 10)]
        case 4:
            start = p(22, 102); destination = p(78, 20); title = "모서리를 따라서"
            obstacles = [obstacle(0, 10, 48 + offset, 48, 16),
                         obstacle(1, 65, 73 + offset, 12, 19, .car)]
        case 5:
            start = p(78, 102); destination = p(22, 20); title = "빈자리 찾기"
            obstacles = [obstacle(0, 39, 62 + offset, 12, 22, .car),
                         obstacle(1, 59, 45 + offset, 12, 22, .car),
                         obstacle(2, 39, 28 + offset, 12, 22, .car)]
        case 6:
            start = p(22, 102); destination = p(78, 20); title = "작은 섬 두 개"
            obstacles = [obstacle(0, 39, 69 + offset, 18, 15),
                         obstacle(1, 39, 37 + offset, 18, 15)]
        default:
            start = p(50, 102); destination = p(50, 20); title = "마지막 통로"
            obstacles = [obstacle(0, 14, 34 + offset, 25, 54),
                         obstacle(1, 61, 34 - offset, 25, 54)]
        }
        return Self(id: id, title: title, hint: "장애물을 피해 빈자리로. 차 앞쪽은 위로 맞춰요.",
                    start: start, destination: destination, obstacles: obstacles)
    }
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

enum ParkingTheme: String, CaseIterable, Codable {
    case blossoms, rainy, sunset, night

    var title: String {
        switch self {
        case .blossoms: "벚꽃 공영 주차장"
        case .rainy: "비 오는 편의점"
        case .sunset: "해 질 녘 골목"
        case .night: "밤의 아파트"
        }
    }

    var symbol: String {
        switch self {
        case .blossoms: "leaf.fill"
        case .rainy: "cloud.rain.fill"
        case .sunset: "sun.haze.fill"
        case .night: "moon.stars.fill"
        }
    }
}

struct ParkingAwards: OptionSet, Codable, Equatable {
    let rawValue: Int
    static let parked = Self(rawValue: 1)
    static let oneLine = Self(rawValue: 2)
    static let noCollision = Self(rawValue: 4)
    static let all: Self = [.parked, .oneLine, .noCollision]
    var count: Int { (rawValue & 7).nonzeroBitCount }
}

enum ParkingCarStyle: String, CaseIterable, Codable, Identifiable {
    case blue, taxi, mintVan, pickup, suv, coral, camper, classic, roadster, deliveryVan
    var id: String { rawValue }
    var requiredStars: Int {
        switch self {
        case .blue: 0
        case .taxi: 3
        case .mintVan: 12
        case .pickup: 18
        case .suv: 24
        case .coral: 30
        case .camper: 48
        case .classic: 60
        case .roadster: 90
        case .deliveryVan: 120
        }
    }
    var title: String {
        switch self {
        case .blue: "파란 경차"
        case .taxi: "노란 택시"
        case .mintVan: "민트 미니밴"
        case .pickup: "초록 픽업트럭"
        case .suv: "보라 SUV"
        case .coral: "산호빛 쿠페"
        case .camper: "작은 캠핑카"
        case .classic: "크림 클래식카"
        case .roadster: "빨간 로드스터"
        case .deliveryVan: "주황 배송밴"
        }
    }
    var detail: String {
        switch self {
        case .blue: "작고 둥근 기본 경차"
        case .taxi: "지붕 위 택시등이 포인트"
        case .mintVan: "긴 창이 있는 미니밴"
        case .pickup: "뒤에 짐칸을 실은 픽업트럭"
        case .suv: "루프 레일을 얹은 SUV"
        case .coral: "낮은 지붕의 두 문짜리 쿠페"
        case .camper: "지붕 환기창과 줄무늬 캠핑카"
        case .classic: "크롬 범퍼가 있는 클래식카"
        case .roadster: "지붕을 연 두 자리 로드스터"
        case .deliveryVan: "작은 상자를 실은 배송밴"
        }
    }
}

enum ParkingDaily {
    // A dated variation of a proven board, optionally mirrored. No untested random walls.
    static func stage(on date: Date, timeZone: TimeZone = .current) -> ParkingStage {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 2026
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        let seed = year * 372 + month * 31 + day
        let base = ParkingStage.all[1 + seed % (ParkingStage.all.count - 1)]
        let mirror = seed % 2 == 0
        func point(_ point: ParkingPoint) -> ParkingPoint {
            .init(x: mirror ? 100 - point.x : point.x, y: point.y)
        }
        let obstacles = base.obstacles.map { obstacle in
            let r = obstacle.rect
            return ParkingObstacle(id: obstacle.id,
                                   rect: .init(x: mirror ? 100 - r.x - r.width : r.x,
                                               y: r.y, width: r.width, height: r.height), kind: obstacle.kind)
        }
        return ParkingStage(id: base.id, title: "오늘의 주차",
                            hint: "장애물을 피해 빈자리로. 마지막엔 차 앞쪽을 위로 맞춰요.",
                            start: point(base.start), destination: point(base.destination), obstacles: obstacles,
                            dailyKey: key, themeOverride: ParkingTheme.allCases[seed % ParkingTheme.allCases.count])
    }
}

struct ParkingProgressStore {
    private let defaults: UserDefaults
    private let key = "majung.parking.completed.v1"
    private let starsKey = "majung.parking.awards.v1"
    private let dailyKey = "majung.parking.daily.v1"
    private let carKey = "majung.parking.car.v1"
    private let soundKey = "majung.parking.sound.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> Set<Int> {
        Set(ParkingStage.all.filter { awards(for: $0).contains(.parked) }.map(\.id))
    }

    func awards(for stage: ParkingStage) -> ParkingAwards {
        let dictionary = defaults.dictionary(forKey: stage.dailyKey == nil ? starsKey : dailyKey) ?? [:]
        let recordKey = stage.dailyKey ?? String(stage.id)
        let raw = (dictionary[recordKey] as? Int ?? 0) & 7
        // Preserve completion from the first version without inventing extra achievements.
        let legacy = (defaults.array(forKey: key) as? [Int] ?? []).contains(stage.id)
        guard raw & 1 != 0 else {
            return stage.dailyKey == nil && legacy ? [.parked] : []
        }
        return ParkingAwards(rawValue: raw)
    }

    var totalStars: Int { ParkingStage.all.reduce(0) { $0 + awards(for: $1).count } }

    func complete(stageId: Int) {
        guard let stage = ParkingStage.all.first(where: { $0.id == stageId }) else { return }
        save([.parked], for: stage)
    }

    func save(_ awards: ParkingAwards, for stage: ParkingStage) {
        guard awards.contains(.parked), ParkingStage.all.contains(where: { $0.id == stage.id }) else { return }
        let storageKey = stage.dailyKey == nil ? starsKey : dailyKey
        var records = defaults.dictionary(forKey: storageKey) ?? [:]
        records[stage.dailyKey ?? String(stage.id)] = self.awards(for: stage).union(awards).rawValue & 7
        if stage.dailyKey != nil {
            // Keep today's result even if the device clock moved back after a future date.
            let current = stage.dailyKey ?? ""
            let keep = Set(records.keys.filter { $0 != current }.sorted().suffix(29)).union([current])
            records = records.filter { keep.contains($0.key) }
        }
        defaults.set(records, forKey: storageKey)
    }

    var selectedCar: ParkingCarStyle {
        guard let raw = defaults.string(forKey: carKey), let car = ParkingCarStyle(rawValue: raw),
              car.requiredStars <= totalStars else { return .blue }
        return car
    }

    func select(car: ParkingCarStyle) {
        guard car.requiredStars <= totalStars else { return }
        defaults.set(car.rawValue, forKey: carKey)
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: soundKey) }
        nonmutating set { defaults.set(newValue, forKey: soundKey) }
    }
}

struct ParkingChapter: Identifiable {
    let id: Int
    let theme: ParkingTheme
    let subtitle: String
    var stages: [ParkingStage] { ParkingStage.all.filter { ($0.id - 1) / 12 == id } }
    static let all: [Self] = [
        .init(id: 0, theme: .blossoms, subtitle: "꽃잎 옆 빈자리부터, 가볍게 한 바퀴"),
        .init(id: 1, theme: .rainy, subtitle: "우산은 잠시 접고, 차 사이를 쏙"),
        .init(id: 2, theme: .sunset, subtitle: "낮은 담장 너머로 꺾어 들어가는 길"),
        .init(id: 3, theme: .night, subtitle: "불 켜진 창 아래, 조용히 주차 한 판")
    ]
    static func containing(stageId: Int) -> Self {
        all[min(all.count - 1, max(0, (stageId - 1) / 12))]
    }
}
