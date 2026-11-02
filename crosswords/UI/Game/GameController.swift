import Accessibility
import Foundation
import Observation
#if DEBUG
import SwiftUI
#endif

/// The outcome of the last submitted word, for the preview bubble animation.
struct WordFeedback: Equatable {
    enum Kind { case found, bonus, repeated, invalid }
    let id = UUID()
    let word: String
    let kind: Kind

    /// How VoiceOver describes the outcome.
    var spokenText: String {
        switch kind {
        case .found: String(localized: "\(word) found")
        case .bonus: String(localized: "\(word) is a bonus word")
        case .repeated: String(localized: "\(word) already found")
        case .invalid: String(localized: "\(word) is not in the puzzle")
        }
    }
}

/// Briefly highlights cells, e.g. when a word is entered a second time.
struct CellPulse: Equatable {
    var cells: Set<GridPoint> = []
    var token = 0
}

/// A short message floating over the game.
struct Toast: Equatable, Identifiable {
    enum Style { case praise, info, reward, warning }
    let id = UUID()
    let text: String
    var symbol: String?
    var style: Style = .info
}

/// What the level-complete card shows.
struct CompletionSummary: Equatable {
    struct Reward: Equatable, Identifiable {
        let id = UUID()
        let label: String
        let coins: Int
    }

    let praise: String
    let rewards: [Reward]
    let wordCount: Int
    let bonusCount: Int
    let elapsed: TimeInterval
    let isPerfect: Bool
    let completedChapter: Chapter?
    let streak: Int?
    let unlockedHints: [HintKind]
    let hasNext: Bool

    var totalCoins: Int { rewards.reduce(0) { $0 + $1.coins } }
}

/// Drives one game screen: turns gestures into session moves and moves into rewards,
/// sounds, haptics and saved progress.
@Observable
final class GameController {
    let app: AppModel
    let language: PuzzleLanguage
    private(set) var session: LevelSession

    /// Letter ids (see `LevelSession.wheelOrder`) connected by the player's finger, in order.
    private(set) var selection: [Int] = []
    private(set) var feedback: WordFeedback?
    /// Cells that just received their letter, mapped to an animation delay.
    private(set) var freshCells: [GridPoint: Double] = [:]
    private(set) var pulse = CellPulse()
    private(set) var toast: Toast?
    private(set) var completion: CompletionSummary?
    private(set) var giftBump = 0
    var isSpotlightActive = false
    var showSwipeTutorial: Bool
    #if DEBUG
    /// The App Preview's finger, drawn by the wheel (debug builds only).
    let demo = DemoFinger()
    /// Whether the launch arguments' pose has been set up: once, should the view appear again.
    @ObservationIgnored private var debugArgumentsApplied = false
    #endif

    @ObservationIgnored private var activeSince: Date?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(app: AppModel, source: PuzzleSource) {
        self.app = app
        language = app.language
        session = Self.makeSession(app: app, language: app.language, source: source)
        // Whichever puzzle a new player opens first, the daily one included.
        showSwipeTutorial = !app.data.tutorial.swipeLearned
    }

    private static func makeSession(app: AppModel, language: PuzzleLanguage, source: PuzzleSource) -> LevelSession {
        let puzzle = app.library.puzzle(for: source, language: language)
            ?? app.library.pack(for: language).levels[0]
        let progress = app.data[language]
        let snapshot: SessionSnapshot? = switch source {
        case .level: progress.levelSession
        case .daily: progress.dailySession
        case .replay: progress.replaySession
        }
        return LevelSession(source: source, puzzle: puzzle, snapshot: snapshot)
    }

    // MARK: - Presentation

    var source: PuzzleSource { session.source }

    var scene: SceneTheme {
        switch source {
        case .level(let index), .replay(let index):
            SceneTheme.forChapter(Chapter.index(containing: index))
        case .daily(let key):
            SceneTheme.forChapter(abs(DailySchedule.dayNumber(for: DailySchedule.date(forKey: key) ?? .now)))
        }
    }

    var title: String {
        switch source {
        case .level(let index), .replay(let index): String(localized: "Level \(String(index + 1))")
        case .daily: String(localized: "Daily Puzzle")
        }
    }

