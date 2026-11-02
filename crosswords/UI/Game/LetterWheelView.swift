import SwiftUI

/// The letter wheel. Drag across letters to spell a word; release to submit. When spelling by
/// tapping, each tap adds a letter (the last one tapped again takes it back) and a button submits.
struct LetterWheelView: View {
    let controller: GameController
    let accent: Color
    var spellsByTapping = false

    @State private var fingerLocation: CGPoint?
    @State private var lastSample: CGPoint?
    @State private var dragStart: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let geometry = WheelGeometry(size: geometry.size, count: controller.session.puzzle.letters.count)
            let session = controller.session
            ZStack {
                Circle()
                    .fill(Palette.cream.opacity(0.94))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    .frame(width: geometry.diameter, height: geometry.diameter)
                    .position(geometry.center)

                connectionPath(geometry: geometry)
                    .stroke(accent.opacity(0.85),
                            style: StrokeStyle(lineWidth: geometry.letterSize * 0.18, lineCap: .round, lineJoin: .round))

                // In wheel order, clockwise from the top: VoiceOver reads the letters as they are
                // placed, so that a shuffle reorders them for its users too. Identified by letter,
                // so a shuffled letter glides to its new place.
                ForEach(session.wheelOrder, id: \.self) { id in
                    let selected = controller.selection.contains(id)
                    LetterBubble(letter: session.puzzle.letters[id], isSelected: selected,
                                 size: geometry.letterSize, accent: accent)
                        // Before `position`, which would stretch the tap area over the whole wheel.
                        .contentShape(.circle)
                        .gesture(TapGesture().onEnded { controller.tapLetter(id) },
                                 including: spellsByTapping ? .all : .none)
                        .position(geometry.position(ofSlot: session.slot(ofLetter: id)))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(String(session.puzzle.letters[id])))
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { controller.tapLetter(id) }
                }

                // The hand traces a swipe, which a player spelling by tapping does not make.
                if controller.showSwipeTutorial, !spellsByTapping, let path = tutorialPath(geometry: geometry) {
                    SwipeHint(points: path)
                        .allowsHitTesting(false)
                }

                #if DEBUG
                if let id = controller.demo.finger {
                    DemoHand(size: geometry.letterSize)
                        .position(geometry.position(ofSlot: session.slot(ofLetter: id)))
                        .animation(.easeInOut(duration: 0.2), value: id)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                #endif
            }
            // Shuffled letters glide to their new places, or with Reduce Motion simply appear there.
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75), value: session.wheelOrder)
            .contentShape(Circle().inset(by: -geometry.letterSize * 0.3))
            // Off while spelling by tapping, leaving the letters' own taps.
            .gesture(dragGesture(geometry: geometry), including: spellsByTapping ? .subviews : .all)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func connectionPath(geometry: WheelGeometry) -> Path {
        var path = Path()
        let points = controller.selection.map { geometry.position(ofSlot: controller.session.slot(ofLetter: $0)) }
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if let finger = fingerLocation { path.addLine(to: finger) }
        return path
    }

    private func dragGesture(geometry: WheelGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if value.startLocation != dragStart {
                    // A new drag. One cancelled by the system never reaches `onEnded`,
                    // so drop whatever it left behind.
                    dragStart = value.startLocation
                    lastSample = nil
                    controller.cancelSelection()
                }
                // Walk the segment since the last sample so a fast swipe can't skip a letter.
                let from = lastSample ?? value.location
                let distance = hypot(value.location.x - from.x, value.location.y - from.y)
                let steps = max(1, Int(distance / (geometry.letterSize * 0.25)))
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    track(CGPoint(x: from.x + (value.location.x - from.x) * t, y: from.y + (value.location.y - from.y) * t),
                          geometry: geometry)
                }
                lastSample = value.location
                fingerLocation = controller.selection.isEmpty ? nil : value.location
            }
            .onEnded { _ in
                fingerLocation = nil
                lastSample = nil
                dragStart = nil
                controller.submitSelection()
            }
    }

    private func track(_ point: CGPoint, geometry: WheelGeometry) {
        guard let id = letter(at: point, geometry: geometry) else { return }
        let selection = controller.selection
        if selection.count >= 2, selection[selection.count - 2] == id {
            controller.backtrack()
        } else if selection.last != id {
            controller.connect(id)
        }
    }

    private func letter(at location: CGPoint, geometry: WheelGeometry) -> Int? {
        let session = controller.session
        let hitRadius = geometry.letterSize * 0.55
        return session.puzzle.letters.indices.first { id in
            let center = geometry.position(ofSlot: session.slot(ofLetter: id))
            return hypot(center.x - location.x, center.y - location.y) <= hitRadius
        }
    }

    /// Wheel positions spelling the shortest grid word, for the first-level tutorial.
    private func tutorialPath(geometry: WheelGeometry) -> [CGPoint]? {
        let session = controller.session
        guard let word = session.board.words.indices
            .filter({ !session.solvedWords.contains($0) })
            .map({ session.board.words[$0] })
            .min(by: { $0.length < $1.length }) else { return nil }
        var available = Array(session.puzzle.letters.indices)
        var points: [CGPoint] = []
        for letter in word.letters {
            guard let position = available.firstIndex(where: { session.puzzle.letters[$0] == letter }) else { return nil }
            let id = available.remove(at: position)
            points.append(geometry.position(ofSlot: session.slot(ofLetter: id)))
        }
        return points
    }
}

