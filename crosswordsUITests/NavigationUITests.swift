import XCTest

/// Walks the menus with the debug launch arguments (see README) that fake a player's progress.
final class NavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(route: String, progress: Int = 30) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debugProgress", String(progress), "-debugRoute", route, "-debugLanguage", "en",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    func testChapterOpensFromTheJourneyAndReplaysALevel() {
        let app = launch(route: "journey")
        XCTAssertTrue(app.navigationBars["Journey"].waitForExistence(timeout: 10))

        let chapter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chapter 1,'")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        // A finished chapter or level says so in words; its checkmark doesn't make it "selected".
        XCTAssertEqual(chapter.value as? String, "Completed, 8 levels without hints")
        XCTAssertFalse(chapter.isSelected)
        chapter.tap()
        let firstLevel = app.buttons["Level 1"]
        XCTAssertTrue(firstLevel.waitForExistence(timeout: 5), "the chapter's levels should be listed")
        XCTAssertFalse(firstLevel.isSelected)
        XCTAssertFalse(app.buttons["Level 2"].isSelected)

        firstLevel.tap()
        XCTAssertTrue(app.buttons["Shuffle letters"].waitForExistence(timeout: 5), "the level should open")
        // The game's own back button, not the navigation bar's underneath the cover.
        app.buttons.matching(NSPredicate(format: "label == 'Back' AND identifier != 'BackButton'")).firstMatch.tap()
        XCTAssertTrue(firstLevel.waitForExistence(timeout: 5))
    }

    /// Settings › Spell by tapping: the wheel's letters are tapped one by one, and a button submits.
    @MainActor
    func testSpellingByTapping() {
        let app = launch(route: "settings")
        let toggle = app.switches["Spell by tapping"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let knob = toggle.switches.firstMatch
        if knob.exists {
            knob.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Done"].tap()

        let play = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Play level'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()

        let submit = app.buttons["Submit word"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "a button submits instead of lifting the finger")
        XCTAssertFalse(submit.isEnabled)
        let letter = app.buttons.matching(NSPredicate(format: "label MATCHES '^[A-Z]$'")).firstMatch
        XCTAssertTrue(letter.exists)
        letter.tap()
        XCTAssertTrue(submit.isEnabled, "a tapped letter joins the word")
        letter.tap()
        XCTAssertFalse(submit.isEnabled, "tapping it again takes it back")
    }

    /// The daily puzzle's screen, and the menu tint it is drawn in: SwiftUI resolves colours off
    /// the main thread as well, which once stopped the app right here.
    @MainActor
    func testTheDailyPuzzleScreenOpens() {
        let app = launch(route: "dailyHub")
        XCTAssertTrue(app.navigationBars["Daily Puzzle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Previous month"].waitForExistence(timeout: 5))
        app.buttons["Previous month"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testChapterDebugRouteOpensTheCurrentChapter() {
        let app = launch(route: "chapter")
        let levelTile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Level '")).firstMatch
        XCTAssertTrue(levelTile.waitForExistence(timeout: 10))
    }

    /// The journey opens on the current chapter, but only the first time: coming back from a
    /// chapter leaves it where the player had scrolled to.
    @MainActor
    func testTheJourneyKeepsItsPlaceAfterAChapter() {
        let app = launch(route: "journey", progress: 120)
        XCTAssertTrue(app.navigationBars["Journey"].waitForExistence(timeout: 10))
        let current = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chapter 11,'")).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 5) && current.isHittable, "the journey should open on the current chapter")
        for _ in 0..<10 where current.exists && current.isHittable {
            app.swipeDown(velocity: .fast)
        }
        XCTAssertFalse(current.exists && current.isHittable, "scrolling up should leave the current chapter behind")

        // A tap while the list still glides from the last swipe only stops it, so it waits,
        // and is tried again: what is tested is the way back, not the way in.
        Thread.sleep(forTimeInterval: 1.5)
        let chapters = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Chapter '"))
        // A card whole below the navigation bar: one half under it counts as hittable, but a tap
        // at its middle lands on the bar.
        let barBottom = app.navigationBars["Journey"].frame.maxY
        guard let shown = chapters.allElementsBoundByIndex.first(where: { $0.isHittable && $0.frame.minY >= barBottom }) else {
            return XCTFail("no chapter on screen")
        }
        let label = shown.label
        let level = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Level '")).firstMatch
        for _ in 0..<3 where !level.exists {
            app.buttons[label].tap()
            _ = level.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(level.exists, "the chapter should open")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Journey"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 2) && app.buttons[label].isHittable,
                      "back from the chapter, the journey should still show it")
        XCTAssertFalse(current.exists && current.isHittable, "the journey should not jump back to the current chapter")
    }
}
