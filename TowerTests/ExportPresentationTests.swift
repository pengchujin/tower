import UIKit
import XCTest
@testable import Tower

final class ExportPresentationTests: XCTestCase {
    func testTUICUsesADedicatedAvailableExportProtocolIcon() {
        XCTAssertEqual(ProxyKind.tuic.symbol, "bolt.circle.fill")
        XCTAssertNotNil(UIImage(systemName: ProxyKind.tuic.symbol))
        XCTAssertNotEqual(ProxyKind.tuic.symbol, ProxyKind.vmess.symbol)
        XCTAssertNotEqual(ProxyKind.tuic.symbol, ProxyKind.shadowsocks.symbol)
    }

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

    func testQuanXPreviewUsesSectionSpecificSyntaxColors() throws {
        let content = """
        # Generated locally by 塔台
        [general]
        server_check_url = http://www.gstatic.com/generate_204
        [dns]
        no-system
        server = 1.1.1.1
        [policy]
        static=🚀 节点选择, direct
        """

        let spans = ConfigurationSyntaxHighlighter.spans(in: content)

        XCTAssertEqual(style(at: "# Generated locally by 塔台", in: content, spans: spans), .comment)
        XCTAssertEqual(style(at: "[general]", in: content, spans: spans), .section(.blue))
        XCTAssertEqual(style(at: "server_check_url", in: content, spans: spans), .key(.blue))
        XCTAssertEqual(style(at: "http://www.gstatic.com/generate_204", in: content, spans: spans), .url)
        XCTAssertEqual(style(at: "[dns]", in: content, spans: spans), .section(.purple))
        XCTAssertEqual(style(at: "no-system", in: content, spans: spans), .directive(.purple))
        XCTAssertEqual(style(at: "[policy]", in: content, spans: spans), .section(.teal))
        XCTAssertEqual(style(at: "static=", in: content, spans: spans), .key(.teal))
    }

    func testYAMLPreviewCarriesSemanticColorIntoNestedKeys() {
        let content = """
        proxies:
          - name: "Tokyo 01"
            port: 443
        rules:
          - DOMAIN-SUFFIX,example.com,🚀 节点选择
        """

        let spans = ConfigurationSyntaxHighlighter.spans(in: content)

        XCTAssertEqual(style(at: "proxies", in: content, spans: spans), .key(.teal))
        XCTAssertEqual(style(at: "name", in: content, spans: spans), .key(.teal))
        XCTAssertEqual(style(at: "\"Tokyo 01\"", in: content, spans: spans), .string)
        XCTAssertEqual(style(at: "443", in: content, spans: spans), .number)
        XCTAssertEqual(style(at: "rules", in: content, spans: spans), .key(.orange))
        XCTAssertEqual(style(at: "DOMAIN-SUFFIX", in: content, spans: spans), .directive(.orange))
    }

    @MainActor
    func testHighlightedConfigurationPreservesOriginalTextAndUsesDistinctColors() throws {
        let content = "# note\n[general]\ntimeout = 5000"
        let attributed = ConfigurationSyntaxHighlighter.attributedString(
            for: content,
            baseFont: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )

        XCTAssertEqual(attributed.string, content)
        let commentRange = try XCTUnwrap((content as NSString).range(of: "# note").nonEmpty)
        let sectionRange = try XCTUnwrap((content as NSString).range(of: "[general]").nonEmpty)
        let commentColor = attributed.attribute(.foregroundColor, at: commentRange.location, effectiveRange: nil)
            as? UIColor
        let sectionColor = attributed.attribute(.foregroundColor, at: sectionRange.location, effectiveRange: nil)
            as? UIColor

        XCTAssertNotNil(commentColor)
        XCTAssertNotNil(sectionColor)
        XCTAssertNotEqual(commentColor, sectionColor)
    }

    @MainActor
    func testConfigurationTextViewAppliesHighlightingWithoutLosingSelection() {
        let textView = ConfigurationTextViewFactory.make()
        let content = "# note\n[general]\ntimeout = 5000"

        ConfigurationTextViewFactory.render(content, in: textView)

        XCTAssertEqual(textView.text, content)
        XCTAssertGreaterThan(textView.attributedText.length, 0)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertGreaterThanOrEqual(textView.font?.pointSize ?? 0, 13)
        XCTAssertGreaterThanOrEqual(textView.textContainerInset.left, 14)
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

    func testConfigurationNameDraftLoadsThePersistedNameOnlyOncePerEditingSession() {
        var draft = ConfigurationNameDraft()

        draft.loadPersistedNameIfNeeded("塔台")
        draft.text = "tower"
        draft.loadPersistedNameIfNeeded("塔台")

        XCTAssertEqual(draft.text, "tower", "视图再次出现时不能用旧配置覆盖正在输入的名称")
    }

    func testConfigurationNameDraftKeepsTheLastValidNameWhenTextFieldEndsWithATransientEmptyWrite() {
        var draft = ConfigurationNameDraft(text: "塔台")

        // This is the exact event sequence captured from the physical iPhone:
        // the field receives the complete name, then SwiftUI writes an empty
        // value while the focused field is being dismissed by the toolbar.
        draft.text = "tower"
        draft.text = ""

        XCTAssertEqual(
            draft.committedName,
            "tower",
            "结束编辑时的临时空值不能覆盖本次输入的最后一个有效名称"
        )
    }

    /// The flip side of that rule: because a blank field is ignored, clearing
    /// it can no longer mean "back to the default name". Writing the default in
    /// has to work, which is what the reset control does.
    func testConfigurationNameDraftCanBeReturnedToTheDefaultAfterACustomName() {
        var draft = ConfigurationNameDraft(text: TowerBrand.localizedName)

        draft.text = "tower"
        draft.text = TowerBrand.localizedName

        XCTAssertEqual(
            draft.committedName,
            TowerBrand.localizedName,
            "改过名之后必须还能回到默认名称，否则默认值就成了单向门"
        )
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

private extension ExportPresentationTests {
    func style(
        at substring: String,
        in content: String,
        spans: [ConfigurationSyntaxHighlighter.Span]
    ) -> ConfigurationSyntaxHighlighter.Style? {
        let location = (content as NSString).range(of: substring).location
        return spans.last { NSLocationInRange(location, $0.range) }?.style
    }
}

private extension NSRange {
    var nonEmpty: NSRange? {
        location == NSNotFound || length == 0 ? nil : self
    }
}
