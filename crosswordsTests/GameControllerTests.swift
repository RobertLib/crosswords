import Foundation
import Testing
@testable import crosswords

/// Economy rules enforced by `GameController`, played on the bundled puzzles.
struct GameControllerTests {
    func makeApp(_ change: (inout PlayerData) -> Void = { _ in }) -> AppModel {
        let store = PlayerStore(fileURL: nil)
        store.update { data in
            data.settings.soundEnabled = false
            data.settings.hapticsEnabled = false
            data.settings.puzzleLanguage = .english
            change(&data)
        }
        return AppModel(store: store)
    }

    /// Drags across the wheel letters spelling `word` and lifts the finger.
    func spell(_ word: String, in controller: GameController) {
        var available = Array(controller.session.puzzle.letters.enumerated())
        for letter in word {
            guard let index = available.firstIndex(where: { $0.element == letter }) else {
                Issue.record("\(word) can't be spelled")
                return
            }
            controller.connect(available.remove(at: index).offset)
        }
        controller.submitSelection()
    }

    func solve(_ controller: GameController) {
        for word in controller.session.board.words.map(\.text) {
            spell(word, in: controller)
        }
    }

    @Test func completingALevelPaysOnlyOnce() {
        let app = makeApp()
        let first = GameController(app: app, source: .level(0))
        solve(first)
        #expect(first.completion != nil)
        let coins = app.data.coins
        #expect(coins > Economy.startingCoins)
        #expect(app.progress.completedLevels == 1)

        // The same level finished again earns nothing, even when it opens as a journey level.
        let second = GameController(app: app, source: .level(0))
        solve(second)
        #expect(second.completion?.rewards.isEmpty == true)
        #expect(app.data.coins == coins)
        #expect(app.data.stats.levelsCompleted == 1)
    }

    @Test func replaysEarnNoCoinsGiftsOrStatistics() throws {
        let pack = try PuzzlePack.load(.english)
        let index = try #require(pack.levels.indices.first { !pack.levels[$0].bonus.isEmpty })
        let app = makeApp { $0[.english].completedLevels = index + 1 }
        let controller = GameController(app: app, source: .replay(index))
        let bonus = try #require(pack.levels[index].bonus.sorted().first)
        let before = app.data

        controller.session.elapsed = 30
        controller.use(.letter)
        spell(bonus, in: controller)
        solve(controller)

        #expect(controller.completion?.rewards.isEmpty == true)
        // Hints still cost coins.
        #expect(app.data.coins == before.coins - HintKind.letter.cost)
        #expect(app.data.bonusGift == before.bonusGift)
        #expect(app.data.stats.bonusWordsFound == before.stats.bonusWordsFound)
        #expect(app.data.stats.wordsFound == before.stats.wordsFound)
        #expect(app.data.stats.levelsCompleted == before.stats.levelsCompleted)
        #expect(app.data.stats.hintsUsed == before.stats.hintsUsed)
        #expect(app.data.stats.playTime == before.stats.playTime)
        // Words still join the lexicon, which can't be farmed.
        #expect(app.progress.bonusWords.contains(bonus))
    }

    @Test func aReplayWithoutHintsEarnsTheLevelItsCrown() {
        let app = makeApp { $0[.english].completedLevels = 3 }
        let controller = GameController(app: app, source: .replay(1))
        solve(controller)
        #expect(controller.completion?.isPerfect == true)
        #expect(controller.completion?.rewards.isEmpty == true)
        #expect(app.progress.perfectLevels.contains(1))
        // Still no statistics: the crown is the level's, the achievement counts first solves.
        #expect(app.data.stats.perfectLevels == 0)
        #expect(app.data.coins == Economy.startingCoins)
    }

    @Test func finishingAChapterPaysItsBonus() throws {
        let last = Chapter.size - 1
        let app = makeApp {
            $0[.english].completedLevels = last
            $0.unlockedHints = Set(HintKind.allCases)
        }
        let controller = GameController(app: app, source: .level(last))
        solve(controller)
        let completion = try #require(controller.completion)
        #expect(completion.completedChapter?.index == 0)
        #expect(completion.rewards.contains { $0.coins == Economy.chapterReward })
        #expect(app.data.stats.chaptersCompleted == 1)
    }

