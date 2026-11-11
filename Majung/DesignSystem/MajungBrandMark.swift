import SwiftUI

/// Brand color tokens matching the unified Majung vehicle/web/iOS symbol (`#2669DD` + `#B9E7FF`).
enum MajungBrand {
    static let blue = Color(red: 38.0 / 255.0, green: 105.0 / 255.0, blue: 221.0 / 255.0)
    static let deepBlue = Color(red: 20.0 / 255.0, green: 68.0 / 255.0, blue: 162.0 / 255.0)
    static let skyDot = Color(red: 185.0 / 255.0, green: 231.0 / 255.0, blue: 255.0 / 255.0)
}

/// Vector mark depicting two paths meeting at one arrival point (`128x128` coordinate geometry).
struct MajungSymbolGlyph: View {
    var size: CGFloat = 96
    var strokeTrim: CGFloat = 1
    var dotScale: CGFloat = 1

    private var scale: CGFloat { size / 128.0 }

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 32 * scale, y: 53 * scale))
                path.addCurve(
                    to: CGPoint(x: 64 * scale, y: 92 * scale),
                    control1: CGPoint(x: 32 * scale, y: 77 * scale),
                    control2: CGPoint(x: 64 * scale, y: 67 * scale)
                )
            }
            .trim(from: 0, to: strokeTrim)
            .stroke(.white, style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round))

            Path { path in
                path.move(to: CGPoint(x: 96 * scale, y: 53 * scale))
                path.addCurve(
                    to: CGPoint(x: 64 * scale, y: 92 * scale),
                    control1: CGPoint(x: 96 * scale, y: 77 * scale),
                    control2: CGPoint(x: 64 * scale, y: 67 * scale)
                )
            }
            .trim(from: 0, to: strokeTrim)
            .stroke(.white, style: StrokeStyle(lineWidth: 9 * scale, lineCap: .round))

            Circle()
                .fill(.white)
                .frame(width: 20 * scale, height: 20 * scale)
                .scaleEffect(dotScale)
                .position(x: 32 * scale, y: 34 * scale)

            Circle()
                .fill(.white)
                .frame(width: 20 * scale, height: 20 * scale)
                .scaleEffect(dotScale)
                .position(x: 96 * scale, y: 34 * scale)

            Circle()
                .fill(MajungBrand.skyDot)
                .frame(width: 22 * scale, height: 22 * scale)
                .scaleEffect(dotScale)
                .position(x: 64 * scale, y: 94 * scale)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Rounded square Majung brand badge matching the launcher and home screen icon.
struct MajungBrandBadge: View {
    var size: CGFloat = 48
    var cornerRadius: CGFloat? = nil

    private var resolvedRadius: CGFloat {
        cornerRadius ?? size * (14.0 / 48.0)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: resolvedRadius, style: .continuous)
                .fill(MajungBrand.blue)
            MajungSymbolGlyph(size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
