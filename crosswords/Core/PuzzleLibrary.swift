import Foundation
import os

/// A run of consecutive journey levels sharing one landscape.
struct Chapter: Identifiable, Hashable {
    static let size = 12

    let index: Int
    let levelRange: Range<Int>

    var id: Int { index }
    var scene: SceneTheme { SceneTheme.forChapter(index) }
    /// The landscape cycle: chapters 1–24 are the first visit, 25–48 the second…
    var cycle: Int { index / SceneTheme.all.count + 1 }

    static func index(containing level: Int) -> Int { level / size }
}

/// Lazily loads and caches the bundled puzzle packs.
final class PuzzleLibrary {
    private let packs: PackCache

    init(bundle: Bundle = .main) {
        packs = PackCache(bundle: bundle)
    }

    func pack(for language: PuzzleLanguage) -> PuzzlePack { packs.pack(language) }

    /// Decodes a pack in the background ahead of its first use, so that it doesn't stall
    /// the interface (decoding takes tens of milliseconds).
    func prefetch(_ language: PuzzleLanguage) {
        let packs = packs
        Task.detached(priority: .userInitiated) { _ = packs.pack(language) }
    }

    func levelCount(for language: PuzzleLanguage) -> Int { pack(for: language).levels.count }

    func chapterCount(for language: PuzzleLanguage) -> Int {
        (levelCount(for: language) + Chapter.size - 1) / Chapter.size
    }

    func chapter(_ index: Int, language: PuzzleLanguage) -> Chapter {
        let start = index * Chapter.size
        let end = min(start + Chapter.size, levelCount(for: language))
        return Chapter(index: index, levelRange: start..<end)
    }

    func chapters(for language: PuzzleLanguage) -> [Chapter] {
        (0..<chapterCount(for: language)).map { chapter($0, language: language) }
    }

    func puzzle(for source: PuzzleSource, language: PuzzleLanguage) -> Puzzle? {
        let pack = pack(for: language)
        switch source {
        case .level(let index), .replay(let index):
            return pack.levels.indices.contains(index) ? pack.levels[index] : nil
        case .daily(let key):
            guard let date = DailySchedule.date(forKey: key) else { return nil }
            return pack.daily[DailySchedule.puzzleIndex(for: date, count: pack.daily.count)]
        }
    }
}

/// The decoded packs, safe to fill from a background prefetch.
nonisolated private final class PackCache: @unchecked Sendable {
    private let bundle: Bundle
    private let packs = OSAllocatedUnfairLock(initialState: [PuzzleLanguage: PuzzlePack]())
    /// One per language: decoding one pack never blocks reading another, and asking for a pack
    /// that is still being decoded waits for it instead of decoding it twice.
    private let decoding = Dictionary(uniqueKeysWithValues: PuzzleLanguage.allCases.map { ($0, NSLock()) })

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    func pack(_ language: PuzzleLanguage) -> PuzzlePack {
        if let pack = packs.withLock({ $0[language] }) { return pack }
        return decoding[language]!.withLock {
            if let pack = packs.withLock({ $0[language] }) { return pack }
            do {
                let pack = try PuzzlePack.load(language, bundle: bundle)
                packs.withLock { $0[language] = pack }
                return pack
            } catch {
                // The packs ship inside the app; failing to read one is a build defect.
                fatalError("Could not load puzzle pack \(language.rawValue): \(error)")
            }
        }
    }
}
