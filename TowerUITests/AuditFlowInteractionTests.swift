import XCTest
import UIKit

@MainActor
final class AuditFlowInteractionTests: XCTestCase {
    func testPersistentExportNameFilter() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["TOWER_PERFORMANCE_NODE_COUNT"] = "30"
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        func openFilter() {
            XCTAssertTrue(app.buttons["source-management-button"].waitForExistence(timeout: 15))
            app.buttons["source-management-button"].tap()
            app.segmentedControls.buttons["导出筛选"].tap()
            app.buttons["node-name-export-filter"].tap()
        }
        openFilter()
        app.buttons["node-keyword-add"].tap()
        let keyword = app.textFields["关键词"].firstMatch
        XCTAssertTrue(keyword.waitForExistence(timeout: 5))
        keyword.typeText("IEPL")
        let save = app.buttons["保存"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "export-name-keyword-filter"
        shot.lifetime = .keepAlways
        add(shot)
        save.tap()
        let filterSummary = app.buttons["node-name-export-filter"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "IEPL"), evaluatedWith: filterSummary)
        waitForExpectations(timeout: 5)
        app.terminate(); app.launch()
        openFilter()
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "IEPL")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["删除关键词 IEPL"].tap()
        XCTAssertTrue(app.buttons["保存"].isEnabled)
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["未设置"].waitForExistence(timeout: 5))
    }

    func testLocalNodeDeletionAndSubscriptionContextMenu() {
        let app = launch()
        let source = app.buttons["展开 云帆机场 的节点"]
        for _ in 0..<6 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.isHittable)
        source.press(forDuration: 0.7)
        let speed = app.buttons["测速"].firstMatch
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        let menuShot = XCTAttachment(screenshot: app.screenshot())
        menuShot.name = "subscription-context-speed-test"
        menuShot.lifetime = .keepAlways
        add(menuShot)
        speed.tap()
        let local = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "展开", "自建")).firstMatch
        for _ in 0..<6 where !local.isHittable { app.swipeUp() }
        XCTAssertTrue(local.isHittable)
        local.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["编辑"].firstMatch.waitForExistence(timeout: 5))
        let localMenuShot = XCTAttachment(screenshot: app.screenshot())
        localMenuShot.name = "local-node-whole-card-menu"
        localMenuShot.lifetime = .keepAlways
        add(localMenuShot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.12)).tap()
        let inclusion = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "node-inclusion-")).firstMatch
        XCTAssertTrue(inclusion.exists)
        XCTAssertEqual(inclusion.frame.midY, local.frame.midY, accuracy: 2)
        for right in [true, false] {
            if right { local.swipeRight() } else { local.swipeLeft() }
            let delete = app.buttons["删除"].firstMatch
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            delete.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.alerts.buttons["取消"].tap()
            XCTAssertEqual(inclusion.frame.midY, local.frame.midY, accuracy: 2)
        }
        local.swipeLeft()
        app.buttons["删除"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["删除"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: local)
        waitForExpectations(timeout: 5)
    }

    func testSubscriptionSwipeDeletionFromBothSides() {
        let app = launchPerformanceFixture()
        let collapsed = app.buttons["展开 云帆机场 的节点"]
        for _ in 0..<6 where !collapsed.isHittable { app.swipeUp() }
        XCTAssertTrue(collapsed.isHittable)
        // The lower summary must respond too, not just the title row.
        let facts = app.staticTexts["60 个节点"].firstMatch
        // The shorter overview card can leave this row under the tab bar.
        // Nudge without momentum: a full swipe pushes the card's top, and
        // its swipe actions, under the navigation bar.
        for _ in 0..<4 where !facts.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
        XCTAssertTrue(facts.isHittable)
        facts.swipeLeft()
        let summaryDelete = app.buttons["删除"].firstMatch
        XCTAssertTrue(summaryDelete.waitForExistence(timeout: 5))
        summaryDelete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        collapsed.tap()
        let header = app.buttons["收起 云帆机场 的节点"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let initialX = header.frame.minX
        header.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["编辑"].firstMatch.waitForExistence(timeout: 5))
        let previewTitle = app.staticTexts["云帆机场"].firstMatch
        XCTAssertTrue(previewTitle.exists)
        XCTAssertGreaterThan(previewTitle.frame.width, 60, "Expanded preview must retain readable width")
        let previewShot = XCTAttachment(screenshot: app.screenshot())
        previewShot.name = "expanded-subscription-bounded-menu"
        previewShot.lifetime = .keepAlways
        add(previewShot)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.12)).tap()
        XCTAssertTrue(header.exists, "Dismissing the menu must preserve expansion")
        for swipeRight in [true, false] {
            if swipeRight { header.swipeRight() } else { header.swipeLeft() }
            let delete = app.buttons["删除"].firstMatch
            XCTAssertTrue(delete.waitForExistence(timeout: 5))
            XCTAssertTrue(delete.isHittable)
            XCTAssertLessThanOrEqual(delete.frame.maxY, app.staticTexts["香港 · Perf 0"].frame.minY)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = swipeRight ? "subscription-leading-delete" : "subscription-trailing-delete"
            shot.lifetime = .keepAlways
            add(shot)
            delete.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.alerts.buttons["取消"].tap()
            XCTAssertTrue(header.exists)
            XCTAssertEqual(header.frame.minX, initialX, accuracy: 2)
        }
        header.swipeLeft()
        app.buttons["删除"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["删除"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: header)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(collapsed.exists)
    }

    func testManagementEmptySearchCancellationKeepsLayout() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["TOWER_PERFORMANCE_NODE_COUNT"] = "300"
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let management = app.buttons["source-management-button"]
        XCTAssertTrue(management.waitForExistence(timeout: 15))
        management.tap()
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let tabs = app.segmentedControls.firstMatch
        let initialY = tabs.frame.minY
        for _ in 0..<3 {
            search.tap()
            // Device keyboards can be hosted by an extension outside app.keyboards.
            expectation(for: NSPredicate { _, _ in
                app.keyboards.firstMatch.exists || search.debugDescription.contains("Keyboard Focused")
            }, evaluatedWith: search)
            waitForExpectations(timeout: 5)
            XCTAssertTrue(app.navigationBars.staticTexts["批量管理"].exists)
            let cancel = app.buttons["关闭"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            cancel.tap()
            XCTAssertTrue(app.buttons["source-management-list"].exists || tabs.exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            XCTAssertEqual(tabs.frame.minY, initialY, accuracy: 3)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "management-empty-search-restored"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testManagementSearchCancellationRestoresNodes() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["TOWER_PERFORMANCE_NODE_COUNT"] = "300"
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let management = app.buttons["source-management-button"]
        XCTAssertTrue(management.waitForExistence(timeout: 15))
        management.tap()
        app.segmentedControls.buttons["导出筛选"].tap()
        let search = app.searchFields.firstMatch
        app.swipeDown()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        for query in ["31", "no-matching-node", "31"] {
            search.tap()
            search.typeText(query)
            let cancel = app.buttons["关闭"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            cancel.tap()
            let count = app.staticTexts["节点 · 300 / 300"]
            XCTAssertTrue(count.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["toggle-all-filtered-nodes"].isEnabled)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "management-search-restored"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSubscriptionRefreshShowsTopStatusAndCanCancel() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["TOWER_REFRESH_UI_TEST"] = "1"
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["add-source-button"].waitForExistence(timeout: 15))
        // The introduction only shows before any source exists; the counts
        // are the card's stable content.
        let summary = app.buttons["overview-subscriptions"].firstMatch
        let originalY = summary.frame.minY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90))
        start.press(forDuration: 0.05, thenDragTo: end)
        let capsule = app.descendants(matching: .any)["subscription-refresh-progress"].firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(capsule.frame.midX, window.midX, accuracy: 8)
        XCTAssertLessThan(capsule.frame.midY, window.midY, "Progress shares the top slot with every other status message")
        // It fits between the navigation buttons, and the page stays usable.
        for id in ["add-source-button", "source-management-button"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable)
            XCTAssertFalse(capsule.frame.intersects(button.frame), "\(id) must stay uncovered")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "subscription-refresh-top-status"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["subscription-refresh-progress-cancel"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: capsule)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(summary.frame.minY, originalY, accuracy: 8, "Pull indicator must retract without shifting the page")
        // A fresh pull after cancellation must run normally and dismiss on success.
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: capsule)
        waitForExpectations(timeout: 25)
        XCTAssertTrue(app.buttons["add-source-button"].isEnabled)
        XCTAssertFalse(app.staticTexts["更新失败"].exists)
        app.terminate()
    }

    private func launch() -> XCUIApplication {
        handleClipboardPermission()
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    private func handleClipboardPermission() {
        addUIInterruptionMonitor(withDescription: "Clipboard permission") { alert in
            let deny = alert.buttons["不允许粘贴"]
            guard deny.exists else { return false }
            deny.tap()
            return true
        }
    }

    private func openAddSource(_ app: XCUIApplication) {
        app.buttons["add-source-button"].tap()
        // iOS 27 may fail to route SpringBoard paste prompts through the
        // interruption monitor. Handle the observed system button directly.
        let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .alerts.buttons["不允许粘贴"]
        if deny.waitForExistence(timeout: 3) { deny.tap() }
    }

    private func launchPerformanceFixture(disableTabHaptics: Bool = false,
                                          disableCardSwipe: Bool = false) -> XCUIApplication {
        handleClipboardPermission()
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["TOWER_PERFORMANCE_NODE_COUNT"] = "1000"
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)"]
        if disableTabHaptics { app.launchArguments.append("--disable-tab-haptics") }
        if disableCardSwipe { app.launchArguments.append("--disable-card-swipe") }
        app.launch()
        // Leave a short unmeasured attach window for the device frame profiler.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(app.buttons["add-source-button"].waitForExistence(timeout: 10))
        print("PERF_DEVICE maxFPS=\(UIScreen.main.maximumFramesPerSecond) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
        let fixtureImage = XCTAttachment(screenshot: app.screenshot())
        fixtureImage.name = "performance-30-regions-16-subscriptions"
        fixtureImage.lifetime = .keepAlways
        add(fixtureImage)
        return app
    }

    /// Repeatable local-only flows for Instruments / XCTest scroll metrics.
    /// This exercises UI work, never refreshes subscriptions or exports to an app.
    func testPerformanceAuditScroll() {
        let app = launchPerformanceFixture()
        measureScrolling(app)
    }

    func testHomeBottomOverscrollSettles() {
        let app = launchPerformanceFixture()
        let next = app.buttons["continue-to-rules"]
        for _ in 0..<35 where !next.isHittable { app.swipeUp() }
        XCTAssertTrue(next.isHittable)
        app.swipeUp()
        let restingY = next.frame.midY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.38))
        for _ in 0..<3 {
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertEqual(next.frame.midY, restingY, accuracy: 3, "Bottom overscroll must return to the same content extent")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "home-bottom-after-overscroll"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPerformanceAuditExpandedNodes() {
        let app = launchPerformanceFixture()
        let expand = app.buttons["展开 云帆机场 的节点"]
        for _ in 0..<3 where !expand.isHittable { app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        expand.tap()
        measureScrolling(app)
    }

    func testMapRegionCollapseKeepsSubscriptionTrafficAligned() {
        let app = launchPerformanceFixture()
        let japan = app.buttons["日本"]
        XCTAssertTrue(japan.waitForExistence(timeout: 5))
        japan.tap()
        let collapse = app.buttons["收起 日本 的节点"]
        // The first map tap may zoom a cluster before selecting the country.
        if !collapse.waitForExistence(timeout: 2) { japan.tap() }
        XCTAssertTrue(collapse.waitForExistence(timeout: 3))
        let edgeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
        let edgeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
        // Keep the map detail heading well above the bottom bar, so the
        // subscription card's movement is visible during the collapse itself.
        edgeStart.press(forDuration: 0.05, thenDragTo: edgeEnd, withVelocity: .slow, thenHoldForDuration: 0.1)
        for _ in 0..<3 where !collapse.isHittable {
            edgeStart.press(forDuration: 0.05, thenDragTo: edgeEnd)
        }
        XCTAssertTrue(collapse.isHittable)
        collapse.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: collapse)
        waitForExpectations(timeout: 3)
        let header = app.buttons["展开 云帆机场 的节点"]
        for _ in 0..<3 where !header.isHittable {
            edgeStart.press(forDuration: 0.05, thenDragTo: edgeEnd)
        }
        let traffic = app.descendants(matching: .any)["剩余流量"].firstMatch
        XCTAssertTrue(header.isHittable)
        XCTAssertTrue(traffic.exists)
        XCTAssertGreaterThanOrEqual(traffic.frame.minY, header.frame.maxY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "map-collapse-subscription-traffic"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func measureScrolling(_ app: XCUIApplication) {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        // Keep the deceleration baseline while also measuring finger tracking.
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTCPUMetric(application: app)], options: options) {
            for _ in 0..<3 { app.swipeUp(); app.swipeDown() }
        }
    }

    /// A/B for `CardSwipeDeletion`: every card carries a hidden sizing copy
    /// and its own List. Compare on a device before changing the design.
    func testPerformanceAuditLocalNodesWithCardSwipe() { measureLocalNodeScrolling(disableCardSwipe: false) }
    func testPerformanceAuditLocalNodesWithoutCardSwipe() { measureLocalNodeScrolling(disableCardSwipe: true) }

    private func measureLocalNodeScrolling(disableCardSwipe: Bool) {
        let app = launchPerformanceFixture(disableCardSwipe: disableCardSwipe)
        let localNodes = app.descendants(matching: .any)["local-nodes-section"]
        for _ in 0..<30 where !(localNodes.exists && localNodes.isHittable) { app.swipeUp() }
        XCTAssertTrue(localNodes.exists)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        var metrics: [any XCTMetric] = [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTCPUMetric(application: app)]
        if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        measure(metrics: metrics, options: options) {
            for _ in 0..<3 { app.swipeUp(); app.swipeDown() }
        }
    }

    /// Zoomed map: drags with release glides, then country taps that
    /// recentre. Used to compare the raster strategy before and after
    /// 2026-09-27 (renderer swap per gesture vs. one settled raster).
    func testPerformanceZoomedMapDragging() {
        let app = launchPerformanceFixture()
        let japan = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "regions-section", "日本")).firstMatch
        XCTAssertTrue(japan.waitForExistence(timeout: 5))
        // Selecting recentres at 1.8×; one more pinch at the centre reaches
        // about 3.2× (a single synthesized pinch tops out near 2×).
        japan.tap()
        Thread.sleep(forTimeInterval: 1.5)
        japan.pinch(withScale: 1.7, velocity: 1)
        Thread.sleep(forTimeInterval: 1.5)
        // Horizontal flicks across the middle of the zoomed map card.
        let frame = japan.frame
        let y = frame.midY / app.frame.height
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: y))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: y))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTCPUMetric(application: app)], options: options) {
            for _ in 0..<3 {
                right.press(forDuration: 0.01, thenDragTo: left, withVelocity: .fast, thenHoldForDuration: 0)
                Thread.sleep(forTimeInterval: 0.5)
                left.press(forDuration: 0.01, thenDragTo: right, withVelocity: .fast, thenHoldForDuration: 0)
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    func testPerformanceMapSelectionRecentring() {
        let app = launchPerformanceFixture()
        let japan = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "regions-section", "日本")).firstMatch
        let singapore = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "regions-section", "新加坡")).firstMatch
        XCTAssertTrue(japan.waitForExistence(timeout: 5))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTCPUMetric(application: app)], options: options) {
            for _ in 0..<3 {
                if japan.isHittable { japan.tap() }
                Thread.sleep(forTimeInterval: 0.6)
                if singapore.isHittable { singapore.tap() }
                Thread.sleep(forTimeInterval: 0.6)
            }
        }
    }

    func testPerformanceAuditTabsWithHaptics() { measureTabSwitching(disableHaptics: false) }
    func testPerformanceAuditTabsWithoutHaptics() { measureTabSwitching(disableHaptics: true) }

    private func measureTabSwitching(disableHaptics: Bool) {
        let app = launchPerformanceFixture(disableTabHaptics: disableHaptics)
        // Warm the destinations before measuring repeated switching.
        for title in ["规则", "导出", "订阅"] { app.tabBars.buttons[title].tap() }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        var metrics: [any XCTMetric] = [XCTCPUMetric(application: app)]
        if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        measure(metrics: metrics, options: options) {
            for title in ["规则", "导出", "订阅"] { app.tabBars.buttons[title].tap() }
        }
    }

    func testPerformanceAuditNavigation() {
        let app = launchPerformanceFixture()
        for _ in 0..<3 {
            for title in ["规则", "导出", "订阅"] { app.tabBars.buttons[title].tap() }
        }
        openAddSource(app)
        app.buttons["手动添加"].tap()
        XCTAssertTrue(app.textFields["manual-server"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["取消"].tap()
        let formDismissed = NSPredicate(format: "exists == false")
        expectation(for: formDismissed, evaluatedWith: app.buttons["save-source"])
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["规则"].tap()
        app.swipeUp(); app.swipeDown()
        app.buttons["编辑 ACL4SSR 默认"].tap()
        app.swipeUp(); app.swipeDown()
        app.buttons["完成"].tap()
        app.tabBars.buttons["导出"].tap()
        app.swipeUp(); app.swipeDown()
        app.buttons["open-settings"].tap()
        app.swipeUp(); app.swipeDown()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["open-settings"].isHittable)
    }

    func testOnboardingPagesAndReplay() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "NO", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["你的订阅，一处打理"].waitForExistence(timeout: 10))
        let swipeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.3))
        let swipeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3))
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)
        XCTAssertTrue(app.staticTexts["先添加订阅或节点"].waitForExistence(timeout: 3))
        swipeEnd.press(forDuration: 0.05, thenDragTo: swipeStart)
        XCTAssertTrue(app.staticTexts["你的订阅，一处打理"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Karing"].exists)
        let introduction = XCTAttachment(screenshot: app.screenshot())
        introduction.name = "用途介绍"
        introduction.lifetime = .keepAlways
        add(introduction)
        for title in ["先添加订阅或节点", "选一套分流规则", "交给你常用的客户端"] {
            app.buttons["onboarding-next"].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = title
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let egern = app.buttons["onboarding-client-egern"]
        XCTAssertTrue(egern.isHittable)
        egern.tap()
        XCTAssertTrue(egern.isSelected)
        XCTAssertFalse(app.segmentedControls["onboarding-export-mode"].exists)
        let preview = app.descendants(matching: .any)["onboarding-export-preview"].firstMatch
        // The final page must fit without scrolling; do not scroll to make this pass.
        XCTAssertTrue(preview.isHittable)
        XCTAssertLessThanOrEqual(preview.frame.maxY, app.buttons["onboarding-next"].frame.minY)
        XCTAssertTrue(app.staticTexts["交给你常用的客户端"].isHittable)
        XCTAssertTrue(preview.label.contains("Egern"))
        let exportPreview = XCTAttachment(screenshot: app.screenshot())
        exportPreview.name = "交互导出预览"
        exportPreview.lifetime = .keepAlways
        add(exportPreview)
        app.buttons["onboarding-back"].tap()
        XCTAssertTrue(app.staticTexts["选一套分流规则"].exists)
        app.buttons["onboarding-next"].tap()
        app.buttons["onboarding-next"].tap()
        // The launch argument overrides reads for this process. Relaunch without
        // it to verify the completed flag in the persistent defaults domain.
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["导出"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-next"].exists)
        app.tabBars.buttons["导出"].tap()
        app.buttons["open-settings"].tap()
        let replay = app.buttons["replay-onboarding"]
        for _ in 0..<6 where !replay.isHittable { app.swipeUp() }
        XCTAssertTrue(replay.isHittable)
        replay.tap()
        XCTAssertTrue(app.staticTexts["你的订阅，一处打理"].waitForExistence(timeout: 3))
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 3))
        app.swipeUp()
        for _ in 0..<4 where !replay.isHittable { app.swipeDown() }
        XCTAssertTrue(replay.isHittable)
    }

    func testCancelPreservesDraftUntilExplicitDiscard() {
        let app = launch()
        openAddSource(app)
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

    func testAutomaticClipboardFillFromSharedSubscription() {
        let app = launch()
        let share = app.buttons["分享 云帆机场"]
        for _ in 0..<4 where !share.isHittable { app.swipeUp() }
        XCTAssertTrue(share.isHittable)
        share.tap()
        XCTAssertTrue(app.buttons["复制链接"].waitForExistence(timeout: 5))
        app.buttons["复制链接"].tap()
        app.navigationBars.buttons["完成"].tap()
        openAddSource(app)
        let input = app.descendants(matching: .any)["source-value-field"].firstMatch
        expectation(for: NSPredicate(format: "value == %@", "https://example.com/private-subscription"), evaluatedWith: input)
        waitForExpectations(timeout: 5)
        // Auto-filled content is the initial draft, so Cancel needs no discard.
        app.navigationBars.buttons["取消"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["save-source"])
        waitForExpectations(timeout: 5)
    }

    func testManualDoneDismissesKeyboard() {
        let app = launch()
        openAddSource(app)
        app.buttons["手动添加"].tap()
        let server = app.textFields["manual-server"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        // Third-party keyboards on device may live outside the app's AX tree.
        // Test focus/dismissal without synthetic typing through that keyboard;
        // draft text entry is covered independently by the cancellation test.
        let done = app.buttons["完成"]
        // Focus can return before the keyboard toolbar finishes appearing.
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: done)
        waitForExpectations(timeout: 5)
        done.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: done)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    func testEmptyExportRemainsDisabledUntilProtocolIsEnabled() {
        let app = launch()
        app.tabBars.buttons["导出"].tap()
        app.buttons["open-protocol-filter"].tap()
        for id in ["filter-ss", "filter-trojan", "filter-vmess"] {
            let toggle = app.switches[id]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "0")
        }
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["暂时无法导出"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["export-config"].isEnabled)
        app.buttons["open-protocol-filter"].tap()
        let toggle = app.switches["filter-ss"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["export-config"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "compact-export-card"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPreviewCopyShowsFeedbackAboveFullScreenCover() {
        let app = launch()
        app.tabBars.buttons["导出"].tap()
        let preview = app.buttons["preview-config"]
        let exportBar = app.buttons["export-config"]
        for _ in 0..<6 {
            // AX can report the button as hittable while the pinned export
            // bar still covers its center. Reveal the entire tap target.
            if preview.exists && preview.isHittable && preview.frame.maxY < exportBar.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(preview.isHittable)
        XCTAssertLessThan(preview.frame.maxY, exportBar.frame.minY)
        preview.tap()
        let copy = app.buttons["preview-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
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
