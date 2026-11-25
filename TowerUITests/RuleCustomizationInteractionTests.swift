import XCTest

@MainActor
final class RuleCustomizationInteractionTests: XCTestCase {
    /// Groups open a detail page that edits rule groups in place; node-filter
    /// groups still open their filter editor from a row on that page.
    private func openRouting(_ app: XCUIApplication, group name: String) {
        let row = app.buttons["rule-group-\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), name)
        row.tap()
        XCTAssertTrue(app.textFields["rule-group-name-field"].waitForExistence(timeout: 5), name)
        let route = app.buttons["rule-group-routing-\(name)"]
        if route.exists { route.tap() }
    }

    /// Candidates are added from one menu row under the current list.
    private func openCandidateMenu(_ app: XCUIApplication) {
        let add = app.buttons["policy-candidate-add"]
        for _ in 0..<8 { if add.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(add.isHittable)
        add.tap()
    }

    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
    }

    private func verifyLiveRuleImportFailureStaysInOverlay() throws {
        guard let url = ProcessInfo.processInfo.environment["TOWER_IMPORT_FAILURE_UI_URL"] else {
            throw XCTSkip("Requires an explicitly supplied public configuration with missing rule files")
        }
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let entry = app.buttons["import-rule-scheme"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15)); entry.tap()
        let field = app.textFields["scheme-url-field"].exists
            ? app.textFields["scheme-url-field"] : app.textViews["scheme-url-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(url)
        app.buttons["save-scheme"].tap()
        let failure = app.descendants(matching: .any)["scheme-import-error"].firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 45))
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(failure.frame.midX, window.midX, accuracy: 8)
        XCTAssertLessThan(abs(failure.frame.midY - window.midY), window.height * 0.15)
        XCTAssertLessThan(failure.frame.height, window.height - 48)
        XCTAssertEqual(failure.buttons.count, 1)
        XCTAssertTrue(app.buttons["scheme-import-error-confirm"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "rule-import-failure-overlay"; shot.lifetime = .keepAlways; add(shot)
        let details = app.scrollViews["scheme-import-error-details"]
        XCTAssertTrue(details.exists)
        details.swipeUp()
        XCTAssertTrue(app.buttons["scheme-import-error-confirm"].isHittable, "Actions must remain visible while scrolling errors")
        app.buttons["scheme-import-error-confirm"].tap()
        XCTAssertEqual(field.value as? String, url, "Return to editing must keep the draft")
        XCTAssertFalse(failure.exists)
        XCTAssertTrue(app.buttons["scheme-import-source-link"].isHittable, "The form must not be pushed down by an inline error")
        app.buttons["save-scheme"].tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 45))
        app.buttons["scheme-import-error-confirm"].tap()
        app.terminate()
    }

    func testLiveMirrorImportProgressCancelAndOriginalRetry() throws {
        if ProcessInfo.processInfo.environment["TOWER_IMPORT_FAILURE_UI_URL"] != nil {
            try verifyLiveRuleImportFailureStaysInOverlay()
            return
        }
        guard let url = ProcessInfo.processInfo.environment["TOWER_IMPORT_UI_URL"] else {
            throw XCTSkip("Requires an explicitly supplied public configuration with an unavailable mirror")
        }
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let entry = app.buttons["import-rule-scheme"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15)); entry.tap()
        let field = app.textFields["scheme-url-field"].exists
            ? app.textFields["scheme-url-field"] : app.textViews["scheme-url-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(url)
        app.buttons["save-scheme"].tap()
        let source = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "ghp.ci")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 20))
        let progressShot = XCTAttachment(screenshot: app.screenshot())
        progressShot.name = "import-download-progress"; progressShot.lifetime = .keepAlways; add(progressShot)
        let card = app.descendants(matching: .any)["scheme-import-progress"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(card.frame.midX, window.midX, accuracy: 8)
        XCTAssertLessThan(abs(card.frame.midY - window.midY), window.height * 0.15)
        app.buttons["scheme-import-progress-cancel"].coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let save = app.buttons["save-scheme"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(field.value as? String, url, "Cancel must retain the input draft")
        save.tap()
        let failure = app.descendants(matching: .any)["scheme-import-error"].firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 45))
        XCTAssertEqual(failure.frame.midX, window.midX, accuracy: 8)
        XCTAssertLessThan(abs(failure.frame.midY - window.midY), window.height * 0.15)
        XCTAssertEqual(failure.buttons.count, 1, "Failure offers only confirmation")
        let confirm = app.buttons["scheme-import-error-confirm"]
        XCTAssertTrue(confirm.isHittable)
        let failedShot = XCTAttachment(screenshot: app.screenshot())
        failedShot.name = "import-mirror-timeout"; failedShot.lifetime = .keepAlways; add(failedShot)
        confirm.tap()
        XCTAssertFalse(failure.exists)
        XCTAssertEqual(field.value as? String, url, "Confirmation must retain the input draft")
        XCTAssertTrue(save.isEnabled)
        app.terminate()
    }

    func testReaddingOriginalYouTubeUpdatesVisibleCurrentRules() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let importButton = app.buttons["import-rule-scheme"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15)); importButton.tap()
        app.buttons["scheme-import-source-text"].tap()
        let text = app.textViews["scheme-text-field"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap()
        text.typeText("proxy-groups:\n  - {name: 节点选择, type: select, proxies: [DIRECT]}\n  - {name: YouTube, type: select, proxies: [节点选择, DIRECT]}\nrules:\n  - DOMAIN-SUFFIX,youtube.com,YouTube\n  - MATCH,节点选择\n")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["save-scheme"].tap()
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        let imported = app.buttons["编辑 导入的规则"]
        for _ in 0..<10 { if imported.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(imported.isHittable); imported.tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("YouTube")
        let group = app.buttons["rule-group-YouTube"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.press(forDuration: 1.2)
        app.buttons["删除"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["删除"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: group)
        waitForExpectations(timeout: 5)
        let catalog = app.buttons["catalog-entry-acl4ssr-youtube"]
        for _ in 0..<5 { if catalog.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(catalog.isHittable); catalog.tap()
        expectation(for: NSPredicate(format: "value == %@", "已添加"), evaluatedWith: catalog)
        waitForExpectations(timeout: 30)
        XCTAssertTrue(group.waitForExistence(timeout: 5), "Re-added original group must be visible without reopening")
    }

    func testImportFullConfigurationAsText() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let importButton = app.buttons["import-rule-scheme"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15)); importButton.tap()
        let source = app.buttons["scheme-import-source-link"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["scheme-url-field"].waitForExistence(timeout: 5))
        app.buttons["scheme-import-source-file"].tap()
        XCTAssertTrue(app.buttons["scheme-file-picker"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-scheme"].isEnabled)
        app.buttons["scheme-import-source-text"].tap()
        let text = app.textViews["scheme-text-field"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap()
        text.typeText("proxies:\n  - {name: Fixture, type: trojan, server: example.com, port: 443, password: fixture}\nproxy-groups:\n  - {name: OpenAI, type: select, proxies: [Fixture, DIRECT]}\nrules:\n  - DOMAIN-SUFFIX,openai.com,OpenAI\n  - MATCH,OpenAI\n")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["save-scheme"].tap()
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        let imported = app.buttons["编辑 导入的规则"]
        for _ in 0..<10 { if imported.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(imported.isHittable); imported.tap()
        XCTAssertTrue(app.buttons["rule-group-OpenAI"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        XCTAssertTrue(imported.waitForExistence(timeout: 5))
        // Long press exposes deletion, and cancelling must retain the scheme.
        let cardWidth = app.windows.firstMatch.frame.width - 36
        imported.press(forDuration: 1.2)
        let collapsedPreview = app.otherElements["预览"]
        XCTAssertTrue(collapsedPreview.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(collapsedPreview.frame.width, cardWidth * 0.85, "Long press must retain the card width, not substitute a narrow summary")
        let collapsedAttachment = XCTAttachment(screenshot: app.screenshot())
        collapsedAttachment.name = "collapsed-native-menu"
        collapsedAttachment.lifetime = .keepAlways
        add(collapsedAttachment)
        let delete = app.buttons["删除"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(imported.exists)
        imported.swipeRight()
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        imported.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["删除"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: imported)
        waitForExpectations(timeout: 5)
        app.terminate(); app.launch()
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(imported.exists, "Deletion must persist after relaunch")
    }

    func testExpandedImportedSchemeCanReachBottom() {
        assertExpandedImportedSchemeCanReachBottom(groupCount: 40)
    }

    func testExpandedSmallImportedSchemeCanReachBottom() {
        assertExpandedImportedSchemeCanReachBottom(groupCount: 2)
    }

    func testExpandedImportedSchemeDeletionStaysInHeader() {
        assertExpandedImportedSchemeCanReachBottom(groupCount: 40, verifyDeletion: true)
    }

    private func assertExpandedImportedSchemeCanReachBottom(groupCount: Int, verifyDeletion: Bool = false) {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let importButton = app.buttons["import-rule-scheme"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15)); importButton.tap()
        app.buttons["scheme-import-source-text"].tap()
        let input = app.textViews["scheme-text-field"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap()
        let groups = (0..<groupCount).map { "  - {name: Group \($0), type: select, proxies: [DIRECT]}" }.joined(separator: "\n")
        input.typeText("proxy-groups:\n" + groups + "\nrules: ['MATCH,Group 0']\n")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        app.buttons["save-scheme"].tap()
        XCTAssertTrue(importButton.waitForExistence(timeout: 10))
        let edit = app.buttons["编辑 导入的规则"]
        for _ in 0..<10 { if edit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        let cell = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scheme-card-")).containing(.button, identifier: "编辑 导入的规则").firstMatch
        let disclosure = cell.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scheme-detail-")).firstMatch
        XCTAssertTrue(disclosure.exists); disclosure.tap()

        // A visible hit target is required; exists alone accepts clipped List descendants.
        let viewport = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 110)
        func visible(_ element: XCUIElement) -> Bool {
            element.exists && element.isHittable && viewport.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
        }
        if verifyDeletion {
            let firstGroup = app.staticTexts["Group 0"]
            let initialX = firstGroup.frame.minX
            let initialHeaderX = edit.frame.minX
            for swipeRight in [true, false] {
                if swipeRight { edit.swipeRight() } else { edit.swipeLeft() }
                let delete = app.buttons["删除"].firstMatch
                XCTAssertTrue(delete.waitForExistence(timeout: 5))
                XCTAssertTrue(visible(delete), "Expanded deletion must stay on screen")
                XCTAssertLessThanOrEqual(delete.frame.maxY, disclosure.frame.maxY + 2)
                XCTAssertEqual(firstGroup.frame.minX, initialX, accuracy: 2, "Expanded content must not translate with the header")
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = swipeRight ? "expanded-leading-delete" : "expanded-trailing-delete"
                attachment.lifetime = .keepAlways
                add(attachment)
                delete.tap()
                XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
                app.alerts.buttons["取消"].tap()
                XCTAssertTrue(edit.exists)
                XCTAssertEqual(edit.frame.minX, initialHeaderX, accuracy: 2, "Cancelled deletion restores header alignment")
            }
        }
        let lastGroup = app.staticTexts["Group \(groupCount - 1)"]
        for _ in 0..<16 { if visible(lastGroup) { break }; app.swipeUp() }
        XCTAssertTrue(visible(lastGroup), "Last expanded group must be reachable; frame=\(lastGroup.frame), viewport=\(viewport)")
        let bottom = app.buttons["continue-to-export"]
        for _ in 0..<8 { if visible(bottom) { break }; app.swipeUp() }
        XCTAssertTrue(visible(bottom), "Bottom action must be reachable after expansion; frame=\(bottom.frame)")
        for _ in 0..<16 { if visible(disclosure) { break }; app.swipeDown() }
        XCTAssertTrue(visible(disclosure))
        if verifyDeletion {
            // The original controls are the menu anchor, even for a long expanded card.
            for _ in 0..<8 { if visible(edit) { break }; app.swipeDown() }
            XCTAssertTrue(visible(edit))
            edit.press(forDuration: 1.2)
            // UIKit exposes the preview container, rather than its SwiftUI content ID.
            let preview = app.otherElements["预览"]
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            XCTAssertLessThan(preview.frame.height, 300, "Context menu must lift the original header, not the entire expanded list")
            XCTAssertGreaterThan(preview.frame.width, (app.windows.firstMatch.frame.width - 36) * 0.85)
            let menuAttachment = XCTAttachment(screenshot: app.screenshot())
            menuAttachment.name = "expanded-context-menu"
            menuAttachment.lifetime = .keepAlways
            add(menuAttachment)
            let delete = app.buttons["删除"].firstMatch
            XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.alerts.buttons["删除"].tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: edit)
            waitForExpectations(timeout: 5)
            for _ in 0..<8 { if visible(bottom) { break }; app.swipeUp() }
            XCTAssertTrue(visible(bottom), "Deleting an expanded card must release its scroll extent")
            app.terminate(); app.launch()
            for _ in 0..<8 { app.swipeUp() }
            XCTAssertFalse(edit.exists, "Expanded deletion must persist")
            return
        }
        disclosure.tap()
        for _ in 0..<8 { if visible(bottom) { break }; app.swipeUp() }
        XCTAssertTrue(visible(bottom), "Collapsing restores the correct scroll extent")
        bottom.tap()
        XCTAssertTrue(app.staticTexts["目标客户端"].waitForExistence(timeout: 5))
    }

    func testRuleDisclosureKeepsHeaderAnchoredAcrossRepeatedToggles() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let disclosure = app.buttons["scheme-detail-acl4ssr-default"]
        let header = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 15))
        let initialHeader = header.frame
        let initialDisclosure = disclosure.frame
        for _ in 0..<3 {
            disclosure.tap()
            XCTAssertEqual(header.frame.minY, initialHeader.minY, accuracy: 2)
            XCTAssertEqual(disclosure.frame.minY, initialDisclosure.minY, accuracy: 2)
            disclosure.tap()
            XCTAssertEqual(header.frame.minY, initialHeader.minY, accuracy: 2)
            XCTAssertEqual(disclosure.frame.minY, initialDisclosure.minY, accuracy: 2)
        }
    }

    func testExpandedBuiltInSchemeCanReachBottom() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let expand = app.buttons["scheme-detail-acl4ssr-default"]
        XCTAssertTrue(expand.waitForExistence(timeout: 15)); expand.tap()
        let bottom = app.buttons["continue-to-export"]
        let viewport = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 110)
        for _ in 0..<16 {
            if bottom.exists && bottom.isHittable && viewport.contains(CGPoint(x: bottom.frame.midX, y: bottom.frame.midY)) { break }
            app.swipeUp()
        }
        XCTAssertTrue(bottom.isHittable)
        XCTAssertTrue(viewport.contains(CGPoint(x: bottom.frame.midX, y: bottom.frame.midY)))
        bottom.tap()
        XCTAssertTrue(app.staticTexts["目标客户端"].waitForExistence(timeout: 5))
    }

    func testCustomNodeFilterDefaultsToKeywordsWithGuidance() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15)); customize.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("苹果")
        openRouting(app, group: "🍎 苹果服务")
        openCandidateMenu(app)
        let create = app.buttons["custom-node-filter-create"]
        XCTAssertTrue(app.navigationBars["添加候选策略"].waitForExistence(timeout: 5))
        for _ in 0..<6 { if create.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(create.isHittable)
        let reject = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "拒绝")).firstMatch
        XCTAssertTrue(reject.exists)
        XCTAssertGreaterThan(create.frame.minY, reject.frame.minY, "Custom filter belongs at the end")
        create.tap()
        let name = app.textFields["custom-node-filter-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "自定义节点")
        XCTAssertFalse(app.buttons["node-filter-example-uk"].exists)
        XCTAssertFalse(app.segmentedControls["node-filter-scope"].exists)
        let style = app.buttons["node-filter-match-style"]
        XCTAssertTrue(style.exists)
        XCTAssertTrue(style.label.contains("包含关键词"))
        let help = app.staticTexts["node-keyword-help"]
        XCTAssertTrue(help.exists)
        XCTAssertTrue(help.label.contains("jp、hk"))
        let save = app.buttons["custom-node-filter-save"]
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["node-filter-empty-prompt"].exists)
        XCTAssertEqual(app.staticTexts["node-filter-empty-prompt"].label, "请添加关键词")
        XCTAssertFalse(app.staticTexts["节点筛选表达式无效"].exists)
        style.tap()
        XCTAssertFalse(app.buttons["匹配全部节点"].exists)
        app.buttons["包含关键词"].tap()
        app.buttons["node-keyword-add"].tap()
        let input = app.textFields.matching(identifier: "node-keyword-input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.typeText("hk\n")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5); save.tap()
        // Candidates save in place: the new filter is already a candidate.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "自定义节点")).firstMatch.waitForExistence(timeout: 5))
        goBack(app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.buttons["清除文本"].tap(); search.typeText("自定义节点")
        openRouting(app, group: "自定义节点")
        XCTAssertTrue(style.waitForExistence(timeout: 5))
        XCTAssertTrue(style.label.contains("包含关键词"))
        XCTAssertFalse(app.buttons["node-filter-group-save"].exists, "Node filters are edited on the group page")
        let remove = app.buttons["删除关键词 hk"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        // The previous preview stays in place until the debounced result arrives.
        XCTAssertTrue(app.staticTexts["node-filter-empty-prompt"].waitForExistence(timeout: 5))
        XCTAssertTrue(help.exists)
        // Deleting the last keyword must not save a filter that selects every node.
        Thread.sleep(forTimeInterval: 1.5)
        goBack(app)
        openRouting(app, group: "自定义节点")
        XCTAssertTrue(app.buttons["删除关键词 hk"].waitForExistence(timeout: 5))
    }

    /// TestFlight 反馈：详情页点「删除策略组」没反应，返回上一层才弹确认框。
    func testDeletingGroupConfirmsOnTheDetailPage() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15))
        customize.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("苹果")
        openRouting(app, group: "🍎 苹果服务")
        let delete = app.buttons["rule-group-delete"]
        for _ in 0..<10 { if delete.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(delete.isHittable)

        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "确认框必须在详情页直接弹出")
        alert.buttons["取消"].tap()
        XCTAssertTrue(app.textFields["rule-group-name-field"].exists, "取消后留在详情页")

        delete.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["删除"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5), "删除后回到规则定制列表")
        XCTAssertFalse(app.buttons["rule-group-🍎 苹果服务"].waitForExistence(timeout: 2))
    }

    func testNodeFilterDeletionPersistsWhenImmediatelyReopened() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15))
        customize.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("苹果")
        openRouting(app, group: "🍎 苹果服务")
        openCandidateMenu(app)
        let addJapan = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "日本节点")).firstMatch
        XCTAssertTrue(addJapan.waitForExistence(timeout: 5))
        addJapan.tap()
        goBack(app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.buttons["清除文本"].tap()
        search.typeText("日本")
        let row = app.buttons["rule-group-🇯🇵 日本节点"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("延迟优选"))
        openRouting(app, group: "🇯🇵 日本节点")
        let remove = app.buttons["删除关键词 Japan"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertFalse(remove.exists)
        // Saves on its own once the preview has validated the change.
        Thread.sleep(forTimeInterval: 1.5)
        goBack(app)
        openRouting(app, group: "🇯🇵 日本节点")
        let inputs = app.textFields.matching(identifier: "node-keyword-input")
        XCTAssertTrue(inputs.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["删除关键词 Japan"].exists, "Deleted keyword must stay deleted when reopening from the same list")
        XCTAssertFalse(app.buttons["node-filter-options"].exists)
        // Keyword mode now ignores case without a separate toggle.
        XCTAssertTrue(app.buttons["node-filter-match-style"].exists)
        XCTAssertTrue(app.buttons["切换到正则表达式"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Reopened after deleting Japan"; shot.lifetime = .keepAlways
        add(shot)
    }

    func testNodeFilterKeywordRegexPersistenceAndRestore() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 全分组"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15))
        func openGroup() {
            customize.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("日本")
            openRouting(app, group: "🇯🇵 日本节点")
        }
        func finishCustomization() {
            let done = app.navigationBars["规则定制"].buttons["完成"]
            if !done.exists { goBack(app) }
            if app.buttons["关闭"].exists { app.buttons["关闭"].firstMatch.tap() }
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
        }
        openGroup()
        let inputs = app.textFields.matching(identifier: "node-keyword-input")
        XCTAssertTrue(inputs.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["node-filter-group-save"].exists, "Edits save in place, no separate sheet")
        XCTAssertFalse(app.navigationBars["编辑节点筛选"].exists)
        XCTAssertFalse(app.buttons["添加节点筛选"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "node-keyword-add").count, 1)
        let count = app.staticTexts["node-filter-match-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Inline node filter"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        let first = inputs.element(boundBy: 0)
        // Replace the keyword by deleting it rather than double-tap selecting:
        // a double tap on CJK text does not reliably select the whole word.
        // Tap the trailing edge so the caret lands after the word, then erase it.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let existing = first.value as? String ?? ""
        first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2) + "JP QA\n")
        XCTAssertEqual(first.value as? String, "JP QA")
        let add = app.buttons["node-keyword-add"]
        for _ in 0..<6 { if add.isHittable { break }; app.swipeUp() }
        add.tap()
        // iOS may omit value entirely for an empty, focused TextField.
        let empty = inputs.matching(NSPredicate(format: "value == nil OR value == '' OR value == %@", "关键词")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        empty.tap()
        // Deliberately no Return: the focused tag must be saved too.
        empty.typeText("Hong Kong [A+B]")
        Thread.sleep(forTimeInterval: 1.5)
        finishCustomization()
        app.terminate(); app.launch()
        XCTAssertTrue(customize.waitForExistence(timeout: 15))
        openGroup()
        let added = inputs.matching(NSPredicate(format: "value == %@", "Hong Kong [A+B]")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertTrue(inputs.matching(NSPredicate(format: "value == %@", "JP QA")).firstMatch.exists)
        let remove = app.buttons["删除关键词 Hong Kong [A+B]"]
        for _ in 0..<6 { if remove.isHittable { break }; app.swipeUp() }
        remove.tap()
        XCTAssertFalse(added.exists)
        Thread.sleep(forTimeInterval: 1.5)
        let raw = app.buttons["切换到正则表达式"]
        for _ in 0..<6 { if raw.isHittable { break }; app.swipeUp() }
        raw.tap()
        let regex = app.textViews["node-filter-regex"]
        XCTAssertTrue(regex.waitForExistence(timeout: 5))
        XCTAssertTrue((regex.value as? String ?? "").contains("JP QA"))
        regex.tap()
        let value = regex.value as? String ?? ""
        regex.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count) + "[")
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        XCTAssertTrue(app.staticTexts["节点筛选表达式无效"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        finishCustomization()
        openGroup()
        // The invalid expression was never saved; the earlier removal was.
        XCTAssertTrue(inputs.matching(NSPredicate(format: "value == %@", "JP QA")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(added.exists)
        let restore = app.buttons["恢复方案默认筛选"]
        for _ in 0..<12 { if restore.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(restore.isHittable)
        restore.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: restore)
        waitForExpectations(timeout: 5)
        Thread.sleep(forTimeInterval: 1.5)
        finishCustomization()
        openGroup()
        XCTAssertFalse(inputs.matching(NSPredicate(format: "value == %@", "JP QA")).firstMatch.waitForExistence(timeout: 3),
                       "Restoring the scheme default is saved too")
    }

    func testLocalLogicalRuleTextAndCompatibilityRoundTrip() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15))
        customize.tap()
        let create = app.buttons["local-rule-create"]
        for _ in 0..<12 {
            if create.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(create.isHittable)
        create.tap()
        let name = app.textFields["名称，例如 🎬 奈飞"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("UI QUIC")
        let text = app.textViews["local-rules-text"]
        text.tap()
        let original = "AND,((NETWORK,UDP),(DST-PORT,443),(DOMAIN-SUFFIX,openai.com)),REJECT\nDOMAIN-SUFFIX,openai.com"
        text.typeText(original)
        if app.buttons["收起键盘"].exists { app.buttons["收起键盘"].tap() }
        let compatibility = app.staticTexts["客户端兼容性"]
        for _ in 0..<6 {
            if compatibility.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(compatibility.exists)
        XCTAssertFalse(app.staticTexts["条件预览与编辑"].exists)
        XCTAssertFalse(app.buttons["local-rule-line-0"].exists)
        XCTAssertFalse(app.buttons["local-rule-add"].exists)
        let supported = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "可完整转换：")).firstMatch
        XCTAssertTrue(supported.waitForExistence(timeout: 5))
        XCTAssertTrue(supported.label.contains("Clash / Mihomo"))
        app.navigationBars["新建规则集"].buttons["保存"].tap()
        let saved = app.buttons["local-rule-set-UI QUIC"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertEqual(text.value as? String, original)
        app.navigationBars["编辑规则集"].buttons["取消"].tap()
        app.navigationBars["规则定制"].buttons["完成"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(customize.waitForExistence(timeout: 15))
        customize.tap()
        for _ in 0..<12 {
            if saved.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(saved.isHittable)
        saved.tap()
        XCTAssertEqual(text.value as? String, original)
    }

    func testRenameRuleCanCancelSaveAndPersistAcrossLaunches() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        customize.tap()
        app.buttons["rule-group-🌍 国外媒体"].tap()
        // The name is edited on the group page itself and saves on Return.
        let name = app.textFields["rule-group-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "国外媒体")
        name.tap()
        let current = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "媒体测试\n")
        XCTAssertTrue(app.navigationBars["媒体测试"].waitForExistence(timeout: 5))
        goBack(app)
        let renamed = app.buttons["rule-group-🌍 媒体测试"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rule-group-🌍 国外媒体"].exists)
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        customize.tap()
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "媒体测试")
    }

    func testSaveSchemeCanCancelAndSaveFromNestedSheet() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tabBars.buttons["规则"].tap()
        app.buttons["编辑 ACL4SSR 默认"].tap()
        app.buttons["rule-actions-menu"].tap()
        app.buttons["另存为新方案"].tap()
        XCTAssertTrue(app.textFields["方案名称"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["rule-actions-menu"].waitForExistence(timeout: 5))
        app.buttons["rule-actions-menu"].tap()
        app.buttons["另存为新方案"].tap()
        XCTAssertTrue(app.textFields["方案名称"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["编辑 ACL4SSR 默认 · 自定义"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["编辑 ACL4SSR 默认"].exists)
    }

    func testAddManualSwitchCandidate() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tabBars.buttons["规则"].tap()
        app.buttons["编辑 ACL4SSR 默认"].tap()
        openRouting(app, group: "🚀 节点选择")
        openCandidateMenu(app)
        let manual = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "手动切换")).firstMatch
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
        goBack(app)
        // A group without rules sits at the end of the same list, without a handle.
        let manualGroup = app.buttons["rule-group-🚀 手动切换"]
        for _ in 0..<8 { if manualGroup.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(manualGroup.waitForExistence(timeout: 5))
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
        let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "rule-group-")).firstMatch
        XCTAssertTrue(group.exists)
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
        let openAIGroup = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "rule-group-", "OpenAI")).firstMatch
        XCTAssertTrue(openAIGroup.waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        app.buttons["完成"].tap()
        // The scheme card's summary line carries the count since the rules
        // page lost its separate overview card.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "12 个策略组")).firstMatch
            .waitForExistence(timeout: 5))
        customize.tap()
        search.tap()
        search.typeText("OpenAI")
        catalog.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: openAIGroup)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(catalog.value as? String, "未添加")
        app.buttons["关闭"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "11 个策略组")).firstMatch
            .waitForExistence(timeout: 5))
        customize.tap()
        XCTAssertFalse(openAIGroup.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "rule-customization-default-editing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Issue #45: a group shows what reaches it and accepts a site of its own.
    func testGroupShowsItsRulesAndAcceptsAddedSite() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15)); customize.tap()

        let media = app.buttons["rule-group-🌍 国外媒体"]
        for _ in 0..<6 { if media.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(media.isHittable)
        media.tap()
        let list = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ProxyMedia")).firstMatch
        for _ in 0..<6 { if list.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(list.isHittable); list.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ruleset-content"].waitForExistence(timeout: 5))
        // Split by kind, like the choices for adding a site.
        let keywords = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "关键词")).firstMatch
        XCTAssertTrue(keywords.waitForExistence(timeout: 5)); keywords.tap()
        XCTAssertTrue(app.staticTexts["openai"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["go.com"].exists)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "全部")).firstMatch.tap()
        let listSearch = app.searchFields.firstMatch
        listSearch.tap(); listSearch.typeText("youtube")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "youtube")).firstMatch.waitForExistence(timeout: 5))
        if app.buttons["关闭"].exists { app.buttons["关闭"].firstMatch.tap() }
        goBack(app)

        // The type menu opens even though the page keeps its drag handles on.
        let kind = app.buttons["rule-group-kind-🌍 国外媒体"]
        for _ in 0..<6 { if kind.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(kind.isHittable); kind.tap()
        let urlTest = app.buttons["延迟优选"].firstMatch
        XCTAssertTrue(urlTest.waitForExistence(timeout: 3), "策略类型菜单必须能打开")
        urlTest.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "延迟优选"), evaluatedWith: kind)
        waitForExpectations(timeout: 5)

        let addRule = app.buttons["rule-group-add-supplement"]
        for _ in 0..<6 { if addRule.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(addRule.isHittable); addRule.tap()
        let input = app.textFields["supplement-rule-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap()
        input.typeText("203.0.113.7")
        app.buttons["supplement-rule-save"].tap()
        XCTAssertTrue(app.staticTexts["203.0.113.7/32"].waitForExistence(timeout: 5))
        goBack(app)
        XCTAssertTrue(media.waitForExistence(timeout: 5))
        XCTAssertTrue(media.label.contains("我添加 1 条"), media.label)
        app.navigationBars["规则定制"].buttons["完成"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(customize.waitForExistence(timeout: 15)); customize.tap()
        XCTAssertTrue(media.waitForExistence(timeout: 5))
        XCTAssertTrue(media.label.contains("我添加 1 条"), media.label)

        // Node groups only pick nodes; sites are added to routing groups.
        let auto = app.buttons["rule-group-♻️ 自动选择"]
        for _ in 0..<6 { if auto.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(auto.isHittable); auto.tap()
        XCTAssertTrue(app.textFields["rule-group-name-field"].waitForExistence(timeout: 5))
        // Type and node-name filter are edited right on this page.
        XCTAssertFalse(app.buttons["rule-group-routing-♻️ 自动选择"].exists)
        XCTAssertTrue(app.buttons["rule-group-kind-♻️ 自动选择"].exists)
        // `.*` reads as words, not as an expression.
        XCTAssertTrue(app.descendants(matching: .any)["node-filter-all"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["node-filter-regex"].exists)
        XCTAssertTrue(app.buttons["node-filter-use-keywords"].exists)
        XCTAssertFalse(app.buttons["rule-group-add-supplement"].exists)
        XCTAssertFalse(app.staticTexts["方案里的规则"].exists)
    }

    /// The list is in the order clients show the groups, every row drags,
    /// and the order survives a relaunch.
    func testDraggingRuleGroupChangesAndKeepsItsPlace() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 默认"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15)); customize.tap()
        let proxy = app.buttons["rule-group-🚀 节点选择"]
        let telegram = app.buttons["rule-group-📲 电报信息"]
        XCTAssertTrue(proxy.waitForExistence(timeout: 5))
        XCTAssertTrue(telegram.waitForExistence(timeout: 5))
        XCTAssertLessThan(proxy.frame.minY, telegram.frame.minY, "和客户端面板一样，节点选择排第一")
        XCTAssertFalse(app.staticTexts["节点分组"].exists, "所有组在同一个列表里")

        let width = app.windows.firstMatch.frame.width
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let handle = origin.withOffset(CGVector(dx: width - 30, dy: telegram.frame.midY))
        let target = origin.withOffset(CGVector(dx: width - 30, dy: proxy.frame.minY + 4))
        handle.press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.3)
        expectation(for: NSPredicate { _, _ in telegram.frame.minY < proxy.frame.minY }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.alerts.firstMatch.exists, "拖动只调整策略组顺序，不弹匹配提示")

        app.navigationBars["规则定制"].buttons["完成"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(customize.waitForExistence(timeout: 15)); customize.tap()
        XCTAssertTrue(telegram.waitForExistence(timeout: 5))
        XCTAssertLessThan(telegram.frame.minY, proxy.frame.minY, "拖动后的顺序重启后仍在")
    }

    /// 全分组: dragging 📹 油管视频 below 🌍 国外媒体 hands YouTube's sites to
    /// 国外媒体's list. The app says so, and undo puts both orders back.
    func testDraggingYouTubeBelowForeignMediaWarnsAndCanUndo() {
        let app = XCUIApplication()
        app.launchEnvironment["TOWER_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["--tab=rules", "-hasSeenWelcome", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let customize = app.buttons["编辑 ACL4SSR 全分组"]
        XCTAssertTrue(customize.waitForExistence(timeout: 15)); customize.tap()
        let youtube = app.buttons["rule-group-📹 油管视频"]
        let media = app.buttons["rule-group-🌍 国外媒体"]
        XCTAssertTrue(youtube.waitForExistence(timeout: 5))
        // Nudge the list a little at a time; a full swipe scrolls 油管视频 away
        // before 国外媒体, nine rows lower, comes into view.
        let nudgeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        let nudgeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
        for _ in 0..<12 where !media.isHittable {
            nudgeStart.press(forDuration: 0.05, thenDragTo: nudgeEnd, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(youtube.isHittable && media.isHittable)
        XCTAssertLessThan(youtube.frame.minY, media.frame.minY)
        let width = app.windows.firstMatch.frame.width
        let origin = app.coordinate(withNormalizedOffset: .zero)
        func dragYouTubeBelowMedia() {
            origin.withOffset(CGVector(dx: width - 30, dy: youtube.frame.midY))
                .press(forDuration: 0.6,
                       thenDragTo: origin.withOffset(CGVector(dx: width - 30, dy: media.frame.maxY - 4)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }

        dragYouTubeBelowMedia()
        let alert = app.alerts["匹配结果会改变"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        // Examples are the shortest domains (ytimg.com, youtu.be…), so check
        // the groups named rather than a particular site.
        let message = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "油管视频", "国外媒体")).firstMatch
        XCTAssertTrue(message.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "drag-youtube-below-media"; shot.lifetime = .keepAlways; add(shot)
        alert.buttons["撤销"].tap()
        expectation(for: NSPredicate { _, _ in youtube.frame.minY < media.frame.minY }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)

        dragYouTubeBelowMedia()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["保留新顺序"].tap()
        expectation(for: NSPredicate { _, _ in youtube.frame.minY > media.frame.minY }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }
}
