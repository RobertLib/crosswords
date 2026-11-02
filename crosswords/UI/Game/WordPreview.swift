import SwiftUI

/// Shows the word being spelled, then briefly how it was judged.
struct WordPreview: View {
    let word: String
    let feedback: WordFeedback?
    let accent: Color

    @State private var shown: WordFeedback?
    @State private var shakes: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !word.isEmpty {
                bubble(word, color: accent)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if let shown {
                bubble(shown.word, color: color(for: shown.kind))
                    .modifier(ShakeEffect(travel: shakes))
                    .transition(.asymmetric(insertion: .identity,
                                            removal: removal(for: shown.kind)))
                    .id(shown.id)
            }
        }
        .frame(height: 50)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: word.isEmpty)
        .onChange(of: feedback) { _, feedback in
            guard let feedback else { return }
            shown = feedback
            if feedback.kind == .invalid, !reduceMotion {
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(feedback.kind == .invalid ? 650 : 450))
                if shown?.id == feedback.id {
                    withAnimation(.easeIn(duration: 0.35)) { shown = nil }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func bubble(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.game(26, weight: .heavy))
            .tracking(3)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(color, in: .capsule)
            .shadow(color: color.opacity(0.4), radius: 8, y: 4)
    }

    private func color(for kind: WordFeedback.Kind) -> Color {
        switch kind {
        case .found: Palette.success
        case .bonus: Palette.bonus
        case .repeated: .gray
        case .invalid: .hex(0xD64545)
        }
    }

    private func removal(for kind: WordFeedback.Kind) -> AnyTransition {
        // The word flies to the grid or into the gift, or with Reduce Motion just fades.
        if reduceMotion { return .opacity }
        return switch kind {
        case .found: .offset(y: -90).combined(with: .opacity).combined(with: .scale(scale: 0.6))
        case .bonus: .offset(x: -140, y: 90).combined(with: .scale(scale: 0.2)).combined(with: .opacity)
        case .repeated, .invalid: .opacity
        }
    }

    private var accessibilityText: String {
        if !word.isEmpty { return word }
        return shown?.spokenText ?? ""
    }
}

struct ShakeEffect: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(travel * .pi * 6), y: 0))
    }
}
