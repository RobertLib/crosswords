import Foundation

/// Everything persisted about the player. Decoding tolerates missing keys so that older
/// save files keep working as fields are added.
nonisolated struct PlayerData: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = PlayerData.currentVersion
    var coins = Economy.startingCoins
    var progress: [String: LanguageProgress] = [:]
    var stats = PlayerStats()
    /// Achievement id → number of tiers already claimed.
    var claimedTiers: [String: Int] = [:]
    /// Free uses of each hint, granted when a hint unlocks.
    var freeHints: [HintKind: Int] = [:]
    var unlockedHints: Set<HintKind> = [.letter]
    /// Bonus words collected towards the next bonus gift.
    var bonusGift = 0
    var settings = PlayerSettings()
    var tutorial = TutorialState()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, default: PlayerData.currentVersion)
        coins = c.value(.coins, default: Economy.startingCoins)
        progress = c.value(.progress, default: [:])
        stats = c.value(.stats, default: PlayerStats())
        claimedTiers = c.value(.claimedTiers, default: [:])
        freeHints = c.value(.freeHints, default: [:])
        unlockedHints = c.value(.unlockedHints, default: [.letter])
        bonusGift = c.value(.bonusGift, default: 0)
        settings = c.value(.settings, default: PlayerSettings())
        tutorial = c.value(.tutorial, default: TutorialState())
    }

    subscript(language: PuzzleLanguage) -> LanguageProgress {
        get { progress[language.rawValue] ?? LanguageProgress() }
        set { progress[language.rawValue] = newValue }
    }

    /// Days on which any daily puzzle was solved, across languages.
    var dailyDays: Set<String> {
        progress.values.reduce(into: Set<String>()) { $0.formUnion($1.dailyCompleted) }
    }

    var lexiconSize: Int {
        progress.values.reduce(0) { $0 + $1.lexiconSize }
    }
}

/// Progress through one language's puzzle pack.
nonisolated struct LanguageProgress: Codable, Equatable, Sendable {
    /// Levels `0..<completedLevels` are done; the next level to play is `completedLevels`.
    var completedLevels = 0
    var perfectLevels: Set<Int> = []
    var levelSession: SessionSnapshot?
    var dailyCompleted: Set<String> = []
    var dailySession: SessionSnapshot?
    /// An unfinished replay of a completed level (the latest one; its source says which level).
    var replaySession: SessionSnapshot?
    /// Grid answers the player has found.
    var foundWords: Set<String> = []
    /// Bonus words the player has found.
    var bonusWords: Set<String> = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completedLevels = c.value(.completedLevels, default: 0)
        perfectLevels = c.value(.perfectLevels, default: [])
        levelSession = c.value(.levelSession, default: nil)
        dailyCompleted = c.value(.dailyCompleted, default: [])
        dailySession = c.value(.dailySession, default: nil)
        replaySession = c.value(.replaySession, default: nil)
        foundWords = c.value(.foundWords, default: [])
        bonusWords = c.value(.bonusWords, default: [])
    }

    var lexiconSize: Int { foundWords.union(bonusWords).count }
}

nonisolated struct PlayerStats: Codable, Equatable, Sendable {
    var levelsCompleted = 0
    var perfectLevels = 0
    var chaptersCompleted = 0
    var wordsFound = 0
    var bonusWordsFound = 0
    var sevenLetterWords = 0
    var hintsUsed = 0
    var giftsOpened = 0
    var dailyCompleted = 0
    var bestStreak = 0
    var fastLevels = 0
    var bonusRichLevels = 0
    var playTime: TimeInterval = 0
    var longestWord = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levelsCompleted = c.value(.levelsCompleted, default: 0)
        perfectLevels = c.value(.perfectLevels, default: 0)
        chaptersCompleted = c.value(.chaptersCompleted, default: 0)
        wordsFound = c.value(.wordsFound, default: 0)
        bonusWordsFound = c.value(.bonusWordsFound, default: 0)
        sevenLetterWords = c.value(.sevenLetterWords, default: 0)
        hintsUsed = c.value(.hintsUsed, default: 0)
        giftsOpened = c.value(.giftsOpened, default: 0)
        dailyCompleted = c.value(.dailyCompleted, default: 0)
        bestStreak = c.value(.bestStreak, default: 0)
        fastLevels = c.value(.fastLevels, default: 0)
        bonusRichLevels = c.value(.bonusRichLevels, default: 0)
        playTime = c.value(.playTime, default: 0)
        longestWord = c.value(.longestWord, default: "")
    }
}

nonisolated struct PlayerSettings: Codable, Equatable, Sendable {
    var soundEnabled = true
    var hapticsEnabled = true
    /// Spell by tapping the wheel's letters one by one and confirming, instead of swiping. Always
    /// on with Switch Control, and the way to play with Voice Control or a hard-to-steady hand.
    var tapToSpell = false
    /// `nil` follows the app's UI language.
    var puzzleLanguage: PuzzleLanguage?
    var reminderEnabled = false
    var reminderHour = 19
    var reminderMinute = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = c.value(.soundEnabled, default: true)
        hapticsEnabled = c.value(.hapticsEnabled, default: true)
        tapToSpell = c.value(.tapToSpell, default: false)
        puzzleLanguage = c.value(.puzzleLanguage, default: nil)
        reminderEnabled = c.value(.reminderEnabled, default: false)
        reminderHour = c.value(.reminderHour, default: 19)
        reminderMinute = c.value(.reminderMinute, default: 0)
    }
}

/// One-time teaching moments that have already been shown.
nonisolated struct TutorialState: Codable, Equatable, Sendable {
    var swipeLearned = false
    var bonusExplained = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        swipeLearned = c.value(.swipeLearned, default: false)
        bonusExplained = c.value(.bonusExplained, default: false)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to a default when the key is missing or malformed.
    nonisolated func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}
