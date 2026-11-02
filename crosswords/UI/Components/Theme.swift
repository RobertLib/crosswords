import SwiftUI
import UIKit

extension Font {
    /// The game's rounded type, at a fixed size (used inside scaled game geometry).
    static func game(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The game's rounded type, following Dynamic Type.
    static func game(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

enum Palette {
    static let ink = Color.hex(0x23243A)
    static let cream = Color.hex(0xFFFCF4)
    static let gold = Color.hex(0xF6C343)
    static let goldDeep = Color.hex(0xD9961A)
    /// The streak's flame, for symbols and outlines.
    static let flame = Color.hex(0xFF7A2F)
    /// The flame as a fill behind white text, deep enough for small text (4.5:1).
    static let flameFill = Color.readable(0xFF7A2F, minimumContrast: 4.5)
    /// Green for success, also used as text and behind small white text (4.5:1).
    static let success = Color.readable(0x2FB67C, minimumContrast: 4.5)
    /// The bonus word's bubble, behind large white text.
    static let bonus = Color.readable(0xD9961A, minimumContrast: 3.6)
}

extension Color {
    /// The colour, or the darker shade of the same hue at which white text on it reaches
    /// `minimumContrast` (WCAG: 4.5:1 for small text, 3:1 for large). 3.6:1 leaves room for the
    /// lighter top of a button's gradient.
    static func readable(_ value: UInt32, minimumContrast: Double = 3.6) -> Color {
        let target = 1.05 / minimumContrast - 0.05
        let linear = [16, 8, 0].map { Color.linear(Double((value >> UInt32($0)) & 0xFF) / 255) }
        let luminance = Color.luminance(linear)
        guard luminance > target else { return .hex(value) }
        // Scaling linear light keeps the hue and lowers the luminance in proportion.
        let srgb = linear.map { Color.gamma($0 * target / luminance) }
        return Color(.sRGB, red: srgb[0], green: srgb[1], blue: srgb[2])
    }

    /// The background the dark-mode menus put accents on: grouped cells and the dark material
    /// over the landscapes are this dark or darker.
    static let darkSurface: UInt32 = 0x2C2C2E

    /// The colour as an accent drawn on a dark surface (text, symbols, a bordered button's label):
    /// its linear light scaled up until it reaches `minimumContrast` against `darkSurface`. A
    /// colour deep enough for white text on it is often too dark for that.
    func readableOnDark(minimumContrast: Double = 4.5) -> Color {
        let resolved = resolve(in: EnvironmentValues())
        let linear = [Double(resolved.linearRed), Double(resolved.linearGreen), Double(resolved.linearBlue)]
        let surface = [16, 8, 0].map { Color.linear(Double((Self.darkSurface >> UInt32($0)) & 0xFF) / 255) }
        let target = minimumContrast * (Color.luminance(surface) + 0.05) - 0.05
        let scaled = { (k: Double) in linear.map { min(1, $0 * k) } }
        guard Color.luminance(linear) < target else { return self }
        // Brightening clips the strongest channel first, so the factor is searched for.
        var low = 1.0, high = 1_000.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if Color.luminance(scaled(mid)) < target { low = mid } else { high = mid }
        }
        let srgb = scaled(high).map(Color.gamma)
        return Color(.sRGB, red: srgb[0], green: srgb[1], blue: srgb[2])
    }

    /// `light` in the light appearance and `dark` in the dark one. Nonisolated: SwiftUI resolves
    /// colours off the main thread too (a `TimelineView` updating, say), and a provider isolated to
    /// the main actor, as this app's code is by default, would stop the app there.
    nonisolated static func adaptive(light: Color, dark: Color) -> Color {
        let light = UIColor(light), dark = UIColor(dark)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Contrast of white text on this colour (1…21).
    var contrastWithWhite: Double {
        contrast(with: .white)
    }

    /// Contrast between this colour and `other` (1…21), both resolved in `environment`.
    func contrast(with other: Color, in environment: EnvironmentValues = EnvironmentValues()) -> Double {
        let luminances = [self, other].map { color in
            let resolved = color.resolve(in: environment)
            return Color.luminance([Double(resolved.linearRed), Double(resolved.linearGreen),
                                    Double(resolved.linearBlue)])
        }
        return (luminances.max()! + 0.05) / (luminances.min()! + 0.05)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func gamma(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    private static func luminance(_ linear: [Double]) -> Double {
        0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}

extension View {
    /// White text drawn straight on a landscape: a tight dark rim and a soft shadow keep it
    /// legible on the palest skies.
    func legibleOnScenery() -> some View {
        shadow(color: .black.opacity(0.55), radius: 1.2)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1.5)
    }
}

/// A small gold coin, drawn rather than shipped as an image.
struct CoinIcon: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.hex(0xFFE27A), Palette.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(Color.hex(0xFFF3B8).opacity(0.9), lineWidth: size * 0.08)
                .padding(size * 0.12)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(Color.hex(0xB9770E).opacity(0.85))
        }
        .frame(width: size, height: size)
        .shadow(color: Palette.goldDeep.opacity(0.4), radius: size * 0.1, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

/// The player's coin balance.
struct CoinBadge: View {
    let amount: Int

    var body: some View {
        HStack(spacing: 6) {
            CoinIcon(size: 22)
            Text(amount, format: .number)
                .font(.game(17, weight: .heavy))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(amount)))
                .foregroundStyle(Palette.ink)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Palette.cream.opacity(0.92), in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .animation(.snappy, value: amount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(amount) coins"))
    }
}

/// Gives buttons a soft, springy press.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A round, frosted icon button used on top of scenery.
struct RoundIconButton: View {
    let symbol: String
    let label: LocalizedStringResource
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: size, height: size)
                .background(Palette.cream.opacity(0.9), in: .circle)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(label))
    }
}

/// The large primary call-to-action.
struct PrimaryButton: View {
    let title: LocalizedStringResource
    var symbol: String?
    var tint: Color = Palette.flameFill
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.game(.title3, weight: .heavy))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: [tint.mix(with: .white, by: 0.15), tint], startPoint: .top, endPoint: .bottom),
                in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: tint.opacity(0.45), radius: 10, y: 6)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }
}

/// A frosted rounded panel for menus layered over scenery.
struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
    }
}

extension TimeInterval {
    /// "1:05" style duration.
    var clockString: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