    @Test func hintsUnlockWithFreeUses() {
        let level = HintKind.spotlight.unlockAfterLevels - 1
        let app = makeApp { $0[.english].completedLevels = level }
        let controller = GameController(app: app, source: .level(level))
        solve(controller)
        #expect(controller.completion?.unlockedHints == [.spotlight])
        #expect(app.data.unlockedHints == [.letter, .spotlight])
        #expect(app.data.freeHints[.spotlight] == Economy.unlockGiftCharges)
    }

    @Test func everySeventhDayInARowPaysAStreakBonus() {
        let app = makeApp { data in
            for offset in 1..<Economy.streakMilestoneDays {
                let day = DailySchedule.calendar.date(byAdding: .day, value: -offset, to: .now)!
                data[.czech].dailyCompleted.insert(DailySchedule.key(for: day))
            }
        }
        let controller = GameController(app: app, source: .daily(app.todayKey))
        solve(controller)
        #expect(controller.completion?.streak == Economy.streakMilestoneDays)
        #expect(app.data.coins == Economy.startingCoins + Economy.dailyReward + Economy.streakMilestoneReward)
        #expect(app.data.stats.bestStreak == Economy.streakMilestoneDays)
    }

    @Test func tenBonusWordsOpenTheGift() throws {
        let pack = try PuzzlePack.load(.english)
        let index = try #require(pack.levels.indices.first { !pack.levels[$0].bonus.isEmpty })
        let app = makeApp {
            $0[.english].completedLevels = index
            $0.bonusGift = Economy.giftCapacity - 1
        }
        let controller = GameController(app: app, source: .level(index))
        spell(try #require(pack.levels[index].bonus.sorted().first), in: controller)
        #expect(app.data.bonusGift == 0)
        #expect(app.data.coins == Economy.startingCoins + Economy.giftReward)
        #expect(app.data.stats.giftsOpened == 1)
    }

    @Test func nextLevelOpensInPlace() {
        let app = makeApp()
        let controller = GameController(app: app, source: .level(0))
        solve(controller)
        #expect(controller.advance())
        #expect(controller.source == .level(1))
        #expect(controller.completion == nil)
        #expect(controller.earnsRewards)
    }

    @Test func replayingTheLastFinishedLevelLeadsBackOntoTheJourney() {
        let app = makeApp { $0[.english].completedLevels = 3 }
        let controller = GameController(app: app, source: .replay(2))
        solve(controller)
        #expect(controller.completion?.hasNext == true)
        #expect(controller.advance())
        #expect(controller.source == .level(3))
        #expect(controller.earnsRewards)
    }

    /// A replay left half-played waits where it was left, like a journey level; another replay
    /// starts afresh, and a finished one is not restored.
    @Test func anUnfinishedReplayWaitsWhereItWasLeft() throws {
        let app = makeApp { $0[.english].completedLevels = 5 }
        let first = GameController(app: app, source: .replay(3))
        let word = try #require(first.session.board.words.first?.text)
        spell(word, in: first)
        first.pause()

        let again = GameController(app: app, source: .replay(3))
        #expect(again.session.foundWords == [word])
        #expect(again.session.wheelOrder == first.session.wheelOrder)
        #expect(GameController(app: app, source: .replay(2)).session.foundWords.isEmpty)

        solve(again)
        #expect(again.completion != nil)
        #expect(app.progress.replaySession == nil)
        #expect(GameController(app: app, source: .replay(3)).session.foundWords.isEmpty)
    }

    @Test func aDayIsRewardedOnceAcrossLanguages() {
        let app = makeApp()
        let english = GameController(app: app, source: .daily(app.todayKey))
        solve(english)
        let coins = app.data.coins
        #expect(coins == Economy.startingCoins + Economy.dailyReward)

        app.setPuzzleLanguage(.czech)
        let czech = GameController(app: app, source: .daily(app.todayKey))
        solve(czech)
        #expect(czech.completion?.rewards.isEmpty == true)
        #expect(app.data.coins == coins)
        #expect(app.data.stats.dailyCompleted == 1)
        #expect(app.data[.english].dailyCompleted.contains(app.todayKey))
        #expect(app.data[.czech].dailyCompleted.contains(app.todayKey))
        #expect(app.isTodayRewarded)
    }

    @Test func spotlightChecksTheBalanceWhenTheSquareIsChosen() throws {
        let app = makeApp {
            $0.coins = HintKind.spotlight.cost + 10
            $0.unlockedHints = [.letter, .spotlight]
        }
        let controller = GameController(app: app, source: .level(0))
        controller.use(.spotlight)
        #expect(controller.isSpotlightActive)
        controller.use(.letter)
        #expect(app.data.coins == HintKind.spotlight.cost + 10 - HintKind.letter.cost)

        let cell = try #require(controller.session.hiddenCells.first)
        controller.tapCell(cell)
        #expect(!controller.isSpotlightActive)
        #expect(!controller.session.isVisible(cell))
        #expect(app.data.coins >= 0)
    }

    @Test func spotlightCanBeDisarmedWhateverTheBalance() {
        let app = makeApp {
            $0.coins = HintKind.spotlight.cost + 10
            $0.unlockedHints = [.letter, .spotlight]
        }
        let controller = GameController(app: app, source: .level(0))
        controller.use(.spotlight)
        controller.use(.letter)
        #expect(!controller.canUse(.spotlight))

        controller.use(.spotlight)
        #expect(!controller.isSpotlightActive)
        #expect(controller.toast == nil, "disarming must not complain about coins")
    }

    @Test func starburstCostsLessWhenFewSquaresRemain() {
        #expect(HintKind.starburst.price(hiddenCells: 12) == HintKind.starburst.cost)
        #expect(HintKind.starburst.price(hiddenCells: Economy.starburstLetters) == HintKind.starburst.cost)
        #expect(HintKind.starburst.price(hiddenCells: 2) == 36)
        // One square left: a share would be 18, less than the Light Bulb that reveals it too.
        #expect(HintKind.starburst.price(hiddenCells: 1) == HintKind.letter.cost)
        // A solved grid has nothing left to reveal; the button behind the summary shows no "0".
        #expect(HintKind.starburst.price(hiddenCells: 0) == HintKind.starburst.cost)
        #expect(HintKind.letter.price(hiddenCells: 1) == HintKind.letter.cost)
    }

    /// Spelling by tapping: each tap adds a letter, tapping the last one again takes it back.
    @Test func tappingLettersSpellsAndTakesBack() {
        let controller = GameController(app: makeApp(), source: .level(0))
        controller.tapLetter(0)
        controller.tapLetter(1)
        #expect(controller.selection == [0, 1])
        controller.tapLetter(0)
        #expect(controller.selection == [0, 1], "a letter is used once")
        controller.tapLetter(1)
        #expect(controller.selection == [0])
        controller.tapLetter(0)
        #expect(controller.selection.isEmpty)
    }

    /// A word whose squares hints (or crossings) have filled in still counts when it is spelled.
    @Test func spellingAnUncoveredWordStillFindsIt() throws {
        let app = makeApp()
        let controller = GameController(app: app, source: .level(0))
        let word = try #require(controller.session.board.words.last)
        for cell in word.cells { controller.session.reveal(cell: cell) }
        try #require(!controller.session.isComplete)
        spell(word.text, in: controller)
        #expect(controller.feedback?.kind == .found)
        #expect(app.progress.foundWords.contains(word.text))
        #expect(app.data.stats.wordsFound == 1)
    }

    @Test func aNewPlayersFirstPuzzleTeachesTheSwipeWhicheverItIs() {
        let app = makeApp()
        #expect(GameController(app: app, source: .daily(app.todayKey)).showSwipeTutorial)
        let learned = makeApp { $0.tutorial.swipeLearned = true }
        #expect(!GameController(app: learned, source: .level(0)).showSwipeTutorial)
    }

    @Test func pausingDropsAnUnfinishedSwipe() {
        let controller = GameController(app: makeApp(), source: .level(0))
        controller.connect(0)
        controller.connect(1)
        controller.pause()
        #expect(controller.selection.isEmpty)
    }
}
