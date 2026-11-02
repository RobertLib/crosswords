import SwiftUI

/// The playing screen: landscape, crossword, word preview and letter wheel.
struct GameView: View {
    let controller: GameController
    @State private var showingBonusWords = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Letters are tapped one by one and the word submitted with a button, instead of swiped:
    /// with VoiceOver and Switch Control, which cannot swipe across the wheel, and by choice
    /// (Settings), e.g. with Voice Control or a hand that a swipe is hard for.
    private var spellsByTapping: Bool {
        voiceOver || switchControl || controller.app.data.settings.tapToSpell
    }

    var body: some View {
        let scene = controller.scene
        ZStack {
            SceneryView(scene: scene)
                .ignoresSafeArea()
                .id(scene.id)
                .transition(.opacity)

            LinearGradient(colors: [.clear, .black.opacity(scene.isNight ? 0.25 : 0.12)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            GeometryReader { geometry in
                let wide = geometry.size.width > geometry.size.height * 1.15
                VStack(spacing: 0) {
                    topBar(scene: scene)
                    if wide {
                        HStack(spacing: 24) {
                            board(scene: scene)
                            controls(scene: scene, width: geometry.size.width * 0.42)
                        }
                    } else {
                        board(scene: scene)
                            .frame(maxHeight: .infinity)
                        // The width inside the margins below.
                        controls(scene: scene, width: geometry.size.width - 32)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .id(controller.session.source)
            // The next level slides in, or with Reduce Motion fades in.
            .transition(reduceMotion ? .opacity
                                     : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            if let toast = controller.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 70)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .id(toast.id)
            }

            if let summary = controller.completion {
                LevelCompleteView(summary: summary, scene: scene, onNext: next, onHome: close)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        // The scene's accent rather than the app's: the controls and sheets of the game follow
        // its landscape, and the shade they get stays readable in either appearance.
        .tint(scene.tint)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.toast)
        .animation(.easeInOut(duration: 0.45), value: controller.completion != nil)
        .animation(.easeInOut(duration: 0.5), value: controller.session.source)
        .onAppear {
            controller.resume()
            #if DEBUG
            controller.applyDebugArguments()
            if UserDefaults.standard.string(forKey: "debugSheet") == "bonus" { showingBonusWords = true }
            #endif
        }
        .onDisappear { controller.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.resume() } else { controller.pause() }
        }
        .sheet(isPresented: $showingBonusWords) {
            BonusWordsSheet(words: controller.session.bonusFound, progress: controller.giftProgress,
                            fillsGift: controller.earnsRewards, accent: scene.accent, language: controller.language)
                .presentationDetents([.medium, .large])
        }
        .statusBarHidden(false)
    }

    private func topBar(scene: SceneTheme) -> some View {
        HStack(spacing: 12) {
            RoundIconButton(symbol: "chevron.backward", label: "Back", action: close)
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(controller.title)
                    .font(.game(.headline, weight: .heavy))
                Text(controller.subtitle)
                    .font(.game(.caption, weight: .semibold))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .legibleOnScenery()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            CoinBadge(amount: controller.app.data.coins)
        }
        .padding(.top, 4)
    }

    private func board(scene: SceneTheme) -> some View {
        CrosswordGridView(controller: controller, accent: scene.accent, isNight: scene.isNight)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                if controller.isSpotlightActive {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                        Text("Tap an empty square to reveal it")
                        Button("Cancel") { controller.isSpotlightActive = false }
                            .fontWeight(.heavy)
                            // On the cream banner, which is light in either appearance.
                            .tint(scene.accent)
                    }
                    .font(.game(14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Palette.cream, in: .capsule)
                    .shadow(radius: 6, y: 3)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring, value: controller.isSpotlightActive)
    }

    private func controls(scene: SceneTheme, width: CGFloat) -> some View {
        VStack(spacing: 10) {
            WordPreview(word: controller.previewWord, feedback: controller.feedback, accent: scene.accent)
            if spellsByTapping {
                tapControls(scene: scene)
            }
            if controller.showSwipeTutorial {
                (spellsByTapping ? Text("Tap the letters one by one, then Submit word")
                                 : Text("Swipe across the letters to make a word"))
                    .font(.game(.subheadline, weight: .heavy))
                    .foregroundStyle(.white)
                    .legibleOnScenery()
                    .multilineTextAlignment(.center)
            }
            HStack(alignment: .bottom, spacing: 8) {
                VStack(spacing: 14) {
                    ShuffleButton { controller.shuffle() }
                    GiftButton(progress: controller.giftProgress, bump: controller.giftBump, accent: scene.accent) {
                        controller.app.haptics.tap()
                        showingBonusWords = true
                    }
                }
                .frame(width: 64)
                LetterWheelView(controller: controller, accent: scene.accent, spellsByTapping: spellsByTapping)
                    // What the two button columns and their spacing leave. The first layout pass
                    // can report a zero width.
                    .frame(maxWidth: max(0, min(width - 2 * (64 + 8), width > 700 ? 420 : 330)))
                VStack(spacing: 10) {
                    ForEach(HintKind.allCases) { hint in
                        HintButton(hint: hint, controller: controller, accent: scene.accent)
                    }
                }
                .frame(width: 64)
            }
        }
    }

    private func tapControls(scene: SceneTheme) -> some View {
        HStack {
            Button("Clear") { controller.cancelSelection() }
            Button("Submit word") { controller.submitSelection() }
                .disabled(controller.selection.isEmpty)
        }
        .buttonStyle(.borderedProminent)
        // White text on the accent, which is deep enough for it in either appearance.
        .tint(scene.accent)
    }

    private func next() {
        withAnimation(.easeInOut(duration: 0.5)) {
            if !controller.advance() { close() }
        }
    }

    private func close() {
        controller.pause()
        dismiss()
    }
}

/// The bonus words found in this puzzle, and how the gift works.
struct BonusWordsSheet: View {
    let words: [String]
    let progress: Int
    let fillsGift: Bool
    let accent: Color
    let language: PuzzleLanguage

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "gift.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Palette.goldDeep)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Bonus gift")
                                .font(.game(.headline))
                            Text("Real words that are not in the crossword fill the gift. Every \(Economy.giftCapacity) words opens it for \(Economy.giftReward) coins.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(progress), total: Double(Economy.giftCapacity))
                                .tint(Palette.gold)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    if words.isEmpty {
                        Text("No bonus words in this puzzle yet. Try spelling other words with the wheel!")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(words.sorted(), id: \.self) { word in
                            WordRow(word: word, language: language)
                        }
                    }
                } header: {
                    Text("Found in this puzzle")
                } footer: {
                    if !fillsGift {
                        Text("Bonus words found while replaying a level don't fill the gift.")
                    }
                }
            }
            .navigationTitle(Text("Bonus words"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
