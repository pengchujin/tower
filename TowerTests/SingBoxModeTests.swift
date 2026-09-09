import Foundation
import Testing
@testable import Tower

struct SingBoxModeTests {
    private let proxy = ProxyNode(kind: .shadowsocks, name: "test-proxy", server: "proxy.example.com",
                                  port: 443, cipher: "aes-128-gcm", password: "test", rawURI: "")

    private func document(mode: RuleSchemeDNSProtectionMode = .standard,
                          nodes: [ProxyNode]? = nil, target: ClientTarget = .singBox) throws -> [String: Any] {
        let scheme = RuleScheme(id: "mode-test", name: "Modes", summary: "", groups: [
            .init(name: "Proxy", kind: .select, members: [.reference("DIRECT"), .nodePattern(".*")]),
            .init(name: "Local", kind: .select, members: [.reference("DIRECT")])
        ], rulesets: [
            .init(groupName: "Proxy", resource: .inline("DOMAIN,private.example.com")),
            .init(groupName: "Local", resource: .inline("DOMAIN-SUFFIX,example.com")),
            .init(groupName: "REJECT", resource: .inline("DOMAIN,ad.invalid")),
            .init(groupName: "Local", resource: .inline("IP-CIDR,10.0.0.0/8")),
            .init(groupName: "Proxy", resource: .inline("FINAL"))
        ], networkSettings: .init(dnsProtectionMode: mode))
        let content = ConfigurationGenerator().generate(nodes: nodes ?? [proxy], scheme: scheme, target: target).content
        return try #require(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
    }

    @Test func chineseModesHaveAnIndependentGlobalSelectorAndMatchingDNS() throws {
        let second = ProxyNode(kind: .shadowsocks, name: "second-proxy", server: "second.example.com",
                               port: 443, cipher: "aes-128-gcm", password: "test", rawURI: "")
        let config = try document(nodes: [proxy, second])
        let experimental = try #require(config["experimental"] as? [String: Any])
        #expect((experimental["clash_api"] as? [String: Any])?["default_mode"] as? String == "规则判定")
        let rules = try #require((config["route"] as? [String: Any])?["rules"] as? [[String: Any]])
        #expect(Set(rules.compactMap { $0["clash_mode"] as? String }) == ["规则判定", "全局代理", "直接连接"])
        let globalTag = try #require(rules.first { $0["clash_mode"] as? String == "全局代理" }?["outbound"] as? String)
        let outbounds = try #require(config["outbounds"] as? [[String: Any]])
        let global = try #require(outbounds.first { $0["tag"] as? String == globalTag })
        #expect(globalTag == "全局代理")
        #expect(global["type"] as? String == "selector")
        let choices = try #require(global["outbounds"] as? [String])
        #expect(choices.contains(proxy.name) && choices.contains(second.name))
        #expect(!choices.contains("DIRECT"))
        let automatic = try #require(outbounds.first { $0["tag"] as? String == choices.first })
        #expect(automatic["type"] as? String == "urltest")
        #expect(Set(automatic["outbounds"] as? [String] ?? []) == [proxy.name, second.name])
        #expect(global["default"] as? String == choices.first)
        let dns = try #require(config["dns"] as? [String: Any])
        let dnsRules = try #require(dns["rules"] as? [[String: Any]])
        let dnsTag = try #require(dnsRules.first { $0["clash_mode"] as? String == "全局代理" }?["server"] as? String)
        let servers = try #require(dns["servers"] as? [[String: Any]])
        #expect(servers.first { $0["tag"] as? String == dnsTag }?["detour"] as? String == globalTag)
        #expect(servers.first { $0["tag"] as? String == "remote" }?["detour"] as? String != globalTag)
    }

