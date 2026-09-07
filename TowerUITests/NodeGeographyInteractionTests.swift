import XCTest

@MainActor
final class NodeGeographyInteractionTests: XCTestCase {
    func testSetAndClearCountryInDetails() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let node = app.staticTexts["香港 · 高速 01"].firstMatch
        for _ in 0..<5 {
            if node.exists && node.isHittable { break }
            app.swipeUp()
        }
        if !node.isHittable {
            let source = app.staticTexts["云帆机场"].firstMatch
            if source.exists { source.tap() }
        }
        XCTAssertTrue(node.waitForExistence(timeout: 5))
        node.press(forDuration: 1)
        let details = app.buttons["节点详情"]
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        details.tap()
        app.buttons["设置地区"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("SG")
        let singapore = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "新加坡")).firstMatch
        XCTAssertTrue(singapore.waitForExistence(timeout: 3))
        singapore.tap()
        XCTAssertTrue(app.staticTexts["手动地区"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "node-manual-region"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["设置地区"].tap()
        app.buttons["自动识别"].tap()
        XCTAssertTrue(app.staticTexts["名称地区"].waitForExistence(timeout: 3))
    }
}
