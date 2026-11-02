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
}
