import Testing
@testable import crosswords

/// C A T
/// · · E
/// · · A
struct LevelSessionTests {
    static let puzzle = Puzzle(
        letters: Array("CATE"),
        words: [
            PlacedWord(text: "CAT", start: GridPoint(row: 0, col: 0), direction: .across),
            PlacedWord(text: "TEA", start: GridPoint(row: 0, col: 2), direction: .down),
        ],
        bonus: ["ACT", "ATE", "EAT"])

    func makeSession() -> LevelSession {
        LevelSession(source: .level(0), puzzle: Self.puzzle)
    }

    @Test func findingAWordRevealsItsCells() {
        let session = makeSession()
        let result = session.submit("CAT")
        #expect(result == .found(word: "CAT", revealed: [GridPoint(row: 0, col: 0), GridPoint(row: 0, col: 1), GridPoint(row: 0, col: 2)]))
        #expect(session.isVisible(GridPoint(row: 0, col: 2)))
        #expect(!session.isVisible(GridPoint(row: 1, col: 2)))
        #expect(!session.isComplete)
    }

    @Test func crossingLettersAreNotRevealedTwice() {
        let session = makeSession()
        _ = session.submit("CAT")
        #expect(session.submit("TEA") == .found(word: "TEA", revealed: [GridPoint(row: 1, col: 2), GridPoint(row: 2, col: 2)]))
        #expect(session.isComplete)
    }

    @Test func repeatsBonusAndInvalidWords() {
        let session = makeSession()
        _ = session.submit("CAT")
        #expect(session.submit("CAT") == .alreadyFound(word: "CAT"))
        #expect(session.submit("EAT") == .bonus("EAT"))
        #expect(session.submit("EAT") == .bonusRepeat("EAT"))
        #expect(session.submit("TAC") == .invalid("TAC"))
        #expect(session.submit("AT") == .tooShort)
        #expect(session.bonusFound == ["EAT"])
    }

    @Test func letterHintSpellsTheShortestWordFromTheStart() {
        let session = makeSession()
        #expect(session.revealNextLetter() == GridPoint(row: 0, col: 0))
        #expect(session.revealNextLetter() == GridPoint(row: 0, col: 1))
        #expect(session.hintsUsed == 2)
    }

    @Test func wordsUncoveredByHintsCountAsSolved() {
        let session = makeSession()
        _ = session.submit("CAT")
        #expect(session.reveal(cell: GridPoint(row: 1, col: 2)))
        #expect(!session.reveal(cell: GridPoint(row: 1, col: 2)), "already visible")
        #expect(!session.isComplete)
        session.revealScattered(count: 5)
        #expect(session.isComplete)
        #expect(!session.foundWords.contains("TEA"), "uncovered, not found")
    }

    /// A word uncovered letter by letter (by crossings or, here, hints) has not been found by the
    /// player: spelling it counts as finding it, once.
    @Test func spellingAnUncoveredWordStillFindsIt() {
        let session = makeSession()
        for row in 0..<3 { session.reveal(cell: GridPoint(row: row, col: 2)) }
        #expect(session.solvedWords.contains(1))
        #expect(!session.isComplete)
        #expect(session.submit("TEA") == .found(word: "TEA", revealed: []))
        #expect(session.foundWords.contains("TEA"))
        #expect(session.submit("TEA") == .alreadyFound(word: "TEA"))
    }

    @Test func snapshotRestoresProgress() {
        let session = makeSession()
        _ = session.submit("CAT")
        _ = session.submit("ATE")
        session.reveal(cell: GridPoint(row: 2, col: 2))
        session.elapsed = 42
        let restored = LevelSession(source: .level(0), puzzle: Self.puzzle, snapshot: session.snapshot)
        #expect(restored.foundWords == ["CAT"])
        #expect(restored.bonusFound == ["ATE"])
        #expect(restored.hintedCells == [GridPoint(row: 2, col: 2)])
        #expect(restored.wheelOrder == session.wheelOrder)
        #expect(restored.elapsed == 42)
    }

    @Test func snapshotForAnotherPuzzleIsIgnored() {
        let session = makeSession()
        _ = session.submit("CAT")
        let other = LevelSession(source: .level(1), puzzle: Self.puzzle, snapshot: session.snapshot)
        #expect(other.foundWords.isEmpty)
    }

    @Test func snapshotForADifferentPuzzleAtTheSameLevelIsIgnored() {
        let session = makeSession()
        _ = session.submit("CAT")
        let replacement = Puzzle(letters: Self.puzzle.letters,
                                 words: [PlacedWord(text: "CAT", start: GridPoint(row: 0, col: 0), direction: .down),
                                         PlacedWord(text: "ACE", start: GridPoint(row: 1, col: 0), direction: .across)],
                                 bonus: [])
        let restored = LevelSession(source: .level(0), puzzle: replacement, snapshot: session.snapshot)
        #expect(restored.foundWords.isEmpty)
    }

    @Test func shuffleKeepsTheSameLetters() {
        let session = makeSession()
        let before = session.wheel
        session.shuffle()
        #expect(session.wheel.sorted() == before.sorted())
        #expect(session.wheel != before)
        #expect(session.word(fromLetters: [0, 1, 2]) == "CAT")
    }
}
