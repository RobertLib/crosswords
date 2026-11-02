#if DEBUG
import Foundation

/// Launch arguments for QA and screenshots, e.g.
/// `-debugProgress 30 -debugRoute level -debugSolve 3`. Compiled into debug builds only.
/// The App Store media (Tools/AppStoreMedia/media.sh) is shot with these; see AppStore/screenshots.md.
enum DebugLaunch {
    /// Runs before the first screen appears, so every route already sees the seeded player.
    static func prepare(_ app: AppModel) {
        let defaults = UserDefaults.standard
        let progress = defaults.integer(forKey: "debugProgress")
        if progress > 0 {
            // Replaced rather than added to: a level left half-played by an earlier launch would
            // otherwise be restored, and no two launches would show the same board.
            app.store.reset(keepingSettings: false)
        }
        if let language = defaults.string(forKey: "debugLanguage").flatMap(PuzzleLanguage.init(rawValue:)) {
            app.setPuzzleLanguage(language)
        }
        if progress > 0 {
            seed(app: app, completedLevels: progress)
        }
        if defaults.bool(forKey: "debugMute") {
            app.store.update { $0.settings.soundEnabled = false }
            app.applySettings()
        }
    }

    static func apply(to app: AppModel) {
        switch UserDefaults.standard.string(forKey: "debugRoute") {
        case "level": app.playNextLevel()
        case "daily": app.playDaily()
        default: break
        }
    }

    /// Marks a menu pose ready once its screen has appeared and the push or sheet that brought it
    /// has finished animating. `route` is the `-debugRoute` that leads to the screen, `nil` for the
    /// menu itself; a game marks itself ready once its board is set up (`applyDebugArguments`).
    static func screenAppeared(_ route: String?) {
        guard UserDefaults.standard.string(forKey: "debugRoute") == route else { return }
        Task {
            // Longer than a navigation push or a sheet takes to come in.
            try? await Task.sleep(for: .milliseconds(700))
            markReady()
        }
    }

    /// Drops `Documents/shot-ready` once a pose is set up; the media script waits for it
    /// rather than for a guessed number of seconds. A pose whose words the puzzle does not
    /// have writes them into the marker instead, and the script stops on it: the poses name
    /// words from the current packs, and a regenerated pack would otherwise just leave them out.
    static func markReady(problems: [String] = []) {
        let url = URL.documentsDirectory.appending(path: "shot-ready")
        // Atomically: the script polls for the file, and one caught between being created
        // and being filled would read as empty — a pose that failed taken for one that is ready.
        try? Data(problems.joined(separator: "; ").utf8).write(to: url, options: .atomic)
    }

    /// Fakes a player who has finished `completedLevels` levels: the words they found, a few
    /// weeks of daily puzzles and the achievements those earned, all claimed but two. Seeded
    /// from the puzzles themselves, so every launch writes the same history.
    private static func seed(app: AppModel, completedLevels: Int) {
        let defaults = UserDefaults.standard
        let language = app.language
        let pack = app.library.pack(for: language)
        let count = min(completedLevels, pack.levels.count)
        let calendar = DailySchedule.calendar
        let today = calendar.startOfDay(for: .now)

        // A streak that ends yesterday, so today's puzzle is still waiting, and before it a
        // month of play with a missed day here and there.
        let streak = defaults.object(forKey: "debugStreak") != nil ? defaults.integer(forKey: "debugStreak") : 12
        var dailyKeys = Set<String>()
        for offset in 1...45 where offset <= streak || (offset > streak + 1 && offset % 6 != 0) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                dailyKeys.insert(DailySchedule.key(for: day))
            }
        }
        let dailyPuzzles = dailyKeys.compactMap { app.library.puzzle(for: .daily($0), language: language) }

        app.store.update { data in
            var progress = LanguageProgress()
            progress.completedLevels = count
            var words = 0, sevenLetter = 0, bonus = 0, longest = ""
            for (index, puzzle) in pack.levels.prefix(count).enumerated() {
                let found = puzzle.words.map(\.text)
                progress.foundWords.formUnion(found)
                progress.bonusWords.formUnion(puzzle.bonus.sorted().prefix(index % 4))
                bonus += index % 4
                words += found.count
                sevenLetter += found.filter { $0.count >= 7 }.count
                if index % 3 != 0 { progress.perfectLevels.insert(index) }
                for word in found where word.count > longest.count { longest = word }
            }
            for puzzle in dailyPuzzles {
                progress.foundWords.formUnion(puzzle.words.map(\.text))
                words += puzzle.words.count
            }
            progress.dailyCompleted = dailyKeys
            data[language] = progress

            data.stats.levelsCompleted = count
            data.stats.perfectLevels = progress.perfectLevels.count
            data.stats.chaptersCompleted = count / Chapter.size
            data.stats.wordsFound = words
            data.stats.sevenLetterWords = sevenLetter
            data.stats.bonusWordsFound = bonus
            data.stats.giftsOpened = bonus / Economy.giftCapacity
            data.stats.hintsUsed = (count - progress.perfectLevels.count) * 2
            data.stats.dailyCompleted = dailyKeys.count
            data.stats.bestStreak = longestRun(of: dailyKeys, before: today)
            data.stats.fastLevels = count / 3
            data.stats.bonusRichLevels = count / 9
            data.stats.playTime = Double(count) * 97 + Double(dailyKeys.count) * 140
            data.stats.longestWord = longest
            data.bonusGift = defaults.object(forKey: "debugGift") != nil
                ? defaults.integer(forKey: "debugGift") : bonus % Economy.giftCapacity
            data.coins = defaults.object(forKey: "debugCoins") != nil ? defaults.integer(forKey: "debugCoins") : 485
            for hint in HintKind.allCases where count >= hint.unlockAfterLevels {
                data.unlockedHints.insert(hint)
            }
            data.tutorial.swipeLearned = true
            // `-debugBonusTip 1` keeps the one-time explanation of the bonus gift for the next bonus word.
            data.tutorial.bonusExplained = !defaults.bool(forKey: "debugBonusTip")

            // Everything reached is claimed, except the latest tier of two achievements, which
            // leaves the Trophies badge and a Claim button to show.
            var unclaimed = 0
            for achievement in [Achievement.steadyFlame, .treasureHunter] + Achievement.allCases {
                guard data.claimedTiers[achievement.id] == nil else { continue }
                let reached = AchievementStatus(achievement, data: data).reachedTiers
                let leaveOne = reached > 0 && unclaimed < 2
                if leaveOne { unclaimed += 1 }
                data.claimedTiers[achievement.id] = leaveOne ? reached - 1 : reached
            }
        }
    }

    private static func longestRun(of keys: Set<String>, before today: Date) -> Int {
        let calendar = DailySchedule.calendar
        var best = 0, run = 0
        for offset in (1...60).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            run = keys.contains(DailySchedule.key(for: day)) ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }
}
#endif
