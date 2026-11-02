import SwiftUI
import UIKit

/// Every word the player has ever found, with dictionary look-up.
struct LexiconView: View {
    enum Filter: Hashable, CaseIterable {
        case all, crossword, bonus

        var title: LocalizedStringResource {
            switch self {
            case .all: "All"
            case .crossword: "Crossword"
            case .bonus: "Bonus"
            }
        }
    }

    @Environment(AppModel.self) private var app
    @State private var filter = Filter.all
    @State private var query = ""
    @State private var sorter = WordSorter()

    var body: some View {
        let progress = app.progress
        let words = filtered(progress)
        let sections = Dictionary(grouping: words, by: sectionTitle)
        let keys = sections.keys.sorted { $0.compare($1, locale: app.language.locale) == .orderedAscending }

        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                // One sentence per language: Czech declines the language's name ("v češtině").
                switch app.language {
                case .english: Text("\(progress.lexiconSize) unique words collected in English.")
                case .czech:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(progress.lexiconSize) unique words collected in Czech.")
                        // iOS has no Czech dictionary of its own, only a Czech–English one.
                        Text("Their meanings come from the Czech–English dictionary in Settings › General › Dictionary.")
                    }
                }
            }

            if words.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "Your lexicon is empty" : "No matches", systemImage: "books.vertical")
                } description: {
                    Text(query.isEmpty ? "Words you find while playing are collected here." : "Try a different search.")
                }
                .listRowBackground(Color.clear)
            }

            ForEach(keys, id: \.self) { key in
                Section(key) {
                    ForEach(sections[key] ?? [], id: \.self) { word in
                        WordRow(word: word, language: app.language, isBonus: progress.bonusWords.contains(word))
                    }
                }
            }
        }
        .searchable(text: $query, prompt: Text("Search words"))
        .navigationTitle(Text("Lexicon"))
        #if DEBUG
        .onAppear { DebugLaunch.screenAppeared("lexicon") }
        #endif
    }

    private func filtered(_ progress: LanguageProgress) -> [String] {
        let source: Set<String> = switch filter {
        case .all: progress.foundWords.union(progress.bonusWords)
        case .crossword: progress.foundWords
        case .bonus: progress.bonusWords
        }
        let needle = query.trimmingCharacters(in: .whitespaces).uppercased()
        return sorter.sorted(source, locale: app.language.locale)
            .filter { needle.isEmpty || $0.localizedStandardContains(needle) }
    }

    /// The first letter of the alphabet a word is filed under. Czech has Č, Ř, Š, Ž and "CH" (after H)
    /// as letters of their own, and files the other accented letters (Á, Ď, É, Í, Ň, Ó, Ť, Ú, Ý)
    /// under their base letter: "ÚKOL" is among the U words, as in a dictionary.
    private func sectionTitle(_ word: String) -> String {
        let first = String(word.prefix(1))
        guard app.language == .czech else { return first }
        if word.hasPrefix("CH") { return "CH" }
        if "ČŘŠŽ".contains(first) { return first }
        return first.folding(options: .diacriticInsensitive, locale: app.language.locale)
    }
}

/// Remembers the last sorted word list: collating thousands of words takes long enough to
/// make typing in the search field stutter. A class, so that refreshing it while the body is
/// evaluated doesn't invalidate the view.
private final class WordSorter {
    private var source: Set<String> = []
    private var locale: Locale?
    private var result: [String] = []

    func sorted(_ words: Set<String>, locale: Locale) -> [String] {
        if words != source || locale != self.locale {
            source = words
            self.locale = locale
            result = words.sorted { $0.compare($1, locale: locale) == .orderedAscending }
        }
        return result
    }
}

/// A word with a button to open its dictionary definition.
struct WordRow: View {
    let word: String
    let language: PuzzleLanguage
    var isBonus = false
    @State private var showingDefinition = false
    /// Optional: the bonus words sheet in a game shows these rows too.
    @Environment(AppModel.self) private var app: AppModel?

    var body: some View {
        Button {
            showingDefinition = true
        } label: {
            HStack {
                Text(word)
                    .font(.game(.body, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                if isBonus {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Palette.goldDeep)
                        .accessibilityLabel(Text("Bonus word"))
                }
                Spacer()
                Image(systemName: "book.closed")
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityHint(Text("Shows the definition"))
        .sheet(isPresented: $showingDefinition) {
            DefinitionView(term: word.lowercased(with: language.locale), language: language)
                .ignoresSafeArea()
        }
        // Makes way for a game opened by the daily reminder (see HomeView).
        .onChange(of: app?.activeGame?.id) { _, game in
            if game != nil { showingDefinition = false }
        }
    }
}

/// The system dictionary. Works offline with the dictionaries installed on the device. It looks a
/// word up in all of them, so a Czech word that is also English ("den") shows both entries.
struct DefinitionView: View {
    let term: String
    let language: PuzzleLanguage

    var body: some View {
        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
            ReferenceLibraryView(term: term)
        } else {
            NavigationStack {
                ContentUnavailableView {
                    Label(term.uppercased(), systemImage: "book.closed")
                } description: {
                    switch language {
                    case .english:
                        Text("No definition found on this device. You can download more dictionaries in Settings › General › Dictionary.")
                    case .czech:
                        Text("No definition found on this device. For Czech words, download the Czech–English dictionary in Settings › General › Dictionary.")
                    }
                }
                .padding()
            }
            .presentationDetents([.medium])
        }
    }
}

private struct ReferenceLibraryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