    var subtitle: String {
        switch source {
        case .level(let index), .replay(let index):
            app.chapterTitle(app.library.chapter(Chapter.index(containing: index), language: language))
        case .daily(let key):
            (DailySchedule.date(forKey: key) ?? .now).formatted(.dateTime.day().month(.wide))
        }
    }

    var previewWord: String { session.word(fromLetters: selection) }

    var giftProgress: Int { app.data.bonusGift }

    /// Replays play just for fun: they earn no coins, gifts or statistics, which could otherwise
    /// be farmed by repeating a level. A level that has been finished since this game opened
    /// counts as a replay too.
    var earnsRewards: Bool {
        switch source {
        case .level(let index): index >= app.data[language].completedLevels
        case .daily: true
        case .replay: false
        }
    }

    // MARK: - Lifecycle

    func resume() {
        guard activeSince == nil, completion == nil else { return }
        activeSince = .now
        app.haptics.prepare()
    }

    func pause() {
        flushTime()
        activeSince = nil
        // A drag interrupted by the system never ends normally; don't leave its letters behind.
        selection.removeAll()
        persist()
    }

    private func flushTime() {
        guard let start = activeSince else { return }
        session.elapsed += Date.now.timeIntervalSince(start)
        activeSince = completion == nil ? .now : nil
    }

    private func persist() {
        let snapshot = session.isComplete ? nil : session.snapshot
        switch source {
        case .level: app.store.update { $0[language].levelSession = snapshot }
        case .daily: app.store.update { $0[language].dailySession = snapshot }
        case .replay: app.store.update { $0[language].replaySession = snapshot }
        }
    }

    // MARK: - Wheel input

    func connect(_ letter: Int) {
        guard completion == nil, !selection.contains(letter), session.puzzle.letters.indices.contains(letter) else { return }
        selection.append(letter)
        app.sound.play(.letter(selection.count - 1))
        app.haptics.letter()
    }

    /// Steps back when the finger returns to the previously connected letter.
    func backtrack() {
        guard !selection.isEmpty else { return }
        selection.removeLast()
        app.haptics.letter()
    }

    /// Spelling by tapping (VoiceOver, Switch Control, Voice Control or the setting): a tapped letter
    /// joins the word, and tapping the last one again takes it back.
    func tapLetter(_ letter: Int) {
        if selection.last == letter {
            backtrack()
        } else {
            connect(letter)
        }
    }

    func cancelSelection() {
        selection.removeAll()
    }

    func submitSelection() {
        let word = previewWord
        selection.removeAll()
        guard !word.isEmpty, completion == nil else { return }
        handle(session.submit(word), word: word)
    }

    func shuffle() {
        session.shuffle()
        app.sound.play(.shuffle)
        app.haptics.tap()
        persist()
    }

    private func handle(_ result: SubmitResult, word: String) {
        switch result {
        case .found(let word, let revealed):
            judge(word, as: .found)
            animateFresh(revealed)
            app.sound.play(.word(length: word.count))
            app.haptics.success()
            let counts = earnsRewards
            app.store.update { data in
                if counts {
                    data.stats.wordsFound += 1
                    if word.count >= 7 { data.stats.sevenLetterWords += 1 }
                    if word.count > data.stats.longestWord.count { data.stats.longestWord = word }
                }
                data[language].foundWords.insert(word)
                data.tutorial.swipeLearned = true
            }
            showSwipeTutorial = false
            if word.count >= 5, !session.isComplete { showToast(Toast(text: Praise.random(for: word.count), style: .praise)) }
            afterBoardChange()
        case .alreadyFound(let word):
            judge(word, as: .repeated)
            if let index = session.board.index(of: word) {
                pulse = CellPulse(cells: Set(session.board.words[index].cells), token: pulse.token + 1)
            }
            app.sound.play(.repeated)
            app.haptics.tap()
        case .bonus(let word):
            judge(word, as: .bonus)
            app.sound.play(.bonus)
            app.haptics.success()
            collectBonus(word)
            persist()
        case .bonusRepeat(let word):
            judge(word, as: .repeated)
            // VoiceOver has just said so.
            showToast(Toast(text: String(localized: "Already found"), symbol: "sparkles"), spoken: false)
            app.sound.play(.repeated)
        case .invalid(let word):
            judge(word, as: .invalid)
            app.sound.play(.invalid)
            app.haptics.warning()
        case .tooShort:
            // A finger lifted early just lets go. VoiceOver submits with a button, though, and
            // would otherwise hear nothing at all.
            announce(String(localized: "Words need at least \(LevelSession.minimumWordLength) letters"))
        }
    }

