import XCTest

@MainActor
final class RuleCustomizationInteractionTests: XCTestCase {
    func testAddManualSwitchCandidate() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tabBars.buttons["规则"].tap()
        app.buttons["编辑 ACL4SSR 默认"].tap()
        let route = app.buttons.matching(NSPredicate(format: "label == %@", "自动选择")).firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let manual = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "手动切换")).firstMatch
        for _ in 0..<5 {
            if manual.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["rule-group-identity-🚀 手动切换"].waitForExistence(timeout: 5))
    }

    func testCatalogRemovalUpdatesCurrentRulesInDefaultEditingMode() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tabBars.buttons["规则"].tap()
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        customize.tap()
        let menu = app.buttons["rule-actions-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "编辑")
        XCTAssertFalse(app.buttons["结束编辑"].exists)
        let identity = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "rule-group-identity-")).firstMatch
        XCTAssertTrue(identity.exists)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("OpenAI")
        let catalog = app.buttons["catalog-entry-acl4ssr-openai"]
        for _ in 0..<6 {
            if catalog.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        catalog.tap()
        let added = NSPredicate(format: "value == %@", "已添加")
        expectation(for: added, evaluatedWith: catalog)
        waitForExpectations(timeout: 30)
        let openAIGroup = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "rule-group-identity-", "OpenAI")).firstMatch
        XCTAssertTrue(openAIGroup.waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["12 组"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "12 个策略组")).firstMatch.exists)
        customize.tap()
        search.tap()
        search.typeText("OpenAI")
        catalog.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: openAIGroup)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(catalog.value as? String, "未添加")
        app.buttons["关闭"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["11 组"].waitForExistence(timeout: 5))
        customize.tap()
        XCTAssertFalse(openAIGroup.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "rule-customization-default-editing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
