import Foundation

/// Geometry of a puzzle's crossword grid, derived once from its placed words.
nonisolated struct Board: Sendable {
    let rows: Int
    let cols: Int
    let words: [PlacedWord]
    /// The solution letter of every playable cell.
    let solution: [GridPoint: Character]
    /// Indices into `words` of the words that pass through each cell.
    let wordsByCell: [GridPoint: [Int]]

    init(puzzle: Puzzle) {
        words = puzzle.words
        var solution: [GridPoint: Character] = [:]
        var wordsByCell: [GridPoint: [Int]] = [:]
        for (index, word) in words.enumerated() {
            for (cell, letter) in zip(word.cells, word.letters) {
                solution[cell] = letter
                wordsByCell[cell, default: []].append(index)
            }
        }
        self.solution = solution
        self.wordsByCell = wordsByCell
        rows = (solution.keys.map(\.row).max() ?? -1) + 1
        cols = (solution.keys.map(\.col).max() ?? -1) + 1
    }

    var cells: [GridPoint] { solution.keys.sorted() }

    func index(of text: String) -> Int? { words.firstIndex { $0.text == text } }
}
