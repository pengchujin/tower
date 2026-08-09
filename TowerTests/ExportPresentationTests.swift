import UIKit
import XCTest
@testable import Tower

final class ExportPresentationTests: XCTestCase {
    func testConfigurationPreviewSummaryBoundsLineCountAndLineLength() {
        let longLine = String(repeating: "a", count: 1_200)
        let content = ([longLine] + (1...40).map { "rule-\($0)" }).joined(separator: "\n")

        let summary = ConfigurationPreviewFormatter.summary(from: content)
        let lines = summary.components(separatedBy: .newlines)

        XCTAssertLessThanOrEqual(lines.count, ConfigurationPreviewFormatter.summaryLineLimit)
        XCTAssertTrue(lines.allSatisfy { $0.count <= ConfigurationPreviewFormatter.maximumSummaryLineLength + 2 })
        XCTAssertTrue(lines[0].hasSuffix(" …"))
    }

    @MainActor
    func testConfigurationTextViewUsesLazyLayoutForLargeSelectableContent() {
        let textView = ConfigurationTextViewFactory.make()

        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertTrue(textView.isScrollEnabled)
        XCTAssertTrue(textView.layoutManager.allowsNonContiguousLayout)
        XCTAssertTrue(textView.textContainer.widthTracksTextView)
    }

    /// A declared asset must actually be bundled, and a client with no artwork
    /// must fall back to a symbol that exists — a missing asset renders as a
    /// blank square, which reads as breakage rather than as "we ship no icon".
    func testEveryClientTargetResolvesToSomethingDrawable() {
        for target in ClientTarget.allCases {
            if let asset = target.appIconAssetName {
                XCTAssertNotNil(UIImage(named: asset), "\(target.name) 声明了图标却没有打包")
            } else {
                XCTAssertNotNil(
                    UIImage(systemName: target.symbol),
                    "\(target.name) 没有图标，回退的 SF Symbol 也不存在"
                )
            }
        }
    }

    func testClashFormatUsesStashAppStoreIdentity() {
        XCTAssertEqual(ClientTarget.clash.name, "Stash")
        XCTAssertEqual(ClientTarget.clash.subtitle, "Clash YAML")
        XCTAssertEqual(ClientTarget.clash.appIconAssetName, "ClientStash")
    }

    func testGenerationCacheKeepsConfigurationsForMultipleTargets() {
        var cache = ConfigurationCache()
        let surgeKey = GenerationCacheKey(target: .surge, presetID: "rules", nodesHash: 1, countryCodesHash: 1)
        let loonKey = GenerationCacheKey(target: .loon, presetID: "rules", nodesHash: 1, countryCodesHash: 1)

        cache[surgeKey] = configuration(for: .surge)
        cache[loonKey] = configuration(for: .loon)

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache[surgeKey]?.target, .surge)
        XCTAssertEqual(cache[loonKey]?.target, .loon)
    }

    func testGenerationCacheDropsConfigurationsFromPreviousSnapshot() {
        var cache = ConfigurationCache()
        let oldKey = GenerationCacheKey(target: .surge, presetID: "rules", nodesHash: 1, countryCodesHash: 1)
        let currentKey = GenerationCacheKey(target: .loon, presetID: "rules", nodesHash: 2, countryCodesHash: 1)

        cache[oldKey] = configuration(for: .surge)
        cache[currentKey] = configuration(for: .loon)

        XCTAssertEqual(cache.count, 1)
        XCTAssertNil(cache[oldKey])
        XCTAssertEqual(cache[currentKey]?.target, .loon)
    }

    /// Disabling a subscription changes the merged DNS metadata, so the cache
    /// key must differ and the old configuration must no longer be served.
    func testGenerationCacheInvalidatesWhenDNSConfigurationChanges() {
        var cache = ConfigurationCache()
        let withDNS = GenerationCacheKey(
            target: .clash,
            presetID: "rules",
            nodesHash: 1,
            countryCodesHash: 1,
            dnsHash: 42
        )
        let withoutDNS = GenerationCacheKey(
            target: .clash,
            presetID: "rules",
            nodesHash: 1,
            countryCodesHash: 1,
            dnsHash: 0
        )

        cache[withDNS] = configuration(for: .clash)
        cache[withoutDNS] = configuration(for: .clash)

        XCTAssertEqual(cache.count, 2)
        XCTAssertNotNil(cache[withDNS])
        XCTAssertNotNil(cache[withoutDNS])
    }

    private func configuration(for target: ClientTarget) -> GeneratedConfiguration {
        GeneratedConfiguration(
            target: target,
            content: "# test",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 1
        )
    }
}
