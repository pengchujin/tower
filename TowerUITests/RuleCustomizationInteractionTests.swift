import XCTest

@MainActor
final class RuleCustomizationInteractionTests: XCTestCase {
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
        XCTAssertTrue(app.buttons["rule-group-routing-OpenAI"].waitForExistence(timeout: 5))
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
        let apple = app.buttons["rule-group-routing-🍎 苹果服务"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5)); apple.tap()
        let create = app.buttons["custom-node-filter-create"]
        for _ in 0..<10 { if create.isHittable { break }; app.swipeUp() }
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
        let groupSave = app.buttons["node-filter-group-save"]
        XCTAssertTrue(groupSave.waitForExistence(timeout: 5)); groupSave.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.buttons["清除文本"].tap(); search.typeText("自定义节点")
        let route = app.buttons["rule-group-routing-自定义节点"]
        XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
        XCTAssertTrue(style.waitForExistence(timeout: 5))
        XCTAssertTrue(style.label.contains("包含关键词"))
        let remove = app.buttons["删除关键词 hk"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        XCTAssertFalse(groupSave.isEnabled, "Deleting the last keyword must not select all nodes")
        XCTAssertTrue(app.staticTexts["node-filter-empty-prompt"].exists)
        XCTAssertTrue(help.exists)
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
        let apple = app.buttons["rule-group-routing-🍎 苹果服务"]
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        apple.tap()
        let addJapan = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "日本节点")).firstMatch
        for _ in 0..<8 { if addJapan.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(addJapan.isHittable)
        addJapan.tap()
        app.buttons["node-filter-group-save"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.buttons["清除文本"].tap()
        search.typeText("日本")
        let route = app.buttons["rule-group-routing-🇯🇵 日本节点"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        XCTAssertTrue(route.label.contains("延迟优选"))
        route.tap()
        let remove = app.buttons["删除关键词 Japan"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertFalse(remove.exists)
        let save = app.buttons["node-filter-group-save"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        save.tap()
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        route.tap()
        let inputs = app.textFields.matching(identifier: "node-keyword-input")
        XCTAssertTrue(inputs.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["删除关键词 Japan"].exists, "Deleted keyword must stay deleted when reopening from the same list")
        XCTAssertFalse(app.buttons["node-filter-options"].exists)
        XCTAssertTrue(app.switches["忽略大小写"].exists)
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
            let route = app.buttons["rule-group-routing-🇯🇵 日本节点"]
            XCTAssertTrue(route.waitForExistence(timeout: 5))
            route.tap()
        }
        func finishCustomization() {
            if app.buttons["关闭"].exists { app.buttons["关闭"].firstMatch.tap() }
            let done = app.navigationBars["规则定制"].buttons["完成"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
        }
        openGroup()
        let inputs = app.textFields.matching(identifier: "node-keyword-input")
        XCTAssertTrue(inputs.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["node-filter-group-save"].exists)
        XCTAssertFalse(app.navigationBars["编辑节点筛选"].exists)
        XCTAssertFalse(app.buttons["添加节点筛选"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "node-keyword-add").count, 1)
        let count = app.staticTexts["node-filter-match-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.isHittable, "The preview should be visible without scrolling past the filter")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Compact node filter"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        let first = inputs.element(boundBy: 0)
        // Select the existing keyword explicitly: a tap in an intrinsic-width
        // field positions the caret within the word, rather than at its end.
        first.doubleTap()
        first.typeText("JP QA\n")
        XCTAssertEqual(first.value as? String, "JP QA")
        let add = app.buttons["node-keyword-add"]
        for _ in 0..<6 { if add.isHittable { break }; app.swipeUp() }
        add.tap()
        let empty = inputs.matching(NSPredicate(format: "value == '' OR value == %@", "关键词")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        empty.tap()
        empty.typeText("Hong Kong [A+B]")
        let save = app.buttons["node-filter-group-save"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        // Deliberately save without Return: the focused tag must be persisted.
        save.tap()
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
        XCTAssertFalse(save.isEnabled)
        app.navigationBars["日本节点"].buttons["取消"].tap()
        app.buttons["放弃更改"].tap()
        finishCustomization()
        openGroup()
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        let restore = app.buttons["恢复方案默认筛选"]
        for _ in 0..<12 { if restore.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(restore.isHittable)
        restore.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        save.tap()
        XCTAssertTrue(app.navigationBars["规则定制"].waitForExistence(timeout: 5))
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
        let original = app.buttons["rule-group-identity-🌍 国外媒体"]
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.tap()
        let name = app.textFields["规则名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        original.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        let current = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "媒体测试")
        app.buttons["保存"].tap()
        let renamed = app.buttons["rule-group-identity-🌍 媒体测试"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        XCTAssertFalse(original.exists)
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        customize.tap()
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "媒体测试")
        app.buttons["取消"].tap()
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
