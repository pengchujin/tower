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
        XCTAssertTrue(architecture.contains("七种配置生成"))
        XCTAssertTrue(architecture.contains("Hiddify"))
        XCTAssertTrue(architecture.contains("Egern"))
        XCTAssertTrue(readme.contains("名称优先"))
        XCTAssertFalse(readme.contains("IP 优先国家地区聚合"))
    }

    func testMapRegionRowsReuseTheParentCountryResolutionBatch() throws {
        let source = try sourceText("Tower/Features/Subscriptions/NodeMapOverview.swift")

        XCTAssertTrue(
            source.contains("ExpandableNodeRow(node: node, resolvesRegionOnAppear: false)"),
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
        let nextViewStart = try XCTUnwrap(subscriptions.range(of: "private struct SubscriptionUsageRow: View"))
        let cardSource = String(subscriptions[cardStart.lowerBound..<nextViewStart.lowerBound])

        XCTAssertTrue(cardSource.contains(".towerCard()"))
        XCTAssertTrue(
            cardSource.contains(
                "ExpandableNodeRow(node: node, usesInsetBackground: false, showsInclusionToggle: true)"
            ),
            "自有节点应使用白色外层卡片，并显示参与导出的勾选控件"
        )
    }

    func testRulesViewExposesSearchableGroupSelectionAndPersistentCustomFlows() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")

        XCTAssertTrue(source.contains("RulesOverviewCard()"))
        XCTAssertTrue(source.contains(".searchable("))
        XCTAssertTrue(source.contains("rule-group-selector"))
        XCTAssertTrue(source.contains("custom-rule-flow-list"))
        XCTAssertTrue(source.contains("custom-rule-flow-editor"))
        XCTAssertTrue(source.contains("scrollDismissesKeyboard(.interactively)"))
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

    func testRuleGroupCustomizationDoesNotOfferBulkEnableAndIncludesEmojiToggle() throws {
        let source = try sourceText("Tower/Features/Rules/RulesView.swift")

        XCTAssertTrue(source.contains("SectionHeading(title: \"自定义\""))
        XCTAssertTrue(source.contains("Text(\"自定义分组服务\")"))
        XCTAssertTrue(source.contains("\"显示 Emoji\""))
        XCTAssertFalse(source.contains("Button(\"全部启用\")"))
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

    func testRenewalReminderAppearsBeforeLANSharing() throws {
        let source = try sourceText("Tower/Features/Settings/SettingsView.swift")
        let reminder = try XCTUnwrap(source.range(of: "RenewalReminderCard()"))
        let sharing = try XCTUnwrap(source.range(of: "LANSharingCard("))

        XCTAssertLessThan(reminder.lowerBound, sharing.lowerBound)
    }

    func testBottomNavigationHasThreeTabsAndSettingsLivesInExportToolbar() throws {
        let root = try sourceText("Tower/TowerApp.swift")
        let export = try sourceText("Tower/Features/Export/ExportView.swift")

        XCTAssertFalse(root.contains("AppTab.settings"))
        XCTAssertTrue(export.contains("accessibilityIdentifier(\"open-settings\")"))
        XCTAssertTrue(export.contains("SettingsView()"))
        XCTAssertTrue(export.contains("ToolbarItem(placement: .topBarTrailing)"))
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

    private func sourceText(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
