import CryptoKit
import Foundation
import XCTest
@testable import Tower

/// Opt-in compatibility corpus runner. The private subscriptions and generated
/// profiles live under an ignored directory selected by environment variables;
/// this source file contains no provider address, credential or proxy secret.
final class LocalCompatibilityCorpusTests: XCTestCase {
    private struct StoredHeaders: Decodable {
        let status: Int
    }

    private struct AttemptReport: Codable {
        let variant: String
        let status: Int?
        let nodeCount: Int
        let rejectedLineCount: Int
    }

    private struct GenerationReport: Codable {
        let target: String
        let mode: String
        let preferRuleSets: Bool?
        let supportedNodeCount: Int
        let skippedNodeCount: Int
        let ruleCount: Int
        let byteCount: Int
        let sha256: String
    }

    private struct SourceReport: Codable {
        let source: Int
        let selectedVariant: String?
        let nodeCount: Int
        let rejectedLineCount: Int
        let noticeCount: Int
        let protocolCounts: [String: Int]
        let transportCounts: [String: Int]
        let credentialShapes: [String: Int]
        let alpnShapes: [String: Int]
        let realityShapes: [String: Int]
        let attempts: [AttemptReport]
        let generations: [GenerationReport]
    }

    private struct CorpusReport: Codable {
        let schemeGroupCount: Int
        let schemeRulesetCount: Int
        let sources: [SourceReport]
    }

