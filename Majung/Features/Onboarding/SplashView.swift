import SwiftUI

/// Animated launch splash matching `UILaunchScreen` while initial session restoration runs.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var strokeTrim: CGFloat = 0
    @State private var dotScale: CGFloat = 0.72
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [MajungBrand.blue, MajungBrand.blue, MajungBrand.deepBlue],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            MajungBrand.skyDot.opacity(0.22),
                            MajungBrand.skyDot.opacity(0.06),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 210
                    )
                )
                .frame(width: 460, height: 460)
                .offset(y: -48)
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                MajungSymbolGlyph(size: 96, strokeTrim: strokeTrim, dotScale: dotScale)

                VStack(spacing: 6) {
                    Text("마중")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("기다림 없는 만남의 시작")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.86))
                }
                .opacity(textOpacity)
            }
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("마중 시작 화면")
        .accessibilityIdentifier("splash-screen")
        .task {
            if reduceMotion {
                strokeTrim = 1
                dotScale = 1
                textOpacity = 1
                return
            }

            withAnimation(.easeOut(duration: 0.44)) {
                strokeTrim = 1
            }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.76).delay(0.12)) {
                dotScale = 1
            }
            withAnimation(.easeOut(duration: 0.34).delay(0.18)) {
                textOpacity = 1
            }
        }
    }
}
