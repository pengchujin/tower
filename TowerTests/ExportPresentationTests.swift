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

    func testEveryClientTargetUsesBundledOfficialAppIcon() {
        for target in ClientTarget.allCases {
            let asset = try? XCTUnwrap(target.appIconAssetName)
            XCTAssertNotNil(asset, "\(target.name) 缺少 App Store 图标资源名")
            if let asset {
                XCTAssertNotNil(UIImage(named: asset), "\(target.name) 的 App Store 图标未打进资源包")
            }
        }
    }

    func testClashFormatUsesStashAppStoreIdentity() {
        XCTAssertEqual(ClientTarget.clash.name, "Stash")
        XCTAssertEqual(ClientTarget.clash.subtitle, "Clash YAML")
        XCTAssertEqual(ClientTarget.clash.appIconAssetName, "ClientStash")
        XCTAssertEqual(ClientTarget.clash.brandColorHex, "1473E6")
    }

    func testExportedConfigurationUsesAStableClientSpecificFileName() {
        let localizedAppName = String(localized: "塔台")

        for target in ClientTarget.allCases {
            XCTAssertEqual(
                configuration(for: target).fileName,
                "\(localizedAppName).\(target.fileExtension)",
                target.name
            )
        }
    }

    func testCustomProfileNameIsSanitizedAndUsedForEveryTarget() {
        let configuration = GeneratedConfiguration(
            target: .loon,
            content: "x",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 0,
            profileName: "家庭/代理:配置"
        )

        XCTAssertEqual(configuration.fileName, "家庭 代理 配置.conf")
    }

    func testConfigurationNameDraftCanBeClearedBeforeDefaultIsCommitted() {
        var draft = ConfigurationNameDraft(text: "塔台")

        draft.text = ""

        XCTAssertEqual(draft.text, "", "编辑过程中不能把默认名称强行写回输入框")
        XCTAssertEqual(draft.committedName, TowerBrand.localizedName)
        draft.text = "家庭网络配置"
        XCTAssertEqual(draft.committedName, "家庭网络配置")
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

    func testGenerationCacheDropsConfigurationsWhenCustomizedRulesChange() {
        var cache = ConfigurationCache()
        let oldKey = GenerationCacheKey(
            target: .surge,
            presetID: "rules",
            nodesHash: 1,
            countryCodesHash: 1,
            rulesHash: 10
        )
        let currentKey = GenerationCacheKey(
            target: .surge,
            presetID: "rules",
            nodesHash: 1,
            countryCodesHash: 1,
            rulesHash: 11
        )

        cache[oldKey] = configuration(for: .surge)
        cache[currentKey] = configuration(for: .surge)

        XCTAssertEqual(cache.count, 1)
        XCTAssertNil(cache[oldKey])
        XCTAssertEqual(cache[currentKey]?.target, .surge)
    }

    func testGenerationCacheSeparatesRuleSetPreference() {
        var cache = ConfigurationCache()
        let remoteKey = GenerationCacheKey(
            target: .surge,
            presetID: "rules",
            nodesHash: 1,
            countryCodesHash: 1,
            preferRuleSets: true
        )
        let inlineKey = GenerationCacheKey(
            target: .surge,
            presetID: "rules",
            nodesHash: 1,
            countryCodesHash: 1,
            preferRuleSets: false
        )

        cache[remoteKey] = GeneratedConfiguration(
            target: .surge,
            content: "RULE-SET,https://rules.example.com/list,Proxy",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 1
        )
        cache[inlineKey] = GeneratedConfiguration(
            target: .surge,
            content: "DOMAIN-SUFFIX,example.com,Proxy",
            supportedNodeCount: 1,
            skippedNodeCount: 0,
            ruleCount: 1
        )

        XCTAssertNotEqual(cache[remoteKey]?.content, cache[inlineKey]?.content)
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
