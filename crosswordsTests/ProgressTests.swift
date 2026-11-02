import Foundation
import Testing
import UserNotifications
@testable import crosswords

struct DailyScheduleTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func keysRoundTrip() {
        let day = date(2026, 11, 2)
        #expect(DailySchedule.key(for: day, calendar: calendar) == "2026-11-02")
        let parsed = DailySchedule.date(forKey: "2026-11-02", calendar: calendar)!
        #expect(calendar.isDate(parsed, inSameDayAs: day))
    }

    @Test func puzzleIndexIsStableAndInRange() {
        let a = DailySchedule.puzzleIndex(for: date(2026, 11, 2), count: 400, calendar: calendar)
        let b = DailySchedule.puzzleIndex(for: date(2026, 11, 3), count: 400, calendar: calendar)
        #expect(b == (a + 1) % 400)
        #expect((0..<400).contains(DailySchedule.puzzleIndex(for: date(2020, 1, 1), count: 400, calendar: calendar)))
    }

    @Test func dayKeysAreGregorianWhateverTheSystemCalendar() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Europe/Prague")!
        let day = buddhist.date(from: DateComponents(year: 2569, month: 11, day: 2, hour: 12))!
        #expect(DailySchedule.calendar.identifier == .gregorian)
        #expect(DailySchedule.key(for: day).hasPrefix("2026-"))
    }

    @Test func streakCountsConsecutiveDays() {
        let days: Set<String> = ["2026-10-30", "2026-10-31", "2026-11-01"]
        // Today not solved yet: the streak through yesterday still counts.
        #expect(DailySchedule.currentStreak(days: days, today: date(2026, 11, 2), calendar: calendar) == 3)
        #expect(DailySchedule.currentStreak(days: days.union(["2026-11-02"]), today: date(2026, 11, 2), calendar: calendar) == 4)
        // A missed day breaks it.
        #expect(DailySchedule.currentStreak(days: days, today: date(2026, 11, 3), calendar: calendar) == 0)
    }
}