    @Test func globalNamesDoNotOverwriteUserGroupsOrResolvers() throws {
        var config: [String: Any] = [
            "outbounds": [["tag": "全局代理", "type": "selector", "outbounds": ["DIRECT"]],
                          ["tag": proxy.name, "type": "shadowsocks"], ["tag": "DIRECT", "type": "direct"]],
            "route": ["rules": [["action": "hijack-dns"]], "final": "全局代理"],
            "dns": ["servers": [["tag": "remote", "type": "tls", "server": "dns.example", "server_port": 8853],
                                ["tag": "remote-global", "type": "udp", "server": "192.0.2.1"]]]
        ]
        SingBoxDNSPolicy.apply(to: &config, nodeTags: [proxy.name], preferredProxy: "全局代理",
                               domainRules: [], protection: .strict)
        let groups = try #require(config["outbounds"] as? [[String: Any]])
        #expect(groups.first { $0["tag"] as? String == "全局代理" }?["outbounds"] as? [String] == ["DIRECT"])
        let routes = try #require((config["route"] as? [String: Any])?["rules"] as? [[String: Any]])
        #expect(routes.first { $0["clash_mode"] as? String == "全局代理" }?["outbound"] as? String == "全局代理 2")
        let dns = try #require(config["dns"] as? [String: Any])
        let servers = try #require(dns["servers"] as? [[String: Any]])
        let global = try #require(servers.first { $0["tag"] as? String == "remote-global 2" })
        #expect(global["detour"] as? String == "全局代理 2")
        #expect(global["type"] as? String == "tls")
        #expect(global["server"] as? String == "dns.example")
        #expect(global["server_port"] as? Int == 8853)
    }

    @Test func modesPrecedeBusinessRulesButNeverBypassDNSHijacking() throws {
        let config = try document()
        let experimental = try #require(config["experimental"] as? [String: Any])
        #expect((experimental["clash_api"] as? [String: Any])?["default_mode"] as? String == "规则判定")
        let route = try #require(config["route"] as? [String: Any])
        let rules = try #require(route["rules"] as? [[String: Any]])
        let hijack = try #require(rules.firstIndex { $0["action"] as? String == "hijack-dns" })
        for mode in ["全局代理", "直接连接"] {
            let index = try #require(rules.firstIndex { $0["clash_mode"] as? String == mode })
            #expect(index > hijack)
            #expect(index < (rules.firstIndex { $0["domain"] != nil } ?? 0))
        }
        #expect(rules.contains { $0["clash_mode"] as? String == "规则判定" })
    }

    @Test func protectedDNSCannotFollowMutableDirectSelection() throws {
        let config = try document()
        let dns = try #require(config["dns"] as? [String: Any])
        let servers = try #require(dns["servers"] as? [[String: Any]])
        let remote = try #require(servers.first { $0["tag"] as? String == "remote" })
        let detour = try #require(remote["detour"] as? String)
        #expect(detour != "Proxy")
        let outbounds = try #require(config["outbounds"] as? [[String: Any]])
        let safe = try #require(outbounds.first { $0["tag"] as? String == detour })
        #expect(safe["outbounds"] as? [String] == [proxy.name])
        #expect(safe["type"] as? String == "urltest")
        #expect(servers.first { $0["tag"] as? String == "local" }?["detour"] == nil)
    }

    @Test func dnsRulesPreserveDomainPrecedenceAndExplicitModes() throws {
        let dns = try #require(try document()["dns"] as? [String: Any])
        let rules = try #require(dns["rules"] as? [[String: Any]])
        #expect(rules.first { $0["clash_mode"] as? String == "直接连接" }?["server"] as? String == "local")
        #expect(rules.first { $0["clash_mode"] as? String == "全局代理" }?["server"] as? String == "remote-global")
        let specific = try #require(rules.firstIndex { ($0["domain"] as? [String])?.contains("private.example.com") == true })
        let suffix = try #require(rules.firstIndex { ($0["domain_suffix"] as? [String])?.contains("example.com") == true })
        #expect(specific < suffix)
        #expect(rules[specific]["server"] as? String == "remote")
        #expect(rules[suffix]["server"] as? String == "local")
        #expect(rules.first { ($0["domain"] as? [String])?.contains("ad.invalid") == true }?["action"] as? String == "reject")
        #expect(!rules.contains { $0["ip_cidr"] != nil || $0["rule_set"] != nil })
    }

    @Test func strictModeKeepsRuleDNSOnProxyButAllowsExplicitDirectMode() throws {
        let dns = try #require(try document(mode: .strict)["dns"] as? [String: Any])
        let rules = try #require(dns["rules"] as? [[String: Any]])
        #expect(dns["final"] as? String == "remote")
        #expect(rules.filter { $0["server"] as? String == "local" }.count == 1)
        #expect(rules.first { $0["server"] as? String == "local" }?["clash_mode"] as? String == "直接连接")
    }