    /// Shows how a word was judged, and tells VoiceOver, whose focus stays on the wheel.
    private func judge(_ word: String, as kind: WordFeedback.Kind) {
        let feedback = WordFeedback(word: word, kind: kind)
        self.feedback = feedback
        announce(feedback.spokenText)
    }

    /// Speaks with VoiceOver (and does nothing without it). A queued announcement waits for
    /// the current one, so a toast doesn't cut off the verdict on the word before it.
    private func announce(_ text: String, queued: Bool = false) {
        var announcement = AttributedString(text)
        if queued { announcement.accessibilitySpeechAnnouncementPriority = .low }
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func collectBonus(_ word: String) {
        guard earnsRewards else {
            app.store.update { $0[language].bonusWords.insert(word) }
            return
        }
        let firstTime = !app.data.tutorial.bonusExplained
        var opened = false
        app.store.update { data in
            data.stats.bonusWordsFound += 1
            data[language].bonusWords.insert(word)
            data.bonusGift += 1
            data.tutorial.bonusExplained = true
            if data.bonusGift >= Economy.giftCapacity {
                data.bonusGift -= Economy.giftCapacity
                data.coins += Economy.giftReward
                data.stats.giftsOpened += 1
                opened = true
            }
        }
        giftBump += 1
        if opened {
            app.sound.play(.coins)
            showToast(Toast(text: String(localized: "Bonus gift opened! +\(Economy.giftReward)"), symbol: "gift.fill", style: .reward))
        } else if firstTime {
            showToast(Toast(text: String(localized: "Bonus word! Collect \(Economy.giftCapacity) to open a gift."),
                            symbol: "gift.fill", style: .info), duration: 3.2)
        }
    }

    private func animateFresh(_ cells: [GridPoint]) {
        var fresh: [GridPoint: Double] = [:]
        for (offset, cell) in cells.sorted().enumerated() {
            fresh[cell] = Double(offset) * 0.06
        }
        freshCells = fresh
    }

    // MARK: - Hints

    func isUnlocked(_ hint: HintKind) -> Bool { app.data.unlockedHints.contains(hint) }

    func freeCharges(_ hint: HintKind) -> Int { app.data.freeHints[hint] ?? 0 }

    func price(of hint: HintKind) -> Int {
        hint.price(hiddenCells: session.hiddenCells.count)
    }

    func canUse(_ hint: HintKind) -> Bool {
        freeCharges(hint) > 0 || app.data.coins >= price(of: hint)
    }

    func use(_ hint: HintKind) {
        guard completion == nil, isUnlocked(hint) else { return }
        // Disarming costs nothing, so it never depends on the balance.
        if hint == .spotlight, isSpotlightActive {
            isSpotlightActive = false
            app.haptics.tap()
            return
        }
        guard canUse(hint) else {
            showNotEnoughCoins()
            return
        }
        let price = price(of: hint)
        switch hint {
        case .letter:
            guard let cell = session.revealNextLetter() else { return }
            pay(for: hint, price: price)
            revealed([cell])
        case .spotlight:
            isSpotlightActive = true
            app.haptics.tap()
        case .starburst:
            let cells = session.revealScattered(count: Economy.starburstLetters)
            guard !cells.isEmpty else { return }
            pay(for: hint, price: price)
            revealed(cells)
        }
    }

    func tapCell(_ cell: GridPoint) {
        guard isSpotlightActive, completion == nil else { return }
        // Other hints may have been bought since Spotlight was armed.
        guard canUse(.spotlight) else {
            isSpotlightActive = false
            showNotEnoughCoins()
            return
        }
        guard session.reveal(cell: cell) else {
            app.haptics.tap()
            return
        }
        isSpotlightActive = false
        pay(for: .spotlight, price: HintKind.spotlight.cost)
        revealed([cell])
    }

    private func pay(for hint: HintKind, price: Int) {
        let counts = earnsRewards
        app.store.update { data in
            if (data.freeHints[hint] ?? 0) > 0 {
                data.freeHints[hint, default: 0] -= 1
            } else {
                data.coins -= price
            }
            if counts { data.stats.hintsUsed += 1 }
        }
    }

    private func showNotEnoughCoins() {
        app.haptics.error()
        showToast(Toast(text: String(localized: "Not enough coins. Find bonus words or solve the daily puzzle to earn more."),
                        symbol: "bitcoinsign.circle", style: .warning), duration: 3)
    }

    private func revealed(_ cells: [GridPoint]) {
        animateFresh(cells)
        app.sound.play(.reveal)
        app.haptics.cellPop()
        afterBoardChange()
    }

    private func afterBoardChange() {
        if session.isComplete {
            finish()
        } else {
            persist()
        }
    }

    // MARK: - Completion

    private func finish() {
        flushTime()
        activeSince = nil
        selection.removeAll()
        isSpotlightActive = false
        // Read before the level is marked as completed, which turns it into a replay.
        let counts = earnsRewards
        let elapsed = session.elapsed
        let perfect = session.hintsUsed == 0
        var rewards: [CompletionSummary.Reward] = []
        var completedChapter: Chapter?
        var streak: Int?
        var unlocked: [HintKind] = []
        var hasNext = false

        switch source {
        case .level(let index) where !earnsRewards, .replay(let index):
            // Up to and including the level the journey has reached.
            hasNext = index + 1 <= app.data[language].completedLevels && index + 1 < app.library.levelCount(for: language)
            // No coins or statistics, but solving it without hints still earns the level its crown.
            if perfect, !app.data[language].perfectLevels.contains(index) {
                app.store.update { $0[language].perfectLevels.insert(index) }
            }
        case .level(let index):
            let letters = session.puzzle.letters.count
            rewards.append(.init(label: String(localized: "Level complete"), coins: Economy.levelReward(letterCount: letters)))
            if perfect { rewards.append(.init(label: String(localized: "No hints used"), coins: Economy.perfectBonus)) }
            let chapter = app.library.chapter(Chapter.index(containing: index), language: language)
            if index == chapter.levelRange.upperBound - 1 {
                completedChapter = chapter
                rewards.append(.init(label: String(localized: "Chapter complete"), coins: Economy.chapterReward))
            }
            hasNext = index + 1 < app.library.levelCount(for: language)
            app.store.update { data in
                data[language].completedLevels = max(data[language].completedLevels, index + 1)
                if perfect { data[language].perfectLevels.insert(index) }
                data.stats.levelsCompleted += 1
                if perfect { data.stats.perfectLevels += 1 }
                if completedChapter != nil { data.stats.chaptersCompleted += 1 }
                if elapsed < Economy.fastLevelSeconds { data.stats.fastLevels += 1 }
                if self.session.bonusFound.count >= Economy.bonusRichThreshold { data.stats.bonusRichLevels += 1 }
                let completed = data[language].completedLevels
                for hint in HintKind.allCases where !data.unlockedHints.contains(hint) && completed >= hint.unlockAfterLevels {
                    data.unlockedHints.insert(hint)
                    data.freeHints[hint, default: 0] += Economy.unlockGiftCharges
                    unlocked.append(hint)
                }
            }
        case .daily(let key):
            // A day is rewarded once, in whichever language its puzzle is solved first.
            let firstSolveOfDay = !app.data.dailyDays.contains(key)
            var days = app.data.dailyDays
            days.insert(key)
            let newStreak = DailySchedule.currentStreak(days: days, today: app.today)
            streak = newStreak
            if firstSolveOfDay {
                rewards.append(.init(label: String(localized: "Daily puzzle"), coins: Economy.dailyReward))
                if newStreak > 0, newStreak % Economy.streakMilestoneDays == 0 {
                    rewards.append(.init(label: String(localized: "\(newStreak)-day streak"), coins: Economy.streakMilestoneReward))
                }
            }
            app.store.update { data in
                if firstSolveOfDay { data.stats.dailyCompleted += 1 }
                data[language].dailyCompleted.insert(key)
                data.stats.bestStreak = max(data.stats.bestStreak, newStreak)
            }
            app.refreshReminders()
        }

        let total = rewards.reduce(0) { $0 + $1.coins }
        app.store.update { data in
            data.coins += total
            if counts { data.stats.playTime += elapsed }
        }
        persist()

        completion = CompletionSummary(
            praise: Praise.completion(perfect: perfect),
            rewards: rewards,
            wordCount: session.board.words.count,
            bonusCount: session.bonusFound.count,
            elapsed: elapsed,
            isPerfect: perfect,
            completedChapter: completedChapter,
            streak: streak,
            unlockedHints: unlocked,
            hasNext: hasNext)
        app.haptics.success()
        let unlockedHint = !unlocked.isEmpty
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            app.sound.play(.levelComplete)
            guard unlockedHint else { return }
            try? await Task.sleep(for: .milliseconds(1_100))
            app.sound.play(.unlock)
        }
    }

