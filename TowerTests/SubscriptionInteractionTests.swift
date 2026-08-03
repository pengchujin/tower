import XCTest
@testable import Tower

final class SubscriptionInteractionTests: XCTestCase {
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
