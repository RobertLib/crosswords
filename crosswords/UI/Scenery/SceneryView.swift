import SwiftUI

/// A gently animated, procedurally drawn landscape.
struct SceneryView: View {
    let scene: SceneTheme
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let model = SceneryModel.model(for: scene)
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7_200)
                    SceneryCanvas(model: model, time: time)
                }
            } else {
                SceneryCanvas(model: model, time: 0)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SceneryCanvas: View {
    let model: SceneryModel
    let time: Double

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            model.paint(in: &context, size: size, time: time)
        }
    }
}

/// Precomputed shapes for a scene, in unit coordinates, cached per scene.
struct SceneryModel {
    struct Layer {
        var color: Color
        /// Ridge height samples in unit space (0 = top of view, 1 = bottom).
        var ridge: [Double]
        var trees: [Tree]
        var isWater: Bool
    }

    struct Tree {
        var x: Double
        var height: Double
        var width: Double
    }

    struct Particle {
        var x: Double
        var y: Double
        var size: Double
        var speed: Double
        var phase: Double
        var drift: Double
    }

    struct Cloud {
        var x: Double
        var y: Double
        var scale: Double
        var speed: Double
    }

    let scene: SceneTheme
    let layers: [Layer]
    let stars: [Particle]
    let particles: [Particle]
    let clouds: [Cloud]

    private static var cache: [String: SceneryModel] = [:]
    private static let samples = 96

    static func model(for scene: SceneTheme) -> SceneryModel {
        if let cached = cache[scene.id] { return cached }
        let model = SceneryModel(scene: scene)
        cache[scene.id] = model
        return model
    }

    private init(scene: SceneTheme) {
        self.scene = scene
        var rng = SeededRandom(seed: scene.seed)
        var layers: [Layer] = []
        let count = scene.layers.count
        for (index, color) in scene.layers.enumerated() {
            let depth = Double(index) / Double(max(1, count - 1)) // 0 far … 1 near
            layers.append(Self.makeLayer(scene.terrain, depth: depth, index: index, count: count,
                                         color: color, rng: &rng))
        }
        self.layers = layers

        // A storm hides the stars of a dark sky, and brings its heavy clouds by night as well.
        let rain = scene.particles == .rain
        stars = (0..<(scene.isNight && !rain ? 90 : 0)).map { _ in
            Particle(x: rng.unit(), y: pow(rng.unit(), 1.4) * 0.6, size: rng.range(0.5, 1.8),
                     speed: rng.range(0.6, 2.2), phase: rng.range(0, .pi * 2), drift: rng.unit())
        }
        let particleCount: Int = switch scene.particles {
        case .none, .stars: 0
        case .rain: 70
        case .snow: 60
        case .fireflies: 26
        case .sparkle: 18
        case .pollen: 30
        case .embers: 40
        case .petals, .leaves: 22
        }
        particles = (0..<particleCount).map { _ in
            Particle(x: rng.unit(), y: rng.unit(), size: rng.range(0.6, 1.4), speed: rng.range(0.7, 1.3),
                     phase: rng.range(0, .pi * 2), drift: rng.range(-1, 1))
        }
        let cloudCount = rain ? 5 : scene.isNight ? 0 : 3
        clouds = (0..<cloudCount).map { _ in
            Cloud(x: rng.unit(), y: rng.range(0.08, 0.32), scale: rng.range(0.7, 1.3), speed: rng.range(0.004, 0.009))
        }
    }

    // MARK: - Terrain generation