struct PlayerDataTests {
    @Test func decodesOldOrPartialSaves() throws {
        let data = try JSONDecoder().decode(PlayerData.self, from: Data(#"{"coins": 77}"#.utf8))
        #expect(data.coins == 77)
        #expect(data.unlockedHints == [.letter])
        #expect(data.settings.soundEnabled)
    }

    @Test func roundTrips() throws {
        var data = PlayerData()
        data.coins = 321
        data[.czech].completedLevels = 12
        data[.czech].foundWords = ["KOČKA"]
        data.freeHints[.spotlight] = 2
        data[.english].levelSession = SessionSnapshot(source: .daily("2026-11-02"), wheelOrder: [1, 0, 2],
                                                      found: ["CAT"], hinted: [GridPoint(row: 1, col: 1)],
                                                      bonus: [], hintsUsed: 1, elapsed: 12)
        let decoded = try JSONDecoder().decode(PlayerData.self, from: JSONEncoder().encode(data))
        #expect(decoded == data)
    }

    @Test func storePersistsToDisk() throws {
        let url = URL.temporaryDirectory.appending(path: "player-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PlayerStore(fileURL: url)
        store.update { $0.coins = 999 }
        store.saveNow()
        #expect(PlayerStore(fileURL: url).data.coins == 999)
    }

    @Test func anUnreadableSaveIsNotOverwritten() throws {
        let url = URL.temporaryDirectory.appending(path: "player-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data(#"{"coins": 1234}"#.utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)

        let store = PlayerStore(fileURL: url)
        store.update { $0.coins = 1 }
        store.saveNow()

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try Data(contentsOf: url) == original)
    }

    /// E.g. a launch before the device's first unlock, while the file is still encrypted.
    @Test func aSaveUnreadableAtLaunchIsLoadedOnceItCanBeRead() throws {
        let url = URL.temporaryDirectory.appending(path: "player-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"coins": 1234}"#.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)

        let store = PlayerStore(fileURL: url)
        #expect(store.data.coins == Economy.startingCoins)
        #expect(!store.reloadIfUnreadable(), "still locked")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(store.reloadIfUnreadable())
        #expect(store.data.coins == 1234)
        #expect(!store.reloadIfUnreadable(), "loaded once")

        store.update { $0.coins = 1300 }
        store.saveNow()
        #expect(PlayerStore(fileURL: url).data.coins == 1300)
    }
}

struct AchievementTests {
    @Test func tiersBecomeClaimableInOrder() {
        var data = PlayerData()
        data.stats.levelsCompleted = 150
        var status = AchievementStatus(.trailblazer, data: data)
        #expect(status.reachedTiers == 2)
        #expect(status.isClaimable)
        #expect(status.nextReward == Achievement.tierRewards[0])

        data.claimedTiers[Achievement.trailblazer.id] = 2
        status = AchievementStatus(.trailblazer, data: data)
        #expect(!status.isClaimable)
        #expect(status.target == 500)
    }

    @Test func everyAchievementHasFourIncreasingTiers() {
        for achievement in Achievement.allCases {
            let t = achievement.thresholds
            #expect(t.count == Achievement.tierRewards.count)
            #expect(t == t.sorted() && Set(t).count == t.count, "\(achievement)")
        }
    }

    /// A few texts state a rule in words rather than from `Economy`, because a number would read
    /// worse there. Changing one of these rules means rewording them (in both languages) too.
    @Test func textsThatStateTheRulesInWordsStillMatchThem() {
        #expect(Economy.starburstLetters == 5, "HintKind.starburst's explanation says \"five letters\"")
        #expect(Economy.bonusRichThreshold == 5, "Achievement.thorough's goal says \"5+ bonus words\"")
        #expect(Economy.fastLevelSeconds == 60, "Achievement.quickThinker's goal says \"under a minute\"")
    }
}

struct LocalizationTests {
    @Test func czechTranslationsShip() throws {
        let path = try #require(Bundle.main.path(forResource: "cs", ofType: "lproj"))
        let czech = try #require(Bundle(path: path))
        #expect(czech.localizedString(forKey: "Play", value: nil, table: nil) == "Hrát")
        #expect(czech.localizedString(forKey: "Morning Meadow", value: nil, table: nil) == "Ranní louka")
    }

    /// Czech has three plural forms in everyday use (1 slovo, 3 slova, 5 slov).
    @Test func czechPluralsAgreeWithTheirNumber() throws {
        let path = try #require(Bundle.main.path(forResource: "cs", ofType: "lproj"))
        let czech = try #require(Bundle(path: path))
        let locale = Locale(identifier: "cs")
        func format(_ key: String, _ value: Int) -> String {
            String(format: czech.localizedString(forKey: key, value: nil, table: nil), locale: locale, value)
        }
        #expect(format("Words need at least %lld letters", 3) == "Slovo musí mít aspoň 3 písmena")
        #expect(format("%lld unique words collected in Czech.", 1) == "1 nasbírané slovo v češtině.")
        #expect(format("%lld unique words collected in Czech.", 4) == "4 nasbíraná slova v češtině.")
        #expect(format("%lld unique words collected in English.", 25) == "25 nasbíraných slov v angličtině.")
    }

    @Test func romanNumerals() {
        #expect(RomanNumeral.string(for: 2) == "II")
        #expect(RomanNumeral.string(for: 14) == "XIV")
    }
}

struct ReminderTests {
    var settings: PlayerSettings {
        var settings = PlayerSettings()
        settings.reminderEnabled = true
        settings.reminderHour = 19
        settings.reminderMinute = 30
        return settings
    }

    func today(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
    }

    @Test func oneReminderADayFromToday() {
        let noon = today(hour: 12)
        let requests = ReminderScheduler.requests(settings: settings, solvedToday: false, now: noon)
        #expect(requests.count == 56)
        #expect(requests.first?.identifier == ReminderScheduler.prefix + DailySchedule.key(for: noon))
        let trigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 19 && trigger?.dateComponents.minute == 30)
        #expect(trigger?.dateComponents.timeZone == nil, "local time, wherever the player is")
    }

    @Test func noReminderForASolvedOrPastToday() {
        let noon = today(hour: 12)
        let solved = ReminderScheduler.requests(settings: settings, solvedToday: true, now: noon)
        let late = ReminderScheduler.requests(settings: settings, solvedToday: false, now: today(hour: 21))
        for requests in [solved, late] {
            #expect(requests.count == 55)
            #expect(requests.allSatisfy { $0.identifier != ReminderScheduler.prefix + DailySchedule.key(for: noon) })
        }
        var off = settings
        off.reminderEnabled = false
        #expect(ReminderScheduler.requests(settings: off, solvedToday: false, now: noon).isEmpty)
    }

    /// Most activations change nothing, and then the schedule is left alone.
    @Test func anUnchangedScheduleIsRecognised() {
        let noon = today(hour: 12)
        let wanted = ReminderScheduler.requests(settings: settings, solvedToday: false, now: noon)
        #expect(ReminderScheduler.isScheduled(wanted, as: wanted.reversed()))
        var later = settings
        later.reminderMinute = 45
        #expect(!ReminderScheduler.isScheduled(ReminderScheduler.requests(settings: later, solvedToday: false, now: noon),
                                               as: wanted))
        #expect(!ReminderScheduler.isScheduled(Array(wanted.dropFirst()), as: wanted))
        #expect(ReminderScheduler.isScheduled([], as: []))
    }
}
