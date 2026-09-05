import XCTest

@MainActor
final class ClientPickerInteractionTests: XCTestCase {
    func testTapSwipeAndLongPressReorder() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-hasSeenWelcome", "YES"]
        app.launch()
        app.tabBars.buttons.element(boundBy: 2).tap()
        let first = app.buttons["client-shadowrocket"]
        let second = app.buttons["client-clash"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        // The current target is restored into view on entry; browse back to
        // the leading cards before testing their gestures.
        for _ in 0..<2 {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 45, dy: first.frame.midY))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 365, dy: first.frame.midY)))
        }
        second.tap()
        assertExportTarget("Stash", in: app)
        first.tap()
        assertExportTarget("Shadowrocket", in: app)

        let origin = first.frame.midX
        let y = first.frame.midY
        // A quick pan must scroll, without changing order or selection.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: second.frame.midX, dy: y))
            .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 25, dy: y)))
        XCTAssertLessThan(first.frame.midX, origin - 20)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 35, dy: y))
            .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 380, dy: y)))

        // Hold before moving: move the first card into the second slot.
        let target = second.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: target)
        XCTAssertGreaterThan(first.frame.midX, second.frame.midX)
        assertExportTarget("Shadowrocket", in: app)
        second.tap()
        assertExportTarget("Stash", in: app)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
        XCTAssertLessThan(first.frame.midX, second.frame.midX)

        // Reorder after scrolling: viewport and content coordinates differ.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 300, dy: y))
            .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 50, dy: y)))
        // Deceleration varies: choose fully visible cards, not an element
        // whose accessibility frame has its center outside the viewport.
        let visible = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'client-'"))
            .allElementsBoundByIndex
            .filter { $0.frame.minX >= 18 && $0.frame.maxX <= app.frame.width - 18 }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard visible.count >= 2 else {
            XCTFail("Expected two fully visible client cards")
            return
        }
        // Bind by stable identity: index-based XCUIElement queries change
        // which card they refer to when the accessibility order changes.
        let source = app.buttons[visible[0].identifier]
        let neighbor = app.buttons[visible[1].identifier]
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: neighbor.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertGreaterThan(source.frame.midX, neighbor.frame.midX)
        assertExportTarget("Stash", in: app)
    }

    private func assertExportTarget(_ name: String, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", name),
            object: app.buttons["export-config"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    func testFilterReorderAddRemoveAndRestart() {
        exerciseFilter(largeText: false)
    }

    func testFilterAtAccessibilityTextSize() {
        exerciseFilter(largeText: true)
    }

    private func exerciseFilter(largeText: Bool) {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "YES", "--tab=export"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        app.tabBars.buttons.element(boundBy: 2).tap()
        let openFilter = app.buttons["open-client-filter"]
        XCTAssertTrue(openFilter.waitForExistence(timeout: 10))
        openFilter.tap()
        let first = app.descendants(matching: .any)["reorder-client:shadowrocket"].firstMatch
        let second = app.descendants(matching: .any)["reorder-client:clash"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(second.isHittable)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.01, thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertGreaterThan(first.frame.midY, second.frame.midY)
        app.buttons["hide-client:shadowrocket"].tap()
        let add = app.buttons["show-client:shadowrocket"]
        guard add.waitForExistence(timeout: 3) else {
            let image = XCTAttachment(screenshot: app.screenshot())
            image.lifetime = .keepAlways
            self.add(image)
            XCTFail("Remove after reorder must create an add row")
            return
        }
        for _ in 0..<12 {
            if add.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(add.isHittable)
        // The blank trailing area, not just the icon/name, must add the row.
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        XCTAssertFalse(add.exists)
        // Background flushes the coalesced write before relaunch.
        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()
        app.tabBars.buttons.element(boundBy: 2).tap()
        app.buttons["open-client-filter"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(first.frame.midY, second.frame.midY)
        XCTAssertTrue(app.buttons["hide-client:shadowrocket"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = largeText ? "filter-accessibility-text" : "filter-restored"
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}