    private static func makeLayer(_ terrain: SceneTheme.Terrain, depth: Double, index: Int, count: Int,
                                  color: Color, rng: inout SeededRandom) -> Layer {
        let noise = ValueNoise(rng: &rng)
        let baseline = 0.5 + depth * 0.26
        let amplitude = 0.2 - depth * 0.13
        var trees: [Tree] = []
        var isWater = false
        var ridge = [Double](repeating: baseline, count: samples + 1)

        for i in 0...samples {
            let x = Double(i) / Double(samples)
            var h: Double
            switch terrain {
            case .mountains:
                h = noise.ridged(x * (3.2 - depth), octaves: 4)
                h = pow(h, 1.6)
            case .hills, .forest:
                h = noise.fbm(x * (2.2 - depth * 0.8), octaves: 3)
            case .pines:
                h = noise.fbm(x * (2.0 - depth * 0.6), octaves: 2) * 0.8
            case .dunes:
                let f = 1.6 - depth * 0.5
                let w = x * f + noise.fbm(x * 1.2, octaves: 2) * 0.35
                h = 0.5 + 0.5 * sin(2 * .pi * (w + 0.18 * sin(2 * .pi * w)))
            case .mesas:
                let n = noise.fbm(x * (2.4 - depth), octaves: 3)
                h = depth > 0.6 ? n * 0.5 : min(1, max(0, (n - 0.42) * 5)) * 0.9 + n * 0.1
            case .sea:
                h = noise.fbm(x * 2.4, octaves: 3)
            }
            ridge[i] = baseline - amplitude * h
        }

        if terrain == .sea {
            switch index {
            case 0:
                // Distant islands rising out of the water line.
                for i in 0...samples {
                    let x = Double(i) / Double(samples)
                    let island = max(0, noise.fbm(x * 3.1 + 7, octaves: 2) - 0.45) * 2.2
                    ridge[i] = 0.6 - 0.16 * island
                }
            case count - 1:
                // A sandy shore in the foreground.
                for i in 0...samples {
                    let x = Double(i) / Double(samples)
                    ridge[i] = 0.86 + 0.06 * (1 - x) - 0.04 * noise.fbm(x * 2, octaves: 2)
                }
            default:
                isWater = true
                let top = 0.6 + Double(index - 1) * 0.1
                for i in 0...samples { ridge[i] = top }
            }
        }

        if terrain == .pines || terrain == .forest, index > 0 {
            var x = rng.range(0, 0.03)
            let spacing = 0.035 + (1 - depth) * 0.025
            while x < 1.02 {
                if rng.unit() < 0.85 {
                    let scale = 0.6 + depth * 0.9
                    trees.append(Tree(x: x, height: rng.range(0.05, 0.1) * scale, width: rng.range(0.025, 0.04) * scale))
                }
                x += spacing * rng.range(0.6, 1.4)
            }
        }
        return Layer(color: color, ridge: ridge, trees: trees, isWater: isWater)
    }

    // MARK: - Painting

