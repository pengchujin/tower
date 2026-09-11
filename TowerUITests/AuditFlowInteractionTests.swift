import XCTest
import UIKit

@MainActor
final class AuditFlowInteractionTests: XCTestCase {
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

    func testSubscriptionRefreshUsesCenteredProgressAndCanCancel() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["TOWER_REFRESH_UI_TEST"] = "1"
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["add-source-button"].waitForExistence(timeout: 15))
        let summary = app.staticTexts["准备您的节点"].firstMatch
        let originalY = summary.frame.minY
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90))
        start.press(forDuration: 0.05, thenDragTo: end)
        let card = app.descendants(matching: .any)["subscription-refresh-progress"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(card.frame.midX, window.midX, accuracy: 8)
        XCTAssertLessThan(abs(card.frame.midY - window.midY), window.height * 0.15)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "subscription-refresh-centered"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["subscription-refresh-progress-cancel"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: card)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["add-source-button"].isEnabled)
        XCTAssertEqual(summary.frame.minY, originalY, accuracy: 8, "Pull indicator must retract without shifting the page")
        // A fresh pull after cancellation must run normally and dismiss on success.
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: card)
        waitForExpectations(timeout: 15)
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

    private func launchPerformanceFixture(disableTabHaptics: Bool = false) -> XCUIApplication {
        handleClipboardPermission()
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["TOWER_PERFORMANCE_NODE_COUNT"] = "1000"
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)"]
        if disableTabHaptics { app.launchArguments.append("--disable-tab-haptics") }
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
        app.swipeDown()
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
        XCTAssertTrue(done.isHittable)
        done.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: done)
        waitForExpectations(timeout: 3)
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
