import SwiftUI

struct ParkingBoard: View {
    let run: ParkingRun
    let car: ParkingCarStyle
    let reduceMotion: Bool
    private let blue = Color(red: 0.29, green: 0.54, blue: 1)

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / 100
            ZStack {
                RoundedRectangle(cornerRadius: 25).fill(Color(red: 0.80, green: 0.84, blue: 0.80))
                RoundedRectangle(cornerRadius: 20).fill(run.stage.theme.road).padding(unit * 3)
                ParkingScenery(theme: run.stage.theme, unit: unit)
                    .allowsHitTesting(false)
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
                ParkingCar(style: car, unit: unit, foldedMirrors: run.isNearObstacle,
                           celebrating: run.phase == .parked, reduceMotion: reduceMotion)
                    .scaleEffect(run.phase == .collision ? 0.94 : 1)
                    .rotationEffect(.radians(run.pose.heading + .pi / 2))
                    .position(x: run.pose.center.x * unit, y: run.pose.center.y * unit)
                if run.phase == .ready && run.strokes == 0 {
                    Image(systemName: "hand.draw")
                        .font(.system(size: unit * 6)).foregroundStyle(.white.opacity(0.65))
                        .position(x: (run.pose.center.x + 14) * unit, y: run.pose.center.y * unit)
                        .allowsHitTesting(false)
                }
                if run.phase == .collision {
                    Image(systemName: "sparkle").font(.title).foregroundStyle(.orange)
                        .position(x: run.pose.center.x * unit, y: (run.pose.center.y - 12) * unit)
                        .accessibilityHidden(true)
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
                    .fill(run.stage.theme.island)
                    .overlay(RoundedRectangle(cornerRadius: unit * 2).stroke(.white.opacity(0.20), lineWidth: 2))
            }
        }
        .frame(width: rect.width * unit, height: rect.height * unit)
        .position(x: (rect.x + rect.width / 2) * unit, y: (rect.y + rect.height / 2) * unit)
    }
}

struct ParkingCar: View {
    let style: ParkingCarStyle
    let unit: Double
    let foldedMirrors: Bool
    let celebrating: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            HStack {
                Capsule().frame(width: unit * 1.5, height: unit * 1.4)
                Spacer(minLength: 0)
                Capsule().frame(width: unit * 1.5, height: unit * 1.4)
            }.foregroundStyle(style.color).frame(width: unit * (foldedMirrors ? 7 : 9))
                .offset(y: -unit * 1.5)
            RoundedRectangle(cornerRadius: unit * (style == .mintVan ? 1 : 2.4)).fill(style.color)
                .shadow(color: .black.opacity(0.25), radius: unit, y: unit)
            RoundedRectangle(cornerRadius: unit).fill(.white.opacity(0.75))
                .frame(width: unit * 5.8, height: unit * 3).offset(y: -unit * 2.8)
            RoundedRectangle(cornerRadius: unit).fill(.black.opacity(0.22))
                .frame(width: unit * 5.8, height: unit * (style == .mintVan ? 4.8 : 2.4))
                .offset(y: unit * (style == .mintVan ? 2.6 : 3.9))
            if style == .taxi {
                Text("TAXI").font(.system(size: unit * 1.6, weight: .black, design: .rounded))
                    .foregroundStyle(.black).padding(unit * 0.25).background(.white, in: RoundedRectangle(cornerRadius: unit * 0.3))
            }
            HStack {
                Capsule().frame(width: unit * 1.6, height: unit)
                Spacer(minLength: 0)
                Capsule().frame(width: unit * 1.6, height: unit)
            }.foregroundStyle(.yellow).padding(.horizontal, unit).offset(y: -unit * 6)
                .phaseAnimator([false, true, false, true, false], trigger: celebrating) { lights, flash in
                    lights.opacity(celebrating && flash ? 0.15 : 1)
                } animation: { _ in reduceMotion ? nil : .easeInOut(duration: 0.14) }
        }
        .frame(width: unit * 8, height: unit * 14)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: foldedMirrors)
        .accessibilityHidden(true)
    }
}

private extension ParkingCarStyle {
    var color: Color {
        switch self {
        case .blue: Color(red: 0.29, green: 0.54, blue: 1)
        case .taxi: Color(red: 1, green: 0.77, blue: 0.19)
        case .mintVan: Color(red: 0.31, green: 0.79, blue: 0.66)
        case .coral: Color(red: 0.98, green: 0.43, blue: 0.39)
        }
    }
}

extension ParkingTheme {
    var accent: Color {
        switch self {
        case .blossoms: .pink
        case .rainy: .teal
        case .sunset: .orange
        case .night: .indigo
        }
    }
    var road: Color {
        switch self {
        case .blossoms: Color(red: 0.24, green: 0.30, blue: 0.30)
        case .rainy: Color(red: 0.18, green: 0.27, blue: 0.35)
        case .sunset: Color(red: 0.37, green: 0.28, blue: 0.29)
        case .night: Color(red: 0.12, green: 0.16, blue: 0.26)
        }
    }
    var island: Color {
        switch self {
        case .blossoms: Color(red: 0.48, green: 0.63, blue: 0.49)
        case .rainy: Color(red: 0.39, green: 0.57, blue: 0.59)
        case .sunset: Color(red: 0.66, green: 0.47, blue: 0.39)
        case .night: Color(red: 0.36, green: 0.41, blue: 0.56)
        }
    }
}

private struct ParkingScenery: View {
    let theme: ParkingTheme
    let unit: Double
    var body: some View {
        ZStack {
            switch theme {
            case .blossoms:
                ForEach(0..<7) { i in
                    Image(systemName: "leaf.fill").font(.system(size: unit * 2.8))
                        .foregroundStyle(.pink.opacity(0.55)).rotationEffect(.degrees(Double(i * 37)))
                        .position(x: Double(i % 2 == 0 ? 6 : 94) * unit, y: Double(15 + i * 14) * unit)
                }
            case .rainy:
                ForEach(0..<10) { i in
                    Capsule().fill(.cyan.opacity(0.18)).frame(width: unit * 0.35, height: unit * 3)
                        .rotationEffect(.degrees(25))
                        .position(x: Double(8 + (i * 29) % 84) * unit, y: Double(12 + (i * 19) % 94) * unit)
                }
                Text("OPEN").font(.system(size: unit * 2, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.65)).position(x: 50 * unit, y: 7 * unit)
            case .sunset:
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: unit * 0.4).fill(.orange.opacity(0.25))
                        .frame(width: unit * 2, height: unit * 8)
                        .position(x: 6 * unit, y: Double(20 + i * 20) * unit)
                }
                Image(systemName: "sun.haze.fill").font(.system(size: unit * 3))
                    .foregroundStyle(.orange.opacity(0.6)).position(x: 88 * unit, y: 8 * unit)
            case .night:
                ForEach(0..<8) { i in
                    RoundedRectangle(cornerRadius: unit * 0.25).fill(.yellow.opacity(i % 3 == 0 ? 0.15 : 0.55))
                        .frame(width: unit * 2, height: unit * 2)
                        .position(x: Double(15 + i * 10) * unit, y: 6 * unit)
                }
                Image(systemName: "moon.fill").font(.system(size: unit * 3))
                    .foregroundStyle(.yellow.opacity(0.65)).position(x: 93 * unit, y: 12 * unit)
            }
        }.accessibilityHidden(true)
    }
}
