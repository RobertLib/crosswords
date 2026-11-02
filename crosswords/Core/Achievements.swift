import Foundation

/// Long-term goals with four tiers each. Reaching a tier lets the player claim coins.
nonisolated enum Achievement: String, CaseIterable, Identifiable, Sendable {
    case wordsmith, treasureHunter, trailblazer, clearMind, dailyRitual, steadyFlame
    case longHaul, explorer, quickThinker, bookworm, generousSpirit, thorough

    var id: String { rawValue }

    static let tierRewards = [20, 50, 120, 300]

    /// The top tiers of the counts that a journey alone can fill (crossword words, seven-letter
    /// words, levels and chapters) stay within one language's journey, with room left for the
    /// words a player uncovers by hints rather than spells: `PuzzlePackTests` checks both packs.
    var thresholds: [Int] {
        switch self {
        case .wordsmith: [50, 500, 2_500, 7_000]
        case .treasureHunter: [25, 250, 1_000, 5_000]
        case .trailblazer: [12, 100, 500, 1_200]
        case .clearMind: [10, 75, 300, 800]
        case .dailyRitual: [3, 30, 100, 365]
        case .steadyFlame: [3, 7, 30, 100]
        case .longHaul: [5, 50, 200, 400]
        case .explorer: [1, 10, 40, 100]
        case .quickThinker: [5, 25, 100, 300]
        case .bookworm: [100, 1_000, 3_000, 8_000]
        case .generousSpirit: [3, 30, 120, 400]
        case .thorough: [1, 20, 100, 300]
        }
    }

    var symbol: String {
        switch self {
        case .wordsmith: "textformat.abc"
        case .treasureHunter: "sparkles"
        case .trailblazer: "map.fill"
        case .clearMind: "brain.head.profile"
        case .dailyRitual: "calendar"
        case .steadyFlame: "flame.fill"
        case .longHaul: "ruler.fill"
        case .explorer: "mountain.2.fill"
        case .quickThinker: "bolt.fill"
        case .bookworm: "books.vertical.fill"
        case .generousSpirit: "gift.fill"
        case .thorough: "magnifyingglass"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .wordsmith: "Wordsmith"
        case .treasureHunter: "Treasure Hunter"
        case .trailblazer: "Trailblazer"
        case .clearMind: "Clear Mind"
        case .dailyRitual: "Daily Ritual"
        case .steadyFlame: "Steady Flame"
        case .longHaul: "Long Haul"
        case .explorer: "Explorer"
        case .quickThinker: "Quick Thinker"
        case .bookworm: "Bookworm"
        case .generousSpirit: "Gift Collector"
        case .thorough: "Thorough"
        }
    }

    func goal(_ target: Int) -> LocalizedStringResource {
        switch self {
        case .wordsmith: "Find \(target) crossword words"
        case .treasureHunter: "Discover \(target) bonus words"
        case .trailblazer: "Complete \(target) levels"
        case .clearMind: "Complete \(target) levels without hints"
        case .dailyRitual: "Solve \(target) daily puzzles"
        case .steadyFlame: "Reach a streak of \(target) days"
        case .longHaul: "Find \(target) seven-letter words"
        case .explorer: "Complete \(target) chapters"
        case .quickThinker: "Finish \(target) levels in under a minute"
        case .bookworm: "Collect \(target) words in your lexicon"
        case .generousSpirit: "Open \(target) bonus gifts"
        case .thorough: "Find 5+ bonus words in \(target) levels"
        }
    }

    func value(in data: PlayerData) -> Int {
        let s = data.stats
        switch self {
        case .wordsmith: return s.wordsFound
        case .treasureHunter: return s.bonusWordsFound
        case .trailblazer: return s.levelsCompleted
        case .clearMind: return s.perfectLevels
        case .dailyRitual: return s.dailyCompleted
        case .steadyFlame: return s.bestStreak
        case .longHaul: return s.sevenLetterWords
        case .explorer: return s.chaptersCompleted
        case .quickThinker: return s.fastLevels
        case .bookworm: return data.lexiconSize
        case .generousSpirit: return s.giftsOpened
        case .thorough: return s.bonusRichLevels
        }
    }
}

/// An achievement's standing for a particular player.
nonisolated struct AchievementStatus: Identifiable, Sendable {
    let achievement: Achievement
    let value: Int
    /// Tiers reached so far (0...4).
    let reachedTiers: Int
    /// Tiers already claimed (0...4).
    let claimedTiers: Int

    var id: String { achievement.id }

    init(_ achievement: Achievement, data: PlayerData) {
        self.achievement = achievement
        let value = achievement.value(in: data)
        let reached = achievement.thresholds.filter { value >= $0 }.count
        self.value = value
        reachedTiers = reached
        claimedTiers = min(data.claimedTiers[achievement.id] ?? 0, reached)
    }

    var isClaimable: Bool { claimedTiers < reachedTiers }
    var isMaxed: Bool { claimedTiers == achievement.thresholds.count }
    /// The tier currently being worked on (or claimed next).
    var activeTier: Int { min(claimedTiers, achievement.thresholds.count - 1) }
    var target: Int { achievement.thresholds[activeTier] }
    var nextReward: Int { Achievement.tierRewards[activeTier] }

    var fraction: Double {
        isMaxed ? 1 : min(1, Double(value) / Double(max(1, target)))
    }
}
