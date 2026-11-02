import Foundation

/// The language a puzzle pack is written in.
nonisolated enum PuzzleLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case czech = "cs"

    var id: String { rawValue }

    /// Follows the language the app UI is running in: Czech for Czech users, English otherwise.
    static var systemDefault: PuzzleLanguage {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return preferred.hasPrefix("cs") ? .czech : .english
    }

    /// Endonym, deliberately not localized so people can always find their language.
    var nativeName: String {
        switch self {
        case .english: "English"
        case .czech: "Čeština"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}
