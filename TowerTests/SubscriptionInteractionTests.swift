import XCTest
@testable import Tower

private struct EditingSubscriptionFetcher: SubscriptionFetching {
    func fetch(_ source: SubscriptionSource) async throws -> ImportResult {
        ImportResult(nodes: [], rejectedLineCount: 0, usage: source.usage)
    }
}

final class SubscriptionInteractionTests: XCTestCase {
    @MainActor
    func testSubscriptionsCanBeEditedAndReorderedPersistently() async throws {
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
        model.moveSubscription(first, by: 1)

        XCTAssertEqual(model.subscriptions.map(\.id), [second.id, first.id])
        XCTAssertEqual(model.availableNodes.map(\.id), [secondNode.id, firstNode.id])
        XCTAssertEqual(model.subscriptions[1].name, "第一机场")
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.subscriptions.map(\.id), [second.id, first.id])
        XCTAssertEqual(reloaded.availableNodes.map(\.id), [secondNode.id, firstNode.id])
        XCTAssertEqual(reloaded.subscriptions[1].name, "第一机场")
    }

    @MainActor
    func testLocalNodesCanBeEditedAndReorderedPersistently() throws {
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
        model.moveLocalNode(first, by: 1)

        XCTAssertEqual(model.localNodes.map(\.id), [second.id, first.id])
        XCTAssertEqual(model.localNodes[1].name, "编辑后的节点")
        XCTAssertEqual(model.localNodes[1].server, "edited.example")
        XCTAssertEqual(model.nodes[1].id, airport.id, "重排自有节点不能移动机场节点")
        let reloaded = AppModel(persistence: store, arguments: [])
        XCTAssertEqual(reloaded.localNodes.map(\.id), [second.id, first.id])
        XCTAssertEqual(reloaded.localNodes[1].name, "编辑后的节点")
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

    func testOverviewMetricsRouteToDedicatedScrollTargets() {
        XCTAssertEqual(SubscriptionOverviewMetric.subscriptions.scrollTarget, .subscriptions)
        XCTAssertEqual(SubscriptionOverviewMetric.nodes.scrollTarget, .nodes)
        XCTAssertEqual(SubscriptionOverviewMetric.regions.scrollTarget, .regions)
        XCTAssertEqual(SubscriptionOverviewMetric.localNodes.scrollTarget, .localNodes)

        XCTAssertEqual(
            Set(SubscriptionOverviewMetric.allCases.map(\.scrollTarget)).count,
            SubscriptionOverviewMetric.allCases.count
        )
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

    func testSubscriptionExpansionDoesNotAnimateTheWholeCardLayout() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private struct SubscriptionCard"))
        let end = try XCTUnwrap(source.range(of: "private struct LocalNodeCard"))
        let cardSource = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertFalse(
            cardSource.contains("withAnimation(expansionAnimation)"),
            "节点区域收起时不能让整张订阅卡片参与弹簧布局动画，否则下方按钮会向上漂移"
        )
        XCTAssertTrue(
            cardSource.contains(".animation(expansionAnimation, value: isExpanded)"),
            "只保留箭头自身的轻量状态动画"
        )
        #else
        throw XCTSkip("该测试检查订阅卡片的动画作用域，只在模拟器构建环境运行")
        #endif
    }

    func testSubscriptionAndLocalNodeLongPressMenusOfferEditAndSorting() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for action in ["编辑", "上移", "下移"] {
            XCTAssertTrue(source.contains("Label(\"\(action)\""), "长按菜单缺少 \(action)")
        }
        XCTAssertTrue(source.contains("model.moveSubscription"))
        XCTAssertTrue(source.contains("model.moveLocalNode"))
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

    func testSectionHeadingLocalizesStaticDetailText() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Design/TowerTheme.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertTrue(source.contains("Text(LocalizedStringKey(detail))"))
        #else
        throw XCTSkip("该测试检查自定义标题组件，只在模拟器构建环境运行")
        #endif
    }

    func testLocalizedDefaultProfileNamesFollowTheCurrentAppLanguage() {
        XCTAssertEqual(TowerBrand.migratedDefaultName("塔台"), TowerBrand.localizedName)
        XCTAssertEqual(TowerBrand.migratedDefaultName("Tower"), TowerBrand.localizedName)
        XCTAssertEqual(TowerBrand.migratedDefaultName("My Profile"), "My Profile")
    }

    func testAvailableNodesAndRegionsOpenTheNodeFilterPage() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/SubscriptionsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("navigationDestination(item: $nodeFilterRoute)"))
        XCTAssertTrue(source.contains("NodeFilterView(initialFocus: route)"))
        XCTAssertTrue(source.contains("case .nodes:"))
        XCTAssertTrue(source.contains("case .regions:"))
        XCTAssertTrue(source.contains("nodeFilterRoute ="))
        XCTAssertFalse(source.contains("withAnimation(.smooth(duration: 0.32))"))
        #else
        throw XCTSkip("该测试检查开发源码中的首页导航，只在模拟器构建环境运行")
        #endif
    }

    func testNodeFilterKeepsEveryFilterVisibleAndUsesOneLargeBulkAction() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/NodeFilterView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("LazyVGrid(columns: filterColumns"))
        XCTAssertFalse(
            source.contains("ScrollView(.horizontal)"),
            "四个节点筛选项必须同时可见，不能把自有节点隐藏在横向滚动区域"
        )
        for filter in ["countryFilter", "protocolFilter", "sourceFilter", "localFilter"] {
            XCTAssertTrue(source.contains(filter), "缺少筛选项：\(filter)")
        }

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
}