    /// Moves on to the next level in place. Returns false when the screen should close.
    func advance() -> Bool {
        guard let completion, completion.hasNext else { return false }
        let next: PuzzleSource
        switch source {
        case .level(let index), .replay(let index):
            // A replay leads back onto the journey once it reaches the next unfinished level.
            let level = index + 1
            next = level >= app.data[language].completedLevels ? .level(level) : .replay(level)
        case .daily: return false
        }
        session = Self.makeSession(app: app, language: language, source: next)
        self.completion = nil
        feedback = nil
        freshCells = [:]
        toast = nil
        activeSince = .now
        return true
    }

    #if DEBUG
    /// Sets up a screenshot pose from the launch arguments (see README), or starts the App
    /// Preview's demo game. Everything goes through the same moves a player makes.
    func applyDebugArguments() {
        guard !debugArgumentsApplied else { return }
        debugArgumentsApplied = true
        let defaults = UserDefaults.standard
        session.elapsed += defaults.double(forKey: "debugElapsed")
        // `-debugLeave 3` solves all but the last three words, whatever the puzzle's size, and
        // `-debugDemo 6` leaves the last six for the demo to play.
        let demoWords = defaults.integer(forKey: "debugDemo")
        let leave = demoWords > 0 ? demoWords : defaults.object(forKey: "debugLeave") != nil ? defaults.integer(forKey: "debugLeave") : nil
        let solve = leave.map { max(0, session.board.words.count - $0) } ?? defaults.integer(forKey: "debugSolve")
        for word in session.board.words.prefix(solve) {
            _ = session.submit(word.text)
        }
        var problems = ["debugBonusWords", "debugBonusLive", "debugDemoBonus"].flatMap { key in
            Self.debugList(key).filter { !session.puzzle.bonus.contains($0) }.map { "\($0) is not a bonus word here" }
        }
        for word in Self.debugList("debugBonusWords") where session.puzzle.bonus.contains(word) {
            _ = session.submit(word)
        }
        if session.isComplete {
            finish()
            DebugLaunch.markReady(problems: problems)
            return
        }
        for _ in 0..<defaults.integer(forKey: "debugHints") {
            if let cell = session.revealNextLetter() { animateFresh([cell]) }
        }
        // Found the way a player finds them, gift, toast and all.
        for word in Self.debugList("debugBonusLive") where session.puzzle.bonus.contains(word) {
            handle(session.submit(word), word: word)
        }
        let select = defaults.integer(forKey: "debugSelect")
        if select > 0 { selection = Array(session.wheelOrder.prefix(select)) }
        // `-debugSpell next` (or `longest`) spells a word still missing, mid-swipe.
        if let spell = defaults.string(forKey: "debugSpell") {
            let missing = session.board.words.indices.filter { !session.solvedWords.contains($0) }.map { session.board.words[$0].text }
            let word = switch spell {
            case "next": missing.first
            case "longest": missing.max { $0.count < $1.count }
            default: Optional(spell.uppercased())
            }
            selection = word.map(letterIDs(spelling:)) ?? []
            if let word {
                if !missing.contains(word) && !session.puzzle.bonus.contains(word) || selection.count != word.count {
                    problems.append("\(word) cannot be spelled here")
                }
            } else {
                problems.append("no word left to spell")
            }
            if defaults.bool(forKey: "debugFinger") { demo.finger = selection.last }
        }
        if defaults.bool(forKey: "debugSpotlight") { isSpotlightActive = true }
        persist()
        DebugLaunch.markReady(problems: problems)
        if demoWords > 0 {
            Task { await playDemo(bonus: Self.debugList("debugDemoBonus")) }
        }
    }