    func paint(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: scene.sky), startPoint: .zero,
                                                        endPoint: CGPoint(x: 0, y: size.height * 0.72)))
        paintStars(in: &context, size: size, time: time)
        if scene.aurora { paintAurora(in: &context, size: size, time: time) }
        paintCelestial(in: &context, size: size, time: time)
        paintClouds(in: &context, size: size, time: time)
        for layer in layers { paintLayer(layer, in: &context, size: size, time: time) }
        paintParticles(in: &context, size: size, time: time)
    }

    private func paintStars(in context: inout GraphicsContext, size: CGSize, time: Double) {
        for star in stars {
            let twinkle = 0.35 + 0.65 * abs(sin(time * star.speed * 0.8 + star.phase))
            let point = CGPoint(x: star.x * size.width, y: star.y * size.height)
            let r = star.size
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(twinkle)))
            if star.size > 1.6 {
                var glint = Path()
                glint.move(to: CGPoint(x: point.x - r * 3, y: point.y))
                glint.addLine(to: CGPoint(x: point.x + r * 3, y: point.y))
                glint.move(to: CGPoint(x: point.x, y: point.y - r * 3))
                glint.addLine(to: CGPoint(x: point.x, y: point.y + r * 3))
                context.stroke(glint, with: .color(.white.opacity(twinkle * 0.5)), lineWidth: 0.6)
            }
        }
    }

    private func paintAurora(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let colors: [Color] = [.hex(0x3DFFB0), .hex(0x2FD5FF), .hex(0xB57CFF)]
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            for (k, color) in colors.enumerated() {
                let band = Double(k)
                var path = Path()
                let steps = 60
                let thickness = size.height * (0.16 - band * 0.03)
                var top: [CGPoint] = []
                for i in 0...steps {
                    let x = Double(i) / Double(steps)
                    let y = 0.16 + band * 0.05
                        + 0.05 * sin(2 * .pi * (x * 1.2 + time * 0.02 + band * 0.3))
                        + 0.025 * sin(2 * .pi * (x * 3.1 - time * 0.035 + band))
                    top.append(CGPoint(x: x * size.width, y: y * size.height))
                }
                path.addLines(top)
                path.addLines(top.reversed().map { CGPoint(x: $0.x, y: $0.y + thickness) })
                path.closeSubpath()
                let shimmer = 0.32 + 0.12 * sin(time * 0.5 + band * 2)
                layer.fill(path, with: .linearGradient(
                    Gradient(colors: [color.opacity(0), color.opacity(shimmer), color.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: size.height * 0.1),
                    endPoint: CGPoint(x: 0, y: size.height * 0.45)))
            }
        }
    }

    private func paintCelestial(in context: inout GraphicsContext, size: CGSize, time: Double) {
        guard scene.celestial != .none else { return }
        let center = CGPoint(x: scene.celestialPosition.x * size.width, y: scene.celestialPosition.y * size.height)
        let unit = min(size.width, size.height * 0.75)
        let glowRadius = unit * (scene.celestial == .sun ? 0.42 : 0.3)
        context.fill(Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius,
                                            width: glowRadius * 2, height: glowRadius * 2)),
                     with: .radialGradient(Gradient(colors: [scene.celestialColor.opacity(0.55), scene.celestialColor.opacity(0)]),
                                           center: center, startRadius: 0, endRadius: glowRadius))
        let radius = unit * (scene.celestial == .sun ? 0.075 : 0.06)
        let disk = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        if scene.celestial == .sun {
            context.fill(disk, with: .color(scene.celestialColor))
        } else {
            context.drawLayer { layer in
                layer.fill(disk, with: .color(scene.celestialColor))
                layer.blendMode = .destinationOut
                let offset = radius * 0.55
                layer.fill(Path(ellipseIn: CGRect(x: center.x - radius + offset, y: center.y - radius - offset * 0.35,
                                                  width: radius * 2, height: radius * 2)),
                           with: .color(.black.opacity(0.92)))
            }
        }
    }

    private func paintClouds(in context: inout GraphicsContext, size: CGSize, time: Double) {
        guard size.width > 0 else { return }
        let heavy = scene.particles == .rain
        for cloud in clouds {
            let width = size.width * 0.38 * cloud.scale
            // The puffs span 0.96 of the width. Each cloud enters fully left of the view and
            // leaves fully right of it, so it never pops in at the edge.
            let span = width * 0.96
            let cycle = 1 + span / size.width
            let x = (cloud.x * cycle + time * cloud.speed).truncatingRemainder(dividingBy: cycle) * size.width - span
            let y = cloud.y * size.height
            let color = heavy ? Color.hex(0x5B6675, opacity: 0.45) : Color.white.opacity(0.38)
            var path = Path()
            let puffs: [(Double, Double, Double)] = [(0, 0.1, 0.35), (0.22, -0.05, 0.42), (0.48, 0.02, 0.36), (0.68, 0.12, 0.28)]
            for (dx, dy, r) in puffs {
                let radius = width * r * 0.5
                path.addEllipse(in: CGRect(x: x + dx * width, y: y + dy * width - radius, width: radius * 2, height: radius * 1.5))
            }
            context.fill(path, with: .color(color))
        }
    }

    private func paintLayer(_ layer: Layer, in context: inout GraphicsContext, size: CGSize, time: Double) {
        var path = Path()
        let count = layer.ridge.count
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, y) in layer.ridge.enumerated() {
            path.addLine(to: CGPoint(x: Double(i) / Double(count - 1) * size.width, y: y * size.height))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()

        if layer.isWater {
            let top = (layer.ridge.first ?? 0.7) * size.height
            context.fill(path, with: .linearGradient(Gradient(colors: [layer.color.opacity(0.95), layer.color]),
                                                     startPoint: CGPoint(x: 0, y: top),
                                                     endPoint: CGPoint(x: 0, y: size.height)))
            // Shimmering wave streaks.
            var streaks = Path()
            for row in 0..<7 {
                let y = top + Double(row + 1) * size.height * 0.018
                let phase = time * (0.06 + Double(row) * 0.01) + Double(row) * 0.37
                for k in 0..<4 {
                    let x = ((Double(k) * 0.29 + phase).truncatingRemainder(dividingBy: 1.2) - 0.1) * size.width
                    streaks.move(to: CGPoint(x: x, y: y))
                    streaks.addLine(to: CGPoint(x: x + size.width * 0.06, y: y))
                }
            }
            context.stroke(streaks, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        } else {
            context.fill(path, with: .color(layer.color))
        }

        guard !layer.trees.isEmpty else { return }
        var trees = Path()
        for tree in layer.trees {
            let sample = min(count - 1, max(0, Int(tree.x * Double(count - 1))))
            let baseY = layer.ridge[sample] * size.height + 2
            let x = tree.x * size.width
            let h = tree.height * size.height
            let w = tree.width * size.width
            if scene.terrain == .pines {
                trees.move(to: CGPoint(x: x, y: baseY - h))
                trees.addLine(to: CGPoint(x: x + w / 2, y: baseY))
                trees.addLine(to: CGPoint(x: x - w / 2, y: baseY))
                trees.closeSubpath()
            } else {
                trees.addEllipse(in: CGRect(x: x - w * 0.6, y: baseY - h, width: w * 1.2, height: h * 0.9))
                trees.addRect(CGRect(x: x - w * 0.06, y: baseY - h * 0.3, width: w * 0.12, height: h * 0.3))
            }
        }
        context.fill(trees, with: .color(layer.color))
    }

    private func paintParticles(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let color = scene.particleColor
        for p in particles {
            switch scene.particles {
            case .none, .stars:
                return
            case .snow:
                let y = wrap(p.y + time * 0.035 * p.speed) * size.height
                let x = wrap(p.x + sin(time * 0.6 + p.phase) * 0.02 + time * 0.005 * p.drift) * size.width
                let r = 1.2 + p.size * 1.6
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity(0.85)))
            case .rain:
                let y = wrap(p.y + time * 0.9 * p.speed) * size.height
                let x = wrap(p.x - time * 0.08 * p.speed) * size.width
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - 3, y: y + 14 * p.size))
                context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 1)
            case .petals, .leaves:
                let y = wrap(p.y + time * 0.03 * p.speed) * size.height
                let x = wrap(p.x + time * 0.02 * p.speed + sin(time * 0.8 + p.phase) * 0.03) * size.width
                let w = (scene.particles == .leaves ? 9 : 6) * p.size
                var inner = context
                inner.translateBy(x: x, y: y)
                inner.rotate(by: .radians(time * 1.2 * p.drift + p.phase))
                let tint = scene.particles == .leaves
                    ? [color, .hex(0xD94A2B), .hex(0xF2B53A)][Int(p.phase * 10) % 3]
                    : color
                inner.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)),
                           with: .color(tint.opacity(0.9)))
            case .fireflies:
                let x = (p.x + 0.04 * sin(time * 0.3 * p.speed + p.phase)) * size.width
                let y = (0.45 + p.y * 0.5 + 0.03 * cos(time * 0.4 * p.speed + p.phase)) * size.height
                let glow = max(0, sin(time * 1.1 * p.speed + p.phase))
                let r = 7 * p.size
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(0.8 * glow), color.opacity(0)]),
                                                   center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
            case .embers:
                let y = wrap(p.y - time * 0.04 * p.speed) * size.height
                let x = wrap(p.x + sin(time * 0.9 + p.phase) * 0.015 + time * 0.006 * p.drift) * size.width
                let flicker = 0.5 + 0.5 * sin(time * 6 * p.speed + p.phase)
                let r = 1 + p.size
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity(0.4 + 0.5 * flicker)))
            case .pollen:
                let x = wrap(p.x + time * 0.006 * p.drift + 0.01 * sin(time * 0.5 + p.phase)) * size.width
                let y = wrap(p.y - time * 0.004 * p.speed + 0.01 * cos(time * 0.4 + p.phase)) * size.height
                let alpha = 0.3 + 0.5 * abs(sin(time * 0.7 + p.phase))
                let r = 1.2 * p.size + 0.6
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(color.opacity(alpha)))
            case .sparkle:
                let cycle = (time * 0.35 * p.speed + p.phase).truncatingRemainder(dividingBy: .pi * 2)
                let intensity = max(0, sin(cycle))
                guard intensity > 0.05 else { continue }
                let x = p.x * size.width
                let y = (0.55 + p.y * 0.4) * size.height
                let r = 5 * p.size * intensity
                var star = Path()
                star.move(to: CGPoint(x: x - r, y: y))
                star.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x, y: y))
                star.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
                star.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x, y: y))
                star.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x, y: y))
                context.fill(star, with: .color(color.opacity(0.85 * intensity)))
            }
        }
    }

    private func wrap(_ value: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: 1)
        return r < 0 ? r + 1 : r
    }
}

