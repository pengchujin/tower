import XCTest
@testable import Tower

final class SubconverterTimingTests: XCTestCase {
    private func scheme(type: String, members: String = "^Wanted$", timing: String) throws -> RuleScheme {
        try RuleSchemeParser().parse(
            text: "ruleset=Auto,[]FINAL\ncustom_proxy_group=Auto`\(type)`\(members)`https://example.com/check`\(timing)",
            id: "timing", name: "Timing", summary: ""
        )
    }

    func testBareIntervalsForEveryTimedGroup() throws {
        for type in ["url-test", "fallback", "load-balance"] {
            for interval in [0, 1, 60, 180, 300, 947, 3600, 86400] {
                let parsed = try scheme(type: type, timing: String(interval))
                let group = try XCTUnwrap(parsed.groups.first)
                XCTAssertEqual(group.interval, interval, "\(type): \(interval)")
                XCTAssertEqual(group.members, [.nodePattern("^Wanted$")])
                XCTAssertNil(group.tolerance)
                let edited = try RuleSchemeTextEditorService().validatedScheme(
                    from: XCTUnwrap(parsed.rawConfigurationText), replacing: parsed
                )
                XCTAssertEqual(edited.groups, parsed.groups)
            }
        }
    }

    func testOptionalTimingFieldsRetainIntervalAndTolerance() throws {
        for type in ["url-test", "fallback", "load-balance"] {
            for (timing, tolerance) in [("947,5", nil), ("947,,37", 37), ("947,5,37", 37), ("947,,", nil), (" 947, , 37 ", 37)] as [(String, Int?)] {
                let group = try XCTUnwrap(scheme(type: type, timing: timing).groups.first)
                XCTAssertEqual(group.interval, 947)
                XCTAssertEqual(group.tolerance, tolerance)
                XCTAssertEqual(group.members, [.nodePattern("^Wanted$")])
            }
        }
    }

    func testNumericMemberPatternsAreNotTimingFields() throws {
        let timed = try scheme(type: "url-test", members: "180`123,456`[]DIRECT", timing: "947")
        XCTAssertEqual(timed.groups.first?.members, [.nodePattern("180"), .nodePattern("123,456"), .reference("DIRECT")])
        let select = try RuleSchemeParser().parse(
            text: "ruleset=Manual,[]FINAL\ncustom_proxy_group=Manual`select`180`123,456`947",
            id: "manual", name: "Manual", summary: ""
        )
        XCTAssertNil(select.groups.first?.interval)
        XCTAssertEqual(select.groups.first?.members, [.nodePattern("180"), .nodePattern("123,456"), .nodePattern("947")])
    }

    func testImportedIntervalReachesEveryFullConfigurationClient() throws {
        let parsed = try scheme(type: "url-test", timing: "947")
        let nodes = ["Wanted", "Unwanted947"].map {
            ProxyNode(kind: .trojan, name: $0, server: "example.com", port: 443, password: "test", rawURI: "")
        }
        for target in ClientTarget.allCases where target.supportsFullConfigurationExport {
            let generated = ConfigurationGenerator().generate(nodes: nodes, scheme: parsed, target: target)
            XCTAssertFalse(generated.hasInvalidPolicyReferences, target.rawValue)
            XCTAssertNotNil(generated.content.range(
                of: #"interval[\"]?\s*[:=]\s*[\"]?947(?:s|\b)"#, options: .regularExpression
            ), target.rawValue)
        }
    }

    func testFallbackAndLoadBalanceKeepIntervalWithoutAddingNumericMatches() throws {
        let nodes = ["Wanted", "Unwanted180", "Unwanted947"].map {
            ProxyNode(kind: .trojan, name: $0, server: "example.com", port: 443, password: "test", rawURI: "")
        }
        for type in ["fallback", "load-balance"] {
            for interval in [60, 180, 947] {
                let parsed = try scheme(type: type, timing: String(interval))
                let clash = ConfigurationGenerator().generate(nodes: nodes, scheme: parsed, target: .clashMi)
                let restored = try RuleSchemeParser().parse(text: clash.content, id: "export", name: "Export", summary: "")
                let group = try XCTUnwrap(restored.groups.first { $0.name == "Auto" })
                XCTAssertEqual(group.interval, interval)
                XCTAssertEqual(group.members, [.nodePattern("^Wanted$")])
                let surge = ConfigurationGenerator().generate(nodes: nodes, scheme: parsed, target: .surge)
                let line = try XCTUnwrap(surge.content.components(separatedBy: "\n").first { $0.hasPrefix("Auto =") })
                XCTAssertTrue(line.contains("interval=\(interval)"))
                XCTAssertFalse(line.contains("Unwanted"))
            }
        }
    }
}