    private static func debugList(_ key: String) -> [String] {
        (UserDefaults.standard.string(forKey: key) ?? "").split(separator: ",").map { $0.uppercased() }
    }

    /// The wheel letters that spell `word`, each letter used once.
    private func letterIDs(spelling word: String) -> [Int] {
        var available = Array(session.puzzle.letters.indices)
        return word.compactMap { letter in
            available.firstIndex { session.puzzle.letters[$0] == letter }.map { available.remove(at: $0) }
        }
    }

    /// The App Preview's game: the words left on the board are swiped at a person's pace, a
    /// bonus word on the way, then the level-complete card and on to the next landscape, where
    /// one more word is found.
    private func playDemo(bonus: [String]) async {
        let defaults = UserDefaults.standard
        let lead = defaults.object(forKey: "debugDemoLead") != nil ? defaults.double(forKey: "debugDemoLead") : 1.5
        try? await Task.sleep(for: .seconds(lead))
        var words = session.board.words.indices.filter { !session.solvedWords.contains($0) }.map { session.board.words[$0].text }
        words.insert(contentsOf: bonus, at: min(2, words.count))
        for word in words {
            await swipe(word)
            try? await Task.sleep(for: .seconds(0.45))
        }
        demo.finger = nil
        try? await Task.sleep(for: .seconds(defaults.object(forKey: "debugDemoHold") != nil ? defaults.double(forKey: "debugDemoHold") : 3.4))
        withAnimation(.easeInOut(duration: 0.5)) { _ = advance() }
        try? await Task.sleep(for: .seconds(1.3))
        if let first = session.board.words.first {
            await swipe(first.text)
        }
        try? await Task.sleep(for: .seconds(0.6))
        demo.finger = nil
    }

