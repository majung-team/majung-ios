import Foundation

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

struct ParkingSavedSession: Codable, Equatable {
    let stageId: Int
    let dailyKey: String?
    let pose: ParkingPose
    let strokes: Int
    let collisions: Int
    let interruptedByPickup: Bool
}

struct ParkingProgressStore {
    private let defaults: UserDefaults
    private let key = "majung.parking.completed.v1"
    private let starsKey = "majung.parking.awards.v1"
    private let dailyKey = "majung.parking.daily.v1"
    private let carKey = "majung.parking.car.v1"
    private let soundKey = "majung.parking.sound.v1"
    private let sessionKey = "majung.parking.savedSession.v1"

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

    var savedSession: ParkingSavedSession? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(ParkingSavedSession.self, from: data)
    }

    func saveSession(_ session: ParkingSavedSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: sessionKey)
    }

    func clearSession() {
        defaults.removeObject(forKey: sessionKey)
    }
}
