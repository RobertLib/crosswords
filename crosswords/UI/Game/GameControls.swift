import SwiftUI

/// A hint button showing its price, free uses or the level at which it unlocks.
struct HintButton: View {
    let hint: HintKind
    let controller: GameController
    let accent: Color

    var body: some View {
        let unlocked = controller.isUnlocked(hint)
        let free = controller.freeCharges(hint)
        let active = hint == .spotlight && controller.isSpotlightActive
        Button {
            if unlocked {
                controller.use(hint)
            } else {
                controller.app.haptics.tap()
                controller.showToast(Toast(text: String(localized: "Unlocks after level \(hint.unlockAfterLevels)"),
                                           symbol: "lock.fill"))
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(active ? accent : Palette.cream.opacity(0.94))
                        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                    Image(systemName: unlocked ? hint.symbol : "lock.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(active ? .white : unlocked ? accent : .gray)
                        .symbolEffect(.bounce, value: active)
                }
                .frame(width: 52, height: 52)
                .overlay(alignment: .topTrailing) {
                    if unlocked && free > 0 {
                        Text("\(free)")
                            .font(.game(12, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Palette.success, in: .capsule)
                            .offset(x: 4, y: -4)
                    }
                }
                price(unlocked: unlocked, free: free)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(hint.title))
        .accessibilityHint(Text(hint.explanation))
        .accessibilityValue(Text(accessibilityValue(unlocked: unlocked, free: free)))
    }

    @ViewBuilder
    private func price(unlocked: Bool, free: Int) -> some View {
        Group {
            if !unlocked {
                Text("Lv \(hint.unlockAfterLevels + 1)")
            } else if free > 0 {
                Text("Free")
            } else {
                HStack(spacing: 3) {
                    CoinIcon(size: 13)
                    Text("\(controller.price(of: hint))")
                }
            }
        }
        .font(.game(13, weight: .heavy))
        .foregroundStyle(.white)
        .legibleOnScenery()
    }

    private func accessibilityValue(unlocked: Bool, free: Int) -> String {
        if !unlocked { return String(localized: "Locked") }
        if free > 0 { return String(localized: "\(free) free uses") }
        return String(localized: "\(controller.price(of: hint)) coins")
    }
}

/// Bonus words fill this gift; every tenth word opens it for coins.
struct GiftButton: View {
    let progress: Int
    let bump: Int
    let accent: Color
    let action: () -> Void

    @State private var bounce = 0

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(Palette.cream.opacity(0.94))
                        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress) / CGFloat(Economy.giftCapacity))
                        .stroke(Palette.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(3)
                        .animation(.spring, value: progress)
                    Image(systemName: "gift.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Palette.goldDeep)
                        .symbolEffect(.bounce, value: bounce)
                }
                .frame(width: 52, height: 52)
                Text("\(progress)/\(Economy.giftCapacity)")
                    .font(.game(13, weight: .heavy))
                    .foregroundStyle(.white)
                    .legibleOnScenery()
                    .monospacedDigit()
            }
        }
        .buttonStyle(PressableStyle())
        .onChange(of: bump) { bounce += 1 }
        .accessibilityLabel(Text("Bonus gift"))
        .accessibilityValue(Text("\(progress) of \(Economy.giftCapacity) bonus words"))
    }
}

struct ShuffleButton: View {
    let action: () -> Void
    @State private var turns = 0

    var body: some View {
        Button {
            turns += 1
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .symbolEffect(.rotate, value: turns)
                    .frame(width: 52, height: 52)
                    .background(Palette.cream.opacity(0.94), in: .circle)
                    .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                Text("Shuffle")
                    .font(.game(13, weight: .heavy))
                    .foregroundStyle(.white)
                    .legibleOnScenery()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Shuffle letters"))
    }
}

/// A floating message.
struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = toast.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(iconColor)
            }
            Text(toast.text)
                .multilineTextAlignment(.leading)
        }
        .font(.game(toast.style == .praise ? 22 : 15, weight: .heavy))
        .foregroundStyle(toast.style == .praise ? .white : Palette.ink)
        .padding(.horizontal, toast.style == .praise ? 6 : 16)
        .padding(.vertical, 10)
        .background {
            if toast.style != .praise {
                Capsule().fill(Palette.cream.opacity(0.96)).shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            }
        }
        .shadow(color: .black.opacity(toast.style == .praise ? 0.4 : 0), radius: 4, y: 2)
        .accessibilityAddTraits(.isStaticText)
    }

    private var iconColor: Color {
        switch toast.style {
        case .praise: .white
        case .info: .blue
        case .reward: Palette.goldDeep
        case .warning: Palette.flame
        }
    }
}
