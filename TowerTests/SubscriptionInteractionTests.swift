import XCTest
@testable import Tower

final class SubscriptionInteractionTests: XCTestCase {
    func testAddSourceSheetRequestsClipboardWhenPresented() throws {
        #if targetEnvironment(simulator)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tower/Features/Subscriptions/AddSourceSheet.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let presentationRequest = #"\.onAppear\s*\{\s*requestClipboardContent\(\)"#

        XCTAssertNotNil(
            source.range(of: presentationRequest, options: .regularExpression),
            "打开添加面板时应主动请求受支持的剪贴板内容"
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

        XCTAssertTrue(source.contains("private var bulkSelectionButton"))
        XCTAssertTrue(source.contains("model.setNodes(filteredNodes, included: !allFilteredNodesIncluded)"))
        XCTAssertTrue(source.contains(".frame(minHeight: 44)"))
        XCTAssertFalse(source.contains("include-all-filtered-nodes"))
        XCTAssertFalse(source.contains("exclude-all-filtered-nodes"))
        #else
        throw XCTSkip("该测试检查节点筛选页面结构，只在模拟器构建环境运行")
        #endif
    }
}
