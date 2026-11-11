import SwiftUI

/// Three-step first-launch introduction highlighting live ETA, readiness/place coordination, and flexible entry.
struct OnboardingView: View {
    private enum Page: Int, CaseIterable, Identifiable {
        case liveEta = 0
        case readinessAndPlace = 1
        case flexibleEntry = 2

        var id: Int { rawValue }

        var badge: String {
            switch self {
            case .liveEta: return "실시간 위치 · ETA 공유"
            case .readinessAndPlace: return "장소 조율 · 빠른 소통"
            case .flexibleEntry: return "간편 연결 · 게스트 지원"
            }
        }

        var badgeTint: Color {
            switch self {
            case .liveEta: return MajungBrand.blue
            case .readinessAndPlace: return .green
            case .flexibleEntry: return .indigo
            }
        }

        var title: String {
            switch self {
            case .liveEta: return "차량 도착 시간을\n매번 묻지 않아도 돼요"
            case .readinessAndPlace: return "만날 장소를 맞추고\n탑승 준비를 바로 알려요"
            case .flexibleEntry: return "카카오로 한 번 연결하고\n초대 링크로는 바로 열어요"
            }
        }

        var subtitle: String {
            switch self {
            case .liveEta:
                return "차량이 출발하면 내비게이션 이동 경로와 남은 거리, 도착 예정 시각을 한 화면에서 실시간으로 확인해요."
            case .readinessAndPlace:
                return "지도로 원하는 출구를 제안하거나, ‘탈 준비 됐어요’와 짧은 한마디로 운전자와 어긋남 없이 만나요."
            case .flexibleEntry:
                return "카카오로 로그인하면 차량 QR 연결과 지인 마중 요청을 쓸 수 있고, 받은 초대 링크는 비로그인으로도 참여돼요."
            }
        }
    }

    var isReplay = false
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage: Page = .liveEta

    private var isLastPage: Bool { currentPage == .flexibleEntry }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $currentPage) {
                ForEach(Page.allCases) { page in
                    slide(for: page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                MajungBrandBadge(size: 28, cornerRadius: 8)
                Text("마중")
                    .font(.headline.weight(.bold))
            }

            Spacer()

            Button("건너뛰기") {
                onComplete()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .opacity(isLastPage ? 0 : 1)
            .disabled(isLastPage)
            .accessibilityHidden(isLastPage)
            .accessibilityIdentifier("onboarding-skip-button")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func slide(for page: Page) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                illustration(for: page)

                VStack(alignment: .leading, spacing: 12) {
                    MajungStatusPill(text: page.badge, tint: page.badgeTint)

                    Text(page.title)
                        .font(.title.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(page.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.center)
    }

    @ViewBuilder
    private func illustration(for page: Page) -> some View {
        switch page {
        case .liveEta:
            OnboardingEtaCard()
        case .readinessAndPlace:
            OnboardingCommsCard()
        case .flexibleEntry:
            OnboardingEntryCard()
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Page.allCases) { page in
                    let active = page == currentPage
                    Button {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                            currentPage = page
                        }
                    } label: {
                        Capsule()
                            .fill(active ? MajungBrand.blue : Color(.tertiaryLabel).opacity(0.45))
                            .frame(width: active ? 24 : 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(page.rawValue + 1)번째 안내")
                }
            }
            .accessibilityIdentifier("onboarding-page-indicator")

            if isLastPage {
                Button {
                    onComplete()
                } label: {
                    Text(isReplay ? "확인 완료" : "마중 시작하기")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .tint(MajungBrand.blue)
                .accessibilityIdentifier("onboarding-start-button")
            } else {
                Button {
                    guard let next = Page(rawValue: currentPage.rawValue + 1) else { return }
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                        currentPage = next
                    }
                } label: {
                    Text("다음")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .tint(MajungBrand.blue)
                .accessibilityIdentifier("onboarding-next-button")
            }

            Text("픽업이 종료되면 실시간 위치 공유는 자동으로 멈춰요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color(.systemGroupedBackground))
    }
}

private struct OnboardingEtaCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("실시간 갱신 중", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MajungBrand.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MajungBrand.blue.opacity(0.12), in: Capsule())

                Spacer()

                Text("1.2km 남음")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MajungBrand.blue.opacity(0.10), MajungBrand.skyDot.opacity(0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 112)

                RoutePreviewTrack()
                    .padding(.horizontal, 28)
            }

            HStack(spacing: 10) {
                Image(systemName: "car.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(MajungBrand.blue, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("약 4분 후 도착 예정")
                        .font(.headline)
                    Text("의왕역 1호선 1번 출구 앞")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct RoutePreviewTrack: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let start = CGPoint(x: 16, y: h * 0.68)
            let end = CGPoint(x: w - 16, y: h * 0.34)

            ZStack {
                Path { path in
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: w * 0.36, y: h * 0.72),
                        control2: CGPoint(x: w * 0.62, y: h * 0.28)
                    )
                }
                .stroke(
                    MajungBrand.blue,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [8, 6])
                )

                Image(systemName: "car.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(MajungBrand.blue, in: Circle())
                    .position(start)

                Image(systemName: "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(MajungBrand.blue)
                    .background(Circle().fill(.white).padding(2))
                    .position(end)
            }
        }
        .frame(height: 84)
    }
}

private struct OnboardingCommsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("탈 준비 됐어요 · 차량에 전달됨")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(MajungBrand.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("다른 장소 제안 가능")
                        .font(.subheadline.weight(.semibold))
                    Text("의왕역 2번 출구 앞으로 위치 조율")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(MajungBrand.blue)
                Text("“파란 우산 들고 서 있어요”")
                    .font(.footnote.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MajungBrand.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct OnboardingEntryCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "message.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(red: 0.098, green: 0.098, blue: 0.098))
                    .frame(width: 40, height: 40)
                    .background(Color(red: 1.0, green: 0.898, blue: 0.0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("카카오로 간편 시작")
                        .font(.subheadline.weight(.semibold))
                    Text("차량 QR 연결 · 지인에게 바로 마중 요청")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                    .frame(width: 40, height: 40)
                    .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("초대 링크로 게스트 참여")
                        .font(.subheadline.weight(.semibold))
                    Text("로그인 없이 받은 링크만으로 바로 확인")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }
}
