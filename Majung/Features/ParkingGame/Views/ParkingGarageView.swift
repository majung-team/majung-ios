import SwiftUI

struct ParkingGarageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var game: ParkingGame
    @State private var preview: ParkingCarStyle

    private let ink = Color(red: 0.12, green: 0.20, blue: 0.29)
    private let blue = Color(red: 0.23, green: 0.43, blue: 0.91)

    init(game: ParkingGame) {
        self.game = game
        _preview = State(initialValue: game.car)
    }

    private var isUnlocked: Bool { game.totalStars >= preview.requiredStars }
    private var isCurrent: Bool { game.car == preview }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                previewCard
                HStack {
                    Text("차 둘러보기").font(.subheadline.bold())
                    Spacer()
                    Text("\(ParkingCarStyle.allCases.count)종").font(.caption).foregroundStyle(.secondary)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(ParkingCarStyle.allCases) { car in
                                carCard(car).id(car.id)
                            }
                        }.padding(2)
                    }
                    .accessibilityIdentifier("parking-car-list")
                    .onAppear { proxy.scrollTo(game.car.id, anchor: .center) }
                    .onChange(of: game.car) { _, car in
                        proxy.scrollTo(car.id, anchor: .center)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(get: { game.soundEnabled }, set: { game.setSoundEnabled($0) })) {
                        Label("효과음", systemImage: game.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }.font(.subheadline).accessibilityIdentifier("parking-sound")
                    Text("효과음은 iPhone의 무음 설정을 따라요.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(16)
            .foregroundStyle(ink)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("내 차 꾸미기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.accessibilityIdentifier("parking-garage-close")
                }
            }
        }.presentationDragIndicator(.visible)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("지금 타는 차 · \(game.car.title)").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("parking-current-car")
                Spacer(minLength: 8)
                Label("\(game.totalStars)", systemImage: "star.fill").font(.caption.bold())
            }
            HStack(spacing: 24) {
                ParkingCar(style: preview, unit: 8, foldedMirrors: false, celebrating: false, reduceMotion: reduceMotion)
                    .frame(width: 84, height: 122)
                VStack(alignment: .leading, spacing: 8) {
                    Text(preview.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("parking-car-preview-title")
                    Text(preview.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(isCurrent ? "타고 있어요" : isUnlocked ? "탈 수 있어요" : "별 \(preview.requiredStars)개에 열려요",
                          systemImage: isCurrent ? "checkmark.circle.fill" : isUnlocked ? "lock.open" : "lock.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(isUnlocked ? blue : .secondary)
                }
                Spacer(minLength: 0)
            }
            Button { game.select(car: preview) } label: {
                Text(isCurrent ? "타고 있어요" : isUnlocked ? "이 차 타기" : "별 \(preview.requiredStars - game.totalStars)개 더 모으면 탈 수 있어요")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent).tint(blue)
            .disabled(!isUnlocked || isCurrent)
            .accessibilityIdentifier("parking-car-apply")
            Text("별은 줄어들지 않고, 모든 차의 주차 판정은 같아요.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private func carCard(_ car: ParkingCarStyle) -> some View {
        let unlocked = game.totalStars >= car.requiredStars
        let selected = preview == car
        return Button { preview = car } label: {
            VStack(spacing: 7) {
                ParkingCar(style: car, unit: 3.5, foldedMirrors: false, celebrating: false, reduceMotion: true)
                    .frame(height: 54).opacity(unlocked ? 1 : 0.5)
                Text(car.title).font(.caption2.weight(.semibold)).lineLimit(2)
                Label(game.car == car ? "타고 있어요" : unlocked ? "미리보기" : "별 \(car.requiredStars)개",
                      systemImage: game.car == car ? "checkmark.circle.fill" : unlocked ? "eye" : "lock.fill")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100).padding(8)
            .background(selected ? blue.opacity(0.08) : .white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? blue : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("parking-car-\(car.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("큰 미리보기에서 확인한 뒤 이 차 타기로 선택")
    }
}
