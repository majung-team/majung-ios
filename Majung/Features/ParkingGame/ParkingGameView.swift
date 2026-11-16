import SwiftUI
import Observation
import UIKit

@MainActor
@Observable
final class ParkingGame {
    private(set) var run = ParkingRun(stage: ParkingStage.all[0])
    private(set) var completed: Set<Int>
    private let store: ParkingProgressStore
    private var driveTask: Task<Void, Never>?

    init(store: ParkingProgressStore = ParkingProgressStore()) {
        self.store = store
        completed = store.load()
    }

    func select(_ stage: ParkingStage) {
        pause()
        run = ParkingRun(stage: stage)
    }

    func draw(start: ParkingPoint, point: ParkingPoint) {
        if run.phase != .drawing { run.begin(at: start) }
        run.extend(to: point)
    }

    func drive() {
        guard driveTask == nil else { return }
        run.drive()
        guard run.phase == .driving else { return }
        driveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                guard !Task.isCancelled, let self else { break }
                self.run.step()
                if self.run.phase != .driving {
                    if self.run.phase == .parked {
                        self.store.complete(stageId: self.run.stage.id)
                        self.completed = self.store.load()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else if self.run.phase == .collision {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                    self.driveTask = nil
                    return
                }
            }
        }
    }

    func pause() {
        driveTask?.cancel()
        driveTask = nil
        run.pause()
    }
}

struct ParkingGameEntry: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            dismissMajungKeyboard()
            isPresented = true
        } label: {
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
        .buttonStyle(.plain)
        .accessibilityIdentifier("parking-game-open")
        .sheet(isPresented: $isPresented) {
            NavigationStack { ParkingGameView() }
                .preferredColorScheme(.light)
                .presentationDragIndicator(.visible)
        }
    }
}

struct ParkingGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var game = ParkingGame()
    @State private var showingStages = false

    private let ink = Color(red: 0.12, green: 0.20, blue: 0.29)
    private let blue = Color(red: 0.23, green: 0.43, blue: 0.91)

    private var message: String {
        switch game.run.phase {
        case .drawing: "좋아요. 손을 떼면 출발해요."
        case .driving: "주차 중…"
        case .collision: "앗, 닿았어요. 파란 차에서 다시 그려보세요."
        case .parked: "빈자리에 쏙! 잘 주차했어요."
        case .ready: game.run.strokes == 0 ? game.run.stage.hint : "차에서 선을 이어서 그릴 수 있어요."
        }
    }

    var body: some View {
        GeometryReader { layout in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    GeometryReader { board in
                        ParkingBoard(run: game.run, reduceMotion: reduceMotion)
                            .contentShape(Rectangle())
                            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in
                                    game.draw(start: point(value.startLocation, in: board.size),
                                              point: point(value.location, in: board.size))
                                }
                                .onEnded { _ in game.drive() })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("주차장. 파란 차에서 주차 칸까지 이동 경로를 그리세요.")
                            .accessibilityIdentifier("parking-board")
                    }
                    .aspectRatio(5.0 / 6, contentMode: .fit)
                    .frame(maxWidth: min(480, max(230, layout.size.height * 0.53)))
                    .frame(maxWidth: .infinity)
                    feedback
                    controls
                    Text("가상의 주차 퍼즐이에요. 실제 운전 방법과는 달라요.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(red: 0.96, green: 0.96, blue: 0.93))
        }
        .foregroundStyle(ink)
        .navigationTitle("잠깐 주차")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("닫기") { game.pause(); dismiss() }
                    .accessibilityIdentifier("parking-game-close")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { game.pause(); showingStages = true } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .accessibilityLabel("스테이지 선택")
                .accessibilityIdentifier("parking-stage-picker")
            }
        }
        .sheet(isPresented: $showingStages) { stages }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
        }
        .onDisappear { game.pause() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(String(format: "STAGE %02d", game.run.stage.id))
                    .font(.caption.monospaced().weight(.bold))
                    .tracking(2).foregroundStyle(blue)
                Spacer()
                Label("\(game.completed.count) / 8", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityLabel("8개 중 \(game.completed.count)개 완료")
            }
            Text(game.run.stage.title).font(.system(.title, design: .rounded, weight: .bold))
            Text("차에서 선을 그리고, 손을 떼면 출발!")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var feedback: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: game.run.phase == .parked ? "checkmark.circle.fill" :
                    game.run.phase == .collision ? "arrow.counterclockwise.circle.fill" : "hand.draw.fill")
                .foregroundStyle(game.run.phase == .parked ? .green : blue)
            Text(message).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("parking-game-message")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { game.select(game.run.stage) } label: {
                Label("다시 하기", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered).tint(blue)
            .accessibilityIdentifier("parking-restart")
            if game.run.phase == .parked {
                Button {
                    if game.run.stage.id < ParkingStage.all.count {
                        game.select(ParkingStage.all[game.run.stage.id])
                    } else {
                        showingStages = true
                    }
                } label: {
                    Text(game.run.stage.id < 8 ? "다음 주차장" : "주차장 고르기")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent).tint(blue)
                .accessibilityIdentifier("parking-next-stage")
            } else if game.run.phase == .driving {
                Button("멈추기") { game.pause() }
                    .buttonStyle(.bordered).tint(blue)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("parking-pause")
            }
        }
    }

    private var stages: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(ParkingStage.all) { stage in
                        Button {
                            game.select(stage)
                            showingStages = false
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(String(format: "%02d", stage.id))
                                        .font(.title2.monospaced().bold())
                                    Spacer()
                                    Image(systemName: game.completed.contains(stage.id) ? "checkmark.circle.fill" : "parkingsign.circle")
                                }
                                Text(stage.title).font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .foregroundStyle(stage.id == game.run.stage.id ? .white : ink)
                            .background(stage.id == game.run.stage.id ? blue : Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("parking-stage-\(stage.id)")
                    }
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("주차장 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showingStages = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func point(_ point: CGPoint, in size: CGSize) -> ParkingPoint {
        .init(x: Double(point.x / size.width) * 100, y: Double(point.y / size.height) * 120)
    }
}

