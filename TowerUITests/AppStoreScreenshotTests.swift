import XCTest

/// Walks the showcase data through the screens used for App Store screenshots.
///
/// Skipped unless `TOWER_SCREENSHOTS=1` reaches the runner (pass it to
/// xcodebuild as `TEST_RUNNER_TOWER_SCREENSHOTS=1`). Screenshots are kept as
/// attachments; export them from the result bundle with
/// `xcrun xcresulttool export attachments`.
@MainActor
final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOWER_SCREENSHOTS"] == "1",
                          "Set TOWER_SCREENSHOTS=1 to capture App Store screenshots.")
        continueAfterFailure = false
    }

    func testCaptureScreens() throws {
        var app = launch(tab: "subscriptions")
        XCTAssertTrue(app.buttons.matching(identifier: "regions-section").firstMatch.waitForExistence(timeout: 20))
        // Let first-launch system banners slide away before the first capture.
        sleep(6)
        capture("1-home", app)

        app = launch(tab: "rules")
        // The card's identifier wins over the inner button's, so find it by label.
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 20))
        customize.tap()
        XCTAssertTrue(app.staticTexts["规则定制"].waitForExistence(timeout: 10))
        sleep(2)
        capture("2-rules", app)

        app = launch(tab: "export")
        let stash = app.buttons["client-clash"]
        XCTAssertTrue(stash.waitForExistence(timeout: 20))
        stash.tap()
        sleep(2)
        capture("3-export", app)

        let preview = app.buttons["preview-config"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        sleep(3)
        capture("4-preview", app)

        app = launch(tab: "export")
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 10))
        sleep(2)
        // Stop as soon as the iCloud card is whole, so the reset row stays below
        // the fold. Slow drags with a hold do not fling past it.
        let restore = app.buttons["恢复同步备份"]
        for _ in 0..<30 {
            if restore.exists, restore.isHittable, restore.frame.maxY < app.frame.height * 0.95 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.54)),
                withVelocity: .slow,
                thenHoldForDuration: 0.3
            )
        }
        sleep(2)
        capture("5-settings", app)
    }

    private func launch(tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["--demo", "--showcase", "--tab=\(tab)", "-hasSeenWelcome", "YES",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        #if targetEnvironment(macCatalyst)
        let screenshot = app.windows.firstMatch.screenshot()
        #else
        let screenshot = XCUIScreen.main.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
