import Foundation
import Observation

/// A request to open the game screen, with the controller that runs it. Made once, here:
/// SwiftUI may create the game view many times over, and a controller made in its initializer
/// would be built again (and thrown away) every time.
struct GameLaunch: Identifiable {
    let id = UUID()
    let controller: GameController
}

/// Root application state shared by every screen.
@Observable
final class AppModel {
    let store: PlayerStore
    @ObservationIgnored let library: PuzzleLibrary
    @ObservationIgnored let sound = SoundEngine()
    @ObservationIgnored let haptics = Haptics()

    var activeGame: GameLaunch?
    /// The calendar day the UI considers "today"; refreshed when the app becomes active.
    private(set) var today = Date.now
    @ObservationIgnored private var reminderRefresh: Task<Void, Never>?
    @ObservationIgnored private var notificationRouter: NotificationRouter?
    /// Whether the menu is on screen, ready to present a game.
    @ObservationIgnored private var isMenuShown = false
    /// A reminder tapped before the menu appeared (it launched the app), handled once it has.
    @ObservationIgnored private var opensDailyWhenShown = false

    init(store: PlayerStore = PlayerStore(), library: PuzzleLibrary = PuzzleLibrary()) {
        self.store = store
        self.library = library
        // Overlaps decoding with the launch, before the first screen asks for it.
        library.prefetch(language)
        applySettings()
    }

    var data: PlayerData { store.data }

    // MARK: - Language

    var language: PuzzleLanguage { data.settings.puzzleLanguage ?? .systemDefault }

    var progress: LanguageProgress { data[language] }

    func setPuzzleLanguage(_ language: PuzzleLanguage?) {
        store.update { $0.settings.puzzleLanguage = language }
    }

    // MARK: - Journey

    var levelCount: Int { library.levelCount(for: language) }

    /// Index of the next journey level, clamped to the last level once everything is done.
    var nextLevel: Int { min(progress.completedLevels, levelCount - 1) }

    var isJourneyComplete: Bool { progress.completedLevels >= levelCount }

    var currentChapter: Chapter {
        library.chapter(Chapter.index(containing: nextLevel), language: language)
    }

    func chapterTitle(_ chapter: Chapter) -> String {
        let name = String(localized: chapter.scene.name)
        return chapter.cycle > 1 ? "\(name) \(RomanNumeral.string(for: chapter.cycle))" : name
    }

    // MARK: - Daily puzzle

    var todayKey: String { DailySchedule.key(for: today) }

    var isDailySolvedToday: Bool { progress.dailyCompleted.contains(todayKey) }

    /// Whether today's puzzle was solved in any language. The day's reward and streak are shared.
    var isTodayRewarded: Bool { data.dailyDays.contains(todayKey) }

    var currentStreak: Int { DailySchedule.currentStreak(days: data.dailyDays, today: today) }

    // MARK: - Achievements

    var achievementStatuses: [AchievementStatus] {
        Achievement.allCases.map { AchievementStatus($0, data: data) }
    }

    var claimableAchievements: Int { achievementStatuses.filter(\.isClaimable).count }

    func claim(_ achievement: Achievement) {
        let status = AchievementStatus(achievement, data: data)
        guard status.isClaimable else { return }
        let reward = status.nextReward
        store.update {
            $0.claimedTiers[achievement.id] = status.claimedTiers + 1
            $0.coins += reward
        }
        sound.play(.coins)
        haptics.success()
    }

    // MARK: - Launching games

    func playNextLevel() {
        launch(isJourneyComplete ? .replay(nextLevel) : .level(nextLevel))
    }

    func playDaily() {
        launch(.daily(todayKey))
    }

    func replay(level: Int) {
        launch(level >= progress.completedLevels ? .level(level) : .replay(level))
    }

    /// Starts routing taps on the daily reminder here. Called by the app, not by tests.
    func handleReminderTaps() {
        notificationRouter = NotificationRouter(app: self)
    }

    /// The player tapped the daily reminder: open today's puzzle, unless it is solved already
    /// or another game is open.
    func openDailyFromReminder() {
        guard isMenuShown else {
            opensDailyWhenShown = true
            return
        }
        today = .now
        guard activeGame == nil, !isDailySolvedToday else { return }
        playDaily()
    }

    func menuDidAppear() {
        isMenuShown = true
        if opensDailyWhenShown {
            opensDailyWhenShown = false
            openDailyFromReminder()
        }
    }

    private func launch(_ source: PuzzleSource) {
        sound.play(.tap)
        haptics.tap()
        activeGame = GameLaunch(controller: GameController(app: self, source: source))
    }

    // MARK: - Lifecycle

    func applySettings() {
        sound.isEnabled = data.settings.soundEnabled
        haptics.isEnabled = data.settings.hapticsEnabled
        sound.prepare()
    }

    func didBecomeActive() {
        if store.reloadIfUnreadable() {
            library.prefetch(language)
            applySettings()
        }
        today = .now
        sound.prepare()
        refreshReminders()
    }

    func didEnterBackground() {
        store.saveNow()
        sound.suspend()
    }

    func refreshReminders() {
        let settings = data.settings
        let solved = isTodayRewarded
        // One refresh at a time, so quick changes (e.g. scrolling the time picker) can't
        // interleave; a newer request supersedes a queued one.
        let previous = reminderRefresh
        previous?.cancel()
        reminderRefresh = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await ReminderScheduler.refresh(settings: settings, solvedToday: solved)
        }
    }
}

enum RomanNumeral {
    static func string(for value: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var remaining = max(1, value)
        var result = ""
        for (amount, symbol) in table {
            while remaining >= amount {
                result += symbol
                remaining -= amount
            }
        }
        return result
    }
}
