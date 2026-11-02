import Foundation

/// The ways a player can buy help. Each one unlocks as the journey progresses.
nonisolated enum HintKind: String, Codable, CodingKeyRepresentable, CaseIterable, Identifiable, Sendable {
    /// Reveals the next letter of the shortest unsolved word.
    case letter
    /// Reveals any cell the player taps.
    case spotlight
    /// Reveals several letters scattered across the grid.
    case starburst

    var id: String { rawValue }

    var cost: Int {
        switch self {
        case .letter: 25
        case .spotlight: 40
        case .starburst: 90
        }
    }

    /// The price when `hiddenCells` squares are still hidden. Starburst costs proportionally
    /// less once fewer squares remain than it would reveal, but never less than a Light Bulb:
    /// the last letter or two would otherwise be cheapest bought as a Starburst.
    func price(hiddenCells: Int) -> Int {
        guard self == .starburst, (1..<Economy.starburstLetters).contains(hiddenCells) else { return cost }
        let share = (cost * hiddenCells + Economy.starburstLetters - 1) / Economy.starburstLetters
        return max(HintKind.letter.cost, share)
    }

    /// Number of completed journey levels needed before the hint becomes available.
    var unlockAfterLevels: Int {
        switch self {
        case .letter: 0
        case .spotlight: 6
        case .starburst: 15
        }
    }

    var symbol: String {
        switch self {
        case .letter: "lightbulb.max.fill"
        case .spotlight: "scope"
        case .starburst: "wand.and.stars"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .letter: "Light Bulb"
        case .spotlight: "Spotlight"
        case .starburst: "Starburst"
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .letter: "Reveals the next letter of a word."
        case .spotlight: "Tap any empty square to reveal its letter."
        case .starburst: "Reveals five letters scattered across the grid."
        }
    }
}

/// Coin rewards and prices. Tuned to be generous: the game never sells anything, so
/// coins exist only to pace help, not to frustrate.
nonisolated enum Economy {
    static let startingCoins = 200
    static let starburstLetters = 5

    static let perfectBonus = 5
    static let chapterReward = 50
    static let dailyReward = 60
    static let streakMilestoneDays = 7
    static let streakMilestoneReward = 100

    static let giftCapacity = 10
    static let giftReward = 25

    /// Free uses granted when a hint unlocks, so players can try it out.
    static let unlockGiftCharges = 2

    /// A level is "fast" when solved within this many seconds.
    static let fastLevelSeconds: TimeInterval = 60
    /// Levels where this many bonus words were found count towards an achievement.
    static let bonusRichThreshold = 5

    static func levelReward(letterCount: Int) -> Int {
        8 + letterCount * 2
    }
}
