import Foundation

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