private struct ParkingBoard: View {
    let run: ParkingRun
    let reduceMotion: Bool
    private let road = Color(red: 0.19, green: 0.25, blue: 0.31)
    private let blue = Color(red: 0.29, green: 0.54, blue: 1)

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 100
            ZStack {
                RoundedRectangle(cornerRadius: 25).fill(Color(red: 0.80, green: 0.84, blue: 0.80))
                RoundedRectangle(cornerRadius: 20).fill(road).padding(unit * 3)
                // Quiet lane markings, not a moving background.
                Path { path in
                    path.move(to: CGPoint(x: 8 * unit, y: 110 * unit))
                    path.addLine(to: CGPoint(x: 92 * unit, y: 110 * unit))
                }.stroke(.white.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
                ForEach(run.stage.obstacles) { obstacle in
                    obstacleView(obstacle, unit: unit)
                }
                let bay = run.stage.bay
                RoundedRectangle(cornerRadius: unit * 1.6)
                    .fill(Color(red: 0.56, green: 0.87, blue: 0.69).opacity(0.17))
                    .overlay(RoundedRectangle(cornerRadius: unit * 1.6)
                        .stroke(Color(red: 0.65, green: 0.95, blue: 0.77), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    .overlay {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.up").font(.system(size: unit * 3, weight: .bold))
                            Text("P").font(.system(size: unit * 5, weight: .bold, design: .rounded))
                        }.foregroundStyle(Color(red: 0.70, green: 0.98, blue: 0.80))
                    }
                    .frame(width: bay.width * unit, height: bay.height * unit)
                    .position(x: run.stage.destination.x * unit, y: run.stage.destination.y * unit)
                if run.route.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: run.route[0].x * unit, y: run.route[0].y * unit))
                        for point in run.route.dropFirst() {
                            path.addLine(to: CGPoint(x: point.x * unit, y: point.y * unit))
                        }
                    }
                    .stroke(run.phase == .collision ? Color.orange.opacity(0.7) : blue.opacity(0.65),
                            style: StrokeStyle(lineWidth: unit * 1.0, lineCap: .round, lineJoin: .round, dash: [3, 4]))
                }
                ParkingCar(color: blue, unit: unit)
                    .rotationEffect(.radians(run.pose.heading + .pi / 2))
                    .position(x: run.pose.center.x * unit, y: run.pose.center.y * unit)
                if run.phase == .ready && run.strokes == 0 {
                    Image(systemName: "hand.draw")
                        .font(.system(size: unit * 6)).foregroundStyle(.white.opacity(0.65))
                        .position(x: (run.pose.center.x + 14) * unit, y: run.pose.center.y * unit)
                        .allowsHitTesting(false)
                }
                if run.phase == .parked {
                    Label("주차 완료", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.green, in: Capsule())
                        .position(x: 50 * unit, y: 104 * unit)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: run.phase)
            .clipped()
        }
    }

    private func obstacleView(_ obstacle: ParkingObstacle, unit: Double) -> some View {
        let rect = obstacle.rect
        return Group {
            if obstacle.kind == .car {
                RoundedRectangle(cornerRadius: unit * 2)
                    .fill(Color(red: 0.75, green: 0.52, blue: 0.36))
                    .overlay {
                        RoundedRectangle(cornerRadius: unit)
                            .fill(.black.opacity(0.30))
                            .padding(.horizontal, unit * 2).padding(.vertical, unit * 5)
                    }
            } else {
                RoundedRectangle(cornerRadius: unit * 2)
                    .fill(Color(red: 0.44, green: 0.59, blue: 0.46))
                    .overlay(RoundedRectangle(cornerRadius: unit * 2).stroke(.white.opacity(0.20), lineWidth: 2))
            }
        }
        .frame(width: rect.width * unit, height: rect.height * unit)
        .position(x: (rect.x + rect.width / 2) * unit, y: (rect.y + rect.height / 2) * unit)
    }
}

private struct ParkingCar: View {
    let color: Color
    let unit: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: unit * 2).fill(color)
                .shadow(color: .black.opacity(0.25), radius: unit, y: unit)
            RoundedRectangle(cornerRadius: unit).fill(.white.opacity(0.75))
                .frame(width: unit * 5.8, height: unit * 3)
                .offset(y: -unit * 2.8)
            RoundedRectangle(cornerRadius: unit).fill(.black.opacity(0.22))
                .frame(width: unit * 5.8, height: unit * 2.4)
                .offset(y: unit * 3.9)
            HStack {
                Capsule().fill(.yellow.opacity(0.95)).frame(width: unit * 1.6, height: unit)
                Spacer(minLength: 0)
                Capsule().fill(.yellow.opacity(0.95)).frame(width: unit * 1.6, height: unit)
            }.padding(.horizontal, unit).offset(y: -unit * 6)
        }
        .frame(width: unit * 8, height: unit * 14)
        .accessibilityHidden(true)
    }
}
