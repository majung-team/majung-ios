import SwiftUI
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
    private let store: ParkingProgressStore
    private let effects = ParkingEffects()
    private var driveTask: Task<Void, Never>?
    private var nearFeedbackSent = false

    init(store: ParkingProgressStore = ParkingProgressStore()) {
        self.store = store
        totalStars = store.totalStars
        car = store.selectedCar
        soundEnabled = store.soundEnabled
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

    func toggleSound() {
        soundEnabled.toggle()
        store.soundEnabled = soundEnabled
        if !soundEnabled { effects.stop() }
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

    func interrupt(for notice: ParkingPickupNotice?) {
        guard let notice else { return }
        pause()
        if let current = pickupInterruption, current.priority > notice.priority { return }
        pickupInterruption = notice
    }

    func pause() {
        driveTask?.cancel()
        driveTask = nil
        effects.stop()
        run.pause()
    }
}

struct ParkingGameEntry: View {
    var tracker: PickupTracker? = nil
    var compact = false
    @State private var isPresented = false

    var body: some View {
        Button {
            dismissMajungKeyboard()
            isPresented = true
        } label: {
            if compact {
                Label("잠깐 주차", systemImage: "steeringwheel").font(.subheadline)
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "steeringwheel")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color(red: 0.23, green: 0.43, blue: 0.91), in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("잠깐 주차").font(.headline).foregroundStyle(.primary)
                        Text("선을 그려 빈자리에 쏙. 언제든 한 판!")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isPresented && tracker.map {
            ParkingPickupNotice(status: $0.snapshot?.status, connectionProblem: $0.connectionProblem) != nil
        } == true)
        .accessibilityIdentifier(compact ? "pickup-parking-open" : "parking-game-open")
        .sheet(isPresented: $isPresented) {
            ParkingGamePresentation(tracker: tracker)
                .preferredColorScheme(.light)
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ParkingGamePresentation: View {
    var tracker: PickupTracker?
    var body: some View {
        ParkingGameView(pickupNotice: tracker.flatMap {
            ParkingPickupNotice(status: $0.snapshot?.status, connectionProblem: $0.connectionProblem)
        })
    }
}

struct ParkingGameView: View {
    var pickupNotice: ParkingPickupNotice? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var game = ParkingGame()
    @State private var hasStarted = false
    @State private var showingStages = false
    @State private var showingGarage = false

    private let ink = Color(red: 0.12, green: 0.20, blue: 0.29)
    private let blue = Color(red: 0.23, green: 0.43, blue: 0.91)

    private var message: String {
        switch game.run.phase {
        case .drawing: "좋아요. 손을 떼면 출발해요."
        case .driving: game.run.isNearObstacle ? "사이드미러 접고, 살짝 지나가요." : "주차 중…"
        case .collision: "앗, 닿았어요. 차에서 다시 그려보세요."
        case .parked: "빈자리에 쏙! 이번엔 별 \(game.run.awards.count)개예요."
        case .ready: game.run.strokes == 0 ? game.run.stage.hint : "차에서 선을 이어서 그릴 수 있어요."
        }
    }

    var body: some View {
        Group {
            if let notice = game.pickupInterruption ?? pickupNotice {
                pickupNoticeScreen(notice)
            } else if hasStarted { NavigationStack { play } }
            else { chapters }
        }
        .onChange(of: pickupNotice, initial: true) { _, notice in
            guard notice != nil else { return }
            game.interrupt(for: notice)
            showingStages = false
            showingGarage = false
        }
        .onDisappear { game.pause() }
    }

    private func pickupNoticeScreen(_ notice: ParkingPickupNotice) -> some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: notice.symbol).font(.system(size: 52)).foregroundStyle(blue)
                Text(notice.title).font(.title2.bold()).multilineTextAlignment(.center)
                    .accessibilityIdentifier("parking-pickup-notice")
                Text(notice.message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { dismiss() } label: {
                    Text("픽업 확인").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).tint(blue)
                    .accessibilityIdentifier("parking-return-to-pickup")
                Spacer()
            }.padding(28).frame(maxWidth: 500).frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("마중 픽업").navigationBarTitleDisplayMode(.inline)
        }.accessibilityAddTraits(.updatesFrequently)
    }

    private var play: some View {
        GeometryReader { layout in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    GeometryReader { board in
                        ParkingBoard(run: game.run, car: game.car, reduceMotion: reduceMotion)
                            .contentShape(Rectangle())
                            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    game.draw(start: point(value.startLocation, in: board.size),
                                              point: point(value.location, in: board.size))
                                }
                                .onEnded { _ in game.drive() })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("주차장. 차에서 주차 칸까지 이동 경로를 그리세요.")
                            .accessibilityIdentifier("parking-board")
                    }
                    .aspectRatio(5.0 / 6, contentMode: .fit)
                    .frame(maxWidth: min(440, max(230, layout.size.height * 0.43)))
                    .frame(maxWidth: .infinity)
                    awardRow(game.run.phase == .parked ? game.run.awards : game.awards(for: game.run.stage))
                    feedback
                    if !game.newCars.isEmpty {
                        Button { showingGarage = true } label: {
                            Label("\(game.newCars.map(\.title).joined(separator: ", ")) 열렸어요!", systemImage: "gift.fill")
                                .font(.subheadline.bold()).frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).tint(blue)
                        .accessibilityIdentifier("parking-car-unlocked")
                    }
                    controls
                    Text("가상의 주차 퍼즐이에요. 실제 운전 방법과는 달라요.")
                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(red: 0.96, green: 0.96, blue: 0.93))
        }
        .foregroundStyle(ink)
        .navigationTitle("잠깐 주차")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("닫기") { game.pause(); dismiss() }.accessibilityIdentifier("parking-game-close")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { game.pause(); showingGarage = true } label: { Image(systemName: "car.side.fill") }
                    .accessibilityLabel("내 차 꾸미기").accessibilityIdentifier("parking-garage")
                Button { game.pause(); showingStages = true } label: { Image(systemName: "square.grid.2x2") }
                    .accessibilityLabel("챕터 선택").accessibilityIdentifier("parking-stage-picker")
            }
        }
        .sheet(isPresented: $showingStages) { chapters }
        .sheet(isPresented: $showingGarage) { garage }
        .onChange(of: scenePhase) { _, phase in if phase != .active { game.pause() } }
        .onDisappear { game.pause() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(game.run.stage.dailyKey.map { "DAILY · \($0)" } ?? String(format: "STAGE %02d", game.run.stage.id))
                    .font(.caption.monospaced().weight(.bold)).tracking(1).foregroundStyle(blue)
                Spacer()
                Label("\(game.totalStars) / \(ParkingStage.all.count * 3)", systemImage: "star.fill")
                    .font(.caption.bold()).foregroundStyle(ink)
                    .accessibilityIdentifier("parking-total-stars")
            }
            Text(game.run.stage.title).font(.system(.title2, design: .rounded, weight: .bold))
            Label(game.run.stage.theme.title, systemImage: game.run.stage.theme.symbol)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func awardRow(_ awards: ParkingAwards) -> some View {
        HStack(spacing: 8) {
            award("주차 완료", .parked, awards)
            award("한 번에", .oneLine, awards)
            award("무충돌", .noCollision, awards)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("도전 별 \(awards.count)개. 주차 완료, 한 번에 그리기, 부딪히지 않기")
        .accessibilityIdentifier("parking-awards")
    }

    private func award(_ title: String, _ flag: ParkingAwards, _ awards: ParkingAwards) -> some View {
        Label(title, systemImage: awards.contains(flag) ? "star.fill" : "star")
            .font(.caption.weight(.semibold)).foregroundStyle(awards.contains(flag) ? Color.brown : ink.opacity(0.6))
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(awards.contains(flag) ? Color.yellow.opacity(0.22) : .white.opacity(0.7), in: Capsule())
    }

    private var feedback: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: game.run.phase == .parked ? "checkmark.circle.fill" :
                    game.run.phase == .collision ? "arrow.counterclockwise.circle.fill" : "hand.draw.fill")
                .foregroundStyle(game.run.phase == .parked ? .green : blue)
            Text(message).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("parking-game-message")
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { game.select(game.run.stage) } label: {
                Label("다시 하기", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 40)
            }.buttonStyle(.bordered).tint(blue).accessibilityIdentifier("parking-restart")
            if game.run.phase == .parked {
                Button {
                    if game.run.stage.dailyKey == nil && game.run.stage.id < ParkingStage.all.count {
                        game.select(ParkingStage.all[game.run.stage.id])
                    } else { showingStages = true }
                } label: {
                    Text(game.run.stage.dailyKey == nil && game.run.stage.id < ParkingStage.all.count ? "다음 주차장" : "챕터 고르기")
                        .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 40)
                }.buttonStyle(.borderedProminent).tint(blue).accessibilityIdentifier("parking-next-stage")
            } else if game.run.phase == .driving {
                Button("멈추기") { game.pause() }.buttonStyle(.bordered).tint(blue)
                    .frame(minHeight: 44).accessibilityIdentifier("parking-pause")
            }
        }
    }

    private var chapters: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        game.selectDaily()
                        hasStarted = true
                        showingStages = false
                    } label: {
                        HStack {
                            Image(systemName: "calendar").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("오늘의 주차").font(.headline)
                                Text("날짜마다 새로운 길, 오늘도 한 판").font(.caption)
                            }
                            Spacer()
                            StarMarks(awards: game.awards(for: ParkingDaily.stage(on: Date())))
                        }.padding(18).foregroundStyle(.white)
                            .background(blue, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain).accessibilityIdentifier("parking-daily")
                    Text("주차 완료 · 한 번에 그리기 · 무충돌, 한 판에 별 세 개")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(ParkingChapter.all) { chapter in
                        NavigationLink { stageList(chapter) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: chapter.theme.symbol).font(.title)
                                    .frame(width: 56, height: 64)
                                    .foregroundStyle(chapter.theme.accent)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(format: "CHAPTER %02d", chapter.id + 1))
                                        .font(.caption2.monospaced().bold()).foregroundStyle(.secondary)
                                    Text(chapter.theme.title).font(.headline).foregroundStyle(ink)
                                    Text(chapter.subtitle).font(.caption).foregroundStyle(.secondary)
                                    let stars = chapter.stages.reduce(0) { $0 + game.awards(for: $1).count }
                                    Label("\(stars) / 36 · 스테이지 12개", systemImage: "star.fill")
                                        .font(.caption.bold()).foregroundStyle(chapter.theme.accent)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).accessibilityIdentifier("parking-chapter-\(chapter.id)")
                    }
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("챕터 고르기").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") {
                if hasStarted { showingStages = false } else { dismiss() }
            }.accessibilityIdentifier("parking-chapters-close") } }
        }
        .presentationDragIndicator(.visible)
    }

    private func stageList(_ chapter: ParkingChapter) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(chapter.stages) { stage in
                    let selected = game.run.stage.dailyKey == nil && stage.id == game.run.stage.id
                    Button {
                        game.select(stage)
                        hasStarted = true
                        showingStages = false
                    } label: {
                        VStack(spacing: 10) {
                            Text(String(format: "%02d", stage.id)).font(.title2.monospaced().bold())
                            StarMarks(awards: game.awards(for: stage))
                            Text(stage.title).font(.caption2).lineLimit(2).frame(minHeight: 28)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .foregroundStyle(selected ? .white : ink)
                        .background(selected ? blue : .white, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).accessibilityIdentifier("parking-stage-\(stage.id)")
                }
            }.padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(chapter.theme.title)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button("닫기") {
                if hasStarted { showingStages = false } else { dismiss() }
            }.accessibilityIdentifier("parking-chapters-close") } }
    }

    private var garage: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("모은 별 \(game.totalStars)개", systemImage: "star.fill").font(.title2.bold())
                    Text("일반 주차장에서 별을 모으면 차가 열려요. 별은 줄어들지 않고, 차마다 주차 판정은 같아요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(ParkingCarStyle.allCases) { car in
                            let unlocked = game.totalStars >= car.requiredStars
                            Button { game.select(car: car) } label: {
                                VStack(spacing: 12) {
                                    ParkingCar(style: car, unit: 6, foldedMirrors: false, celebrating: false, reduceMotion: true)
                                        .frame(height: 100).opacity(unlocked ? 1 : 0.35)
                                    Text(car.title).font(.subheadline.bold())
                                    Label(game.car == car ? "타고 있어요" : unlocked ? "타기" : "별 \(car.requiredStars)개에 열려요",
                                          systemImage: game.car == car ? "checkmark.circle.fill" : unlocked ? "car.side" : "lock.fill")
                                        .font(.caption)
                                }.frame(maxWidth: .infinity).padding(16)
                                    .foregroundStyle(ink)
                                    .background(game.car == car ? blue.opacity(0.12) : .white, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain).disabled(!unlocked)
                                .accessibilityIdentifier("parking-car-\(car.rawValue)")
                        }
                    }
                    Toggle(isOn: Binding(get: { game.soundEnabled }, set: { _ in game.toggleSound() })) {
                        Label("효과음", systemImage: game.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("parking-sound")
                    Text("효과음은 처음엔 꺼져 있어요. 켜도 iPhone의 무음 설정을 따라요.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color(.systemGroupedBackground))
                .navigationTitle("내 차 꾸미기").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showingGarage = false }.accessibilityIdentifier("parking-garage-close") } }
        }.presentationDragIndicator(.visible)
    }

    private func point(_ point: CGPoint, in size: CGSize) -> ParkingPoint {
        .init(x: Double(point.x / size.width) * 100, y: Double(point.y / size.height) * 120)
    }
}

private struct StarMarks: View {
    let awards: ParkingAwards
    var body: some View {
        HStack(spacing: 3) {
            ForEach([ParkingAwards.parked, .oneLine, .noCollision], id: \.rawValue) { flag in
                Image(systemName: awards.contains(flag) ? "star.fill" : "star")
            }
        }.font(.caption2).accessibilityLabel("별 \(awards.count)개")
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