    @Test func followSchemeDoesNotForcePort53OrStrictRouting() throws {
        let config = try document(mode: .followScheme)
        let tun = try #require((config["inbounds"] as? [[String: Any]])?.first)
        #expect(tun["strict_route"] as? Bool == false)
        let route = try #require(config["route"] as? [String: Any])
        let rules = try #require(route["rules"] as? [[String: Any]])
        let hijack = try #require(rules.first { $0["action"] as? String == "hijack-dns" })
        #expect(hijack["protocol"] as? String == "dns")
        #expect(hijack["rules"] == nil)
    }

    @Test func emptyDocumentRejectsGlobalInsteadOfPretendingToProxy() throws {
        let config = try document(nodes: [])
        let route = try #require(config["route"] as? [String: Any])
        let rules = try #require(route["rules"] as? [[String: Any]])
        #expect(rules.first { $0["clash_mode"] as? String == "全局代理" }?["action"] as? String == "reject")
        let dns = try #require(config["dns"] as? [String: Any])
        #expect(dns["final"] as? String == "local")
        #expect((dns["rules"] as? [[String: Any]])?.first { $0["clash_mode"] as? String == "全局代理" }?["action"] as? String == "reject")
    }

    @Test func hiddifyKeepsItsOwnDialect() throws {
        let config = try document(target: .hiddify)
        #expect((config["experimental"] as? [String: Any])?["clash_api"] == nil)
    }

    @Test func binaryRulesAndInlineRulesProduceTheSameDNSPolicy() throws {
        let schemes = RuleSchemeRepository().bundledSchemes()
        #expect(!schemes.isEmpty)
        for scheme in schemes.prefix(3) {
            var documents: [[String: Any]] = []
            for remote in [true, false] {
                let content = ConfigurationGenerator().generate(nodes: [proxy], scheme: scheme,
                    target: .singBox, preferRuleSets: remote).content
                documents.append(try #require(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any]))
            }
            let first = try #require(documents[0]["dns"] as? [String: Any])
            let second = try #require(documents[1]["dns"] as? [String: Any])
            #expect(first as NSDictionary == second as NSDictionary)
            #expect((first["rules"] as? [[String: Any]])?.contains { $0["domain_suffix"] != nil } == true)
        }
    }

    @Test func proxyGroupAvoidsTagCollisionsAndRejectsIndirectDirectPaths() throws {
        var config = try document()
        config["outbounds"] = [
            ["tag": "Proxy", "type": "selector", "outbounds": ["代理自动选择"]],
            ["tag": "代理自动选择", "type": "selector", "outbounds": ["DIRECT", proxy.name]],
            ["tag": proxy.name, "type": "shadowsocks"],
            ["tag": "DIRECT", "type": "direct"]
        ]
        SingBoxDNSPolicy.apply(to: &config, nodeTags: [proxy.name], preferredProxy: "Proxy",
                               domainRules: [], protection: .standard)
        let dns = try #require(config["dns"] as? [String: Any])
        let servers = try #require(dns["servers"] as? [[String: Any]])
        #expect(servers.first { $0["tag"] as? String == "remote" }?["detour"] as? String == "代理自动选择 2")
    }

    @Test func bothLayoutsAndProtectionModesExportResolvableFixtures() throws {
        // Synthetic credentials only. These exact generated documents are also
        // inputs to the real-core DNS egress regression, outside XCTest.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tower-singbox-mode-fixtures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mode in RuleSchemeDNSProtectionMode.allCases {
            let config = try document(mode: mode)
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("\(mode.rawValue).json"), options: .completeFileProtection)
        }
        let second = ProxyNode(kind: .shadowsocks, name: "second-proxy", server: "second.example.com",
                               port: 443, cipher: "aes-128-gcm", password: "test", rawURI: "")
        let global = try document(nodes: [proxy, second])
        try JSONSerialization.data(withJSONObject: global, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("global-selection.json"), options: .completeFileProtection)
        for empty in [false, true] {
            let content = ConfigurationGenerator().generate(nodes: empty ? [] : [proxy], preset: RulePreset.builtIns[0], target: .singBox).content
            let config = try #require(JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
            #expect((config["experimental"] as? [String: Any])?["clash_api"] != nil)
            try Data(content.utf8).write(to: directory.appendingPathComponent("preset-\(empty).json"), options: .completeFileProtection)
        }
    }
}
