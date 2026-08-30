import XCTest
@testable import Tower

private struct EditingSubscriptionFetcher: SubscriptionFetching {
    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        ImportResult(nodes: [], rejectedLineCount: 0, usage: source.usage)
    }
}

final class SubscriptionInteractionTests: XCTestCase {
    @MainActor
    func testBatchSubscriptionEnablementChangesOnlySelectedSources() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-batch-subscription-enable-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let first = SubscriptionSource(name: "一", urlString: "https://one.example/sub")
        let second = SubscriptionSource(name: "二", urlString: "https://two.example/sub")
        let third = SubscriptionSource(name: "三", urlString: "https://three.example/sub")
        try store.save(AppSnapshot(
            subscriptions: [first, second, third], nodes: [],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge
        ))
        let model = AppModel(persistence: store, arguments: [])

        model.setSubscriptions([first, third], enabled: false)

        XCTAssertEqual(model.subscriptions.map(\.isEnabled), [false, true, false])
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.subscriptions.map(\.isEnabled), [false, true, false])
    }

    @MainActor
    func testBatchSubscriptionDeletionRemovesOnlySelectedSourcesAndTheirNodes() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-batch-subscription-delete-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let first = SubscriptionSource(name: "一", urlString: "https://one.example/sub")
        let second = SubscriptionSource(name: "二", urlString: "https://two.example/sub")
        let firstNode = ProxyNode(
            sourceID: first.id, kind: .shadowsocks, name: "一号节点",
            server: "one.example", port: 8388, cipher: "aes-256-gcm", password: "one",
            rawURI: "ss://one"
        )
        let secondNode = ProxyNode(
            sourceID: second.id, kind: .shadowsocks, name: "二号节点",
            server: "two.example", port: 8388, cipher: "aes-256-gcm", password: "two",
            rawURI: "ss://two"
        )
        try store.save(AppSnapshot(
            subscriptions: [first, second], nodes: [firstNode, secondNode],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge
        ))
        let model = AppModel(persistence: store, arguments: [])

        model.deleteSubscriptions([first])

        XCTAssertEqual(model.subscriptions.map(\.id), [second.id])
        XCTAssertEqual(model.nodes.map(\.id), [secondNode.id])
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.subscriptions.map(\.id), [second.id])
        XCTAssertEqual(reloaded.nodes.map(\.id), [secondNode.id])
    }

    @MainActor
    func testBatchLocalNodeDeletionDoesNotRemoveSubscriptionNodes() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-batch-local-node-delete-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let local = ProxyNode(
            kind: .shadowsocks, name: "本地节点", server: "local.example", port: 8388,
            cipher: "aes-256-gcm", password: "local", rawURI: "ss://local"
        )
        let subscriptionNode = ProxyNode(
            sourceID: UUID(), kind: .shadowsocks, name: "机场节点", server: "airport.example",
            port: 8388, cipher: "aes-256-gcm", password: "airport", rawURI: "ss://airport"
        )
        try store.save(AppSnapshot(
            subscriptions: [], nodes: [local, subscriptionNode],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge
        ))
        let model = AppModel(persistence: store, arguments: [])

        model.deleteLocalNodes([local, subscriptionNode])

        XCTAssertEqual(model.nodes.map(\.id), [subscriptionNode.id])
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.nodes.map(\.id), [subscriptionNode.id])
    }

    @MainActor
    func testBatchRefreshUpdatesOnlySelectedSubscriptions() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-batch-subscription-refresh-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let first = SubscriptionSource(name: "一", urlString: "https://one.example/sub")
        let second = SubscriptionSource(name: "二", urlString: "https://two.example/sub")
        try store.save(AppSnapshot(
            subscriptions: [first, second], nodes: [],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge
        ))
        let model = AppModel(
            persistence: store,
            subscriptionService: EditingSubscriptionFetcher(),
            arguments: []
        )

        await model.refreshSubscriptions([first])

        XCTAssertNotNil(model.subscriptions.first { $0.id == first.id }?.lastUpdatedAt)
        XCTAssertNil(model.subscriptions.first { $0.id == second.id }?.lastUpdatedAt)
    }

    func testHomeOffersDedicatedSourceManagementEntry() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let managementURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("SourceManagementView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
            + String(contentsOf: managementURL, encoding: .utf8)

        XCTAssertTrue(source.contains("source-management-button"))
        XCTAssertTrue(source.contains("SourceManagementView(initialRoute: route)"))
        XCTAssertTrue(source.contains("source-management-list"))
        XCTAssertTrue(source.contains("批量管理"))
        XCTAssertTrue(source.contains("自有节点"))
        for route in ["subscriptions", "nodes", "regions", "localNodes"] {
            XCTAssertTrue(source.contains("case .\(route)"), "管理页面缺少对应入口：\(route)")
        }
        #else
        throw XCTSkip("该测试检查首页批量管理入口，只在模拟器构建环境运行")
        #endif
    }

    @MainActor
    func testSubscriptionsCanBeEditedPersistently() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-subscription-edit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let first = SubscriptionSource(name: "一", urlString: "https://one.example/sub")
        let second = SubscriptionSource(name: "二", urlString: "https://two.example/sub")
        let firstNode = ProxyNode(
            sourceID: first.id, kind: .shadowsocks, name: "一号节点",
            server: "one.example", port: 8388, cipher: "aes-256-gcm", password: "one",
            rawURI: "ss://one"
        )
        let secondNode = ProxyNode(
            sourceID: second.id, kind: .shadowsocks, name: "二号节点",
            server: "two.example", port: 8388, cipher: "aes-256-gcm", password: "two",
            rawURI: "ss://two"
        )
        try store.save(AppSnapshot(
            subscriptions: [first, second], nodes: [firstNode, secondNode],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge
        ))
        let model = AppModel(
            persistence: store,
            subscriptionService: EditingSubscriptionFetcher(),
            arguments: []
        )

        try await model.updateSubscriptionDetails(
            first,
            name: "第一机场",
            urlString: first.urlString,
            userAgent: nil,
            dnsOverHTTPSURL: nil
        )
        XCTAssertEqual(model.subscriptions.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.availableNodes.map(\.id), [firstNode.id, secondNode.id])
        XCTAssertEqual(model.subscriptions[0].name, "第一机场")
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.subscriptions.map(\.id), [first.id, second.id])
        XCTAssertEqual(reloaded.availableNodes.map(\.id), [firstNode.id, secondNode.id])
        XCTAssertEqual(reloaded.subscriptions[0].name, "第一机场")
    }

    @MainActor
    func testLocalNodesCanBeEditedPersistently() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-local-node-edit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PersistenceStore(fileURL: fileURL)
        let first = ProxyNode(
            kind: .shadowsocks, name: "本地一", server: "one.example", port: 8388,
            cipher: "aes-256-gcm", password: "one", rawURI: "ss://one"
        )
        let airport = ProxyNode(
            sourceID: UUID(), kind: .shadowsocks, name: "机场节点", server: "airport.example",
            port: 8388, cipher: "aes-256-gcm", password: "airport", rawURI: "ss://airport"
        )
        let second = ProxyNode(
            kind: .shadowsocks, name: "本地二", server: "two.example", port: 8388,
            cipher: "aes-256-gcm", password: "two", rawURI: "ss://two"
        )
        try store.save(AppSnapshot(
            subscriptions: [], nodes: [first, airport, second],
            selectedPresetID: AppModel.defaultRuleSchemeID, selectedTarget: .surge
        ))
        let model = AppModel(persistence: store, arguments: [])
        var draft = ManualNodeDraft(node: first)
        draft.name = "编辑后的节点"
        draft.server = "edited.example"

        try model.updateLocalNode(first, with: draft)
        XCTAssertEqual(model.localNodes.map(\.id), [first.id, second.id])
        XCTAssertEqual(model.localNodes[0].name, "编辑后的节点")
        XCTAssertEqual(model.localNodes[0].server, "edited.example")
        XCTAssertEqual(model.nodes[1].id, airport.id, "编辑自有节点不能移动机场节点")
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.localNodes.map(\.id), [first.id, second.id])
        XCTAssertEqual(reloaded.localNodes[0].name, "编辑后的节点")
    }

    func testAddSourceSheetRequestsClipboardWhenPresented() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/AddSourceSheet.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        // Matched loosely on purpose: the call may be guarded — editing an
        // existing node opens the same sheet and must not read the clipboard,
        // since that is not a paste and would raise iOS's paste banner for
        // nothing. What the constraint requires is that presenting the sheet
        // to ADD something still asks once.
        let presentationRequest = #"\.onAppear\s*\{[^}]*requestClipboardContent\(\)"#

        XCTAssertNotNil(
            source.range(of: presentationRequest, options: .regularExpression),
            "打开添加面板时应主动请求受支持的剪贴板内容"
        )
        // And the read stays single-shot within one presentation.
        XCTAssertNotNil(
            source.range(of: #"guard\s*!didReadPasteboard\s*else\s*\{\s*return\s*\}"#, options: .regularExpression),
            "同一次面板展示不应重复读取剪贴板"
        )
        #else
        throw XCTSkip("该测试检查开发源码中的 SwiftUI 触发器，只在模拟器构建环境运行")
        #endif
    }

    func testOverviewMetricsOpenMatchingManagementSections() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("sourceManagementRoute = metric.managementRoute"))
        XCTAssertTrue(source.contains("case .subscriptions: .subscriptions"))
        XCTAssertTrue(source.contains("case .nodes: .nodes"))
        XCTAssertTrue(source.contains("case .regions: .regions"))
        XCTAssertTrue(source.contains("case .localNodes: .localNodes"))
        XCTAssertFalse(source.contains("proxy.scrollTo(metric.scrollTarget"))
        #else
        throw XCTSkip("该测试检查首页概览入口，只在模拟器构建环境运行")
        #endif
    }

    func testAddSourceSheetDismissesKeyboardBeforeSaving() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/AddSourceSheet.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("focusedField = nil"))
        XCTAssertTrue(source.contains("ToolbarItemGroup(placement: .keyboard)"))
        #else
        throw XCTSkip("该测试检查 SwiftUI 源码，只在模拟器构建环境运行")
        #endif
    }

    func testAddSourceSheetOffersPasteScanAndManualTabs() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/AddSourceSheet.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for tab in ["粘贴识别", "扫码", "手动添加"] {
            XCTAssertTrue(source.contains(tab), "添加页缺少 \(tab) 标签")
        }
        XCTAssertTrue(source.contains("case paste"))
        XCTAssertTrue(source.contains("case scan"))
        XCTAssertTrue(source.contains("case manual"))
        XCTAssertTrue(source.contains("minHeight: 62"), "三种添加方式需要足够大的触控高度")
        #else
        throw XCTSkip("该测试检查 SwiftUI 源码，只在模拟器构建环境运行")
        #endif
    }

    func testQRCodeScannerIsEmbeddedInAddSourcePage() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/AddSourceSheet.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("QRCodeScannerPreview"))
        XCTAssertFalse(source.contains(".sheet(isPresented: $isScannerPresented)"))
        #else
        throw XCTSkip("该测试检查开发源码中的扫码容器，只在模拟器构建环境运行")
        #endif
    }

    func testQRCodeScannerAndCameraPurposeAreConfigured() throws {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scanner = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/QRCodeScannerSheet.swift"),
            encoding: .utf8
        )
        let project = try String(
            contentsOf: root.appendingPathComponent("Tower.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertTrue(scanner.contains("DataScannerViewController"))
        XCTAssertTrue(scanner.contains(".barcode(symbologies: [.qr])"))
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSCameraUsageDescription"))
        #else
        throw XCTSkip("该测试检查工程配置，只在模拟器构建环境运行")
        #endif
    }

    func testQRCodeArtifactBuilderCreatesShareablePNG() async throws {
        let builtArtifact = await QRCodeShareArtifactBuilder.make(
            value: "ss://example-share-link",
            id: UUID()
        )
        let artifact = try XCTUnwrap(builtArtifact)
        defer { try? FileManager.default.removeItem(at: artifact.fileURL) }

        XCTAssertGreaterThan(artifact.image.size.width, 0)
        XCTAssertEqual(artifact.fileURL.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.fileURL.path))
        XCTAssertGreaterThan(
            (try Data(contentsOf: artifact.fileURL)).count,
            100
        )
    }

    func testMapOffersTopTrailingLatencyButtonAndLongPressModePicker() throws {
        XCTAssertEqual(
            NodeLatencyTestMode.allCases.map(\.rawValue),
            ["自动", "ICMP", "TCP", "HTTP"]
        )

        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/NodeMapOverview.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("test-all-latencies"))
        XCTAssertTrue(source.contains("overlay(alignment: .topTrailing)"))
        XCTAssertTrue(source.contains("contextMenu"))
        XCTAssertTrue(source.contains("NodeLatencyTestMode.allCases"))
        #endif
    }

    func testHomeKeepsMapVisibleWithoutNodes() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("if !model.enabledNodes.isEmpty {\n                            NodeMapOverview"),
            "没有节点时也必须保留地图"
        )
        #else
        throw XCTSkip("该测试检查开发源码中的首页结构，只在模拟器构建环境运行")
        #endif
    }

    func testHomeMapOnlyReceivesIncludedNodes() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("NodeMapOverview(nodes: model.enabledNodes)"),
            "首页地图只能展示用户当前勾选、会被导出的节点"
        )
        XCTAssertFalse(source.contains("NodeMapOverview(nodes: model.availableNodes)"))
        #else
        throw XCTSkip("该测试检查开发源码中的首页地图数据源，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionExpansionMatchesTheRulesPageAnimation() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let rulesURL = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Rules/RulesView.swift")
        let rulesSource = try String(contentsOf: rulesURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private struct SubscriptionCard"))
        let end = try XCTUnwrap(source.range(of: "private struct LocalNodeCard"))
        let cardSource = String(source[start.lowerBound..<end.lowerBound])
        let togglePattern = "withAnimation(TowerMotion.disclosure(reduceMotion: reduceMotion)) { isExpanded.toggle() }"

        XCTAssertTrue(rulesSource.contains(togglePattern), "规则页必须保留作为对照的展开动画")
        XCTAssertTrue(cardSource.contains(togglePattern), "订阅节点应使用与规则页相同的弹簧状态切换")
        XCTAssertTrue(cardSource.contains(".transition(.opacity)"), "订阅节点应与规则详情一样使用透明度过渡")
        XCTAssertFalse(
            cardSource.contains(".animation(TowerMotion.disclosure(reduceMotion: reduceMotion), value: isExpanded)"),
            "箭头应由展开事务统一驱动，不再单独动画"
        )
        XCTAssertFalse(cardSource.contains("private var expansionAnimation"))
        #else
        throw XCTSkip("该测试检查订阅与规则页动画的一致性，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionToggleMovesWithTheCollapsingCard() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let cardStart = try XCTUnwrap(source.range(of: "private struct SubscriptionCard"))
        let cardEnd = try XCTUnwrap(source.range(of: "private struct SubscriptionTrafficBar"))
        let cardSource = String(source[cardStart.lowerBound..<cardEnd.lowerBound])
        let toggleStart = try XCTUnwrap(cardSource.range(of: "Toggle("))
        let toggleEnd = try XCTUnwrap(
            cardSource.range(of: ".accessibilityLabel(\"启用 ", range: toggleStart.lowerBound..<cardSource.endIndex)
        )
        let toggleSource = String(cardSource[toggleStart.lowerBound..<toggleEnd.lowerBound])

        XCTAssertFalse(
            toggleSource.contains(".transaction { $0.animation = nil }"),
            "启用勾选必须继承卡片收起动画，否则会先瞬移到最终位置"
        )
        #else
        throw XCTSkip("该测试检查订阅卡片动画事务，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionDeletionUsesAStableAlertInsteadOfAnAnchoredDialog() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let viewStart = try XCTUnwrap(source.range(of: "struct SubscriptionsView: View"))
        let viewEnd = try XCTUnwrap(source.range(of: "@ViewBuilder\n    private var subscriptionsSection"))
        let viewSource = String(source[viewStart.lowerBound..<viewEnd.lowerBound])

        XCTAssertTrue(
            viewSource.contains(".alert("),
            "订阅删除确认应使用固定居中的系统警告框"
        )
        XCTAssertTrue(
            viewSource.contains("presenting: pendingDeletion"),
            "删除警告框应持有触发时的删除对象"
        )
        XCTAssertFalse(
            viewSource.contains(".confirmationDialog("),
            "页面根视图上的确认对话框会产生与卡片无关的浮动锚点"
        )
        #else
        throw XCTSkip("该测试检查订阅删除确认框的呈现方式，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionCardUsesAirplaneIconInsteadOfCloud() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private struct SubscriptionCard"))
        let end = try XCTUnwrap(source.range(of: "private struct LocalNodeCard"))
        let cardSource = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(cardSource.contains("Image(systemName: \"airplane\")"))
        XCTAssertFalse(cardSource.contains("Image(systemName: \"cloud.fill\")"))
        #else
        throw XCTSkip("该测试检查订阅卡片图标，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionCardsUseCompactTrafficBarAndInlineFacts() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private struct SubscriptionCard"))
        let end = try XCTUnwrap(source.range(of: "private struct LocalNodeCard"))
        let cardSource = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(
            cardSource.contains("SubscriptionTrafficBar("),
            "剩余流量应使用贯穿卡片的横向信息条"
        )
        XCTAssertTrue(
            cardSource.contains("SubscriptionFactsRow("),
            "节点数和到期天数应压缩在同一行直接显示"
        )
        XCTAssertFalse(
            cardSource.contains("SubscriptionUsageRow(usage:"),
            "流量、到期和机场公告不能在展开后重复成一段详情"
        )
        XCTAssertFalse(
            cardSource.contains("SubscriptionMetricTile"),
            "紧凑卡片不应继续使用三个等高大指标块"
        )
        XCTAssertFalse(
            cardSource.contains("minimumTileHeight = 64.0"),
            "订阅信息不应再被 64pt 指标块撑高"
        )
        XCTAssertFalse(
            cardSource.contains("Text(isRefreshing ? String(localized: \"正在更新\") : String(localized: \"更新订阅\"))"),
            "更新订阅应收成图标操作，不能继续占用整宽按钮"
        )
        #else
        throw XCTSkip("该测试检查订阅卡片布局层级，只在模拟器构建环境运行")
        #endif
    }

    func testExpandedSubscriptionShowsDistinctAnnouncementsBeforeNodes() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private struct SubscriptionCard"))
        let end = try XCTUnwrap(source.range(of: "private struct SubscriptionTrafficBar"))
        let cardSource = String(source[start.lowerBound..<end.lowerBound])
        let announcementCall = try XCTUnwrap(
            cardSource.range(of: "SubscriptionAnnouncementSection(notices: source.usage?.distinctNotices ?? [])")
        )
        let nodeRows = try XCTUnwrap(cardSource.range(of: "ForEach(model.nodes(for: source))"))

        XCTAssertLessThan(
            announcementCall.lowerBound,
            nodeRows.lowerBound,
            "机场公告应在展开后先于节点列表出现"
        )
        XCTAssertTrue(
            cardSource.contains("if isExpanded"),
            "公告应跟随节点展开区显示，不能撑高所有收起卡片"
        )
        #else
        throw XCTSkip("该测试检查订阅展开区的公告层级，只在模拟器构建环境运行")
        #endif
    }

    func testMapAndSubscriptionReuseAStaticCompactNodeList() throws {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let subscriptions = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift"),
            encoding: .utf8
        )
        let cardStart = try XCTUnwrap(subscriptions.range(of: "private struct SubscriptionCard"))
        let cardEnd = try XCTUnwrap(subscriptions.range(of: "private struct SubscriptionTrafficBar"))
        let cardSource = String(subscriptions[cardStart.lowerBound..<cardEnd.lowerBound])

        XCTAssertTrue(
            cardSource.contains("LazyVStack(spacing: 0)"),
            "订阅展开后应是紧密平铺列表，不再给每个节点留卡片间距"
        )
        XCTAssertTrue(
            cardSource.contains("CompactNodeRow(node: node)"),
            "订阅展开区应使用不再二次展开的紧凑节点行"
        )
        XCTAssertTrue(
            cardSource.contains(".overlay(alignment: .bottom)"),
            "平铺节点应使用细分隔线建立行边界"
        )

        let nodeRows = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/NodeMapOverview.swift"),
            encoding: .utf8
        )
        let selectedRegionStart = try XCTUnwrap(nodeRows.range(of: "private struct SelectedRegionNodes"))
        let selectedRegionEnd = try XCTUnwrap(nodeRows.range(of: "struct CompactNodeRow"))
        let selectedRegionSource = String(nodeRows[selectedRegionStart.lowerBound..<selectedRegionEnd.lowerBound])
        XCTAssertTrue(
            selectedRegionSource.contains("CompactNodeRow(node: node, resolvesRegionOnAppear: false)"),
            "地图选中地区后的节点应和订阅展开列表共用同一行样式"
        )

        let rowStart = try XCTUnwrap(nodeRows.range(of: "struct CompactNodeRow"))
        let rowEnd = try XCTUnwrap(nodeRows.range(of: "struct ExpandableNodeRow"))
        let rowSource = String(nodeRows[rowStart.lowerBound..<rowEnd.lowerBound])

        XCTAssertTrue(
            rowSource.contains("NodeLatencyBadge(node: node, showsUntestedState: false)"),
            "未测速的紧凑行应留空，测试后再直接显示结果"
        )
        XCTAssertTrue(
            rowSource.contains("Image(systemName: \"square.and.arrow.up\")"),
            "紧凑行右侧应直接提供分享"
        )
        XCTAssertFalse(
            rowSource.contains("isExpanded") || rowSource.contains("info.circle"),
            "紧凑节点行不应再提供第二层详情展开"
        )
        #else
        throw XCTSkip("该测试检查订阅展开区的 SwiftUI 层级，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionTrafficUsesNeutralLabelsWithSemanticGreenProgress() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private struct SubscriptionTrafficBar"))
        let end = try XCTUnwrap(source.range(of: "private struct LocalNodeCard"))
        let compactInfoSource = String(source[start.lowerBound..<end.lowerBound])

        let trafficEnd = try XCTUnwrap(compactInfoSource.range(of: "private struct SubscriptionFactsRow"))
        let trafficSource = String(compactInfoSource[..<trafficEnd.lowerBound])

        XCTAssertFalse(compactInfoSource.contains("Color.purple"), "正常到期信息应使用中性色")
        XCTAssertFalse(trafficSource.contains(".foregroundStyle(Color.green)"), "流量图标和标题不应继续使用绿色")
        XCTAssertTrue(trafficSource.contains(".foregroundStyle(.primary)"), "流量图标和标题应使用主文字色")
        XCTAssertTrue(trafficSource.contains(".tint(Color.green)"), "流量进度应使用语义绿色")
        XCTAssertFalse(
            trafficSource.contains(".background(Color.green.opacity(0.08)"),
            "流量信息条不应再使用淡绿色围合背景"
        )
        XCTAssertTrue(
            compactInfoSource.contains(".background(Color.primary.opacity(0.055)"),
            "次要操作应使用中性按钮底色"
        )
        XCTAssertTrue(
            compactInfoSource.contains("expiryDaysRemaining <= 3 ? Color.orange : Color.secondary"),
            "只有临近到期时才使用语义警告色"
        )
        #else
        throw XCTSkip("该测试检查订阅卡片的色彩层级，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionTrafficBarLabelsRemainingAndTotalTraffic() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let cardStart = try XCTUnwrap(source.range(of: "private struct SubscriptionCard"))
        let trafficStart = try XCTUnwrap(source.range(of: "private struct SubscriptionTrafficBar"))
        let trafficEnd = try XCTUnwrap(source.range(of: "private struct SubscriptionFactsRow"))
        let cardSource = String(source[cardStart.lowerBound..<trafficStart.lowerBound])
        let trafficSource = String(source[trafficStart.lowerBound..<trafficEnd.lowerBound])

        XCTAssertTrue(
            cardSource.contains("totalBytes: metrics.totalBytes"),
            "订阅卡片应将套餐总流量传给流量条"
        )
        XCTAssertTrue(
            trafficSource.contains("Text(\"剩余\")"),
            "流量条的可见文案应精简为剩余"
        )
        XCTAssertTrue(trafficSource.contains("Text(\"总流量\")"))
        #else
        throw XCTSkip("该测试检查订阅流量条文案，只在模拟器构建环境运行")
        #endif
    }

    @MainActor
    func testSubscriptionPresentationNodesExcludeMetadataEntries() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tower-subscription-presentation-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let source = SubscriptionSource(name: "测试订阅", urlString: "https://example.com/sub")
        let actualNode = ProxyNode(
            sourceID: source.id,
            kind: .shadowsocks,
            name: "东京 01",
            server: "node.example.com",
            port: 8388,
            cipher: "aes-256-gcm",
            password: "password",
            rawURI: "ss://node"
        )
        let metadataNode = ProxyNode(
            sourceID: source.id,
            kind: .shadowsocks,
            name: "剩余流量：100 GB",
            server: "metadata.invalid",
            port: 1,
            cipher: "none",
            password: "metadata",
            rawURI: "ss://metadata",
            isSubscriptionMetadata: true
        )
        let store = PersistenceStore(fileURL: fileURL)
        try store.save(AppSnapshot(
            subscriptions: [source],
            nodes: [metadataNode, actualNode],
            selectedPresetID: AppModel.defaultRuleSchemeID,
            selectedTarget: .surge
        ))
        let model = AppModel(persistence: store, arguments: [])

        // Off — the switch's default — the notice is an ordinary node: it shows
        // on the card, and it is also in every exported configuration. The card
        // must not report a number the export does not honour.
        XCTAssertFalse(model.filterSubscriptionInfoNodes)
        XCTAssertEqual(model.nodeCount(for: source), model.enabledNodes.count)
        XCTAssertEqual(
            Set(model.nodes(for: source).map(\.id)),
            [metadataNode.id, actualNode.id]
        )

        model.setFilterSubscriptionInfoNodes(true)

        XCTAssertEqual(model.nodes(for: source).map(\.id), [actualNode.id])
        XCTAssertEqual(model.nodeCount(for: source), 1)
        XCTAssertEqual(model.enabledNodes.map(\.id), [actualNode.id])
    }

    func testSubscriptionCardMetricsExposeAvailableQuotaAndExpiryDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiry = calendar.date(byAdding: .day, value: 20, to: now)!
        let usage = SubscriptionUsage(
            uploadBytes: 3 * 1_024,
            downloadBytes: 7 * 1_024,
            totalBytes: 100 * 1_024,
            expiresAt: expiry
        )

        let metrics = SubscriptionCardMetrics(
            nodeCount: 55,
            usage: usage,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(metrics.nodeCount, 55)
        XCTAssertEqual(metrics.remainingBytes, 90 * 1_024)
        XCTAssertEqual(metrics.totalBytes, 100 * 1_024)
        XCTAssertEqual(metrics.expiryDaysRemaining, 20)
        XCTAssertEqual(try XCTUnwrap(metrics.usedFraction), 0.1, accuracy: 0.000_001)
    }

    func testSubscriptionCardMetricsOmitUnavailableOptionalValues() {
        let metrics = SubscriptionCardMetrics(nodeCount: 7, usage: nil)

        XCTAssertEqual(metrics.nodeCount, 7)
        XCTAssertNil(metrics.remainingBytes)
        XCTAssertNil(metrics.totalBytes)
        XCTAssertNil(metrics.expiryDaysRemaining)
        XCTAssertNil(metrics.usedFraction)
    }

    func testSubscriptionCardMetricsRecoverNoticeOnlyTrafficAndExpiry() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 22))!
        let usage = SubscriptionUsage(
            notices: ["剩余流量：101.69 GB", "套餐到期：2026-09-11"]
        )

        let metrics = SubscriptionCardMetrics(
            nodeCount: 1,
            usage: usage,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(metrics.remainingBytes, Int64(101.69 * 1_073_741_824))
        XCTAssertEqual(metrics.expiryDaysRemaining, 20)
    }

    func testSubscriptionAndLocalNodeLongPressMenusOfferEditingWithoutSorting() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Label(\"编辑\""), "长按菜单缺少编辑")
        XCTAssertFalse(source.contains("Label(\"上移\""))
        XCTAssertFalse(source.contains("Label(\"下移\""))
        XCTAssertFalse(source.contains("model.moveSubscription"))
        XCTAssertFalse(source.contains("model.moveLocalNode"))
        XCTAssertTrue(source.contains("AddSourceSheet(editingNode:"))
        #else
        throw XCTSkip("该测试检查首页长按菜单，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionNameDraftKeepsTheLastTypedNameWhenSavingDismissesTheKeyboard() {
        var draft = SubscriptionNameDraft(text: "原始名称")
        draft.text = "Tower Test"

        // SwiftUI can publish one final empty TextField value while a toolbar
        // button dismisses the keyboard and the sheet at the same time.
        draft.text = ""

        XCTAssertEqual(draft.committedName, "Tower Test")
    }

    func testSubscriptionEditorKeepsItsNameDraftAboveThePresentedSheet() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let rootStart = try XCTUnwrap(source.range(of: "struct SubscriptionsView: View"))
        let sheetStart = try XCTUnwrap(source.range(of: "private struct EditSubscriptionSheet: View"))
        let nextType = try XCTUnwrap(source.range(of: "private struct SubscriptionOverviewCard: View"))
        let root = String(source[rootStart.lowerBound..<sheetStart.lowerBound])
        let sheet = String(source[sheetStart.lowerBound..<nextType.lowerBound])

        XCTAssertTrue(
            root.contains("@State private var subscriptionNameDraft"),
            "名称草稿必须由不会随弹窗重建的首页持有"
        )
        XCTAssertTrue(root.contains("nameDraft: $subscriptionNameDraft"))
        XCTAssertTrue(sheet.contains("@Binding var nameDraft: SubscriptionNameDraft"))
        XCTAssertFalse(
            sheet.contains("@State private var name: String"),
            "弹窗内部状态可能在工具栏提交前被重置，不能保存唯一的名称草稿"
        )
        XCTAssertTrue(sheet.contains("name: nameDraft.committedName"))
        #else
        throw XCTSkip("该测试检查订阅编辑弹窗的状态归属，只在模拟器构建环境运行")
        #endif
    }

    /// `detail` used to be re-localized here with a `LocalizedStringKey` built
    /// at runtime — a key no extractor can see, so a literal passed in never
    /// reached the catalog and rendered in Chinese in the other fourteen
    /// languages while `check_localization.sh` still reported PASS. Callers now
    /// localize before they pass, and this component prints what it is given.
    func testSectionHeadingDoesNotHideKeysFromTheExtractor() throws {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(
            contentsOf: root.appendingPathComponent("Tower/Design/TowerTheme.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(theme.contains("LocalizedStringKey(detail)"))

        let settings = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(settings.contains("SectionHeading(title: \"配置管理\")"))
        #else
        throw XCTSkip("该测试检查自定义标题组件，只在模拟器构建环境运行")
        #endif
    }

    func testLocalizedDefaultProfileNamesFollowTheCurrentAppLanguage() {
        XCTAssertEqual(TowerBrand.migratedDefaultName("塔台"), TowerBrand.localizedName)
        XCTAssertEqual(TowerBrand.migratedDefaultName("Tower"), TowerBrand.localizedName)
        XCTAssertEqual(TowerBrand.migratedDefaultName("My Profile"), "My Profile")
    }

    func testAvailableNodesAndRegionsOpenTheIntegratedManagementPage() throws {
        #if targetEnvironment(simulator)
        let subscriptionsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let managementURL = subscriptionsURL.deletingLastPathComponent()
            .appendingPathComponent("SourceManagementView.swift")
        let subscriptionsSource = try String(contentsOf: subscriptionsURL, encoding: .utf8)
        let managementSource = try String(contentsOf: managementURL, encoding: .utf8)

        XCTAssertTrue(subscriptionsSource.contains("navigationDestination(item: $sourceManagementRoute)"))
        XCTAssertFalse(subscriptionsSource.contains("navigationDestination(item: $nodeFilterRoute)"))
        XCTAssertFalse(subscriptionsSource.contains("proxy.scrollTo(metric.scrollTarget"))
        XCTAssertTrue(managementSource.contains("case .nodes, .regions: .exportFilter"))
        XCTAssertTrue(managementSource.contains("@State private var tab: SourceManagementTab"))
        XCTAssertTrue(managementSource.contains("ForEach(SourceManagementTab.allCases)"))
        XCTAssertTrue(managementSource.contains("case .exportFilter:"))
        XCTAssertTrue(managementSource.contains("NodeFilterSections(searchText: $searchText)"))
        XCTAssertTrue(managementSource.contains("Picker(\"管理内容\", selection: $tab)"))
        #else
        throw XCTSkip("该测试检查统一管理页面，只在模拟器构建环境运行")
        #endif
    }

    func testExportGroupsAreSortedByDescendingNodeCount() {
        let hongKongOne = ProxyNode(
            kind: .shadowsocks, name: "🇭🇰 香港 01", server: "hk-one.example", port: 8388,
            cipher: "aes-256-gcm", password: "one", rawURI: "ss://one"
        )
        let hongKongTwo = ProxyNode(
            kind: .shadowsocks, name: "🇭🇰 香港 02", server: "hk-two.example", port: 8388,
            cipher: "aes-256-gcm", password: "two", rawURI: "ss://two"
        )
        let japan = ProxyNode(
            kind: .trojan, name: "🇯🇵 日本 01", server: "jp.example", port: 443,
            password: "three", rawURI: "trojan://three"
        )

        let countries = NodeExportGroupBuilder.countryGroups(
            nodes: [japan, hongKongOne, hongKongTwo],
            countryCodes: [:]
        )
        XCTAssertEqual(countries.map(\.code), ["HK", "JP"])
        XCTAssertEqual(countries.map { $0.nodes.count }, [2, 1])

        let protocols = NodeExportGroupBuilder.protocolGroups(
            nodes: [japan, hongKongOne, hongKongTwo]
        )
        XCTAssertEqual(protocols.map(\.kind), [.shadowsocks, .trojan])
        XCTAssertEqual(protocols.map { $0.nodes.count }, [2, 1])
    }

    func testExportGroupSelectionStateDistinguishesNonePartialAndAll() {
        let none = NodeExportGroupSelectionState(includedCount: 0, totalCount: 3)
        let partial = NodeExportGroupSelectionState(includedCount: 1, totalCount: 3)
        let all = NodeExportGroupSelectionState(includedCount: 3, totalCount: 3)

        XCTAssertEqual(none, .none)
        XCTAssertEqual(partial, .partial)
        XCTAssertEqual(all, .all)
        XCTAssertFalse(none.isMenuSelected)
        XCTAssertTrue(
            partial.isMenuSelected,
            "地区或协议里只要还有一个启用节点，筛选菜单就应保留勾选"
        )
        XCTAssertTrue(all.isMenuSelected)
    }

    func testExportFilterKeepsRegionAndProtocolGroupSelectorsVisible() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/NodeFilterView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("LazyVGrid(columns: filterColumns"))
        XCTAssertFalse(
            source.contains("ScrollView(.horizontal)"),
            "地区和协议必须同时可见"
        )
        for filter in ["countryFilter", "protocolFilter"] {
            XCTAssertTrue(source.contains(filter), "缺少筛选项：\(filter)")
        }
        XCTAssertFalse(source.contains("private var sourceFilter"))
        XCTAssertFalse(source.contains("private var localFilter"))
        XCTAssertFalse(source.contains("Picker(\"国家地区\", selection: $countryCode)"))
        XCTAssertFalse(source.contains("Picker(\"协议\", selection: $kind)"))
        XCTAssertTrue(source.contains("exportGroupSelectionToggle("))
        XCTAssertTrue(source.contains("title: String(localized: \"全部地区\")"))
        XCTAssertTrue(source.contains("title: String(localized: \"全部协议\")"))
        XCTAssertTrue(source.contains("model.setNodes(nodes, included: shouldInclude)"))
        XCTAssertTrue(source.contains("NodeExportGroupBuilder.countryGroups"))
        XCTAssertTrue(source.contains("NodeExportGroupBuilder.protocolGroups"))

        // Still one bulk action, now taking the already-filtered list instead of
        // recomputing it: the filter used to run five times per redraw, once per
        // reader, which showed up as lag while typing in the search field.
        XCTAssertTrue(source.contains("private func bulkSelectionButton"))
        XCTAssertTrue(source.contains("model.setNodes(filteredNodes, included: !allIncluded)"))
        XCTAssertTrue(source.contains("let filteredNodes = self.filteredNodes"))
        XCTAssertTrue(source.contains(".frame(minHeight: 44)"))
        XCTAssertFalse(source.contains("include-all-filtered-nodes"))
        XCTAssertFalse(source.contains("exclude-all-filtered-nodes"))
        #else
        throw XCTSkip("该测试检查节点筛选页面结构，只在模拟器构建环境运行")
        #endif
    }

    func testBatchManagementRemovesManualSortingAndKeepsOnlyTopUpdate() throws {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let management = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/SourceManagementView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(management.contains("ToolbarItem(placement: .topBarTrailing)"))
        XCTAssertTrue(management.contains("SubscriptionRefreshToolbarButton(sources: subscriptionsToRefresh)"))
        XCTAssertTrue(management.contains("Button(\"更新\") {"))
        XCTAssertFalse(management.contains("Text(\"刷新\")"))
        XCTAssertFalse(management.contains("Image(systemName: \"arrow.clockwise\")"))
        XCTAssertFalse(management.contains(".labelStyle(.titleAndIcon)"))
        XCTAssertFalse(management.contains("EditMode"))
        XCTAssertFalse(management.contains(".onMove("))
        XCTAssertFalse(management.contains("\"排序\""))
        #else
        throw XCTSkip("该测试检查批量管理页面结构，只在模拟器构建环境运行")
        #endif
    }

    func testBatchManagementActionButtonsMatchExportActionBarGeometry() throws {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let management = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/SourceManagementView.swift"),
            encoding: .utf8
        )
        let export = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Export/ExportView.swift"),
            encoding: .utf8
        )
        let theme = try String(
            contentsOf: root.appendingPathComponent("Tower/Design/TowerTheme.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(theme.contains("static let actionBarButtonHeight: CGFloat = 50"))
        XCTAssertTrue(theme.contains("static let actionBarButtonCornerRadius: CGFloat = 16"))
        for source in [management, export] {
            XCTAssertTrue(source.contains("TowerTheme.actionBarButtonHeight"))
            XCTAssertTrue(source.contains("TowerTheme.actionBarButtonCornerRadius"))
            XCTAssertTrue(source.contains(".buttonStyle(ResponsivePressButtonStyle())"))
        }
        XCTAssertTrue(management.contains(".background(.bar)"))
        XCTAssertTrue(management.contains(".font(.headline)"))
        XCTAssertFalse(management.contains(".buttonStyle(.bordered)"))
        #else
        throw XCTSkip("该测试检查批量操作栏样式，只在模拟器构建环境运行")
        #endif
    }

    func testBatchManagementShowsNotificationsInItsCurrentNavigationLayer() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SourceManagementView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(".towerToast()"),
            "批量管理页必须在当前导航层承载通知，否则通知会被页面盖住，直到返回首页才显示"
        )
        XCTAssertTrue(
            source.contains(".subscriptionRefreshReport()"),
            "部分更新失败的报告也必须显示在当前批量管理页面"
        )
        #else
        throw XCTSkip("该测试检查批量管理页的通知层，只在模拟器构建环境运行")
        #endif
    }

    func testBatchRefreshStateIsScopedToTextOnlyToolbarButton() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SourceManagementView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let rootEnd = try XCTUnwrap(source.range(of: "private struct SubscriptionRefreshToolbarButton"))
        let buttonEnd = try XCTUnwrap(source.range(of: "enum SourceManagementRoute", range: rootEnd.upperBound..<source.endIndex))
        let rootSource = String(source[..<rootEnd.lowerBound])
        let buttonSource = String(source[rootEnd.lowerBound..<buttonEnd.lowerBound])

        XCTAssertFalse(
            rootSource.contains("@State private var isRefreshing"),
            "更新进度状态放在整页会让千节点筛选列表跟着每次动画重算"
        )
        XCTAssertTrue(buttonSource.contains("@State private var isRefreshing"))
        XCTAssertTrue(buttonSource.contains("Button(\"更新\") {"))
        XCTAssertFalse(buttonSource.contains("ProgressView()"))
        XCTAssertFalse(buttonSource.contains("arrow.clockwise"))
        XCTAssertFalse(buttonSource.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(buttonSource.contains(".font(.subheadline"))
        XCTAssertTrue(buttonSource.contains("isRefreshing = true"))
        XCTAssertTrue(buttonSource.contains("await model.refreshSubscriptions(sources)"))
        #else
        throw XCTSkip("该测试检查批量更新按钮的状态范围，只在模拟器构建环境运行")
        #endif
    }

    func testBatchManagementPlacesSelectAllBesideEachManagedSection() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SourceManagementView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private var subscriptionSectionHeader"))
        XCTAssertTrue(source.contains("private var localNodeSectionHeader"))
        XCTAssertTrue(source.contains("selectAllVisibleSubscriptions"))
        XCTAssertTrue(source.contains("selectAllVisibleLocalNodes"))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "Button(\"全选\")").count - 1, 2)
        #else
        throw XCTSkip("该测试检查分区全选按钮，只在模拟器构建环境运行")
        #endif
    }

    func testHomeAndManagementListsUseStableEnabledFirstOrdering() throws {
        #if targetEnvironment(simulator)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let home = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift"),
            encoding: .utf8
        )
        let management = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/SourceManagementView.swift"),
            encoding: .utf8
        )
        let nodeFilter = try String(
            contentsOf: root.appendingPathComponent("Tower/Features/Subscriptions/NodeFilterView.swift"),
            encoding: .utf8
        )

        XCTAssertGreaterThanOrEqual(home.components(separatedBy: "EnabledFirstOrdering.apply").count - 1, 2)
        XCTAssertGreaterThanOrEqual(management.components(separatedBy: "EnabledFirstOrdering.apply").count - 1, 2)
        XCTAssertTrue(nodeFilter.contains("EnabledFirstOrdering.apply"))
        XCTAssertTrue(management.contains("values.filter(isEnabled) + values.filter { !isEnabled($0) }"))
        XCTAssertFalse(home.contains("onMoveUp"))
        XCTAssertFalse(home.contains("onMoveDown"))
        #else
        throw XCTSkip("该测试检查启用优先排序，只在模拟器构建环境运行")
        #endif
    }

    func testNodeFilterShowsOnlyEnabledOverTotalCount() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/NodeFilterView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Text(\"节点 · \\(includedFilteredNodeCount) / \\(filteredNodes.count)\")"))
        XCTAssertFalse(source.contains("Text(\"节点 · \\(filteredNodes.count)\")"))
        XCTAssertFalse(source.contains("Text(verbatim: \"\\(String(localized: \\\"已启用\\\"))"))
        #else
        throw XCTSkip("该测试检查节点数量展示，只在模拟器构建环境运行")
        #endif
    }

    func testEnabledFirstOrderingKeepsRelativeOrderWithinEachState() {
        let values = [1, 2, 3, 4, 5]

        let displayed = EnabledFirstOrdering.apply(values) { $0.isMultiple(of: 2) }

        XCTAssertEqual(displayed, [2, 4, 1, 3, 5])
    }
}
