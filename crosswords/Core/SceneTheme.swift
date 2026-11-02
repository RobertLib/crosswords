import SwiftUI

/// A procedurally drawn landscape. Each chapter of the journey travels through one.
struct SceneTheme: Identifiable, Hashable {
    enum Terrain: Hashable { case mountains, hills, dunes, sea, pines, mesas, forest }
    enum Particles: Hashable { case none, stars, fireflies, snow, petals, leaves, rain, embers, pollen, sparkle }
    enum Celestial: Hashable { case none, sun, moon }

    let id: String
    let name: LocalizedStringResource
    /// Sky gradient from zenith to horizon.
    let sky: [Color]
    let celestial: Celestial
    let celestialColor: Color
    /// Position of the sun or moon in unit coordinates.
    let celestialPosition: UnitPoint
    let terrain: Terrain
    /// Landscape layers from the farthest to the nearest.
    let layers: [Color]
    let particles: Particles
    let particleColor: Color
    let aurora: Bool
    /// Highlight used for the letter wheel and other accents; deep enough for white text on it.
    let accent: Color
    let isNight: Bool

    static func == (lhs: SceneTheme, rhs: SceneTheme) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The accent as the menus' tint: itself in the light appearance, and in the dark one a
    /// brighter shade that stays readable as text on dark cells and materials. Where white text
    /// sits on the colour (filled buttons, the wheel, solved squares), `accent` is the one to use.
    var tint: Color { Self.tints[id] ?? accent }

    private static let tints = Dictionary(uniqueKeysWithValues: all.map { scene in
        (scene.id, Color.adaptive(light: scene.accent, dark: scene.accent.readableOnDark()))
    })

    /// A stable seed for the scene's procedural shapes.
    var seed: UInt64 { id.utf8.reduce(1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 } }

    static func forChapter(_ index: Int) -> SceneTheme { all[index % all.count] }

