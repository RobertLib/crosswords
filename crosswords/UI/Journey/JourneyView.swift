import SwiftUI

/// Every chapter of the journey, from the first meadow onwards.
struct JourneyView: View {
    @Environment(AppModel.self) private var app
    /// The map opens on the current chapter once. Coming back from a chapter appears the view again,
    /// and scrolling then would throw away where the player had scrolled to.
    @State private var hasScrolled = false

    var body: some View {
        let chapters = app.library.chapters(for: app.language)
        let completed = app.progress.completedLevels
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(chapters) { chapter in
                        let unlocked = chapter.levelRange.lowerBound <= completed
                        NavigationLink(value: chapter) {
                            ChapterCard(chapter: chapter, title: app.chapterTitle(chapter), completed: completed,
                                        perfect: chapter.levelRange.filter(app.progress.perfectLevels.contains).count,
                                        unlocked: unlocked)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                        .disabled(!unlocked)
                        .id(chapter.index)
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                guard !hasScrolled else { return }
                hasScrolled = true
                proxy.scrollTo(app.currentChapter.index, anchor: .center)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("Journey"))
        #if DEBUG
        .onAppear { DebugLaunch.screenAppeared("journey") }
        #endif
        .navigationDestination(for: Chapter.self) { chapter in
            ChapterDetailView(chapter: chapter)
        }
    }
}

private struct ChapterCard: View {
    let chapter: Chapter
    let title: String
    let completed: Int
    let perfect: Int
    let unlocked: Bool

    var body: some View {
        let done = max(0, min(chapter.levelRange.count, completed - chapter.levelRange.lowerBound))
        ZStack(alignment: .bottomLeading) {
            SceneryView(scene: chapter.scene, animated: false)
                .frame(height: 132)
                .saturation(unlocked ? 1 : 0.2)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chapter \(chapter.index + 1)")
                        .font(.game(.caption, weight: .heavy))
                        .opacity(0.85)
                    Text(title)
                        .font(.game(.title3, weight: .heavy))
                    Text("Levels \(String(chapter.levelRange.lowerBound + 1))–\(String(chapter.levelRange.upperBound))")
                        .font(.game(.caption, weight: .semibold))
                        .opacity(0.85)
                }
                Spacer()
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                } else if done == chapter.levelRange.count {
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title)
                            .foregroundStyle(Palette.gold)
                        if perfect > 0 {
                            Label("\(perfect)", systemImage: "crown.fill")
                                .font(.game(.caption, weight: .heavy))
                        }
                    }
                } else {
                    Text("\(done)/\(chapter.levelRange.count)")
                        .font(.game(.headline, weight: .heavy))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.25), in: .capsule)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        // Spoken in words: combined, the card would read its crown count as a bare number, its
        // progress as "0/12", and its checkmark seal as "selected".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Chapter \(chapter.index + 1), \(title), Levels \(String(chapter.levelRange.lowerBound + 1))–\(String(chapter.levelRange.upperBound))"))
        .accessibilityValue(Text(accessibilityValue(done: done)))
    }

    private func accessibilityValue(done: Int) -> String {
        if !unlocked { return String(localized: "Locked") }
        guard done == chapter.levelRange.count else {
            return String(localized: "\(done) of \(chapter.levelRange.count) levels completed")
        }
        return perfect > 0 ? String(localized: "Completed, \(perfect) levels without hints") : String(localized: "Completed")
    }
}

/// The twelve levels of a chapter; finished ones can be replayed.
struct ChapterDetailView: View {
    let chapter: Chapter
    @Environment(AppModel.self) private var app

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 14)]

    var body: some View {
        let completed = app.progress.completedLevels
        ZStack {
            SceneryView(scene: chapter.scene)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text(app.chapterTitle(chapter))
                        .font(.game(.largeTitle, weight: .black))
                        .foregroundStyle(.white)
                        .legibleOnScenery()
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(chapter.levelRange), id: \.self) { level in
                            LevelTile(level: level, completed: completed,
                                      perfect: app.progress.perfectLevels.contains(level),
                                      accent: chapter.scene.accent) {
                                app.replay(level: level)
                            }
                        }
                    }
                    .padding(18)
                    .background(.regularMaterial, in: .rect(cornerRadius: 28))
                    Text("Replays earn no coins, but solving a level without hints still earns its crown.")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .legibleOnScenery()
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .onAppear { DebugLaunch.screenAppeared("chapter") }
        #endif
    }
}

private struct LevelTile: View {
    let level: Int
    let completed: Int
    let perfect: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        let isDone = level < completed
        let isCurrent = level == completed
        Button(action: action) {
            VStack(spacing: 4) {
                Text(verbatim: String(level + 1))
                    .font(.game(24, weight: .black))
                    .minimumScaleFactor(0.6)
                Group {
                    if isDone {
                        Image(systemName: perfect ? "crown.fill" : "checkmark")
                    } else if isCurrent {
                        Image(systemName: "play.fill")
                    } else {
                        Image(systemName: "lock.fill")
                    }
                }
                .font(.system(size: 13, weight: .bold))
                // The value says it; a checkmark would make VoiceOver call the tile "selected".
                .accessibilityHidden(true)
            }
            .foregroundStyle(isDone || isCurrent ? .white : .secondary)
            .frame(width: 76, height: 76)
            .background(isCurrent ? AnyShapeStyle(accent.gradient) : isDone ? AnyShapeStyle(accent.opacity(0.75)) : AnyShapeStyle(Color.primary.opacity(0.08)),
                        in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(isCurrent ? 0.8 : 0.2), lineWidth: isCurrent ? 3 : 1))
        }
        .buttonStyle(PressableStyle())
        .disabled(!isDone && !isCurrent)
        .accessibilityLabel(Text("Level \(String(level + 1))"))
        .accessibilityValue(Text(isDone ? (perfect ? String(localized: "Completed without hints") : String(localized: "Completed"))
                                 : isCurrent ? String(localized: "Next") : String(localized: "Locked")))
    }
}
