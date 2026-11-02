import Foundation

/// Maps calendar days to daily puzzles and computes streaks. Days are keyed as
/// "yyyy-MM-dd" in the Gregorian calendar and the player's time zone.
nonisolated enum DailySchedule {
    private static let epoch = DateComponents(year: 2026, month: 1, day: 1)

    /// Always Gregorian, so day keys and the puzzle rotation don't depend on (or change with)
    /// the calendar chosen in the system settings.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    static func key(for date: Date, calendar: Calendar = DailySchedule.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(forKey key: String, calendar: Calendar = DailySchedule.calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Days elapsed since the schedule's epoch.
    static func dayNumber(for date: Date, calendar: Calendar = DailySchedule.calendar) -> Int {
        let start = calendar.date(from: epoch) ?? .distantPast
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func puzzleIndex(for date: Date, count: Int, calendar: Calendar = DailySchedule.calendar) -> Int {
        guard count > 0 else { return 0 }
        let day = dayNumber(for: date, calendar: calendar)
        return ((day % count) + count) % count
    }

    /// Consecutive solved days ending today, or ending yesterday when today is not solved yet.
    static func currentStreak(days: Set<String>, today: Date = .now, calendar: Calendar = DailySchedule.calendar) -> Int {
        var day = calendar.startOfDay(for: today)
        if !days.contains(key(for: day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(key(for: day, calendar: calendar)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    static func nextMidnight(after date: Date = .now, calendar: Calendar = DailySchedule.calendar) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0, second: 0),
                          matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
    }
}