    static let all: [SceneTheme] = [
        SceneTheme(id: "morningMeadow", name: "Morning Meadow",
                   sky: [.hex(0x7EC8F2), .hex(0xBFE6F7), .hex(0xFCE9C8)],
                   celestial: .sun, celestialColor: .hex(0xFFE8A3), celestialPosition: UnitPoint(x: 0.78, y: 0.2),
                   terrain: .hills, layers: [.hex(0xA9D3A2), .hex(0x84BF84), .hex(0x5FA36A), .hex(0x41824F)],
                   particles: .pollen, particleColor: .hex(0xFFF6C8), aurora: false, accent: .readable(0xEE7B30), isNight: false),
        SceneTheme(id: "mistyPines", name: "Misty Pines",
                   sky: [.hex(0x8FA8B8), .hex(0xB9CBD3), .hex(0xDCE5E6)],
                   celestial: .sun, celestialColor: .hex(0xF4F1E6), celestialPosition: UnitPoint(x: 0.25, y: 0.24),
                   terrain: .pines, layers: [.hex(0xA3B7B9), .hex(0x7F999C), .hex(0x5C7A7D), .hex(0x3D5A5E)],
                   particles: .none, particleColor: .white, aurora: false, accent: .readable(0x2F8A78), isNight: false),
        SceneTheme(id: "goldenDunes", name: "Golden Dunes",
                   sky: [.hex(0xF0A94E), .hex(0xF7CF86), .hex(0xFCEBC2)],
                   celestial: .sun, celestialColor: .hex(0xFFF4D6), celestialPosition: UnitPoint(x: 0.7, y: 0.28),
                   terrain: .dunes, layers: [.hex(0xEBC07A), .hex(0xDFA557), .hex(0xCC8A3F), .hex(0xB0702E)],
                   particles: .sparkle, particleColor: .hex(0xFFF3D1), aurora: false, accent: .readable(0xC2502A), isNight: false),
        SceneTheme(id: "coralLagoon", name: "Coral Lagoon",
                   sky: [.hex(0x4FC3E8), .hex(0x9BE3F0), .hex(0xE2F8F5)],
                   celestial: .sun, celestialColor: .hex(0xFFFBE0), celestialPosition: UnitPoint(x: 0.2, y: 0.2),
                   terrain: .sea, layers: [.hex(0x6CCB9C), .hex(0x2FB0A8), .hex(0x1C97A3), .hex(0xF2DDB0)],
                   particles: .sparkle, particleColor: .white, aurora: false, accent: .readable(0xF2605A), isNight: false),
        SceneTheme(id: "lavenderHills", name: "Lavender Hills",
                   sky: [.hex(0xA79BD8), .hex(0xD4C3EC), .hex(0xF6DDE8)],
                   celestial: .sun, celestialColor: .hex(0xFFF0F5), celestialPosition: UnitPoint(x: 0.65, y: 0.26),
                   terrain: .hills, layers: [.hex(0xBBA8DD), .hex(0x9C84CD), .hex(0x7C64B5), .hex(0x5E4A96)],
                   particles: .petals, particleColor: .hex(0xE9D8FF), aurora: false, accent: .readable(0x8A52CC), isNight: false),
        SceneTheme(id: "autumnValley", name: "Autumn Valley",
                   sky: [.hex(0xF2A365), .hex(0xF8C88C), .hex(0xFBE3C0)],
                   celestial: .sun, celestialColor: .hex(0xFFE2B0), celestialPosition: UnitPoint(x: 0.3, y: 0.3),
                   terrain: .forest, layers: [.hex(0xDB9A5E), .hex(0xC6703A), .hex(0xA3502A), .hex(0x7A3B22)],
                   particles: .leaves, particleColor: .hex(0xE0782E), aurora: false, accent: .readable(0xC0392B), isNight: false),
        SceneTheme(id: "starlitPeaks", name: "Starlit Peaks",
                   sky: [.hex(0x0B1A3A), .hex(0x1E3A6B), .hex(0x3D5A8F)],
                   celestial: .moon, celestialColor: .hex(0xF5F3E6), celestialPosition: UnitPoint(x: 0.75, y: 0.18),
                   terrain: .mountains, layers: [.hex(0x34507E), .hex(0x284369), .hex(0x1C3254), .hex(0x10213D)],
                   particles: .stars, particleColor: .white, aurora: false, accent: .readable(0xE39A2D), isNight: true),
        SceneTheme(id: "cherryBlossom", name: "Cherry Blossom",
                   sky: [.hex(0xF6B8C8), .hex(0xFCDCE4), .hex(0xFFF5F2)],
                   celestial: .sun, celestialColor: .white, celestialPosition: UnitPoint(x: 0.8, y: 0.24),
                   terrain: .forest, layers: [.hex(0xF4AFC0), .hex(0xE58FA6), .hex(0xC9728E), .hex(0xA85A78)],
                   particles: .petals, particleColor: .hex(0xFFD6E2), aurora: false, accent: .readable(0xDB3F76), isNight: false),
        SceneTheme(id: "northernLights", name: "Northern Lights",
                   sky: [.hex(0x05121F), .hex(0x0B2A3B), .hex(0x14455A)],
                   celestial: .none, celestialColor: .white, celestialPosition: .center,
                   terrain: .mountains, layers: [.hex(0x24475A), .hex(0x1A3747), .hex(0x112937), .hex(0x091A24)],
                   particles: .stars, particleColor: .white, aurora: true, accent: .readable(0x16A987), isNight: true),
        SceneTheme(id: "canyonSunset", name: "Canyon Sunset",
                   sky: [.hex(0x5B2A6E), .hex(0xD9574A), .hex(0xF7A35C)],
                   celestial: .sun, celestialColor: .hex(0xFFD27F), celestialPosition: UnitPoint(x: 0.5, y: 0.5),
                   terrain: .mesas, layers: [.hex(0xC0603F), .hex(0x9C4532), .hex(0x763025), .hex(0x4F1F1A)],
                   particles: .none, particleColor: .white, aurora: false, accent: .readable(0xE2932A), isNight: false),
        SceneTheme(id: "frozenFjord", name: "Frozen Fjord",
                   sky: [.hex(0x9ACFEC), .hex(0xD2ECF8), .hex(0xF4FBFF)],
                   celestial: .sun, celestialColor: .white, celestialPosition: UnitPoint(x: 0.3, y: 0.2),
                   terrain: .mountains, layers: [.hex(0xD3E3EE), .hex(0xAFCADC), .hex(0x86A9C4), .hex(0x5F86A6)],
                   particles: .snow, particleColor: .white, aurora: false, accent: .readable(0x2F7BE0), isNight: false),
        SceneTheme(id: "fireflyForest", name: "Firefly Forest",
                   sky: [.hex(0x0E1F1A), .hex(0x173A2E), .hex(0x24533F)],
                   celestial: .moon, celestialColor: .hex(0xEAF7D6), celestialPosition: UnitPoint(x: 0.2, y: 0.17),
                   terrain: .pines, layers: [.hex(0x24503D), .hex(0x1B4030), .hex(0x123023), .hex(0x0A1F17)],
                   particles: .fireflies, particleColor: .hex(0xE4FF7A), aurora: false, accent: .readable(0x6E9F1A), isNight: true),
        SceneTheme(id: "tidalShore", name: "Tidal Shore",
                   sky: [.hex(0xFF9A8B), .hex(0xFFC3A0), .hex(0xFFE6CC)],
                   celestial: .sun, celestialColor: .hex(0xFFF1D0), celestialPosition: UnitPoint(x: 0.5, y: 0.44),
                   terrain: .sea, layers: [.hex(0xD98C8C), .hex(0x6595BF), .hex(0x467BA6), .hex(0xEBD5B3)],
                   particles: .sparkle, particleColor: .white, aurora: false, accent: .readable(0xE8505B), isNight: false),
        SceneTheme(id: "emberRidge", name: "Ember Ridge",
                   sky: [.hex(0x2B0F1E), .hex(0x6E1F2B), .hex(0xC2452D)],
                   celestial: .sun, celestialColor: .hex(0xFF9C5B), celestialPosition: UnitPoint(x: 0.7, y: 0.55),
                   terrain: .mountains, layers: [.hex(0x5A1E27), .hex(0x43161E), .hex(0x2E0F15), .hex(0x1C0A0E)],
                   particles: .embers, particleColor: .hex(0xFFB15C), aurora: false, accent: .readable(0xF26B21), isNight: true),
        SceneTheme(id: "moonlitLake", name: "Moonlit Lake",
                   sky: [.hex(0x141E46), .hex(0x2B3A73), .hex(0x51609A)],
                   celestial: .moon, celestialColor: .hex(0xFFFBE8), celestialPosition: UnitPoint(x: 0.68, y: 0.2),
                   terrain: .sea, layers: [.hex(0x2C3768), .hex(0x26346A), .hex(0x1D2A58), .hex(0x121A3A)],
                   particles: .stars, particleColor: .white, aurora: false, accent: .readable(0x5C74E0), isNight: true),
        SceneTheme(id: "springRain", name: "Spring Rain",
                   sky: [.hex(0x8EA7B5), .hex(0xB8C9CF), .hex(0xDCE6E3)],
                   celestial: .none, celestialColor: .white, celestialPosition: .center,
                   terrain: .hills, layers: [.hex(0xADCDA6), .hex(0x8AB383), .hex(0x6A9763), .hex(0x4E7D4B)],
                   particles: .rain, particleColor: .white, aurora: false, accent: .readable(0x3D8AA0), isNight: false),
        SceneTheme(id: "highlandHeather", name: "Highland Heather",
                   sky: [.hex(0x9FB7D6), .hex(0xC9D6E8), .hex(0xEEE7EF)],
                   celestial: .sun, celestialColor: .hex(0xFFF8E6), celestialPosition: UnitPoint(x: 0.22, y: 0.24),
                   terrain: .hills, layers: [.hex(0xB797B8), .hex(0x96709A), .hex(0x765278), .hex(0x5A3C5D)],
                   particles: .pollen, particleColor: .hex(0xF6E7FF), aurora: false, accent: .readable(0xA1407A), isNight: false),
        SceneTheme(id: "desertNight", name: "Desert Night",
                   sky: [.hex(0x1B1035), .hex(0x3B2160), .hex(0x6A3F7A)],
                   celestial: .moon, celestialColor: .hex(0xFFE9C4), celestialPosition: UnitPoint(x: 0.3, y: 0.19),
                   terrain: .dunes, layers: [.hex(0x5E3869), .hex(0x4A2B58), .hex(0x372044), .hex(0x241430)],
                   particles: .stars, particleColor: .white, aurora: false, accent: .readable(0xE8783A), isNight: true),
        SceneTheme(id: "emeraldIsles", name: "Emerald Isles",
                   sky: [.hex(0x6FD3D6), .hex(0xB5EBDF), .hex(0xF0FBF2)],
                   celestial: .sun, celestialColor: .hex(0xFFFDE8), celestialPosition: UnitPoint(x: 0.75, y: 0.2),
                   terrain: .sea, layers: [.hex(0x4CB98A), .hex(0x2BA4A0), .hex(0x1A8C99), .hex(0xE7E2B8)],
                   particles: .sparkle, particleColor: .white, aurora: false, accent: .readable(0x0E9470), isNight: false),
        SceneTheme(id: "silentSnowfall", name: "Silent Snowfall",
                   sky: [.hex(0x8E9AAF), .hex(0xB8C1D1), .hex(0xDDE2EA)],
                   celestial: .none, celestialColor: .white, celestialPosition: .center,
                   terrain: .pines, layers: [.hex(0xCAD2DE), .hex(0xAEB8C8), .hex(0x93A0B4), .hex(0x77869C)],
                   particles: .snow, particleColor: .white, aurora: false, accent: .readable(0x5468D4), isNight: false),
        SceneTheme(id: "roseDawn", name: "Rose Dawn",
                   sky: [.hex(0xF4A7BD), .hex(0xFBD3C4), .hex(0xFFF0D9)],
                   celestial: .sun, celestialColor: .hex(0xFFF6E0), celestialPosition: UnitPoint(x: 0.5, y: 0.47),
                   terrain: .mountains, layers: [.hex(0xDBA7BA), .hex(0xBC839E), .hex(0x9C6683), .hex(0x7B4D67)],
                   particles: .pollen, particleColor: .white, aurora: false, accent: .readable(0xD13D69), isNight: false),
        SceneTheme(id: "thunderPlains", name: "Thunder Plains",
                   sky: [.hex(0x3E4A5C), .hex(0x6B7889), .hex(0xA2ADB8)],
                   celestial: .none, celestialColor: .white, celestialPosition: .center,
                   terrain: .hills, layers: [.hex(0x8A9773), .hex(0x6F7F5B), .hex(0x556646), .hex(0x3F4F34)],
                   particles: .rain, particleColor: .white, aurora: false, accent: .readable(0xD4A017), isNight: true),
        SceneTheme(id: "velvetDusk", name: "Velvet Dusk",
                   sky: [.hex(0x3A2D5C), .hex(0x8C5A8C), .hex(0xE59B8F)],
                   celestial: .sun, celestialColor: .hex(0xFFD1A6), celestialPosition: UnitPoint(x: 0.62, y: 0.55),
                   terrain: .hills, layers: [.hex(0x8A5A88), .hex(0x6A4470), .hex(0x4A2F54), .hex(0x2E1D36)],
                   particles: .fireflies, particleColor: .hex(0xFFD9A0), aurora: false, accent: .readable(0xE5675A), isNight: true),
        SceneTheme(id: "summitOfLight", name: "Summit of Light",
                   sky: [.hex(0x4A90E2), .hex(0x8CC1F2), .hex(0xE3F2FF)],
                   celestial: .sun, celestialColor: .white, celestialPosition: UnitPoint(x: 0.5, y: 0.16),
                   terrain: .mountains, layers: [.hex(0xB3D0EC), .hex(0x84AAD3), .hex(0x5B86B8), .hex(0x3B6596)],
                   particles: .sparkle, particleColor: .white, aurora: false, accent: .readable(0xE8961C), isNight: false),
    ]
}

extension Color {
    static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: opacity)
    }
}
