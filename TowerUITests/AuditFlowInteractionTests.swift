import XCTest

@MainActor
final class AuditFlowInteractionTests: XCTestCase {
    private func launch() -> XCUIApplication {
        addUIInterruptionMonitor(withDescription: "Clipboard permission") { alert in
            let deny = alert.buttons["不允许粘贴"]
            guard deny.exists else { return false }
            deny.tap()
            return true
        }
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    func testCancelPreservesDraftUntilExplicitDiscard() {
        let app = launch()
        app.buttons["add-source-button"].tap()
        let input = app.descendants(matching: .any)["source-value-field"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("https://example.invalid/draft")
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(app.alerts["放弃更改？"].waitForExistence(timeout: 3))
        app.alerts.buttons["继续编辑"].tap()
        XCTAssertTrue((input.value as? String)?.contains("example.invalid/draft") == true)
        app.navigationBars.buttons["取消"].tap()
        app.alerts.buttons["放弃更改"].tap()
        XCTAssertTrue(app.buttons["add-source-button"].waitForExistence(timeout: 3))
    }

    func testManualDoneDismissesKeyboard() {
        let app = launch()
        app.buttons["add-source-button"].tap()
        app.buttons["手动添加"].tap()
        let server = app.textFields["manual-server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("example.invalid")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["完成"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    func testEmptyExportRemainsDisabledUntilProtocolIsEnabled() {
        let app = launch()
        app.tabBars.buttons["导出"].tap()
        for id in ["filter-ss", "filter-trojan", "filter-vmess"] {
            let toggle = app.switches[id]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "0")
        }
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["暂时无法导出"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["export-config"].isEnabled)
        app.swipeDown()
        let toggle = app.switches["filter-ss"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["export-config"].isEnabled)
    }

    func testPreviewCopyShowsFeedbackAboveFullScreenCover() {
        let app = launch()
        app.tabBars.buttons["导出"].tap()
        let preview = app.buttons["preview-config"]
        for _ in 0..<6 {
            if preview.exists && preview.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        app.navigationBars.buttons["preview-copy"].tap()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "preview-copy-feedback"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Toast combines its label and icon into one accessible element.
        // Query immediately: waiting a polling interval wastes its short life.
        let toast = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "tower-toast", "配置已复制"
        )).firstMatch
        XCTAssertTrue(toast.exists)
    }
}