    /// Glides the demo finger to each letter in turn, connecting it, then lets go.
    private func swipe(_ word: String) async {
        let ids = letterIDs(spelling: word)
        guard let first = ids.first else { return }
        demo.finger = first
        try? await Task.sleep(for: .seconds(0.3))
        for id in ids {
            demo.finger = id
            try? await Task.sleep(for: .seconds(0.09))
            connect(id)
            try? await Task.sleep(for: .seconds(0.09))
        }
        try? await Task.sleep(for: .seconds(0.12))
        submitSelection()
    }
    #endif

    // MARK: - Toasts

    func showToast(_ toast: Toast, duration: Double = 1.6, spoken: Bool = true) {
        self.toast = toast
        // Praise only repeats the verdict on the word, which VoiceOver has already heard.
        if spoken, toast.style != .praise { announce(toast.text, queued: true) }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

#if DEBUG
/// Which wheel letter the demo finger rests on; `nil` hides it.
@Observable
final class DemoFinger {
    var finger: Int?
}
#endif

/// Words of encouragement.
enum Praise {
    static func random(for length: Int) -> String {
        let options: [String] = length >= 7
            ? [String(localized: "Magnificent!"), String(localized: "Outstanding!"), String(localized: "Brilliant!")]
            : length == 6
            ? [String(localized: "Excellent!"), String(localized: "Superb!"), String(localized: "Splendid!")]
            : [String(localized: "Great!"), String(localized: "Nice!"), String(localized: "Good one!")]
        return options.randomElement() ?? ""
    }

    static func completion(perfect: Bool) -> String {
        let options: [String] = perfect
            ? [String(localized: "Flawless!"), String(localized: "Pure genius!"), String(localized: "Masterful!")]
            : [String(localized: "Well done!"), String(localized: "Wonderful!"), String(localized: "Splendid!"), String(localized: "Fantastic!")]
        return options.randomElement() ?? ""
    }
}
