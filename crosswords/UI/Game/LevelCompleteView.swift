import SwiftUI

/// Celebrates a solved puzzle and tallies the rewards.
struct LevelCompleteView: View {
    let summary: CompletionSummary
    let scene: SceneTheme
    let onNext: () -> Void
    let onHome: () -> Void

    @State private var appeared = false
    @State private var shownCoins = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At the accessibility text sizes a label and its figure stack instead of squeezing each other.
    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            if !reduceMotion {
                ConfettiView(colors: [scene.accent, Palette.gold, .white, scene.sky.first ?? .blue, Palette.success])
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            ScrollView {
                VStack(spacing: 18) {
                    header
                    if let chapter = summary.completedChapter {
                        chapterBanner(chapter)
                    }
                    if let streak = summary.streak {
                        streakBanner(streak)
                    }
                    if !summary.rewards.isEmpty {
                        rewards
                    }
                    stats
                    ForEach(summary.unlockedHints) { hint in
                        unlockCard(hint)
                    }
                    buttons
                }
                .padding(24)
                .frame(maxWidth: 440)
                .background(.regularMaterial, in: .rect(cornerRadius: 32))
                .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.45)))
                // A light card in either appearance: its ink and white panels assume one.
                .environment(\.colorScheme, .light)
                .shadow(color: .black.opacity(0.25), radius: 30, y: 14)
                .padding(20)
                // With Reduce Motion the card fades in without zooming.
                .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
        // VoiceOver stays on the card instead of wandering to the finished board behind it.
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.25)) { appeared = true }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                // Once the card has faded in, move VoiceOver's focus onto it.
                AccessibilityNotification.ScreenChanged().post()
                withAnimation(.easeOut(duration: 0.9)) { shownCoins = summary.totalCoins }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: summary.isPerfect ? "crown.fill" : "star.fill")
                .font(.system(size: 44))
                .foregroundStyle(LinearGradient(colors: [Palette.gold, Palette.goldDeep], startPoint: .top, endPoint: .bottom))
                .symbolEffect(.bounce, value: appeared)
            Text(summary.praise)
                .font(.game(.largeTitle, weight: .black))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            if summary.isPerfect {
                Text("Solved without hints")
                    .font(.game(.subheadline, weight: .bold))
                    .foregroundStyle(Palette.success)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func chapterBanner(_ chapter: Chapter) -> some View {
        HStack(spacing: 12) {
            SceneryView(scene: chapter.scene, animated: false)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("Chapter complete!")
                    .font(.game(.headline, weight: .heavy))
                Text("A new landscape awaits.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.55), in: .rect(cornerRadius: 18))
    }

    private func streakBanner(_ streak: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.title)
                .foregroundStyle(Palette.flame)
                .symbolEffect(.pulse)
            Text("\(streak)-day streak")
                .font(.game(.title3, weight: .heavy))
            Spacer()
        }
        .padding(12)
        .background(Palette.flame.opacity(0.12), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var rewards: some View {
        let row = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
        return VStack(alignment: stacks ? .leading : .center, spacing: 8) {
            ForEach(summary.rewards) { reward in
                row {
                    Text(reward.label)
                        .font(.game(.body, weight: .semibold))
                    if !stacks { Spacer() }
                    HStack {
                        Text("+\(reward.coins)")
                            .font(.game(.body, weight: .heavy))
                            .monospacedDigit()
                        CoinIcon(size: 18)
                    }
                }
            }
            Divider()
            row {
                Text("Total")
                    .font(.game(.title3, weight: .heavy))
                if !stacks { Spacer() }
                HStack {
                    Text("+\(shownCoins)")
                        .font(.game(.title2, weight: .black))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shownCoins)))
                    CoinIcon(size: 26)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Total \(summary.totalCoins) coins"))
        }
        .foregroundStyle(Palette.ink)
        .padding(14)
        .background(Color.white.opacity(0.55), in: .rect(cornerRadius: 18))
    }

    private var stats: some View {
        let row = stacks ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 0))
        return row {
            stat(value: "\(summary.wordCount)", label: "Words", symbol: "textformat.abc")
            stat(value: "\(summary.bonusCount)", label: "Bonus", symbol: "sparkles")
            stat(value: summary.elapsed.clockString, label: "Time", symbol: "clock")
        }
        .foregroundStyle(Palette.ink)
    }

    private func stat(value: String, label: LocalizedStringResource, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(scene.accent)
            Text(value)
                .font(.game(.title3, weight: .heavy))
                .monospacedDigit()
            Text(label)
                .font(.game(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func unlockCard(_ hint: HintKind) -> some View {
        HStack(spacing: 12) {
            Image(systemName: hint.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(scene.accent, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text("New hint: \(String(localized: hint.title))")
                    .font(.game(.headline, weight: .heavy))
                Text(hint.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(Economy.unlockGiftCharges) free uses to try it out")
                    .font(.game(.caption, weight: .bold))
                    .foregroundStyle(Palette.success)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(scene.accent.opacity(0.12), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if summary.hasNext {
                PrimaryButton(title: "Next level", symbol: "arrow.right", tint: scene.accent, action: onNext)
            }
            Button(action: onHome) {
                Text(summary.hasNext ? "Back to menu" : "Continue")
                    .font(.game(.headline, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(Palette.ink)
        }
        .padding(.top, 4)
    }
}

/// A one-shot burst of falling confetti.
struct ConfettiView: View {
    let colors: [Color]
    @State private var start = Date.now
    @State private var finished = false
    /// Kept in state: the parent re-creates this view whenever it updates, and fresh random
    /// pieces would make the confetti jump.
    @State private var pieces: [Piece]
    private static let duration = 4.5

    struct Piece {
        let x: Double, delay: Double, speed: Double, drift: Double, spin: Double, size: Double, color: Int, shape: Int
    }

    init(colors: [Color], count: Int = 90) {
        self.colors = colors
        var rng = SeededRandom(seed: UInt64.random(in: 0...UInt64.max))
        _pieces = State(initialValue: (0..<count).map { _ in
            Piece(x: rng.unit(), delay: rng.range(0, 0.6), speed: rng.range(0.55, 1.1), drift: rng.range(-0.25, 0.25),
                  spin: rng.range(2, 8), size: rng.range(6, 12), color: Int(rng.range(0, 100)), shape: Int(rng.range(0, 3)))
        })
    }

    var body: some View {
        TimelineView(.animation(paused: finished)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0, t < Self.duration else { continue }
                    let y = -20 + t * piece.speed * size.height * 0.45 + 40 * t * t
                    guard y < size.height + 20 else { continue }
                    let x = piece.x * size.width + sin(t * 2 + piece.spin) * 30 + piece.drift * t * size.width * 0.2
                    var context = canvas
                    context.translateBy(x: x, y: y)
                    context.rotate(by: .radians(t * piece.spin))
                    context.scaleBy(x: cos(t * piece.spin * 0.8), y: 1)
                    context.opacity = min(1, max(0, Self.duration - t))
                    let color = colors[piece.color % colors.count]
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    switch piece.shape {
                    case 0: context.fill(Path(rect), with: .color(color))
                    case 1: context.fill(Path(ellipseIn: rect.insetBy(dx: piece.size * 0.15, dy: -piece.size * 0.1)), with: .color(color))
                    default: context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                    }
                }
            }
        }
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(Self.duration + 0.7))
            finished = true
        }
    }
}