struct WheelGeometry {
    let center: CGPoint
    let diameter: CGFloat
    let radius: CGFloat
    let letterSize: CGFloat
    let count: Int

    init(size: CGSize, count: Int) {
        let side = min(size.width, size.height)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        diameter = side * 0.96
        self.count = max(count, 1)
        radius = diameter * (count <= 3 ? 0.27 : count <= 5 ? 0.31 : 0.335)
        let chord = 2 * radius * sin(.pi / CGFloat(self.count))
        letterSize = min(diameter * 0.26, chord * 0.86)
    }

    func position(ofSlot slot: Int) -> CGPoint {
        let angle = -CGFloat.pi / 2 + 2 * .pi * CGFloat(slot) / CGFloat(count)
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}

private struct LetterBubble: View {
    let letter: Character
    let isSelected: Bool
    let size: CGFloat
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(accent)
                .scaleEffect(isSelected ? 1 : 0.3)
                .opacity(isSelected ? 1 : 0)
            Text(String(letter))
                .font(.game(size * 0.62, weight: .heavy))
                .foregroundStyle(isSelected ? .white : Palette.ink)
        }
        .frame(width: size, height: size)
        .scaleEffect(isSelected ? 1.06 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isSelected)
    }
}

#if DEBUG
/// The App Preview's finger: the tutorial's hand, its fingertip on the letter.
private struct DemoHand: View {
    let size: CGFloat

    var body: some View {
        // The wheel is cream, so the white hand needs a dark rim to read against it.
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: size * 1.05))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1.5)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .offset(x: size * 0.4, y: size * 0.58)
    }
}
#endif

/// An animated hand tracing a word across the wheel. With Reduce Motion the whole path is
/// drawn at once, the hand resting on its first letter.
private struct SwipeHint: View {
    let points: [CGPoint]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            ZStack {
                trail(upTo: 1)
                    .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                hand.position(position(at: 0))
            }
        } else {
            animated
        }
    }

    private var hand: some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 40))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .offset(x: 14, y: 22)
    }

    private var animated: some View {
        TimelineView(.animation) { context in
            let cycle = 2.6
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
            let travel = min(1, max(0, (t - 0.12) / 0.7))
            let point = position(at: travel)
            ZStack {
                trail(upTo: travel)
                    .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                hand
                    .position(point)
                    .opacity(t > 0.9 ? 0 : 1)
            }
        }
    }

    private func position(at progress: Double) -> CGPoint {
        guard points.count > 1 else { return points.first ?? .zero }
        let scaled = progress * Double(points.count - 1)
        let index = min(points.count - 2, Int(scaled))
        let local = scaled - Double(index)
        let a = points[index], b = points[index + 1]
        return CGPoint(x: a.x + (b.x - a.x) * local, y: a.y + (b.y - a.y) * local)
    }

    private func trail(upTo progress: Double) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let scaled = progress * Double(points.count - 1)
        for index in 1..<points.count where Double(index) <= scaled {
            path.addLine(to: points[index])
        }
        path.addLine(to: position(at: progress))
        return path
    }
}