    func testPrivateCompatibilityCorpus() throws {
        let environment = ProcessInfo.processInfo.environment
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let defaultCorpus = repositoryRoot
            .appendingPathComponent(".codex_work/subscription-compat", isDirectory: true)
        let corpusPath = environment["TOWER_COMPAT_CORPUS_DIR"] ?? defaultCorpus.path
        let defaultRuleConfig = defaultCorpus.appendingPathComponent(
            "tools/acl4ssr/Clash/config/ACL4SSR_Online_Full.ini"
        ).path
        let ruleConfigPath = environment["TOWER_COMPAT_RULE_CONFIG"] ?? defaultRuleConfig
        guard FileManager.default.fileExists(atPath: corpusPath),
              FileManager.default.fileExists(atPath: ruleConfigPath) else {
            throw XCTSkip("Set TOWER_COMPAT_CORPUS_DIR and TOWER_COMPAT_RULE_CONFIG to run the private corpus")
        }

        let corpusRoot = URL(fileURLWithPath: corpusPath, isDirectory: true)
        let inputRoot = corpusRoot.appendingPathComponent("inputs", isDirectory: true)
        let outputRoot = corpusRoot.appendingPathComponent("tower-outputs", isDirectory: true)
        try createPrivateDirectory(outputRoot)

        let ruleData = try Data(contentsOf: URL(fileURLWithPath: ruleConfigPath))
        let scheme = try RuleSchemeParser().parse(
            data: ruleData,
            id: "local-acl4ssr-online-full",
            name: "ACL4SSR Online Full",
            summary: "Local compatibility reference",
            isBundled: false
        )

        let sourceFolders = try FileManager.default.contentsOfDirectory(
            at: inputRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
            .filter { $0.lastPathComponent.hasPrefix("source-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let parser = SubscriptionParser()
        let generator = ConfigurationGenerator()
        var reports: [SourceReport] = []

        for folder in sourceFolders {
            guard let sourceIndex = Int(folder.lastPathComponent.dropFirst("source-".count)) else {
                continue
            }
            let sourceID = stableSourceID(sourceIndex)
            var attempts: [AttemptReport] = []
            var selectedVariant: String?
            var selected: SubscriptionParser.ParsedContent?

            for variant in ["shadowrocket", "clashMeta"] {
                let bodyURL = folder.appendingPathComponent("\(variant).body")
                let headersURL = folder.appendingPathComponent("\(variant).headers.json")
                guard FileManager.default.fileExists(atPath: bodyURL.path),
                      FileManager.default.fileExists(atPath: headersURL.path) else {
                    attempts.append(
                        AttemptReport(
                            variant: variant,
                            status: nil,
                            nodeCount: 0,
                            rejectedLineCount: 0
                        )
                    )
                    continue
                }
                let status = try JSONDecoder().decode(
                    StoredHeaders.self,
                    from: Data(contentsOf: headersURL)
                ).status
                let parsed = parser.parse(data: try Data(contentsOf: bodyURL), sourceID: sourceID)
                attempts.append(
                    AttemptReport(
                        variant: variant,
                        status: status,
                        nodeCount: parsed.nodes.count,
                        rejectedLineCount: parsed.rejectedLineCount
                    )
                )

                if selected == nil,
                   (200..<300).contains(status),
                   !parsed.nodes.isEmpty {
                    selectedVariant = variant
                    selected = parsed
                }
            }

            guard let selected else {
                reports.append(
                    SourceReport(
                        source: sourceIndex,
                        selectedVariant: nil,
                        nodeCount: 0,
                        rejectedLineCount: attempts.map(\.rejectedLineCount).max() ?? 0,
                        noticeCount: 0,
                        protocolCounts: [:],
                        transportCounts: [:],
                        credentialShapes: [:],
                        alpnShapes: [:],
                        realityShapes: [:],
                        attempts: attempts,
                        generations: []
                    )
                )
                continue
            }

            let sourceOutput = outputRoot.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
            try createPrivateDirectory(sourceOutput)
            var generationReports: [GenerationReport] = []

            for target in ClientTarget.allCases {
                for preferRuleSets in [false, true] {
                    let generated = generator.generate(
                        nodes: selected.nodes,
                        scheme: scheme,
                        target: target,
                        preferRuleSets: preferRuleSets
                    )
                    let mode = preferRuleSets ? "rulesets-on" : "rulesets-off"
                    try store(
                        generated.content,
                        at: sourceOutput.appendingPathComponent(
                            "\(target.rawValue).full.\(mode).\(generated.fileExtension)"
                        )
                    )
                    generationReports.append(
                        report(
                            generated,
                            target: target,
                            mode: "full",
                            preferRuleSets: preferRuleSets
                        )
                    )
                }

                guard target.supportsNodesOnlyImport else { continue }
                let generated = generator.generateNodeSubscription(
                    nodes: selected.nodes,
                    target: target,
                    profileName: "Tower Compatibility"
                )
                try store(
                    generated.content,
                    at: sourceOutput.appendingPathComponent(
                        "\(target.rawValue).nodes.\(generated.fileExtension)"
                    )
                )
                generationReports.append(
                    report(
                        generated,
                        target: target,
                        mode: "nodes",
                        preferRuleSets: nil
                    )
                )
            }

            reports.append(
                SourceReport(
                    source: sourceIndex,
                    selectedVariant: selectedVariant,
                    nodeCount: selected.nodes.count,
                    rejectedLineCount: selected.rejectedLineCount,
                    noticeCount: selected.notices.count,
                    protocolCounts: Dictionary(grouping: selected.nodes, by: { $0.kind.rawValue })
                        .mapValues(\.count),
                    transportCounts: counts(selected.nodes) { node in
                        "\(node.kind.rawValue):\(node.transport?.lowercased() ?? "tcp")"
                    },
                    credentialShapes: counts(selected.nodes.compactMap(credentialShape)),
                    alpnShapes: counts(selected.nodes) { node in
                        guard let alpn = node.alpn else { return "missing" }
                        return alpn.contains(",") ? "comma-list" : "scalar"
                    },
                    realityShapes: counts(selected.nodes.compactMap(realityShape)),
                    attempts: attempts,
                    generations: generationReports
                )
            )
        }

        let report = CorpusReport(
            schemeGroupCount: scheme.groups.count,
            schemeRulesetCount: scheme.rulesets.count,
            sources: reports
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try store(
            encoder.encode(report),
            at: corpusRoot.appendingPathComponent("tower-report.json")
        )

        XCTAssertFalse(reports.isEmpty)
        XCTAssertTrue(reports.contains { $0.nodeCount > 0 })
    }

    private func report(
        _ generated: GeneratedConfiguration,
        target: ClientTarget,
        mode: String,
        preferRuleSets: Bool?
    ) -> GenerationReport {
        let data = Data(generated.content.utf8)
        return GenerationReport(
            target: target.rawValue,
            mode: mode,
            preferRuleSets: preferRuleSets,
            supportedNodeCount: generated.supportedNodeCount,
            skippedNodeCount: generated.skippedNodeCount,
            ruleCount: generated.ruleCount,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func stableSourceID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    private func credentialShape(_ node: ProxyNode) -> String? {
        guard [.vless, .vmess].contains(node.kind) else { return nil }
        let kind = node.kind.rawValue
        guard let value = node.uuid, !value.isEmpty else { return "\(kind):missing" }
        if UUID(uuidString: value) != nil { return "\(kind):standard" }
        if node.exportableUUID != nil { return "\(kind):normalized" }
        return "\(kind):nonstandard-\(value.count)"
    }

    private func realityShape(_ node: ProxyNode) -> String? {
        guard node.usesReality else { return nil }
        if node.realityPublicKey?.isEmpty != false { return "missing-public-key" }
        if node.realityShortID?.isEmpty != false { return "missing-short-id" }
        return "complete"
    }

    private func counts<S: Sequence>(_ values: S) -> [String: Int] where S.Element == String {
        Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
    }

    private func counts<S: Sequence>(
        _ values: S,
        key: (S.Element) -> String
    ) -> [String: Int] {
        Dictionary(grouping: values, by: key).mapValues(\.count)
    }

    private func createPrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func store(_ text: String, at url: URL) throws {
        try store(Data(text.utf8), at: url)
    }

    private func store(_ data: Data, at url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
