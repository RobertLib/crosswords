import Foundation
import Observation

/// Identifies which puzzle a session is playing.
nonisolated enum PuzzleSource: Hashable, Codable, Sendable {
    /// The next level on the main journey (zero based).
    case level(Int)
    /// Revisiting an already completed level; plays for fun, without level rewards.
    case replay(Int)
    /// The daily puzzle for a `DailySchedule` day key, e.g. "2026-11-02".
    case daily(String)
}

/// Everything needed to resume an unfinished puzzle.
nonisolated struct SessionSnapshot: Codable, Equatable, Sendable {
    var source: PuzzleSource
    /// Wheel slot → index into the puzzle's letters.
    var wheelOrder: [Int]
    var found: [String]
    var hinted: [GridPoint]
    var bonus: [String]
    var hintsUsed: Int
    var elapsed: TimeInterval
    /// `Puzzle.fingerprint` of the puzzle being played.
    var puzzleID: String?
}

nonisolated enum SubmitResult: Equatable, Sendable {
    /// A grid answer, newly found. `revealed` are the cells that were hidden until now.
    case found(word: String, revealed: [GridPoint])
    case alreadyFound(word: String)
    case bonus(String)
    case bonusRepeat(String)
    case invalid(String)
    case tooShort
}

/// The rules of a single puzzle: which words are found, which cells are visible and how
/// hints reveal letters. Contains no economy or presentation logic.
@Observable
final class LevelSession {
    static let minimumWordLength = 3

    let source: PuzzleSource
    let puzzle: Puzzle
    let board: Board

    /// Wheel slot → letter id (an index into `puzzle.letters`). Letter ids stay stable
    /// across shuffles so the wheel can animate letters to their new places.
    private(set) var wheelOrder: [Int]
    private(set) var foundWords: Set<String>
    /// Cells revealed by hints.
    private(set) var hintedCells: Set<GridPoint>
    /// Cells belonging to a solved word (found, or fully uncovered by hints and crossings).
    private(set) var solvedCells: Set<GridPoint> = []
    private(set) var solvedWords: Set<Int> = []
    private(set) var bonusFound: [String]
    private(set) var hintsUsed: Int
    var elapsed: TimeInterval

    init(source: PuzzleSource, puzzle: Puzzle, snapshot: SessionSnapshot? = nil) {
        self.source = source
        self.puzzle = puzzle
        let board = Board(puzzle: puzzle)
        self.board = board
        let restored = snapshot.flatMap { $0.source == source && $0.puzzleID == puzzle.fingerprint ? $0 : nil }
        if let restored, restored.wheelOrder.sorted() == Array(puzzle.letters.indices) {
            wheelOrder = restored.wheelOrder
        } else {
            wheelOrder = Array(puzzle.letters.indices)
        }
        let gridWords = Set(puzzle.words.map(\.text))
        foundWords = Set(restored?.found ?? []).intersection(gridWords)
        hintedCells = Set(restored?.hinted ?? []).filter { board.solution[$0] != nil }
        bonusFound = (restored?.bonus ?? []).filter { puzzle.bonus.contains($0) }
        hintsUsed = restored?.hintsUsed ?? 0
        elapsed = restored?.elapsed ?? 0
        if restored == nil { shuffle() }
        refreshSolved()
    }

    // MARK: - State

    var isComplete: Bool { solvedWords.count == board.words.count }

    /// The wheel letters in slot order.
    var wheel: [Character] { wheelOrder.map { puzzle.letters[$0] } }

    func slot(ofLetter id: Int) -> Int { wheelOrder.firstIndex(of: id) ?? id }

    func word(fromLetters ids: [Int]) -> String {
        String(ids.compactMap { puzzle.letters.indices.contains($0) ? puzzle.letters[$0] : nil })
    }

    func isVisible(_ cell: GridPoint) -> Bool {
        solvedCells.contains(cell) || hintedCells.contains(cell)
    }

    var hiddenCells: [GridPoint] { board.cells.filter { !isVisible($0) } }