/// Smooth 1D value noise with fractal helpers.
private struct ValueNoise {
    private let lattice: [Double]

    init(rng: inout SeededRandom) {
        lattice = (0..<256).map { _ in rng.unit() }
    }

    func value(_ x: Double) -> Double {
        let i = Int(floor(x))
        let f = x - floor(x)
        let a = lattice[((i % 256) + 256) % 256]
        let b = lattice[(((i + 1) % 256) + 256) % 256]
        let t = f * f * (3 - 2 * f)
        return a + (b - a) * t
    }

    func fbm(_ x: Double, octaves: Int) -> Double {
        var sum = 0.0, amplitude = 0.5, frequency = 1.0, norm = 0.0
        for octave in 0..<octaves {
            sum += value(x * frequency + Double(octave) * 17.3) * amplitude
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2.1
        }
        return sum / norm
    }

    func ridged(_ x: Double, octaves: Int) -> Double {
        var sum = 0.0, amplitude = 0.5, frequency = 1.0, norm = 0.0
        for octave in 0..<octaves {
            let n = 1 - abs(value(x * frequency + Double(octave) * 31.7) * 2 - 1)
            sum += n * n * amplitude
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2.2
        }
        return sum / norm
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack {
            ForEach(SceneTheme.all) { scene in
                SceneryView(scene: scene)
                    .frame(width: 200, height: 400)
                    .clipShape(.rect(cornerRadius: 16))
            }
        }
    }
}
