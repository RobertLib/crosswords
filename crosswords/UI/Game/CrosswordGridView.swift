import SwiftUI

/// The crossword: hidden squares wait as frosted tiles and pop open as words are found.
struct CrosswordGridView: View {
    let controller: GameController
    let accent: Color
    let isNight: Bool

    var body: some View {
        let session = controller.session
        let board = session.board
        GeometryReader { geometry in
            let layout = GridLayout(size: geometry.size, rows: board.rows, cols: board.cols)
            ZStack(alignment: .topLeading) {
                ForEach(board.cells, id: \.self) { point in
                    let targetable = controller.isSpotlightActive && !session.isVisible(point)
                    GridCellView(
                        letter: board.solution[point] ?? " ",
                        state: state(of: point),
                        size: layout.cell,
                        accent: accent,
                        isNight: isNight,
                        revealDelay: controller.freshCells[point] ?? 0,
                        pulseToken: controller.pulse.cells.contains(point) ? controller.pulse.token : 0,
                        isTargetable: targetable)
                    .position(layout.center(of: point))
                    .onTapGesture { controller.tapCell(point) }
                    // While Spotlight waits for a square, VoiceOver can pick any hidden one.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Row \(point.row + 1), column \(point.col + 1)"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { controller.tapCell(point) }
                    .accessibilityHidden(!targetable)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement(children: controller.isSpotlightActive ? .contain : .ignore)
        // Not "Crossword": that key is the Lexicon's filter, translated "from crosswords" in Czech.
        .accessibilityLabel(Text("Crossword grid"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    private func state(of point: GridPoint) -> GridCellView.State {
        let session = controller.session
        if session.solvedCells.contains(point) { return .solved }
        if session.hintedCells.contains(point) { return .hinted }
        return .hidden
    }

    private var accessibilitySummary: String {
        let session = controller.session
        let solved = session.solvedWords.count
        let total = session.board.words.count
        var parts = [String(localized: "\(solved) of \(total) words found.")]
        for index in session.board.words.indices where !session.solvedWords.contains(index) {
            let pattern = session.pattern(ofWord: index)
                .map { $0.map(String.init) ?? String(localized: "blank") }
                .joined(separator: ", ")
            parts.append(String(localized: "\(session.board.words[index].length) letters: \(pattern)."))
        }
        return parts.joined(separator: " ")
    }
}

/// Fits a rows × cols grid into a size, centred, with proportional gaps.
struct GridLayout {
    let cell: CGFloat
    let gap: CGFloat
    let origin: CGPoint

    init(size: CGSize, rows: Int, cols: Int, maxCell: CGFloat = 72) {
        let rows = CGFloat(max(rows, 1)), cols = CGFloat(max(cols, 1))
        let rough = min(size.width / cols, size.height / rows)
        let gap = max(2, rough * 0.09)
        let cell = min(maxCell, (size.width - gap * (cols - 1)) / cols, (size.height - gap * (rows - 1)) / rows)
        self.cell = max(cell, 8)
        self.gap = gap
        let width = cols * self.cell + (cols - 1) * gap
        let height = rows * self.cell + (rows - 1) * gap
        origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
    }

    func center(of point: GridPoint) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(point.col) * (cell + gap) + cell / 2,
                y: origin.y + CGFloat(point.row) * (cell + gap) + cell / 2)
    }
}

struct GridCellView: View {
    enum State { case hidden, hinted, solved }

    let letter: Character
    let state: State
    let size: CGFloat
    let accent: Color
    let isNight: Bool
    let revealDelay: Double
    let pulseToken: Int
    let isTargetable: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var targetGlow = false
    @SwiftUI.State private var bump = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        ZStack {
            shape
                .fill(isNight ? Color.white.opacity(0.18) : Color.white.opacity(0.78))
                .overlay(shape.strokeBorder(isNight ? Color.white.opacity(0.35) : Color.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(isNight ? 0 : 0.12), radius: size * 0.06, y: size * 0.04)

            if state != .hidden {
                ZStack {
                    shape.fill(fill)
                    shape.strokeBorder(.white.opacity(state == .solved ? 0.35 : 0.9), lineWidth: 1)
                    Text(String(letter))
                        .font(.game(size * 0.6, weight: .heavy))
                        .foregroundStyle(state == .solved ? Color.white : accent)
                        .shadow(color: .black.opacity(state == .solved ? 0.18 : 0), radius: 1, y: 1)
                        .minimumScaleFactor(0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.05)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
            }

            if isTargetable {
                shape
                    .strokeBorder(accent, lineWidth: 2.5)
                    // With Reduce Motion the outline stays lit instead of pulsing.
                    .opacity(targetGlow || reduceMotion ? 1 : 0.35)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.7).repeatForever()) { targetGlow = true }
                    }
                    .onDisappear { targetGlow = false }
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.55).delay(revealDelay),
                   value: state)
        .scaleEffect(bump ? 1.16 : 1)
        .onChange(of: pulseToken) { _, token in
            guard token != 0, !reduceMotion else { return }
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { bump = true }
            Task {
                try? await Task.sleep(for: .milliseconds(170))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { bump = false }
            }
        }
        .contentShape(.rect)
    }

    private var fill: AnyShapeStyle {
        switch state {
        case .solved:
            AnyShapeStyle(LinearGradient(colors: [accent.mix(with: .white, by: 0.12), accent],
                                         startPoint: .top, endPoint: .bottom))
        case .hinted, .hidden:
            AnyShapeStyle(Palette.cream)
        }
    }
}
