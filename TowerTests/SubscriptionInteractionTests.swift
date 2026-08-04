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
}
