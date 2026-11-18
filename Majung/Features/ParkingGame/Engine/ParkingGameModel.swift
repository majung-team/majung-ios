import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ParkingGame {
    private(set) var run = ParkingRun(stage: ParkingStage.all[0])
    private(set) var totalStars: Int
    private(set) var car: ParkingCarStyle
    private(set) var soundEnabled: Bool
    private(set) var newCars: [ParkingCarStyle] = []
    private(set) var pickupInterruption: ParkingPickupNotice?
    private(set) var savedSession: ParkingSavedSession?
    private let store: ParkingProgressStore
    private let effects = ParkingEffects()
    private var driveTask: Task<Void, Never>?
    private var nearFeedbackSent = false

    init(store: ParkingProgressStore = ParkingProgressStore()) {
        self.store = store
        totalStars = store.totalStars
        car = store.selectedCar
        soundEnabled = store.soundEnabled
        savedSession = store.savedSession
    }

    func awards(for stage: ParkingStage) -> ParkingAwards { store.awards(for: stage) }

    func select(_ stage: ParkingStage) {
        guard pickupInterruption == nil else { return }
        pause()
        run = ParkingRun(stage: stage)
        newCars = []
    }

    func selectDaily(on date: Date = Date()) { select(ParkingDaily.stage(on: date)) }

    func select(car: ParkingCarStyle) {
        store.select(car: car)
        self.car = store.selectedCar
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        store.soundEnabled = enabled
        if !enabled { effects.stop() }
    }

    func draw(start: ParkingPoint, point: ParkingPoint) {
        guard pickupInterruption == nil else { return }
        if run.phase != .drawing { run.begin(at: start) }
        run.extend(to: point)
    }

    func drive() {
        guard pickupInterruption == nil, driveTask == nil else { return }
        run.drive()
        guard run.phase == .driving else { return }
        nearFeedbackSent = false
        driveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                guard !Task.isCancelled, let self else { break }
                self.run.step()
                if self.run.isNearObstacle && !self.nearFeedbackSent {
                    self.nearFeedbackSent = true
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
                }
                if self.run.phase != .driving {
                    if self.run.phase == .parked {
                        let previousStars = self.totalStars
                        self.store.save(self.run.awards, for: self.run.stage)
                        self.store.clearSession()
                        self.savedSession = nil
                        self.totalStars = self.store.totalStars
                        self.newCars = ParkingCarStyle.allCases.filter {
                            $0.requiredStars > previousStars && $0.requiredStars <= self.totalStars
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        if self.soundEnabled { self.effects.play(success: true) }
                    } else if self.run.phase == .collision {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        if self.soundEnabled { self.effects.play(success: false) }
                    }
                    self.driveTask = nil
                    return
                }
            }
        }
    }

    func saveCurrentSession(interruptedByPickup: Bool = false) {
        guard run.phase != .parked else { return }
        guard run.strokes > 0 || run.pose.center != run.stage.start || interruptedByPickup else { return }
        let session = ParkingSavedSession(
            stageId: run.stage.id,
            dailyKey: run.stage.dailyKey,
            pose: run.pose,
            strokes: run.strokes,
            collisions: run.collisions,
            interruptedByPickup: interruptedByPickup
        )
        store.saveSession(session)
        savedSession = session
    }

    @discardableResult
    func resumeSavedSession(on date: Date = Date()) -> Bool {
        guard let session = savedSession else { return false }
        let stage: ParkingStage
        if session.dailyKey != nil {
            stage = ParkingDaily.stage(on: date)
        } else if let found = ParkingStage.all.first(where: { $0.id == session.stageId }) {
            stage = found
        } else {
            return false
        }
        driveTask?.cancel()
        driveTask = nil
        effects.stop()
        pickupInterruption = nil
        newCars = []
        run = ParkingRun(
            stage: stage,
            pose: session.pose,
            strokes: session.strokes,
            collisions: session.collisions
        )
        return true
    }

    func interrupt(for notice: ParkingPickupNotice?) {
        guard let notice else { return }
        pause()
        saveCurrentSession(interruptedByPickup: true)
        if let current = pickupInterruption, current.priority > notice.priority { return }
        pickupInterruption = notice
    }

    func pause() {
        driveTask?.cancel()
        driveTask = nil
        effects.stop()
        run.pause()
        if run.strokes > 0 && run.phase != .parked {
            saveCurrentSession(interruptedByPickup: savedSession?.interruptedByPickup ?? false)
        }
    }
}

// Shared by guest invitations and signed-in ride tracking; no pickup mutation from the game.
enum ParkingPickupNotice: Equatable {
    case arrived, completed, cancelled, expired, unavailable

    init?(status: PickupSnapshot.Status?, connectionProblem: Bool = false) {
        switch status {
        case .arrived: self = .arrived
        case .completed: self = .completed
        case .cancelled: self = .cancelled
        case .expired, .inviteExpired: self = .expired
        case nil: self = .unavailable
        case .inviting, .waiting, .active:
            if connectionProblem { self = .unavailable } else { return nil }
        }
    }

    var priority: Int {
        switch self {
        case .unavailable: 0
        case .arrived: 1
        case .completed, .cancelled, .expired: 2
        }
    }

    var title: String {
        switch self {
        case .arrived: "차가 도착했어요"
        case .completed: "픽업이 끝났어요"
        case .cancelled: "픽업 요청이 취소됐어요"
        case .expired: "초대를 더 이상 사용할 수 없어요"
        case .unavailable: "픽업 상태를 확인해주세요"
        }
    }
    var message: String {
        switch self {
        case .arrived: "게임은 잠깐 멈췄어요. 픽업 화면에서 차량 위치를 확인해주세요."
        case .completed, .cancelled, .expired: "게임을 멈췄어요. 픽업 화면에서 바뀐 내용을 확인해주세요."
        case .unavailable: "픽업 상태를 확인하지 못해 게임을 멈췄어요. 픽업 화면에서 연결 상태를 확인해주세요."
        }
    }
    var symbol: String {
        switch self {
        case .arrived: "car.side.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled, .expired: "xmark.circle.fill"
        case .unavailable: "wifi.exclamationmark"
        }
    }
}
