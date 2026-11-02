import SwiftUI

/// Achievements to claim and lifetime statistics.
struct TrophiesView: View {
    enum Tab: Hashable { case achievements, statistics }

    @Environment(AppModel.self) private var app
    @State private var tab = Tab.achievements

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Section", selection: $tab) {
                    Text("Achievements").tag(Tab.achievements)
                    Text("Statistics").tag(Tab.statistics)
                }
                .pickerStyle(.segmented)

                switch tab {
                case .achievements:
                    ForEach(app.achievementStatuses) { status in
                        AchievementCard(status: status) { app.claim(status.achievement) }
                    }
                case .statistics:
                    StatisticsGrid(data: app.data, streak: app.currentStreak)
                }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: app.data.claimedTiers)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("Trophies"))
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "debugTab") == "statistics" { tab = .statistics }
            DebugLaunch.screenAppeared("trophies")
        }
        #endif
    }
}

enum Tier {
    static let colors: [Color] = [.hex(0xCD8A4A), .hex(0x9FAAB6), .hex(0xE9B53B), .hex(0x5FC3DF)]

    static func name(_ tier: Int) -> LocalizedStringResource {
        switch tier {
        case 0: "Bronze"
        case 1: "Silver"
        case 2: "Gold"
        default: "Platinum"
        }
    }
}

private struct AchievementCard: View {
    let status: AchievementStatus
    let onClaim: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let tierColor = status.claimedTiers > 0 ? Tier.colors[status.claimedTiers - 1] : Color.secondary.opacity(0.5)
        // At the accessibility text sizes the badge goes above, leaving the text the card's width.
        let stacks = dynamicTypeSize.isAccessibilitySize
        let card = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                          : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        card {
            Image(systemName: status.achievement.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(tierColor.gradient, in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(status.achievement.title)
                        .font(.game(.headline, weight: .heavy))
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { tier in
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(tier < status.claimedTiers ? Tier.colors[tier] : Color.secondary.opacity(0.25))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(status.claimedTiers) of 4 tiers"))
                }
                if status.isMaxed {
                    Text("All tiers complete")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(status.achievement.goal(status.target))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: status.fraction)
                        .tint(Tier.colors[status.activeTier])
                    // The claim button goes under the count at the accessibility text sizes.
                    let row = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
                    row {
                        Text("\(min(status.value, status.target)) / \(status.target)")
                            .font(.game(.caption, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if !stacks { Spacer() }
                        if status.isClaimable {
                            Button(action: onClaim) {
                                HStack(spacing: 4) {
                                    Text("Claim")
                                    CoinIcon(size: 14)
                                    Text("\(status.nextReward)")
                                }
                                .font(.game(.subheadline, weight: .heavy))
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(Palette.flameFill)
                        } else {
                            HStack(spacing: 3) {
                                Text(Tier.name(status.activeTier))
                                CoinIcon(size: 12)
                                Text("\(status.nextReward)")
                            }
                            .font(.game(.caption, weight: .bold))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .overlay {
            if status.isClaimable {
                RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.flame.opacity(0.6), lineWidth: 2)
            }
        }
    }
}

private struct StatisticsGrid: View {
    let data: PlayerData
    let streak: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let s = data.stats
        // One column at the accessibility text sizes, where two would break the labels mid-word.
        let columns = dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())]
                                                          : [GridItem(.adaptive(minimum: 150), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            tile("Levels completed", "\(s.levelsCompleted)", "map.fill")
            tile("Without hints", "\(s.perfectLevels)", "crown.fill")
            tile("Chapters", "\(s.chaptersCompleted)", "mountain.2.fill")
            tile("Crossword words", "\(s.wordsFound)", "textformat.abc")
            tile("Bonus words", "\(s.bonusWordsFound)", "sparkles")
            tile("Lexicon", "\(data.lexiconSize)", "books.vertical.fill")
            tile("Daily puzzles", "\(s.dailyCompleted)", "calendar")
            tile("Current streak", "\(streak)", "flame.fill")
            tile("Best streak", "\(s.bestStreak)", "flame")
            tile("Gifts opened", "\(s.giftsOpened)", "gift.fill")
            tile("Hints used", "\(s.hintsUsed)", "lightbulb.fill")
            tile("Time played", Duration.seconds(s.playTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)), "clock.fill")
            if !s.longestWord.isEmpty {
                tile("Longest word", s.longestWord, "ruler.fill")
            }
        }
    }

    private func tile(_ label: LocalizedStringResource, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(value)
                .font(.game(.title2, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.game(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
