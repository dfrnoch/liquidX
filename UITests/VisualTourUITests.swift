import XCTest

/// Walks the main screens of the demo and attaches a screenshot of each, so
/// changes can be reviewed visually (`xcrun xcresulttool export attachments`).
final class VisualTourUITests: XCTestCase {
    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LiquidXDemo", "YES", "-LiquidXUITesting", "YES", "-ApplePersistenceIgnoreState", "YES"] + extra
        if let appearance = ProcessInfo.processInfo.environment["LIQUIDX_APPEARANCE"] {
            app.launchArguments += ["-LiquidXAppearance", appearance]
        }
        app.launch()
        return app
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        #if os(macOS)
        let image = app.windows.firstMatch.screenshot()
        #else
        let image = XCUIScreen.main.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testHomeTimeline() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Mira Okafor"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        snapshot(app, "home")
    }

    @MainActor
    func testProfile() {
        let app = launch(["-LiquidXSection", "profile"])
        XCTAssertTrue(app.staticTexts["Ava Lindqvist"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        snapshot(app, "my-profile")
    }

    @MainActor
    func testOtherProfile() {
        let app = launch(["-LiquidXOpenProfile", "miraokafor"])
        XCTAssertTrue(app.buttons["Following"].firstMatch.waitForExistence(timeout: 10)
            || app.buttons["Follow"].firstMatch.waitForExistence(timeout: 2))
        sleep(2)
        snapshot(app, "profile")
    }

    @MainActor
    func testPostDetailAndLike() {
        let app = launch()
        let text = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '@priyacodes'")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        text.tap()
        XCTAssertTrue(app.buttons["Post your reply"].waitForExistence(timeout: 5))
        let like = app.buttons["Like"].firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 5))
        like.tap()
        XCTAssertTrue(app.buttons["Unlike"].firstMatch.waitForExistence(timeout: 3))
        sleep(2)
        snapshot(app, "post-detail")
    }

    @MainActor
    func testCompose() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Mira Okafor"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["New post"].firstMatch.tap()
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Hello from LiquidX ✨")
        sleep(1)
        snapshot(app, "compose")
    }

    @MainActor
    func testSignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-LiquidXUITesting", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Explore the Demo"].waitForExistence(timeout: 10))
        sleep(1)
        snapshot(app, "sign-in")
    }

    @MainActor
    func testDeepLinkedPost() {
        let app = launch(["-LiquidXOpenPost", "2008"])
        XCTAssertTrue(app.buttons["Post your reply"].waitForExistence(timeout: 10))
        sleep(1)
        snapshot(app, "deep-linked-post")
    }

    #if os(iOS)
    /// Leaving and returning to the app refreshes the timeline; posts that
    /// arrive while the reader is scrolled down are announced by a pill.
    @MainActor
    func testNewPostsPill() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Mira Okafor"].firstMatch.waitForExistence(timeout: 10))
        app.swipeUp()
        app.swipeUp()
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        // iPad may activate the scene once more at launch, so more than one
        // demo post can have arrived; the label carries the exact count.
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show ' AND label CONTAINS 'new post'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        snapshot(app, "new-posts-pill")
        pill.tap()
        // Jumped to the top, where the newest arrival was posted "now".
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' · now'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(pill.waitForExistence(timeout: 1))
    }
    #endif
}
