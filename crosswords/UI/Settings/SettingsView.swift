import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingReset = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: binding(\.soundEnabled)) {
                        Label("Sound effects", systemImage: "speaker.wave.2.fill")
                    }
                    Toggle(isOn: binding(\.hapticsEnabled)) {
                        Label("Haptics", systemImage: "hand.tap.fill")
                    }
                    Toggle(isOn: binding(\.tapToSpell)) {
                        Label("Spell by tapping", systemImage: "hand.point.up.left.fill")
                    }
                } header: {
                    Text("Game")
                } footer: {
                    Text("Tap the letters one by one and submit the word with a button, instead of swiping. Always on with VoiceOver and Switch Control.")
                }

                Section {
                    Picker(selection: languageBinding) {
                        Text("Automatic (\(PuzzleLanguage.systemDefault.nativeName))").tag(PuzzleLanguage?.none)
                        ForEach(PuzzleLanguage.allCases) { language in
                            Text(verbatim: language.nativeName).tag(PuzzleLanguage?.some(language))
                        }
                    } label: {
                        Label("Puzzle language", systemImage: "character.book.closed.fill")
                    }
                } header: {
                    Text("Puzzles")
                } footer: {
                    Text("Each language has its own journey, daily puzzle and lexicon.")
                }

                Section {
                    Toggle(isOn: reminderBinding) {
                        Label("Daily reminder", systemImage: "bell.fill")
                    }
                    if app.data.settings.reminderEnabled {
                        DatePicker(selection: reminderTime, displayedComponents: .hourAndMinute) {
                            Label("Time", systemImage: "clock")
                        }
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    if notificationsDenied {
                        Text("Notifications are turned off for this app. You can allow them in the Settings app.")
                    } else {
                        Text("A gentle nudge when the daily puzzle is still waiting.")
                    }
                }

                Section {
                    NavigationLink {
                        HowToPlayView()
                    } label: {
                        Label("How to play", systemImage: "questionmark.circle.fill")
                    }
                    NavigationLink {
                        AcknowledgementsView()
                    } label: {
                        Label("Acknowledgements", systemImage: "heart.text.square.fill")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        Label("Reset progress", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Wordwander \(Bundle.main.marketingVersion) · Plays entirely offline.")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
            }
            .navigationTitle(Text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .onAppear { DebugLaunch.screenAppeared("settings") }
            #endif
            // Notifications can be turned off in the Settings app at any time, also while
            // this sheet is open.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                notificationsDenied = await ReminderScheduler.isDenied()
            }
            .task {
                // So that picking another puzzle language doesn't stall the menu behind.
                for language in PuzzleLanguage.allCases { app.library.prefetch(language) }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(Text("Reset all progress?"), isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) {
                    app.store.reset()
                    app.refreshReminders()
                }
            } message: {
                Text("Levels, coins, streaks, achievements and your lexicon will be erased. This cannot be undone.")
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<PlayerSettings, Bool>) -> Binding<Bool> {
        Binding {
            app.data.settings[keyPath: keyPath]
        } set: { value in
            app.store.update { $0.settings[keyPath: keyPath] = value }
            app.applySettings()
            app.haptics.tap()
        }
    }

    private var languageBinding: Binding<PuzzleLanguage?> {
        Binding {
            app.data.settings.puzzleLanguage
        } set: { language in
            app.setPuzzleLanguage(language)
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding {
            app.data.settings.reminderEnabled
        } set: { enabled in
            guard enabled else {
                app.store.update { $0.settings.reminderEnabled = false }
                app.refreshReminders()
                return
            }
            Task {
                let granted = await ReminderScheduler.requestAuthorization()
                notificationsDenied = !granted
                app.store.update { $0.settings.reminderEnabled = granted }
                app.refreshReminders()
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            let settings = app.data.settings
            return Calendar.current.date(bySettingHour: settings.reminderHour, minute: settings.reminderMinute,
                                         second: 0, of: .now) ?? .now
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            app.store.update {
                $0.settings.reminderHour = components.hour ?? 19
                $0.settings.reminderMinute = components.minute ?? 0
            }
            app.refreshReminders()
        }
    }
}

extension Bundle {
    var marketingVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

struct HowToPlayView: View {
    var body: some View {
        List {
            row("hand.draw.fill", "Spell words", "Drag your finger across the letters on the wheel, then lift it. Every word you find fills its place in the crossword.")
            row("hand.point.up.left.fill", "Spell by tapping", "Rather tap than swipe? Turn on Spell by tapping in Settings: tap the letters one by one, then submit the word with a button. It is always on with VoiceOver and Switch Control.")
            row("shuffle", "Shuffle", "Seeing the letters in a new order often reveals a hidden word.")
            row("gift.fill", "Bonus words", "Real words that aren't in the crossword still count. Every \(Economy.giftCapacity) of them opens a gift worth \(Economy.giftReward) coins.")
            ForEach(HintKind.allCases) { hint in
                row(hint.symbol, hint.title, hint.explanation)
            }
            row("crown.fill", "Solve without hints", "Finishing a level without help earns a crown and extra coins.")
            row("flame.fill", "Daily puzzle", "A new puzzle every day. Solve it on consecutive days to build a streak.")
            row("books.vertical.fill", "Lexicon", "Every word you discover is kept in your lexicon, where you can look up its meaning.")
        }
        .navigationTitle(Text("How to play"))
    }

    private func row(_ symbol: String, _ title: LocalizedStringResource, _ text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.game(.headline, weight: .heavy))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                Text("Wordwander was made with care to be calm and fair: no ads, no purchases, no tracking, and it works completely offline.")
            }
            Section {
                credit(Text("ENABLE word list"), "Public domain. English word validation.")
                // ShareAlike: the shipped puzzle packs are adapted from wordfreq, so they carry its licence.
                // Its NOTICE.md asks for the author to be credited as Robyn Speer, and by no other name.
                credit(Text(verbatim: "wordfreq"), "© 2022 Robyn Speer and contributors, github.com/rspeer/wordfreq. Word frequency data, CC BY-SA 4.0 (creativecommons.org/licenses/by-sa/4.0), provided as is, without warranty. The puzzles, their word lists and crosswords alike, are adapted from it and shared under the same licence at github.com/RobertLib/crosswords.")
                // wordfreq's terms ask everything derived from it to credit SUBTLEX and OpenSubtitles.
                credit(Text(verbatim: "SUBTLEX, OpenSubtitles"), "Part of wordfreq's data: the SUBTLEX word lists by Marc Brysbaert et al., which are freely available (crr.ugent.be), and subtitles from OpenSubtitles (opensubtitles.org) through OPUS. wordfreq also draws on Wikipedia, Google Books Ngram Viewer (books.google.com/ngrams), the Leeds Internet Corpus and ParaCrawl.")
                credit(Text("Hunspell dictionaries (en_US, cs_CZ)"), "SCOWL by Kevin Atkinson; Czech dictionary by Petr Kolář, Miroslav Pošta and contributors. Used to check spelling while building the puzzles.")
                // A title, which stays in English.
                credit(Text(verbatim: "List of Dirty, Naughty, Obscene and Otherwise Bad Words"), "© Shutterstock, github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words, CC BY 4.0 (creativecommons.org/licenses/by/4.0). Keeps the puzzles family friendly.")
            } header: {
                Text("Word sources")
            }
        }
        .navigationTitle(Text("Acknowledgements"))
    }

    /// A source's name stays as it is (`Text(verbatim:)`); a description of one is translated.
    private func credit(_ title: Text, _ detail: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
