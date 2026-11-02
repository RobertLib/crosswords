import SwiftUI

/// The title screen: where the journey continues and the daily puzzle waits.
struct HomeView: View {
    enum Destination: Hashable { case journey, daily, lexicon, trophies }

    @Environment(AppModel.self) private var app
    /// Heterogeneous, because the journey pushes `Chapter` values on top of `Destination`s.
    @State private var path = NavigationPath()
    @State private var showingSettings = false
    @State private var titleFloat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At the accessibility text sizes rows stack, so that no label is squeezed letter by letter.
    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack(path: $path) {
            let chapter = app.currentChapter
            ZStack {
                // Paused while a game covers the screen, to save battery.
                SceneryView(scene: chapter.scene, animated: app.activeGame == nil)
                    .ignoresSafeArea()
                    .id(chapter.scene.id)
                LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom)
                    .ignoresSafeArea()

                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 16) {
                            topBar
                            Spacer(minLength: 12)
                            title
                            Spacer(minLength: 24)
                            journeyCard(chapter: chapter)
                            dailyCard
                            tiles
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .frame(maxWidth: 560, minHeight: geometry.size.height)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .journey: JourneyView()
                case .daily: DailyView()
                case .lexicon: LexiconView()
                case .trophies: TrophiesView()
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            // A game opened from elsewhere (the daily reminder) can't cover a sheet; SwiftUI would
            // hold it back until the sheet is closed. So the sheet makes way.
            .onChange(of: app.activeGame?.id) { _, game in
                if game != nil { showingSettings = false }
            }
            #if DEBUG
            .task {
                switch UserDefaults.standard.string(forKey: "debugRoute") {
                case "journey": path.append(Destination.journey)
                case "chapter":
                    path.append(Destination.journey)
                    path.append(app.currentChapter)
                case "dailyHub": path.append(Destination.daily)
                case "lexicon": path.append(Destination.lexicon)
                case "trophies": path.append(Destination.trophies)
                case "settings": showingSettings = true
                default: break
                }
                DebugLaunch.screenAppeared(nil)
            }
            #endif
        }
        .tint(app.currentChapter.scene.tint)
    }

    private var topBar: some View {
        HStack {
            RoundIconButton(symbol: "gearshape.fill", label: "Settings") {
                app.sound.play(.tap)
                showingSettings = true
            }
            Spacer()
            CoinBadge(amount: app.data.coins)
        }
        .padding(.top, 8)
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text(verbatim: "Wordwander")
                .font(.game(46, weight: .black))
                .foregroundStyle(.white)
                .legibleOnScenery()
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .offset(y: titleFloat ? -4 : 4)
            Text("A journey through words")
                .font(.game(.headline, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .legibleOnScenery()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { titleFloat = true }
        }
    }

    private func journeyCard(chapter: Chapter) -> some View {
        let completed = app.progress.completedLevels
        let inChapter = max(0, min(chapter.levelRange.count, completed - chapter.levelRange.lowerBound))
        let header = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                header {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.chapterTitle(chapter))
                            .font(.game(.title3, weight: .heavy))
                        Text("Chapter \(chapter.index + 1)")
                            .font(.game(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if !stacks { Spacer() }
                    Button {
                        path.append(Destination.journey)
                    } label: {
                        Label("Map", systemImage: "map.fill")
                            .font(.game(.subheadline, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                ChapterProgressDots(total: chapter.levelRange.count, completed: inChapter, accent: chapter.scene.tint)
                if app.isJourneyComplete {
                    Text("You've completed every level. Replay any level from the map!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    PrimaryButton(title: "Play level \(String(app.nextLevel + 1))", symbol: "play.fill", tint: chapter.scene.accent) {
                        app.playNextLevel()
                    }
                }
            }
        }
    }

    private var dailyCard: some View {
        let row = stacks ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 14))
        return Panel {
            row {
                // The calendar and the streak. A button rather than a tap gesture on the card,
                // so that VoiceOver can open it too.
                Button {
                    path.append(Destination.daily)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(Palette.flameFill.gradient)
                            VStack(spacing: 0) {
                                Text(app.today.formatted(.dateTime.month(.abbreviated)).uppercased())
                                    .font(.game(10, weight: .heavy))
                                Text(app.today.formatted(.dateTime.day()))
                                    .font(.game(22, weight: .black))
                            }
                            .foregroundStyle(.white)
                        }
                        .frame(width: 54, height: 54)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Daily Puzzle")
                                .font(.game(.headline, weight: .heavy))
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(app.currentStreak > 0 ? Palette.flame : .secondary)
                                if app.currentStreak > 0 {
                                    Text("\(app.currentStreak)-day streak")
                                } else {
                                    Text("Start a streak today")
                                }
                            }
                            .font(.game(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(.rect)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                if app.isDailySolvedToday {
                    Button {
                        path.append(Destination.daily)
                    } label: {
                        Label("Solved", systemImage: "checkmark.circle.fill")
                            .font(.game(.subheadline, weight: .heavy))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Palette.success)
                } else {
                    Button {
                        app.playDaily()
                    } label: {
                        Text("Play")
                            .font(.game(.headline, weight: .heavy))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Palette.flameFill)
                }
            }
        }
    }

    private var tiles: some View {
        let row = stacks ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return row {
            tile("Journey", symbol: "map.fill", destination: .journey)
            tile("Lexicon", symbol: "books.vertical.fill", destination: .lexicon)
            tile("Trophies", symbol: "trophy.fill", destination: .trophies, badge: app.claimableAchievements)
        }
    }

    private func tile(_ title: LocalizedStringResource, symbol: String, destination: Destination, badge: Int = 0) -> some View {
        Button {
            app.sound.play(.tap)
            path.append(destination)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(app.currentChapter.scene.tint)
                Text(title)
                    .font(.game(.subheadline, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.regularMaterial, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.4)))
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.game(13, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Palette.flameFill, in: .capsule)
                        .offset(x: 4, y: -6)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityValue(badge > 0 ? Text("\(badge) rewards to claim") : Text(verbatim: ""))
    }
}

/// Twelve pips showing progress through a chapter.
struct ChapterProgressDots: View {
    let total: Int
    let completed: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < completed ? accent : Color.primary.opacity(0.12))
                    .frame(height: 8)
                    .overlay {
                        if index == completed {
                            Capsule().strokeBorder(accent, lineWidth: 2)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(completed) of \(total) levels completed"))
    }
}
