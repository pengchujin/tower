import XCTest
@testable import Tower

/// The DNS settings Tower writes when the subscription supplies none.
///
/// A rule-based client has to answer DNS itself, because a rule written against
/// a domain cannot match a connection that arrives as an IP. What it answers
/// with decides whether the query was observable, so these defaults are part of
/// the configuration's correctness rather than a nicety.
final class DNSDefaultsTests: XCTestCase {
    private func configuration(for target: ClientTarget) -> String {
        let node = SubscriptionParser().parseURI("trojan://pw@a.example.com:443?sni=c.example.com#T")!
        return ConfigurationGenerator()
            .generate(nodes: [node], preset: RulePreset.builtIns[0], target: target)
            .content
    }

    /// `system` is not "unset" — it tells the client to prefer the carrier's
    /// resolver, which is the exact path a leak takes. Writing it was worse
    /// than writing nothing at all.
    func testNoTargetAsksForTheSystemResolver() {
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = configuration(for: target)
            XCTAssertFalse(
                content.contains("dns-server = system") || content.contains("dns-server=system"),
                "\(target.name) 仍然把系统 DNS 排在第一位"
            )
        }
    }

    /// Mihomo queries every resolver in a list concurrently and takes the
    /// fastest answer. One plaintext entry beside encrypted ones therefore
    /// sends the query in the clear anyway and makes the encrypted entries
    /// pointless — so the general lists have to be encrypted throughout.
    func testClashResolverListsCarryNoPlaintextServer() throws {
        let content = configuration(for: .clash)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let start = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("dns:") }, content)

        var section: String?
        for line in lines[(start + 1)...] {
            let indent = line.prefix { $0 == " " }.count
            if !line.trimmingCharacters(in: .whitespaces).isEmpty, indent == 0 { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":"), indent == 2 {
                section = String(trimmed.dropLast())
                continue
            }
            guard ["nameserver", "fallback"].contains(section ?? ""), trimmed.hasPrefix("- ") else {
                continue
            }
            let server = String(trimmed.dropFirst(2))
            XCTAssertTrue(
                server.hasPrefix("https://") || server.hasPrefix("tls://") || server.hasPrefix("quic://"),
                "\(section ?? "") 里混入了明文解析器 \(server)，同列表里的加密解析器会因此失效"
            )
        }
    }

    /// Resolving the node's own hostname cannot go through the node. Without
    /// this key a fake-ip client answers that lookup with a fake address and
    /// nothing connects at all — the one mistake that turns a DNS improvement
    /// into a total outage.
    func testClashResolvesNodeHostnamesOutsideFakeIP() {
        let content = configuration(for: .clash)

        XCTAssertTrue(content.contains("enhanced-mode: fake-ip"), content)
        XCTAssertTrue(content.contains("proxy-server-nameserver:"), content)
        XCTAssertTrue(content.contains("default-nameserver:"), content)
    }

    /// An IP-based rule without `no-resolve` makes the engine resolve a domain
    /// locally just to evaluate the rule — before any domain rule has had a
    /// chance to match. The domains it happens to are the ones no rule list
    /// covered, which are the ones worth protecting.
    func testEveryGeoIPRuleSkipsResolution() {
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let content = configuration(for: target)

            // Egern writes the rule as a mapping, so its flag is a neighbouring
            // key rather than a trailing field.
            if target == .egern {
                if content.contains("- geoip:") {
                    XCTAssertTrue(content.contains("no_resolve: true"), content)
                }
                continue
            }

            // A rule, not a setting: `GEOIP,CN,DIRECT` has the comma, while the
            // `geoip: true` inside `fallback-filter` does not.
            let rules = content
                .split(separator: "\n")
                .map(String.init)
                .filter { $0.lowercased().contains("geoip,") }
            for rule in rules {
                XCTAssertTrue(
                    rule.lowercased().contains("no-resolve"),
                    "\(target.name) 的 GEOIP 规则缺少 no-resolve：\(rule)"
                )
            }
        }
    }
}
