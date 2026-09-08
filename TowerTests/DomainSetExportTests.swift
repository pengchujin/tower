import XCTest
@testable import Tower

final class DomainSetExportTests: XCTestCase {
    private let url = URL(string: "https://example.com/domains.conf")!
    private var scheme: RuleScheme {
        RuleScheme(id: "domains", name: "Domains", summary: "", groups: [], rulesets: [
            .init(groupName: "DIRECT", resource: .inline("DOMAIN-SET,\(url.absoluteString)")),
            .init(groupName: "DIRECT", resource: .inline("FINAL"))
        ])
    }

    func testLegacyDomainSetsParticipateInDownloads() {
        XCTAssertEqual(scheme.remoteRulesetURLs, [url])
    }

    func testLoonAndOtherTargetsExpandDomainSetsWithoutLosingExactOrSuffixMeaning() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RuleDownloadStore(folderURL: folder)
        try store.store("# comment\nexact.example.com\n.suffix.example.com\n// comment\n", for: url)
        let planner = RuleSetEmissionPlanner(repository: RuleSchemeRepository(downloadStore: store))
        for target in ClientTarget.allCases where target != .surge && target != .surgeMac {
            for prefer in [false, true] {
                let plan = planner.plan(for: scheme, target: target, preferRuleSets: prefer)
                XCTAssertEqual(plan.inlineRules.map(\.line), ["DOMAIN,exact.example.com", "DOMAIN-SUFFIX,suffix.example.com"], target.rawValue)
            }
        }
        let native = planner.plan(for: scheme, target: .surge, preferRuleSets: true)
        XCTAssertEqual(native.inlineRules.first?.line, "DOMAIN-SET,\(url.absoluteString)")
        let output = ConfigurationGenerator()
            .generate(nodes: [], scheme: scheme, target: .loon, schemes: RuleSchemeRepository(downloadStore: store))
        XCTAssertTrue(output.content.contains("DOMAIN,exact.example.com,DIRECT"))
        XCTAssertTrue(output.content.contains("DOMAIN-SUFFIX,suffix.example.com,DIRECT"))
        XCTAssertFalse(output.content.contains("DOMAIN-SET,"))
    }

    func testMissingDomainSetDoesNotSilentlyProduceIncompleteConfiguration() {
        let result = ConfigurationGenerator().generate(nodes: [], scheme: scheme, target: .loon)
        XCTAssertTrue(result.content.isEmpty)
        XCTAssertFalse(result.diagnostics.isEmpty)
    }
}
