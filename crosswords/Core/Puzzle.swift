import Foundation

/// Orientation of a word in the crossword grid.
nonisolated enum Direction: String, Codable, Sendable {
    case across = "a"
    case down = "d"
}

/// A cell coordinate in the crossword grid (row-major, zero based).
nonisolated struct GridPoint: Hashable, Codable, Sendable, Comparable {
    var row: Int
    var col: Int

    static func < (lhs: GridPoint, rhs: GridPoint) -> Bool {
        (lhs.row, lhs.col) < (rhs.row, rhs.col)
    }
}

/// A word placed in the crossword grid.
nonisolated struct PlacedWord: Decodable, Hashable, Sendable {
    let text: String
    let start: GridPoint
    let direction: Direction

    var letters: [Character] { Array(text) }
    var length: Int { text.count }

    var cells: [GridPoint] {
        (0..<length).map { offset in
            switch direction {
            case .across: GridPoint(row: start.row, col: start.col + offset)
            case .down: GridPoint(row: start.row + offset, col: start.col)
            }
        }
    }

    init(text: String, start: GridPoint, direction: Direction) {
        self.text = text
        self.start = start
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case text = "w", row = "r", col = "c", direction = "d"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        start = GridPoint(row: try container.decode(Int.self, forKey: .row),
                          col: try container.decode(Int.self, forKey: .col))
        direction = try container.decode(Direction.self, forKey: .direction)
    }
}

/// One letter-wheel crossword: the wheel letters, the grid answers and every extra word
/// the wheel can spell.
nonisolated struct Puzzle: Decodable, Hashable, Sendable {
    let letters: [Character]
    let words: [PlacedWord]
    let bonus: Set<String>

    init(letters: [Character], words: [PlacedWord], bonus: Set<String>) {
        self.letters = letters
        self.words = words
        self.bonus = bonus
    }

    private enum CodingKeys: String, CodingKey {
        case letters, words, bonus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        letters = Array(try container.decode(String.self, forKey: .letters))
        words = try container.decode([PlacedWord].self, forKey: .words)
        bonus = Set(try container.decode([String].self, forKey: .bonus))
    }

    /// Identifies the puzzle's content, so saved progress is never applied to a different
    /// puzzle that took its place in an updated pack.
    var fingerprint: String {
        String(letters.sorted()) + ":" + words
            .map { "\($0.text)@\($0.start.row),\($0.start.col)\($0.direction.rawValue)" }
            .sorted()
            .joined(separator: ";")
    }
}

/// A bundled set of puzzles for one language.
nonisolated struct PuzzlePack: Decodable, Sendable {
    static let supportedFormat = 1

    let format: Int
    let language: String
    let levels: [Puzzle]
    let daily: [Puzzle]

    enum LoadError: Error {
        case missingResource(String)
        case unsupportedFormat(Int)
    }

    static func load(_ language: PuzzleLanguage, bundle: Bundle = .main) throws -> PuzzlePack {
        let name = "puzzles-\(language.rawValue)"
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LoadError.missingResource(name)
        }
        let pack = try JSONDecoder().decode(PuzzlePack.self, from: Data(contentsOf: url, options: .mappedIfSafe))
        guard pack.format == supportedFormat else { throw LoadError.unsupportedFormat(pack.format) }
        return pack
    }
}
