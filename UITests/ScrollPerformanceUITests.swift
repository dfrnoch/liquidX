import XCTest

/// Measures scrolling smoothness of the home timeline in demo mode.
/// Results include the hitch time ratio (ms of hitches per second of scrolling);
/// Apple considers < 5 ms/s good. Simulator numbers are only indicative.
final class ScrollPerformanceUITests: XCTestCase {
    @MainActor
    func testTimelineScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-LiquidXDemo", "YES", "-LiquidXUITesting", "YES", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Mira Okafor"].firstMatch.waitForExistence(timeout: 10))

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            app.swipeDown(velocity: .fast)
        }
    }
}
