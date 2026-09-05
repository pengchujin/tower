import XCTest

/// Keeps generated-resource inputs and maintainer documentation aligned with
/// the implementation that actually ships. These checks intentionally read
/// the source checkout: they guard repository hygiene, not app runtime state.
final class RepositoryConsistencyTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testAppKeepsUniversalIPhoneAndIPadSupport() throws {
        let project = try sourceText("Tower.xcodeproj/project.pbxproj")

        XCTAssertTrue(
            project.contains("TARGETED_DEVICE_FAMILY = \"1,2\";"),
            "Tower must remain available on both iPhone and iPad"
        )
        XCTAssertFalse(
            project.contains("TARGETED_DEVICE_FAMILY = \"1\";"),
            "An iPhone-only build setting silently removes iPad support"
        )
        XCTAssertTrue(
            project.contains("INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad"),
            "iPad orientations should be declared explicitly"
        )
    }

    func testWelcomeViewUsesAReadableAdaptiveWidthOnIPad() throws {
        let source = try sourceText("Tower/Features/Onboarding/WelcomeView.swift")

        XCTAssertTrue(source.contains("private let readableContentWidth"))
        XCTAssertTrue(source.contains(".frame(maxWidth: readableContentWidth"))
        XCTAssertFalse(source.contains("UIScreen.main.bounds"))
    }

    func testNaturalEarthUpdatersDefaultToImmutableRevisions() throws {
        for relativePath in [
            "Scripts/update_country_table.py",
            "Scripts/update_world_dot_map.py",
        ] {
            let source = try sourceText(relativePath)
            XCTAssertNotNil(
                source.range(of: #"REVISION = "[0-9a-f]{40}""#, options: .regularExpression),
                "\(relativePath) must pin an immutable Natural Earth commit"
            )
            XCTAssertFalse(source.contains(#"REVISION = "master""#))
        }
    }

    func testFlatMapUsesMapNamingEverywhere() throws {
        let fileManager = FileManager.default
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent("Tower/Features/Subscriptions/NodeGlobeView.swift")
                    .path
            ),
            "The flat map wrapper must not keep the historical globe filename"
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: repositoryRoot
                    .appendingPathComponent("Tower/Features/Subscriptions/NodeMapOverview.swift")
                    .path
            )
        )

        let subscriptions = try sourceText("Tower/Features/Subscriptions/SubscriptionsView.swift")
        XCTAssertTrue(subscriptions.contains("NodeMapOverview"))
        XCTAssertFalse(subscriptions.contains("NodeGlobeOverview"))
    }

    func testMaintainerDocsDescribeCurrentFlatMapAndNameFirstResolution() throws {
        let architecture = try sourceText("docs/ARCHITECTURE.md")
        let handoff = try sourceText("docs/HANDOFF.md")
        let readme = try sourceText("README.md")

        for (name, text) in [
            ("docs/ARCHITECTURE.md", architecture),
            ("docs/HANDOFF.md", handoff),
        ] {
            XCTAssertTrue(text.contains("WorldDotMapView"), name)
            XCTAssertFalse(text.contains("MapKit globe"), name)
            XCTAssertFalse(text.contains("NodeGlobeView"), name)
        }

        XCTAssertTrue(architecture.contains("名称优先"))
        XCTAssertTrue(architecture.contains("完整配置与节点订阅生成"))
        XCTAssertTrue(architecture.contains("Hiddify"))
        XCTAssertTrue(architecture.contains("sing-box MT"))
        XCTAssertTrue(architecture.contains("Egern"))
        XCTAssertTrue(readme.contains("名称优先"))
        XCTAssertFalse(readme.contains("IP 优先国家地区聚合"))
    }

    func testMapRegionRowsReuseTheParentCountryResolutionBatch() throws {
        let source = try sourceText("Tower/Features/Subscriptions/NodeMapOverview.swift")

        XCTAssertTrue(
            source.contains("CompactNodeRow(node: node, resolvesRegionOnAppear: false)"),
            "The map already resolves every node as one bounded batch; its rows must not start duplicate lookups while scrolling."
        )
        XCTAssertTrue(
            source.contains("if resolvesRegionOnAppear"),
            "Rows used outside the map still need an opt-in on-appear lookup."
        )
    }

    func testLocalNodeCardMatchesSubscriptionSurfaceAndExposesSelection() throws {
        let subscriptions = try sourceText("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let cardStart = try XCTUnwrap(subscriptions.range(of: "private struct LocalNodeCard: View"))
        let cardSource = String(subscriptions[cardStart.lowerBound...])

        XCTAssertTrue(cardSource.contains(".towerCard()"))
        XCTAssertTrue(
            cardSource.contains(
                "ExpandableNodeRow(node: node, usesInsetBackground: false, showsInclusionToggle: true)"
            ),
            "自有节点应使用白色外层卡片，并显示参与导出的勾选控件"
        )
    }

    func testSubscriptionRefreshReportUsesOneVisibilityState() throws {
        let source = try sourceText("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let overlayStart = try XCTUnwrap(source.range(of: "private struct SubscriptionRefreshReportOverlay: View"))
        let nextViewStart = try XCTUnwrap(source.range(of: "enum SubscriptionScrollTarget: Hashable"))
        let overlaySource = String(source[overlayStart.lowerBound..<nextViewStart.lowerBound])

        XCTAssertFalse(
            overlaySource.contains("@State private var isVisible"),
            "失败报告只能由 AppModel 控制显示；本地状态会与父视图 transition 叠加并造成关闭闪烁"
        )
        XCTAssertFalse(overlaySource.contains("if isVisible"))
        XCTAssertEqual(
            overlaySource.components(separatedBy: "model.dismissSubscriptionRefreshReport()").count - 1,
            1
        )
    }

    func testRulesViewExposesSearchableGroupSelectionAndPersistentCustomFlows() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")

        XCTAssertTrue(source.contains("RulesOverviewCard()"))
        XCTAssertTrue(source.contains(".searchable("))
        XCTAssertTrue(source.contains("rule-customization"))
        XCTAssertTrue(source.contains("rule-customization-list"))
        XCTAssertTrue(source.contains("customRuleGroupsSection"))
        XCTAssertTrue(source.contains("规则定制"))
        XCTAssertTrue(source.contains("当前规则"))
        XCTAssertTrue(source.contains("我的规则集"))
        XCTAssertTrue(source.contains("在线规则库"))
        XCTAssertTrue(source.contains("新建规则集"))
        XCTAssertTrue(source.contains("支持手动创建规则和引用规则集。"))
        XCTAssertTrue(source.contains("model.addLocalRuleSet"))
        XCTAssertTrue(source.contains("model.removeLocalRuleSet"))
        XCTAssertTrue(source.contains("名称，例如 🎬 奈飞"))
        XCTAssertTrue(source.contains("https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/UnBan.list"))
        XCTAssertTrue(source.contains("DOMAIN,apple.comscoreresearch.com"))
        XCTAssertTrue(source.contains("IP-CIDR,17.0.0.0/8,no-resolve"))
        XCTAssertFalse(source.contains(".swipeActions"))
        XCTAssertTrue(source.contains("pendingDeletion = .group("))
        XCTAssertTrue(source.contains("custom-rule-flow-editor"))
        XCTAssertTrue(source.contains("scrollDismissesKeyboard(.interactively)"))
        XCTAssertTrue(source.contains("scheme.routingTargetGroupNames("))
        XCTAssertFalse(source.contains("model.effectiveScheme(scheme).groups.map(\\.name) + [\"DIRECT\", \"REJECT\"]"))
    }

    func testEachRuleSchemeOpensItsOwnCustomizationWithoutBottomShortcut() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private struct RuleSchemeCard: View"))
        let nextCardStart = try XCTUnwrap(source.range(of: "private struct ImportRuleSchemeSheet: View"))
        let cardSource = String(source[cardStart.lowerBound..<nextCardStart.lowerBound])

        XCTAssertFalse(
            source.contains("customizationSection("),
            "规则定制属于每个方案，不应继续作为页面底部的全局入口"
        )
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "onCustomize: { customizationScheme =").count - 1,
            3,
            "本机规则、Self-Configuration 和普通导入方案都应直接打开自己的定制页"
        )
        XCTAssertTrue(cardSource.contains("let onCustomize: () -> Void"))
        XCTAssertTrue(cardSource.contains("Button(action: onCustomize)"))
        XCTAssertTrue(cardSource.contains("Button(action: onSelect)"))
        XCTAssertTrue(cardSource.contains("rule-customization-\\(scheme.id)"))
    }

    func testRuleSchemeInlinePreviewUsesTheSameLiveSchemeAsCustomization() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private struct RuleSchemeCard: View"))
        let editorStart = try XCTUnwrap(source.range(of: "private struct ImportRuleSchemeSheet: View"))
        let cardSource = String(source[cardStart.lowerBound..<editorStart.lowerBound])

        XCTAssertEqual(
            source.components(separatedBy: "previewScheme: model.customizableScheme(for:").count - 1,
            3,
            "每类规则卡片都必须从 AppModel 获取实时定制结果"
        )
        XCTAssertTrue(cardSource.contains("let previewScheme: RuleScheme"))
        XCTAssertTrue(cardSource.contains("ForEach(previewScheme.groups"))
        XCTAssertTrue(cardSource.contains("previewScheme.groups.count"))
        XCTAssertTrue(cardSource.contains("previewScheme.remoteRulesetURLs.count"))
        XCTAssertFalse(cardSource.contains("ForEach(scheme.groups"))
        XCTAssertFalse(cardSource.contains("scheme.remoteRulesetURLs.count"))
    }

    func testRulesHomeExplainsThatSchemeCardsAreEditable() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")

        XCTAssertTrue(source.contains("点击规则方案即可修改规则"))
        XCTAssertTrue(source.contains("rules-editing-hint"))
    }

    func testRuleCustomizationUsesRequestedOnlineSearchPrompt() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")

        XCTAssertTrue(source.contains("在线搜索规则：如 YouTube OpenAI"))
        XCTAssertTrue(source.contains("compactRuleRowInsets"))
        XCTAssertTrue(source.contains(".towerToast()"))
    }

    func testCurrentRuleRowsHideTheRedundantGroupModeLabel() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let rowStart = try XCTUnwrap(source.range(of: "private func customRuleGroupRow"))
        let nextFunctionStart = try XCTUnwrap(
            source.range(of: "private func categoryButton", range: rowStart.upperBound..<source.endIndex)
        )
        let rowSource = String(source[rowStart.lowerBound..<nextFunctionStart.lowerBound])

        XCTAssertFalse(rowSource.contains("Text(groupModeTitle(group))"))
        XCTAssertTrue(rowSource.contains("Text(groupSelectionSummary(group))"))
    }

    func testCustomRuleEditorUsesCompactMonospacedExamples() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let editorStart = try XCTUnwrap(source.range(of: "private struct LocalRuleSetEditor: View"))
        let editorSource = String(source[editorStart.lowerBound...])

        XCTAssertTrue(editorSource.contains(".font(.system(.footnote, design: .monospaced))"))
        XCTAssertTrue(editorSource.contains(".lineLimit(1)"))
        XCTAssertTrue(editorSource.contains(".minimumScaleFactor(0.72)"))
        XCTAssertFalse(editorSource.contains(".font(.system(.body, design: .monospaced))"))
    }

    func testRulesPageDoesNotExposeSwipeEditingOrDeletion() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let importedSection = try XCTUnwrap(source.range(of: "private var importedSchemesSection"))
        let overviewStart = try XCTUnwrap(source.range(of: "private struct RulesOverviewCard"))
        let importedSource = String(source[importedSection.lowerBound..<overviewStart.lowerBound])
        let cardStart = try XCTUnwrap(source.range(of: "private struct RuleSchemeCard"))
        let editorStart = try XCTUnwrap(source.range(of: "private struct ImportRuleSchemeSheet"))
        let cardSource = String(source[cardStart.lowerBound..<editorStart.lowerBound])

        XCTAssertFalse(source.contains("private struct ImportedRuleSchemeRow"))
        XCTAssertFalse(source.contains(".swipeActions"))
        XCTAssertFalse(source.contains("DragGesture(minimumDistance:"))
        XCTAssertTrue(importedSource.contains("onEdit: { editingImportedScheme = scheme }"))
        XCTAssertTrue(importedSource.contains("onDelete: { pendingDeletion = scheme }"))
        XCTAssertTrue(cardSource.contains(".contextMenu"))
        XCTAssertTrue(cardSource.contains("Label(\"编辑\", systemImage: \"pencil\")"))
        XCTAssertTrue(cardSource.contains("Label(\"删除\", systemImage: \"trash\")"))
        XCTAssertTrue(source.contains("ImportedRuleSchemeEditor("))
        XCTAssertTrue(source.contains("TextField(\"名称\""))
        XCTAssertTrue(source.contains("TextField(\"简介\""))
    }

    func testRuleDeletionUsesStableAlertsInsteadOfAnchoredDialogs() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let rulesViewStart = try XCTUnwrap(source.range(of: "struct RulesView: View"))
        let builtInSectionStart = try XCTUnwrap(source.range(of: "private var builtInSection"))
        let rulesViewSource = String(
            source[rulesViewStart.lowerBound..<builtInSectionStart.lowerBound]
        )

        XCTAssertTrue(rulesViewSource.contains(".alert("))
        XCTAssertTrue(rulesViewSource.contains("presenting: pendingDeletion"))
        XCTAssertFalse(
            rulesViewSource.contains(".confirmationDialog("),
            "规则方案删除确认不应锚定在长按菜单或滚动卡片上"
        )

        let sheetStart = try XCTUnwrap(
            source.range(of: "private struct RuleCustomizationSheet: View")
        )
        let identityEditorStart = try XCTUnwrap(
            source.range(of: "private struct RuleGroupIdentityEditor: View")
        )
        let sheetSource = String(source[sheetStart.lowerBound..<identityEditorStart.lowerBound])

        XCTAssertTrue(sheetSource.contains("@State private var pendingDeletion: RuleCustomizationDeletion?"))
        XCTAssertTrue(sheetSource.contains("presenting: pendingDeletion"))
        XCTAssertEqual(
            sheetSource.components(separatedBy: ".confirmationDialog(").count - 1,
            1,
            "规则定制中只保留非删除操作“恢复初始规则”的确认对话框"
        )
        XCTAssertFalse(sheetSource.contains("pendingCatalogDeletion"))
        XCTAssertFalse(sheetSource.contains("pendingLocalRuleSetDeletion"))
        XCTAssertFalse(sheetSource.contains("pendingGroupDeletion"))
        XCTAssertTrue(source.contains("private enum RuleCustomizationDeletion"))
    }

    func testRulesViewDoesNotShowRedundantTopSectionTabs() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")

        XCTAssertFalse(source.contains("RuleSectionTabs("))
        XCTAssertFalse(source.contains("rule-section-tabs"))
        XCTAssertFalse(source.contains("proxy.scrollTo"))
    }

    func testRulesViewKeepsManualSelfConfigurationWithLocalRulesAndImportInToolbar() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let localSection = try XCTUnwrap(source.range(of: "private var builtInSection"))
        let importedSection = try XCTUnwrap(source.range(of: "private var importedSchemesSection"))
        let localSource = String(source[localSection.lowerBound..<importedSection.lowerBound])

        XCTAssertTrue(localSource.contains("SelfConfigurationDownloadCard("))
        XCTAssertFalse(source.contains("private var selfConfigurationSection"))
        XCTAssertTrue(source.contains("ToolbarItem(placement: .topBarTrailing)"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"import-rule-scheme\")"))
    }

    func testRuleImportSheetUsesImportAsItsConfirmationAction() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let sheetStart = try XCTUnwrap(source.range(of: "private struct ImportRuleSchemeSheet: View"))
        let nextType = try XCTUnwrap(source.range(of: "private struct CatalogRuleEditorRequest"))
        let sheetSource = String(source[sheetStart.lowerBound..<nextType.lowerBound])

        XCTAssertTrue(sheetSource.contains("Button(isSaving ? \"正在下载…\" : \"导入\")"))
        XCTAssertFalse(sheetSource.contains("Button(isSaving ? \"正在下载…\" : \"导出\")"))
    }

    func testSettingsResetRequiresExplicitDestructiveConfirmation() throws {
        let source = try sourceText("Tower/Features/Settings/SettingsView.swift")

        XCTAssertTrue(source.contains("ConfigurationManagementCard("))
        XCTAssertTrue(source.contains(".alert(\"重置所有配置？\""))
        XCTAssertTrue(source.contains("Button(\"重置所有配置\", role: .destructive)"))
        XCTAssertTrue(source.contains("此操作无法撤销"))
        XCTAssertTrue(source.contains("iCloud 上的副本不会被删除"))
        XCTAssertTrue(
            source.contains(
                "configurationNameDraft = ConfigurationNameDraft(text: TowerBrand.localizedName)"
            )
        )
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"reset-all-configuration\")"))
    }

    func testSettingsGroupsConfigurationManagementAndUsesAQuietVersionFooter() throws {
        let source = try sourceText("Tower/Features/Settings/SettingsView.swift")
        let managementStart = try XCTUnwrap(source.range(of: "private struct ConfigurationManagementCard: View"))
        let footerStart = try XCTUnwrap(source.range(of: "private struct SettingsFooter: View"))
        let securityViewStart = try XCTUnwrap(source.range(of: "struct SecurityAndSourceView: View"))
        let management = String(source[managementStart.lowerBound..<footerStart.lowerBound])
        let footer = String(source[footerStart.lowerBound..<securityViewStart.lowerBound])

        XCTAssertTrue(source.contains("ConfigurationManagementCard(configurationNameDraft:"), source)
        XCTAssertFalse(source.contains("CloudSyncCard()"), source)
        XCTAssertFalse(source.contains("ResetAllConfigurationCard("), source)
        XCTAssertTrue(management.contains("SectionHeading(title: \"配置管理\""), management)
        XCTAssertTrue(management.contains("CloudSyncControls()"), management)
        XCTAssertTrue(management.contains("ResetAllConfigurationRow(configurationNameDraft:"), management)
        XCTAssertTrue(source.contains("Text(\"同步到我的 iCloud\")"), source)
        XCTAssertTrue(source.contains("Text(\"重置所有配置\")"), source)

        XCTAssertTrue(source.contains("SettingsFooter()"), source)
        XCTAssertTrue(footer.contains("Text(\"安全与开源\")"), footer)
        XCTAssertTrue(footer.contains("CFBundleShortVersionString"), footer)
        XCTAssertTrue(footer.contains("CFBundleVersion"), footer)
        XCTAssertTrue(footer.contains("Text(\"版本 \\(versionText)\")"), footer)
        XCTAssertTrue(footer.contains(".font(.caption)"), footer)
        XCTAssertFalse(footer.contains(".towerCard()"), footer)
    }

    func testRuleGroupCustomizationUsesOneReorderableEditableList() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")

        XCTAssertTrue(source.contains("private var customRuleGroupsSection"))
        XCTAssertTrue(source.contains("RuleGroupEditor("))
        XCTAssertTrue(source.contains(".onMove"))
        XCTAssertTrue(source.contains("另存为新方案"))
        XCTAssertFalse(source.contains("private var protectedGroupsSection"))
        XCTAssertFalse(source.contains("private var serviceGroupsSection"))
        XCTAssertFalse(source.contains("Section(\"固定分组\")"))
        XCTAssertFalse(source.contains("Text(\"服务分组\")"))
    }

    func testRestoringInitialRulesLivesInProminentToolbarMenuAndRequiresConfirmation() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let sheetStart = try XCTUnwrap(source.range(of: "private struct RuleCustomizationSheet: View"))
        let identityEditorStart = try XCTUnwrap(source.range(of: "private struct RuleGroupIdentityEditor: View"))
        let sheetSource = String(source[sheetStart.lowerBound..<identityEditorStart.lowerBound])
        let menuStart = try XCTUnwrap(sheetSource.range(of: "ToolbarItem(placement: .cancellationAction)"))
        let confirmationStart = try XCTUnwrap(sheetSource.range(of: "ToolbarItemGroup(placement: .confirmationAction)"))
        let menuSource = String(sheetSource[menuStart.lowerBound..<confirmationStart.lowerBound])

        XCTAssertFalse(sheetSource.contains("schemeActionsSection"))
        XCTAssertFalse(sheetSource.contains("Text(\"恢复为刚导入或内置时的状态\")"))
        XCTAssertFalse(menuSource.contains("Label(\"更多\", systemImage: \"ellipsis.circle\")"))
        XCTAssertTrue(menuSource.contains("Image(systemName: \"ellipsis\")"))
        XCTAssertTrue(menuSource.contains(".font(.title2.weight(.bold))"))
        XCTAssertTrue(menuSource.contains(".foregroundStyle(.tint)"))
        XCTAssertFalse(menuSource.contains("Circle().fill(.tint)"))
        XCTAssertFalse(menuSource.contains(".foregroundStyle(.white)"))
        XCTAssertFalse(menuSource.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(menuSource.contains(".accessibilityLabel(\"更多\")"))
        XCTAssertTrue(menuSource.contains("Button(role: .destructive)"))
        XCTAssertTrue(menuSource.contains("showsResetConfirmation = true"))
        XCTAssertTrue(
            menuSource.contains("Label(\"恢复初始规则\", systemImage: \"arrow.counterclockwise\")")
        )
        XCTAssertTrue(sheetSource.contains("@State private var showsResetConfirmation = false"))
        XCTAssertTrue(sheetSource.contains(".confirmationDialog(\"恢复初始规则\""))
    }

    func testRuleGroupReorderingUsesALocalDraftAndCommitsAfterEditing() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let sheetStart = try XCTUnwrap(source.range(of: "private struct RuleCustomizationSheet: View"))
        let identityEditorStart = try XCTUnwrap(source.range(of: "private struct RuleGroupIdentityEditor: View"))
        let sheetSource = String(source[sheetStart.lowerBound..<identityEditorStart.lowerBound])
        let sectionStart = try XCTUnwrap(sheetSource.range(of: "private var customRuleGroupsSection"))
        let userFlowStart = try XCTUnwrap(sheetSource.range(of: "private func userCreatedFlow"))
        let sectionSource = String(sheetSource[sectionStart.lowerBound..<userFlowStart.lowerBound])

        XCTAssertTrue(sheetSource.contains("@State private var editingGroups: [RuleSchemeGroup] = []"))
        XCTAssertTrue(sectionSource.contains("editingGroups.move(fromOffsets: source, toOffset: destination)"))
        XCTAssertFalse(sectionSource.contains("model.moveRuleGroups(fromOffsets:"))
        XCTAssertTrue(sheetSource.contains("private func commitEditingGroupOrder()"))
        XCTAssertTrue(sheetSource.contains("model.setRuleGroupOrder(names, for: scheme)"))
    }

    func testRuleGroupReorderGestureExistsInBothModesAndUsesLocalDraft() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let sheetStart = try XCTUnwrap(source.range(of: "private struct RuleCustomizationSheet: View"))
        let identityEditorStart = try XCTUnwrap(source.range(of: "private struct RuleGroupIdentityEditor: View"))
        let sheetSource = String(source[sheetStart.lowerBound..<identityEditorStart.lowerBound])
        let sectionStart = try XCTUnwrap(sheetSource.range(of: "private var customRuleGroupsSection"))
        let userFlowStart = try XCTUnwrap(sheetSource.range(of: "private func userCreatedFlow"))
        let sectionSource = String(sheetSource[sectionStart.lowerBound..<userFlowStart.lowerBound])

        XCTAssertTrue(sectionSource.contains("if ruleEditMode.isEditing {"))
        XCTAssertTrue(sectionSource.contains("ForEach(editingGroups, id: \\.name)"))
        XCTAssertTrue(sectionSource.contains("ForEach(visibleGroups, id: \\.name)"))
        XCTAssertEqual(sectionSource.components(separatedBy: ".onMove").count - 1, 2)

        let editingListStart = try XCTUnwrap(sectionSource.range(of: "ForEach(editingGroups, id: \\.name)"))
        let normalListStart = try XCTUnwrap(sectionSource.range(of: "ForEach(visibleGroups, id: \\.name)"))
        let editingBranch = String(sectionSource[editingListStart.lowerBound..<normalListStart.lowerBound])
        let normalBranch = String(sectionSource[normalListStart.lowerBound...])
        XCTAssertTrue(editingBranch.contains(".onMove"))
        XCTAssertTrue(normalBranch.contains(".onMove"))
        XCTAssertTrue(normalBranch.contains("moveRuleGroupsInNormalMode"))
        XCTAssertTrue(sheetSource.contains("private func moveRuleGroupsInNormalMode"))
        XCTAssertTrue(sheetSource.contains("editingGroups.move(fromOffsets: source, toOffset: destination)"))
        XCTAssertTrue(sheetSource.contains("model.setRuleGroupOrder(names, for: scheme)"))
    }

    func testEditModeOffersRuleEmojiAndNameEditing() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let sheetStart = try XCTUnwrap(source.range(of: "private struct RuleCustomizationSheet: View"))
        let identityEditorStart = try XCTUnwrap(source.range(of: "private struct RuleGroupIdentityEditor: View"))
        let sheetSource = String(source[sheetStart.lowerBound..<identityEditorStart.lowerBound])
        let listStart = try XCTUnwrap(sheetSource.range(of: "List {"))
        let navigationTitle = try XCTUnwrap(sheetSource.range(of: ".navigationTitle("))
        let listConfiguration = String(sheetSource[listStart.lowerBound..<navigationTitle.lowerBound])

        XCTAssertTrue(sheetSource.contains("@State private var ruleEditMode: EditMode = .inactive"))
        XCTAssertTrue(listConfiguration.contains(".environment(\\.editMode, $ruleEditMode)"))
        XCTAssertTrue(sheetSource.contains("ruleEditMode.isEditing"))
        XCTAssertFalse(sheetSource.contains("@Environment(\\.editMode) private var editMode"))
        XCTAssertFalse(sheetSource.contains("EditButton()"))
        XCTAssertTrue(sheetSource.contains("toggleRuleEditing()"))
        XCTAssertTrue(sheetSource.contains("private func toggleRuleEditing()"))
        XCTAssertTrue(sheetSource.contains("beginRuleEditing()"))
        XCTAssertTrue(sheetSource.contains("finishRuleEditing()"))
        XCTAssertTrue(source.contains("RuleGroupIdentityEditor("))
        XCTAssertTrue(source.contains("private func editableRuleIdentityButton"))
        XCTAssertTrue(source.contains(".buttonStyle(.borderless)"))
        XCTAssertTrue(source.contains(".frame(minHeight: 44)"))
        XCTAssertTrue(source.contains("openIdentityEditor(for: group)"))
        XCTAssertTrue(source.contains("TextField(\"Emoji\""))
        XCTAssertTrue(source.contains("TextField(\"规则名称\""))
    }

    func testRuleGroupEmojiToggleKeepsRowGeometryStableWithoutImplicitAnimation() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let sheetStart = try XCTUnwrap(source.range(of: "private struct RuleCustomizationSheet: View"))
        let identityEditorStart = try XCTUnwrap(source.range(of: "private struct RuleGroupIdentityEditor: View"))
        let sheetSource = String(source[sheetStart.lowerBound..<identityEditorStart.lowerBound])
        let menuStart = try XCTUnwrap(sheetSource.range(of: "ToolbarItem(placement: .cancellationAction)"))
        let confirmationStart = try XCTUnwrap(sheetSource.range(of: "ToolbarItemGroup(placement: .confirmationAction)"))
        let menuSource = String(sheetSource[menuStart.lowerBound..<confirmationStart.lowerBound])
        let emojiStart = try XCTUnwrap(sheetSource.range(of: "private func visibleRuleGroupEmoji"))
        let identityStart = try XCTUnwrap(sheetSource.range(of: "private func openIdentityEditor"))
        let emojiSource = String(sheetSource[emojiStart.lowerBound..<identityStart.lowerBound])

        XCTAssertTrue(
            sheetSource.contains("Label(\"显示策略组 Emoji\", systemImage: \"face.smiling\")")
        )
        XCTAssertFalse(menuSource.contains("Toggle("))
        XCTAssertTrue(menuSource.contains("toggleRuleGroupEmojiVisibilityAfterMenuDismiss()"))
        XCTAssertTrue(menuSource.contains(".menuActionDismissBehavior(.enabled)"))
        XCTAssertTrue(sheetSource.contains("private func toggleRuleGroupEmojiVisibilityAfterMenuDismiss()"))
        XCTAssertTrue(sheetSource.contains("Task.sleep(for: .milliseconds(180))"))
        XCTAssertTrue(sheetSource.contains("transaction.disablesAnimations = true"))
        XCTAssertEqual(
            sheetSource.components(separatedBy: "visibleRuleGroupEmoji(group)").count - 1,
            2
        )
        XCTAssertTrue(emojiSource.contains("let emojisVisible = model.ruleGroupEmojisAreEnabled(for: scheme)"))
        XCTAssertTrue(emojiSource.contains(".frame(width: 28, height: 28)"))
        XCTAssertTrue(emojiSource.contains(".opacity(emojisVisible ? 1 : 0)"))
        XCTAssertTrue(emojiSource.contains(".accessibilityHidden(!emojisVisible)"))
        XCTAssertTrue(emojiSource.contains(".animation(nil, value: emojisVisible)"))
        XCTAssertFalse(emojiSource.contains("if model.ruleGroupEmojisAreEnabled"))
    }

    func testCurrentRuleGroupNamesAlwaysUsePrimaryForeground() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let rowStart = try XCTUnwrap(source.range(of: "private func customRuleGroupRow"))
        let identityEditorStart = try XCTUnwrap(source.range(of: "private func openIdentityEditor"))
        let rowSource = String(source[rowStart.lowerBound..<identityEditorStart.lowerBound])

        XCTAssertFalse(rowSource.contains("let enabled = model.selectedRuleGroupNames"))
        XCTAssertFalse(rowSource.contains("foregroundStyle(enabled ?"))
        XCTAssertEqual(
            rowSource.components(separatedBy: ".foregroundStyle(Color.primary)").count - 1,
            2
        )
    }

    func testDownloadedSelfConfigurationReusesTheACLRuleCard() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let localSection = try XCTUnwrap(source.range(of: "private var builtInSection"))
        let importedSection = try XCTUnwrap(source.range(of: "private var importedSchemesSection"))
        let localSource = String(source[localSection.lowerBound..<importedSection.lowerBound])
        let cardStart = try XCTUnwrap(source.range(of: "private struct SelfConfigurationDownloadCard: View"))
        let nextCardStart = try XCTUnwrap(source.range(of: "private struct RuleSchemeCard: View"))
        let cardSource = String(source[cardStart.lowerBound..<nextCardStart.lowerBound])

        XCTAssertTrue(localSource.contains("if let selfConfigurationScheme = model.selfConfigurationScheme"))
        XCTAssertTrue(localSource.contains("scheme: selfConfigurationScheme"))
        XCTAssertTrue(localSource.contains("showsInlineRefreshAction: false"))
        XCTAssertFalse(cardSource.contains("SelectionIndicator"))
        XCTAssertFalse(cardSource.contains("使用这套规则"))
        XCTAssertFalse(cardSource.contains("当前使用"))
        XCTAssertFalse(cardSource.contains("Button(action: onRefresh)"))
    }

    func testRuleSelectionDoesNotAnimateTheCardTextPosition() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private struct RuleSchemeCard: View"))
        let nextCardStart = try XCTUnwrap(source.range(of: "private struct ImportRuleSchemeSheet: View"))
        let cardSource = String(source[cardStart.lowerBound..<nextCardStart.lowerBound])

        XCTAssertFalse(
            cardSource.contains(".buttonStyle(ResponsivePressButtonStyle())"),
            "规则选择不能缩放整个多行卡片，否则松手与选中状态同时更新时文字会漂移"
        )
        XCTAssertTrue(
            cardSource.contains(".buttonStyle(SelectionIndicatorButtonStyle())"),
            "规则勾选只应改变按钮透明度，不能缩放多行卡片文字"
        )
    }

    func testRuleSelectionKeepsAStableViewHierarchy() throws {
        let theme = try sourceText("Tower/Design/TowerTheme.swift")
        let indicatorStart = try XCTUnwrap(theme.range(of: "struct SelectionIndicator: View"))
        let toggleStart = try XCTUnwrap(theme.range(of: "struct CheckmarkToggleStyle: ToggleStyle"))
        let indicatorSource = String(theme[indicatorStart.lowerBound..<toggleStart.lowerBound])

        let rules = try sourceText("Tower/Features/Rules/RulesView.swift")
        let cardStart = try XCTUnwrap(rules.range(of: "private struct RuleSchemeCard: View"))
        let nextCardStart = try XCTUnwrap(rules.range(of: "private struct ImportRuleSchemeSheet: View"))
        let cardSource = String(rules[cardStart.lowerBound..<nextCardStart.lowerBound])

        XCTAssertFalse(indicatorSource.contains("if isSelected"))
        XCTAssertTrue(indicatorSource.contains(".opacity(isSelected ? 1 : 0)"))
        XCTAssertTrue(indicatorSource.contains(".frame(width: 25, height: 25)"))
        XCTAssertFalse(cardSource.contains(".overlay {\n            if isSelected"))
        XCTAssertTrue(cardSource.contains(".stroke(isSelected ?"))
    }

    func testRulesOverviewReservesTheSameTextHeightForEverySelection() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let overviewStart = try XCTUnwrap(source.range(of: "private struct RulesOverviewCard: View"))
        let nextViewStart = try XCTUnwrap(source.range(of: "private struct RuleDisclosureRow: View"))
        let overviewSource = String(source[overviewStart.lowerBound..<nextViewStart.lowerBound])

        XCTAssertTrue(
            overviewSource.contains(".lineLimit(1, reservesSpace: true)"),
            "顶部规则标题必须始终预留一行，不能在切换方案时改变卡片高度"
        )
        XCTAssertTrue(
            overviewSource.contains(".lineLimit(2, reservesSpace: true)"),
            "顶部规则说明必须始终预留两行，不能推动下方规则列表"
        )
    }

    func testRulesOverviewCountsEveryGroupInTheSelectedScheme() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let overviewStart = try XCTUnwrap(source.range(of: "private struct RulesOverviewCard: View"))
        let nextViewStart = try XCTUnwrap(source.range(of: "private struct RuleDisclosureRow: View"))
        let overviewSource = String(source[overviewStart.lowerBound..<nextViewStart.lowerBound])

        XCTAssertTrue(
            overviewSource.contains("model.selectedScheme?.groups.count"),
            "顶部总览必须与下载卡片和展开详情一样，统计方案的全部策略组"
        )
        XCTAssertFalse(
            overviewSource.contains("model.selectedScheme?.selectableRuleGroupNames.count"),
            "可自定义规则组是全部策略组的子集，不能用作顶部总数"
        )
    }

    func testRuleSchemeContextMenuOnlyPreviewsTheCompactHeader() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")
        let cardStart = try XCTUnwrap(source.range(of: "private struct RuleSchemeCard: View"))
        let nextCardStart = try XCTUnwrap(source.range(of: "private struct ImportRuleSchemeSheet: View"))
        let cardSource = String(source[cardStart.lowerBound..<nextCardStart.lowerBound])
        let detailDivider = try XCTUnwrap(cardSource.range(of: "\n\n            Divider()"))
        let compactHeader = String(cardSource[..<detailDivider.lowerBound])
        let expandableContent = String(cardSource[detailDivider.lowerBound...])

        XCTAssertTrue(
            compactHeader.contains(".contextMenu"),
            "长按菜单必须挂在固定高度的标题区，不能把展开后的全部策略组做成系统预览"
        )
        XCTAssertFalse(expandableContent.contains(".contextMenu"))
    }

    /// Renewal reminders and automatic refresh both answer "what should Tower
    /// do with my subscriptions", so they live inside the node-and-export card
    /// rather than as separate cards, and ahead of its export options.
    ///
    /// Compares positions only within a single construct. An earlier version
    /// compared across structs and against a property declaration rather than
    /// its use, which measured where the source happens to sit rather than
    /// what the screen shows.
    func testSubscriptionBehaviourSitsAtTheTopOfTheNodeCard() throws {
        let source = try sourceText("Tower/Features/Settings/SettingsView.swift")

        let cardBodyStart = try XCTUnwrap(source.range(of: #"SectionHeading(title: "节点与配置""#))
        let cardBody = String(source[cardBodyStart.lowerBound...])

        let reminder = try XCTUnwrap(cardBody.range(of: "RenewalReminderSection()"))
        let refresh = try XCTUnwrap(cardBody.range(of: "AutoRefreshSection()"))
        // The use, not the computed property that backs it.
        let exportOption = try XCTUnwrap(cardBody.range(of: "Toggle(isOn: appendNameBinding)"))

        XCTAssertLessThan(reminder.lowerBound, refresh.lowerBound)
        XCTAssertLessThan(refresh.lowerBound, exportOption.lowerBound)

        // Neither may reappear as a card of its own, or the settings screen
        // would show the same switch twice.
        XCTAssertFalse(source.contains("RenewalReminderCard()"), source)
        XCTAssertFalse(source.contains("AutoRefreshCard()"), source)
    }

    /// LAN sharing is an export destination, so Settings must not duplicate a
    /// second wayfinder for it.
    func testSettingsDoesNotContainLANSharingWayfinder() throws {
        let source = try sourceText("Tower/Features/Settings/SettingsView.swift")
        let settingsStart = try XCTUnwrap(source.range(of: "struct SettingsView: View"))
        let settingsEnd = try XCTUnwrap(
            source.range(
                of: "private struct ConfigurationManagementCard",
                range: settingsStart.upperBound..<source.endIndex
            )
        )
        let settingsView = String(source[settingsStart.lowerBound..<settingsEnd.lowerBound])

        XCTAssertFalse(source.contains("LANSharingSettingsRow"))
        XCTAssertFalse(source.contains("openLANSharing"))
        XCTAssertFalse(settingsView.contains("LANSharing"))
        XCTAssertFalse(settingsView.contains("局域网共享"))
        XCTAssertTrue(source.contains("struct LANSharingDestinationCard"))
    }

    func testClientSortingMovedIntoFilterWithoutMakingLANSharingAClientFormat() throws {
        let export = try sourceText("Tower/Features/Export/ExportView.swift")
        let filter = try sourceText("Tower/Features/Export/ClientFilterView.swift")
        let models = try sourceText("Tower/Models/DomainModels.swift")

        XCTAssertTrue(export.contains("LANExportTargetCard"))
        XCTAssertTrue(export.contains("LANSharingDestinationCard()"))
        XCTAssertTrue(export.contains("case .lanSharing: \"client-lan-sharing\""))
        let picker = try XCTUnwrap(export.range(of: "private struct ClientPicker"))
        let pickerEnd = try XCTUnwrap(
            export.range(
                of: "private struct ClientPickerDragSession",
                range: picker.upperBound..<export.endIndex
            )
        )
        let pickerSource = String(export[picker.lowerBound..<pickerEnd.lowerBound])
        XCTAssertTrue(
            pickerSource.contains(
                "ClientFilterView(isLANSharingSelected: $isLANSharingSelected)"
            )
        )
        XCTAssertTrue(pickerSource.contains("Text(\"客户端筛选\")"))
        XCTAssertTrue(pickerSource.contains("ForEach(displayedDestinations)"))
        XCTAssertTrue(pickerSource.contains("ClientPickerReorderGestureBridge("))
        XCTAssertTrue(pickerSource.contains("minimumPressDuration: 0.18"))
        XCTAssertTrue(pickerSource.contains("allowableMovement: 12"))
        XCTAssertTrue(
            pickerSource.contains("guard dragSession == nil, !suppressSelection else { return }"),
            "A completed long press must not also fire the Button action for the same touch"
        )
        XCTAssertTrue(
            pickerSource.contains("releaseSelectionSuppressionAfterTouchDelivery()"),
            "Selection suppression must be released after the reorder touch has been delivered"
        )
        XCTAssertTrue(pickerSource.contains("ReorderPlanner.insertionIndex"))
        XCTAssertTrue(pickerSource.contains("model.setExportDestinationOrder(orderedDestinations)"))
        XCTAssertTrue(pickerSource.contains("ReorderAutoScroller("))
        XCTAssertTrue(
            pickerSource.contains("sourceFrame.minX + dragSession.translation")
        )
        XCTAssertTrue(
            pickerSource.contains(".opacity(visualSessions.contains(where: { $0.source == destination }) ? 0 : 1)")
        )
        XCTAssertTrue(pickerSource.contains("completionCriteria: .removed"))
        XCTAssertFalse(pickerSource.contains(".onDrag("))
        XCTAssertFalse(pickerSource.contains(".onDrop("))
        XCTAssertFalse(pickerSource.contains(".dropDestination(for:"))
        XCTAssertFalse(pickerSource.contains(".scrollTargetBehavior(.viewAligned"))
        XCTAssertTrue(filter.contains("ScrollView {"))
        XCTAssertFalse(filter.contains("List {"))
        XCTAssertTrue(filter.contains("ForEach(displayedRows)"))
        XCTAssertTrue(filter.contains("ForEach(hiddenRows)"))
        XCTAssertTrue(filter.contains("model.setExportDestination(destination, isVisible: true)"))
        XCTAssertTrue(filter.contains("model.setExportDestination(destination, isVisible: false)"))
        XCTAssertTrue(filter.contains("Image(systemName: \"line.3.horizontal\")"))
        XCTAssertTrue(filter.contains("Image(systemName: \"plus.circle.fill\")"))
        XCTAssertTrue(filter.contains("ClientPickerReorderGestureBridge("))
        XCTAssertTrue(filter.contains("handleDestination(at:"))
        XCTAssertFalse(filter.contains(".highPriorityGesture("))
        XCTAssertTrue(filter.contains("DestinationRowFramePreferenceKey"))
        XCTAssertTrue(filter.contains("ReorderPlanner.insertionIndex"))
        XCTAssertTrue(filter.contains("model.setExportDestinationOrder(orderedDestinations)"))
        XCTAssertTrue(filter.contains("ClientFilterRowPresentation"))
        XCTAssertTrue(filter.contains("role: .displayed"))
        XCTAssertTrue(filter.contains("role: .hidden"))
        XCTAssertTrue(filter.contains("sourceFrame.minY + dragSession.translation"))
        XCTAssertTrue(filter.contains("let isLifted = !isPreview && visualSessions.contains"))
        XCTAssertTrue(filter.contains("ReorderAutoScroller("))
        XCTAssertTrue(filter.contains("completionCriteria: .removed"))
        XCTAssertFalse(filter.contains("Task.sleep"))
        XCTAssertFalse(filter.contains(".scrollDisabled("))
        XCTAssertTrue(filter.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(filter.contains("withAnimation(TowerMotion.disclosure(reduceMotion: false))"))
        XCTAssertTrue(filter.contains(".transition(.opacity)"))
        XCTAssertTrue(filter.contains(".sensoryFeedback(.selection"))
        XCTAssertFalse(filter.contains(".onMove("))
        XCTAssertFalse(filter.contains("editMode"))
        XCTAssertTrue(filter.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(filter.contains(".frame(width: 44, height: 44)"))
        XCTAssertTrue(filter.contains("case .lanSharing:"))

        let clientStart = try XCTUnwrap(models.range(of: "enum ClientTarget:"))
        let clientEnd = try XCTUnwrap(
            models.range(of: "enum ExportContentMode:", range: clientStart.upperBound..<models.endIndex)
        )
        let clientTarget = String(models[clientStart.lowerBound..<clientEnd.lowerBound])
        XCTAssertFalse(
            clientTarget.contains("case lan"),
            "局域网是传输目的地，不是生成器可以直接输出的一种客户端格式"
        )
    }

    func testClientPickerReorderBridgeLeavesCardTapsAndScrollingNative() throws {
        let export = try sourceText("Tower/Features/Export/ExportView.swift")
        let bridge = try sourceText("Tower/Design/ClientPickerReorderGestureBridge.swift")
        let pickerStart = try XCTUnwrap(export.range(of: "private struct ClientPicker"))
        let pickerEnd = try XCTUnwrap(
            export.range(
                of: "private struct ClientPickerDragSession",
                range: pickerStart.upperBound..<export.endIndex
            )
        )
        let pickerSource = String(export[pickerStart.lowerBound..<pickerEnd.lowerBound])
        let cardsStart = try XCTUnwrap(pickerSource.range(of: "ForEach(displayedDestinations)"))
        let cardsEnd = try XCTUnwrap(
            pickerSource.range(
                of: ".padding(.vertical, 8)",
                range: cardsStart.upperBound..<pickerSource.endIndex
            )
        )
        let cards = String(pickerSource[cardsStart.lowerBound..<cardsEnd.lowerBound])

        XCTAssertTrue(cards.contains("Button {"), "Client cards must remain native buttons")
        XCTAssertFalse(
            cards.contains(".gesture("),
            "A whole-card SwiftUI gesture competes with the Button and horizontal ScrollView"
        )
        XCTAssertFalse(
            cards.contains(".simultaneousGesture("),
            "Even a simultaneous SwiftUI long press can prevent native tap and pan delivery"
        )
        XCTAssertFalse(
            cards.contains(".highPriorityGesture("),
            "A high-priority card gesture intercepts both selection and horizontal scrolling"
        )
        XCTAssertFalse(pickerSource.contains("private func reorderGesture("))
        XCTAssertFalse(pickerSource.contains("LongPressGesture("))
        XCTAssertFalse(pickerSource.contains("DragGesture("))

        XCTAssertTrue(pickerSource.contains("shouldReceiveTouch: isTouchInsideDestination"))
        XCTAssertTrue(pickerSource.contains("private func isTouchInsideDestination("))
        XCTAssertTrue(bridge.contains("UILongPressGestureRecognizer("))
        XCTAssertTrue(bridge.contains("scrollView.addGestureRecognizer(recognizer)"))
        XCTAssertTrue(bridge.contains("recognizer.cancelsTouchesInView = true"))
        XCTAssertTrue(bridge.contains("recognizer.delaysTouchesBegan = false"))
        XCTAssertTrue(bridge.contains("return !(otherGestureRecognizer is UIPanGestureRecognizer)"))
        XCTAssertFalse(
            bridge.contains("panGestureRecognizer.isEnabled"),
            "Manually toggling the scroll pan cancels an in-flight recognizer and causes reentrancy"
        )
        XCTAssertFalse(
            bridge.contains("disableScrollPanGesture"),
            "UIKit should arbitrate between the long press and its sibling scroll pan"
        )

        XCTAssertTrue(bridge.contains("shouldReceive touch: UITouch"))
        XCTAssertTrue(bridge.contains("guard shouldReceiveTouch(viewportLocation) else"))
        XCTAssertTrue(bridge.contains("initialWindowLocation = touch.location(in: scrollView.window)"))
        XCTAssertTrue(bridge.contains("initialViewportLocation = viewportLocation"))
        XCTAssertTrue(bridge.contains("func gestureRecognizerShouldBegin("))
        XCTAssertTrue(
            bridge.contains("initialWindowLocation != nil,")
                && bridge.contains("let initialViewportLocation,")
                && bridge.contains("shouldReceiveTouch(initialViewportLocation) else { return false }"),
            "Only a card touch with both frozen hit point and translation origin may begin reordering"
        )
        XCTAssertTrue(
            bridge.contains("case .began, .changed:") && bridge.contains("return false"),
            "A scroll view whose pan already won must keep ownership of that touch"
        )
        XCTAssertTrue(bridge.contains("recognizer.state == .began"))
        XCTAssertTrue(
            bridge.contains("initialViewportLocation ?? currentViewportLocation"),
            "The began event must use the card hit-tested point frozen at touch-down"
        )

        let beganStart = try XCTUnwrap(bridge.range(of: "case .began:"))
        let changedStart = try XCTUnwrap(
            bridge.range(of: "case .changed:", range: beganStart.upperBound..<bridge.endIndex)
        )
        let began = String(bridge[beganStart.lowerBound..<changedStart.lowerBound])
        XCTAssertTrue(began.contains("isReordering = onBegan(event)"))

        let endedStart = try XCTUnwrap(
            bridge.range(of: "case .ended:", range: changedStart.upperBound..<bridge.endIndex)
        )
        let cancelledStart = try XCTUnwrap(
            bridge.range(
                of: "case .cancelled, .failed:",
                range: endedStart.upperBound..<bridge.endIndex
            )
        )
        let possibleStart = try XCTUnwrap(
            bridge.range(of: "case .possible:", range: cancelledStart.upperBound..<bridge.endIndex)
        )
        let ended = String(bridge[endedStart.lowerBound..<cancelledStart.lowerBound])
        let cancelled = String(bridge[cancelledStart.lowerBound..<possibleStart.lowerBound])
        let endedClear = try XCTUnwrap(ended.range(of: "isReordering = false"))
        let endedCallback = try XCTUnwrap(ended.range(of: "onEnded("))
        let cancelledClear = try XCTUnwrap(cancelled.range(of: "isReordering = false"))
        let cancelledCallback = try XCTUnwrap(cancelled.range(of: "onCancelled()"))
        XCTAssertLessThan(
            endedClear.lowerBound,
            endedCallback.lowerBound,
            "Clear active state before the callback can rebuild and dismantle the bridge"
        )
        XCTAssertLessThan(
            cancelledClear.lowerBound,
            cancelledCallback.lowerBound,
            "Cancellation must also clear active state before reporting it"
        )

        // Preserve the insertion-slot implementation that fixed jumps to the
        // first position while changing only the gesture arbitration layer.
        XCTAssertTrue(pickerSource.contains("ReorderPlanner.insertionIndex"))
        XCTAssertTrue(pickerSource.contains("ReorderPlanner.moving("))
        XCTAssertTrue(pickerSource.contains("stabilizedInsertionIndex("))
        XCTAssertTrue(pickerSource.contains("ReorderAutoScroller("))
        XCTAssertTrue(pickerSource.contains("model.setExportDestinationOrder(orderedDestinations)"))
    }

    func testSelectingLANSharingStartsTheServiceWithoutASecondTap() throws {
        let export = try sourceText("Tower/Features/Export/ExportView.swift")

        XCTAssertTrue(export.contains("activateLANSharing: activateLANSharing"))
        XCTAssertTrue(export.contains("private func activateLANSharing()"))
        XCTAssertTrue(export.contains("Task { await model.startLANSharing() }"))
    }

    func testLANExportDestinationUsesSharingName() throws {
        let export = try sourceText("Tower/Features/Export/ExportView.swift")
        let settings = try sourceText("Tower/Features/Settings/SettingsView.swift")

        XCTAssertTrue(export.contains(".accessibilityLabel(\"局域网共享\")"))
        XCTAssertTrue(export.contains("Text(\"局域网共享\")"))
        XCTAssertTrue(settings.contains("title: \"局域网共享\""))
    }

    func testLANSharingUsesDeviceSupportSummaryAndOfficialClientIcons() throws {
        let settings = try sourceText("Tower/Features/Settings/SettingsView.swift")
        let catalog = try sourceText("Tower/Localizable.xcstrings")

        XCTAssertTrue(settings.contains("String(localized: \"支持安卓、Windows、Mac、路由器等。\")"))
        XCTAssertTrue(settings.contains("LANClientIcon(format: format"))
        XCTAssertTrue(settings.contains("LANClientIcon(format: selectedClient"))
        XCTAssertFalse(settings.contains("Label(format.displayName, systemImage: format.systemImageName)"))
        XCTAssertFalse(settings.contains("String(localized: \"共享的是转换结果，不含机场原始链接\")"))
        XCTAssertTrue(catalog.contains("\"支持安卓、Windows、Mac、路由器等。\""))
        XCTAssertTrue(catalog.contains("\"Supports Android, Windows, Mac, routers, and more.\""))
    }

    func testRenewalDetailsDoNotRepeatTheGlobalNotificationPolicy() throws {
        let settings = try sourceText("Tower/Features/Settings/SettingsView.swift")
        let rowStart = try XCTUnwrap(settings.range(of: "private struct RenewalReminderDetailRow"))
        let rowEnd = try XCTUnwrap(
            settings.range(of: "struct LANSharingDestinationCard", range: rowStart.upperBound..<settings.endIndex)
        )
        let row = String(settings[rowStart.lowerBound..<rowEnd.lowerBound])

        XCTAssertTrue(row.contains("到期日期："))
        XCTAssertFalse(row.contains("到期前一天通知"))
        XCTAssertFalse(row.contains("续费提醒"))
    }

    func testBottomNavigationHasThreeTabsAndSettingsLivesInExportToolbar() throws {
        let root = try sourceText("Tower/TowerApp.swift")
        let export = try sourceText("Tower/Features/Export/ExportView.swift")

        XCTAssertFalse(root.contains("AppTab.settings"))
        XCTAssertTrue(export.contains("accessibilityIdentifier(\"open-settings\")"))
        XCTAssertTrue(export.contains("SettingsView("))
        XCTAssertTrue(export.contains("configurationNameDraft: $configurationNameDraft"))
        XCTAssertTrue(export.contains("ToolbarItem(placement: .topBarTrailing)"))
    }

    func testSettingsDoneCommitsTheConfigurationNameBeforeDismissing() throws {
        let export = try sourceText("Tower/Features/Export/ExportView.swift")
        let settings = try sourceText("Tower/Features/Settings/SettingsView.swift")
        let exportRootStart = try XCTUnwrap(export.range(of: "struct ExportView: View"))
        let sheetStart = try XCTUnwrap(export.range(of: "private struct ExportSettingsSheet: View"))
        let nextType = try XCTUnwrap(export.range(of: "private struct ExportPayload: Identifiable"))
        let exportRoot = String(export[exportRootStart.lowerBound..<sheetStart.lowerBound])
        let sheet = String(export[sheetStart.lowerBound..<nextType.lowerBound])

        XCTAssertTrue(
            exportRoot.contains("@State private var configurationNameDraft"),
            "名称草稿必须由不会随弹窗重建的导出页持有"
        )
        XCTAssertTrue(exportRoot.contains("ExportSettingsSheet("))
        XCTAssertTrue(exportRoot.contains("configurationNameDraft: $configurationNameDraft"))
        XCTAssertFalse(
            sheet.contains("@State private var configurationNameDraft"),
            "弹窗根视图可能在工具栏提交前重建，不能在这里保存唯一的名称草稿"
        )
        XCTAssertTrue(sheet.contains("@Binding var configurationNameDraft"))
        XCTAssertTrue(sheet.contains("SettingsView("))
        XCTAssertTrue(sheet.contains("configurationNameDraft: $configurationNameDraft"))
        let commit = try XCTUnwrap(sheet.range(of: "model.setConfigurationName(configurationNameDraft.committedName)"))
        let dismiss = try XCTUnwrap(sheet.range(of: "dismiss()"))
        XCTAssertLessThan(commit.lowerBound, dismiss.lowerBound)
        XCTAssertFalse(
            sheet.contains(".onDisappear"),
            "设置页消失时不能再用可能已重置的草稿二次覆盖已保存名称"
        )
        XCTAssertTrue(settings.contains("@Binding var configurationNameDraft: ConfigurationNameDraft"))
        XCTAssertFalse(
            settings.contains("@State private var configurationNameDraft = ConfigurationNameDraft()"),
            "名称草稿不能只存在于先于弹窗销毁的子视图里"
        )
    }

    func testConfigurationNameUsesATrailingInlineField() throws {
        let settings = try sourceText("Tower/Features/Settings/SettingsView.swift")
        let rowStart = try XCTUnwrap(settings.range(of: "private struct ConfigurationNameSettingsRow: View"))
        let nextType = try XCTUnwrap(settings.range(of: "struct SettingsIconTile: View"))
        let row = String(settings[rowStart.lowerBound..<nextType.lowerBound])

        XCTAssertTrue(row.contains("HStack(spacing: 13)"), row)
        XCTAssertTrue(row.contains("Text(\"配置名称\")"), row)
        XCTAssertTrue(row.contains("TextField(\"配置名称\""), row)
        XCTAssertTrue(row.contains(".multilineTextAlignment(.trailing)"), row)
        XCTAssertFalse(
            row.contains(".onChange(of: model.configurationName)"),
            "已加载的编辑草稿必须独立，iCloud 或重绘不能在输入中把旧名称写回"
        )
        XCTAssertFalse(row.contains("VStack(alignment: .leading"), row)
    }

    func testScrollingCardsAvoidLiveBlurAndClientIconsAreEagerlyPrepared() throws {
        let theme = try sourceText("Tower/Design/TowerTheme.swift")
        let export = try sourceText("Tower/Features/Export/ExportView.swift")

        XCTAssertTrue(theme.contains("secondarySystemGroupedBackground"))
        XCTAssertFalse(theme.contains("AnyShapeStyle(.thinMaterial)"))
        XCTAssertTrue(export.contains("HStack(spacing: 12)"))
        XCTAssertFalse(export.contains("LazyHStack(spacing: 12)"))
        XCTAssertTrue(export.contains("ConfigurationSummaryView(text: preview)"))
        XCTAssertFalse(export.contains("ConfigurationTextView(text: preview, isScrollEnabled: false)"))
    }

    func testFullConfigurationPreviewIsPresentedFromTheStableExportRoot() throws {
        let source = try sourceText("Tower/Features/Export/ExportView.swift")
        let previewStart = try XCTUnwrap(source.range(of: "private struct ConfigurationPreview: View"))
        let sheetStart = try XCTUnwrap(source.range(of: "private struct ConfigurationPreviewSheet: View"))
        let previewSource = String(source[previewStart.lowerBound..<sheetStart.lowerBound])

        XCTAssertTrue(source.contains("@State private var previewPayload: ConfigurationPreviewPayload?"))
        XCTAssertTrue(source.contains(".fullScreenCover(item: $previewPayload)"))
        XCTAssertTrue(source.contains("previewPayload = ConfigurationPreviewPayload(configuration: configuration)"))
        XCTAssertFalse(
            previewSource.contains(".sheet("),
            "懒加载预览卡片不能持有自己的弹窗状态，否则滚动更新时点击会丢失"
        )
    }

    func testSubscriptionDoHUsesThePublicSwiftNetworkAPI() throws {
        let source = try sourceText("Tower/Services/SubscriptionParser.swift")

        XCTAssertTrue(source.contains("NWParameters.PrivacyContext.default"))
        XCTAssertTrue(source.contains(".https(url, serverAddresses: [])"))
        XCTAssertFalse(source.contains("_nw_privacy_context_default_context"))
        XCTAssertFalse(source.contains("nw_resolver_config_create_https"))
    }

    /// A sheet can be dragged down as well as dismissed by its button, and a
    /// name typed but never committed is simply gone. The button path is
    /// covered above; this covers the other one, from the export page that owns
    /// both the draft and the presentation flag.
    func testClosingTheSettingsSheetAnyWayCommitsTheConfigurationName() throws {
        let export = try sourceText("Tower/Features/Export/ExportView.swift")
        let rootStart = try XCTUnwrap(export.range(of: "struct ExportView: View"))
        let sheetStart = try XCTUnwrap(export.range(of: "private struct ExportSettingsSheet: View"))
        let root = String(export[rootStart.lowerBound..<sheetStart.lowerBound])

        let observer = try XCTUnwrap(
            root.range(of: ".onChange(of: isSettingsPresented)"),
            "拖动关闭设置页时没有任何地方提交名称草稿"
        )
        let commit = try XCTUnwrap(
            root.range(of: "model.setConfigurationName(configurationNameDraft.committedName)"),
            "监听到关闭却没有提交草稿"
        )
        XCTAssertLessThan(observer.lowerBound, commit.lowerBound)
    }

    /// LAN sharing on an Apple silicon Mac lives or dies by one entitlement
    /// that has no effect on iPhone at all. Nothing in an iOS test run — or in
    /// a hundred iPhone installs — would notice it going missing, so the
    /// checkout is the only place it can be guarded.
    func testMacLANSharingKeepsItsIncomingConnectionEntitlement() throws {
        let entitlements = try sourceText("Tower/Tower.entitlements")
        XCTAssertTrue(
            entitlements.contains("com.apple.security.network.server"),
            "the macOS sandbox denies incoming connections without this key"
        )
    }

    func testWelcomeNetworkPromiseIncludesOptInAutomationAndCloudSync() throws {
        let source = try sourceText("Tower/Features/Onboarding/WelcomeView.swift")

        XCTAssertTrue(source.contains("title: \"联网选项由您决定\""), source)
        XCTAssertTrue(
            source.contains("自动更新和 iCloud 同步默认关闭，只有您主动开启后才运行。"),
            source
        )
        XCTAssertFalse(source.contains("title: \"只在您按下时联网\""), source)
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
