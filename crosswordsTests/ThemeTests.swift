import SwiftUI
import Testing
import UIKit
@testable import crosswords

/// White text sits on these colours: letters on solved squares and the wheel, buttons, badges.
struct ThemeTests {
    /// Large white text (buttons, letters) on every landscape's accent, with room for the lighter
    /// top of a button's gradient: WCAG asks 3:1 for large text.
    @Test func whiteTextIsReadableOnEveryAccent() {
        for scene in SceneTheme.all {
            #expect(scene.accent.contrastWithWhite >= 3.59, "\(scene.id): \(scene.accent.contrastWithWhite)")
        }
    }

    /// Small white text (the Play and Claim buttons, badges, the free-hint count): 4.5:1.
    @Test func smallWhiteTextIsReadableOnTheFills() {
        #expect(Palette.flameFill.contrastWithWhite >= 4.49)
        #expect(Palette.success.contrastWithWhite >= 4.49)
        #expect(Palette.bonus.contrastWithWhite >= 3.59)
    }

    /// The app's accent colour tints whatever sets no tint of its own: as a fill behind white text
    /// in the light appearance, and as text on the dark surfaces in the dark one.
    @Test func theAppAccentIsReadableInBothAppearances() {
        let accent = Color("AccentColor")
        #expect(accent.contrastWithWhite >= 4.49)
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        #expect(accent.contrast(with: .hex(Color.darkSurface), in: dark) >= 4.49)
    }

    /// The menus' tint is text and symbols on cells and materials: in the dark appearance it is
    /// brightened until it reads on them (4.5:1), and in the light one it is the accent itself.
    @Test func sceneTintsAreReadableOnDarkSurfaces() {
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        for scene in SceneTheme.all {
            let contrast = scene.tint.contrast(with: .hex(Color.darkSurface), in: dark)
            #expect(contrast >= 4.49, "\(scene.id): \(contrast)")
            // The same colour, give or take the rounding of its trip through UIColor.
            let light = scene.tint.resolve(in: EnvironmentValues()), accent = scene.accent.resolve(in: EnvironmentValues())
            let difference = [light.red - accent.red, light.green - accent.green, light.blue - accent.blue].map(abs).max() ?? 0
            #expect(difference < 0.5 / 255, "\(scene.id)")
        }
    }

    /// SwiftUI resolves colours off the main thread as well; a dynamic colour whose provider were
    /// isolated to the main actor would trap there (it did, on the daily puzzle's screen).
    @Test func sceneTintsResolveOffTheMainThread() async {
        let colors = SceneTheme.all.map { UIColor($0.tint) }
        let resolved = await Task.detached {
            colors.map { $0.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)) }
        }.value
        #expect(resolved.count == SceneTheme.all.count)
    }

    /// Colours that are readable already stay exactly as designed.
    @Test func readableColoursAreLeftAlone() {
        let deep = Color.readable(0xC0392B)
        let resolved = deep.resolve(in: EnvironmentValues())
        let original = Color.hex(0xC0392B).resolve(in: EnvironmentValues())
        #expect(resolved == original)
    }
}