    var snapshot: SessionSnapshot {
        SessionSnapshot(source: source, wheelOrder: wheelOrder, found: foundWords.sorted(),
                        hinted: hintedCells.sorted(), bonus: bonusFound, hintsUsed: hintsUsed,
                        elapsed: elapsed, puzzleID: puzzle.fingerprint)
    }

    // MARK: - Playing

    func submit(_ word: String) -> SubmitResult {
        guard word.count >= Self.minimumWordLength else { return .tooShort }
        if let index = board.index(of: word) {
            if foundWords.contains(word) {
                return .alreadyFound(word: word)
            }
            // A word whose letters crossings or hints have uncovered already is solved, but the
            // player has not found it yet: spelling it still counts, with nothing left to reveal.
            let revealed = board.words[index].cells.filter { !isVisible($0) }
            foundWords.insert(word)
            refreshSolved()
            return .found(word: word, revealed: revealed)
        }
        if puzzle.bonus.contains(word) {
            if bonusFound.contains(word) { return .bonusRepeat(word) }
            bonusFound.append(word)
            return .bonus(word)
        }
        return .invalid(word)
    }

    func shuffle() {
        guard Set(puzzle.letters).count > 1 else { return }
        let current = wheel
        repeat { wheelOrder.shuffle() } while wheel == current
    }

    // MARK: - Hints

    /// Reveals the next hidden letter of the shortest unsolved word, so repeated hints
    /// spell a word out from its beginning.
    @discardableResult
    func revealNextLetter() -> GridPoint? {
        let candidates = board.words.indices
            .filter { !solvedWords.contains($0) }
            .sorted { lhs, rhs in
                let a = board.words[lhs], b = board.words[rhs]
                return (a.length, a.start) < (b.length, b.start)
            }
        for index in candidates {
            if let cell = board.words[index].cells.first(where: { !isVisible($0) }) {
                reveal([cell])
                return cell
            }
        }
        return nil
    }

    /// Reveals the chosen cell. Returns false when it was already visible.
    @discardableResult
    func reveal(cell: GridPoint) -> Bool {
        guard board.solution[cell] != nil, !isVisible(cell) else { return false }
        reveal([cell])
        return true
    }

    /// Reveals up to `count` hidden cells, spread over as many different words as possible.
    @discardableResult
    func revealScattered(count: Int) -> [GridPoint] {
        var pool = hiddenCells.shuffled()
        var chosen: [GridPoint] = []
        var touchedWords = Set<Int>()
        while chosen.count < count, !pool.isEmpty {
            let fresh = pool.firstIndex { cell in
                !(board.wordsByCell[cell] ?? []).contains(where: touchedWords.contains)
            }
            let cell = pool.remove(at: fresh ?? 0)
            chosen.append(cell)
            touchedWords.formUnion(board.wordsByCell[cell] ?? [])
        }
        if !chosen.isEmpty { reveal(chosen) }
        return chosen
    }

    private func reveal(_ cells: [GridPoint]) {
        hintedCells.formUnion(cells)
        hintsUsed += 1
        refreshSolved()
    }

    private func refreshSolved() {
        var words = Set<Int>()
        var cells = Set<GridPoint>()
        for (index, word) in board.words.enumerated() {
            let wordCells = word.cells
            // A word also counts as solved once every letter is uncovered by hints or crossings.
            if foundWords.contains(word.text)
                || wordCells.allSatisfy({ hintedCells.contains($0) || isFoundCell($0) }) {
                words.insert(index)
                cells.formUnion(wordCells)
            }
        }
        solvedWords = words
        solvedCells = cells
    }

    private func isFoundCell(_ cell: GridPoint) -> Bool {
        (board.wordsByCell[cell] ?? []).contains { foundWords.contains(board.words[$0].text) }
    }

    // MARK: - Accessibility

    /// "C _ _ E" style pattern of a word, used for VoiceOver.
    func pattern(ofWord index: Int) -> [Character?] {
        board.words[index].cells.map { isVisible($0) ? board.solution[$0] : nil }
    }
}
