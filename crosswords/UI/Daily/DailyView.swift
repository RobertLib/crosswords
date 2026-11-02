import SwiftUI

/// The daily puzzle hub: today's status, the streak and a calendar of solved days.
struct DailyView: View {
    @Environment(AppModel.self) private var app
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                todayCard
                streakCard
                calendarCard
            }
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("Daily Puzzle"))
        #if DEBUG
        // Early in a month most of a streak sits on the previous month's page.
        .onAppear {
            let back = UserDefaults.standard.integer(forKey: "debugCalendarBack")
            if back > 0 { shiftMonth(-back) }
            DebugLaunch.screenAppeared("dailyHub")
        }
        #endif
    }

    private var todayCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text(app.today.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.game(.title2, weight: .heavy))
                if app.isDailySolvedToday {
                    Label("Today's puzzle is solved", systemImage: "checkmark.circle.fill")
                        .font(.game(.headline, weight: .bold))
                        .foregroundStyle(Palette.success)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let next = DailySchedule.nextMidnight(after: context.date)
                        Text("Next puzzle in \(Text(next, style: .timer))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Group {
                        if app.isTodayRewarded {
                            Text("You've already solved today's puzzle in another language, so its reward is collected. Bonus words still count.")
                        } else {
                            Text("A new crossword every day. Solve it to earn \(Economy.dailyReward) coins and grow your streak.")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    PrimaryButton(title: "Play today's puzzle", symbol: "play.fill", tint: Palette.flameFill) {
                        app.playDaily()
                    }
                }
            }
        }
    }

    private var streakCard: some View {
        Panel {
            // One container: `Panel` would otherwise give each of the two views a card of its own.
            VStack(spacing: 8) {
                // Side by side, or one under another at the accessibility text sizes.
                let stacks = dynamicTypeSize.isAccessibilitySize
                let row = stacks ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout())
                row {
                    streakStat(value: app.currentStreak, label: "Current streak", highlighted: true)
                    if stacks { Divider() } else { Divider().frame(height: 50) }
                    streakStat(value: app.data.stats.bestStreak, label: "Best streak", highlighted: false)
                    if stacks { Divider() } else { Divider().frame(height: 50) }
                    streakStat(value: app.data.dailyDays.count, label: "Days solved", highlighted: false)
                }
                Text("Every \(Economy.streakMilestoneDays) days in a row earns \(Economy.streakMilestoneReward) bonus coins.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func streakStat(value: Int, label: LocalizedStringResource, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if highlighted {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Palette.flame)
                }
                Text("\(value)")
                    .font(.game(.title, weight: .black))
                    .monospacedDigit()
            }
            Text(label)
                .font(.game(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var calendarCard: some View {
        Panel {
            VStack(spacing: 12) {
                HStack {
                    Button {
                        shiftMonth(-1)
                    } label: {
                        Image(systemName: "chevron.backward")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(Text("Previous month"))
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.game(.headline, weight: .heavy))
                    Spacer()
                    Button {
                        shiftMonth(1)
                    } label: {
                        Image(systemName: "chevron.forward")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .disabled(Calendar.current.isDate(month, equalTo: app.today, toGranularity: .month))
                    .accessibilityLabel(Text("Next month"))
                }
                .font(.title3.weight(.bold))
                MonthGrid(month: month, solved: app.data.dailyDays, today: app.today)
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let date = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.snappy) { month = date }
        }
    }
}

private struct MonthGrid: View {
    let month: Date
    let solved: Set<String>
    let today: Date

    var body: some View {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: month) ?? 1..<31
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])

        Grid(horizontalSpacing: 6, verticalSpacing: 8) {
            GridRow {
                ForEach(ordered.indices, id: \.self) { index in
                    Text(ordered[index])
                        .font(.game(.caption, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            let cells = Array(repeating: Int?.none, count: leading) + days.map { Optional($0) }
            ForEach(0..<(cells.count + 6) / 7, id: \.self) { week in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        let index = week * 7 + column
                        if index < cells.count, let day = cells[index] {
                            dayCell(day, calendar: calendar)
                        } else {
                            Color.clear.frame(height: 36)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Int, calendar: Calendar) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
        let isSolved = solved.contains(DailySchedule.key(for: date))
        let isToday = calendar.isDate(date, inSameDayAs: today)
        return ZStack {
            if isSolved {
                Circle().fill(Palette.flameFill.gradient)
            } else if isToday {
                Circle().strokeBorder(Palette.flameFill, lineWidth: 2)
            }
            Text("\(day)")
                .font(.game(15, weight: isSolved || isToday ? .heavy : .medium))
                .foregroundStyle(isSolved ? .white : date > today ? .secondary : .primary)
        }
        .frame(width: 36, height: 36)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date.formatted(date: .long, time: .omitted)))
        .accessibilityValue(isSolved ? Text("Solved") : Text(verbatim: ""))
    }
}
