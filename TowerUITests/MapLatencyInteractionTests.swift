import XCTest

final class MapLatencyInteractionTests: XCTestCase {
    @MainActor
    func testZoomWhileLatencyTestsRun() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let testButton = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "测试全部节点")).firstMatch
        XCTAssertTrue(testButton.waitForExistence(timeout: 10))
        app.swipeUp()
        testButton.tap()
        let map = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "regions-section", "日本")).firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        for scale in [CGFloat(1.8), 1.5] {
            map.pinch(withScale: scale, velocity: 1)
            let target = scale == 1.8 ? map : app.buttons.matching(
                NSPredicate(format: "identifier == %@ AND label == %@", "regions-section", "香港")
            ).firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            target.tap()
            // Capture after the spring and label-placement completion settle.
            try await Task.sleep(for: .seconds(1))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "map-selected-at-zoom-\(scale)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(app.buttons.matching(identifier: "regions-section").firstMatch.exists)
    }
}
