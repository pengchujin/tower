import Foundation

struct ConfigurationGenerator {
    private static let manualGroupName = "手动切换"
    private static let nestedSelectGroupName = "🚀 节点选择"
    private static let nestedAutoGroupName = "♻️ 自动选择"
    private static let nestedManualGroupName = "🎛️ 手动切换"
    private static let directGroupName = "🎯 直接连接"
    private static let regionDefinitions = [
        RegionDefinition(code: "HK", name: "🇭🇰 香港"),
        RegionDefinition(code: "JP", name: "🇯🇵 日本"),
        RegionDefinition(code: "US", name: "🇺🇸 美国"),
        RegionDefinition(code: "SG", name: "🇸🇬 新加坡"),
        RegionDefinition(code: "TW", name: "🇹🇼 台湾"),
        RegionDefinition(code: "KR", name: "🇰🇷 韩国"),
        RegionDefinition(code: "GB", name: "🇬🇧 英国"),
        RegionDefinition(code: "DE", name: "🇩🇪 德国"),
        RegionDefinition(code: "FR", name: "🇫🇷 法国")
    ]
    private static let otherRegionsName = "🌍 其他地区"
    // Rule types Surge, Shadowrocket and Loon all accept in a [Rule] section.
    // The bundled snapshot currently uses DOMAIN-SUFFIX, IP-CIDR, DOMAIN,
    // IP-CIDR6, PROCESS-NAME, DOMAIN-KEYWORD and GEOIP; the rest are listed so a
    // future snapshot does not lose valid rules.
    private static let surgeFamilyRuleTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-SET", "DOMAIN-WILDCARD",
        "IP-CIDR", "IP-CIDR6", "IP6-CIDR", "IP-ASN", "GEOIP",
        "PROCESS-NAME", "USER-AGENT", "URL-REGEX", "RULE-SET",
        "DEST-PORT", "SRC-IP", "SRC-PORT", "IN-PORT", "PROTOCOL", "SUBNET",
        "AND", "OR", "NOT"
    ]

    private let rules: RuleRepository

    init(rules: RuleRepository = RuleRepository()) {
        self.rules = rules
    }

    func generate(
        nodes: [ProxyNode],
        preset: RulePreset,
        target: ClientTarget,
        countryCodes: [UUID: String] = [:],
        excludedKinds: Set<ProxyKind> = [],
        supportedKindsOverride: Set<ProxyKind>? = nil
    ) -> GeneratedConfiguration {
        let supported = uniquedNames(
            nodes.filter {
                writes(
                    $0,
                    to: target,
                    excluding: excludedKinds,
                    supportedKindsOverride: supportedKindsOverride
                )
            },
            reservedNames: reservedProxyNames(for: preset)
        )
        let regionGroups = makeRegionGroups(nodes: supported, countryCodes: countryCodes)
        let content: String
        switch target {
        case .clash, .clashApple:
            content = clash(nodes: supported, preset: preset, regionGroups: regionGroups, target: target)
        case .surge:
            content = surgeLike(nodes: supported, preset: preset, regionGroups: regionGroups, shadowrocket: false)
        case .shadowrocket:
            // Shadowrocket accepts Clash YAML directly. Keeping nodes in that
            // structured form preserves connection fields which have no
            // reliable equivalent in its legacy one-line configuration
            // dialect (client fingerprints, port hopping and nested transport
            // options in particular).
            content = clash(nodes: supported, preset: preset, regionGroups: regionGroups, target: .shadowrocket)
        case .loon:
            content = loon(nodes: supported, preset: preset, regionGroups: regionGroups)
        case .quanx:
            content = quanX(nodes: supported, preset: preset, regionGroups: regionGroups)
        case .hiddify:
            content = singBox(nodes: supported, preset: preset, regionGroups: regionGroups)
        case .egern:
            content = egern(nodes: supported, preset: preset, regionGroups: regionGroups)
        case .v2box:
            content = ""
        }

        return GeneratedConfiguration(
            target: target,
            content: content,
            supportedNodeCount: supported.count,
            skippedNodeCount: nodes.count - supported.count,
            ruleCount: rules.count(for: preset),
            fileExtensionOverride: target == .shadowrocket ? "yaml" : nil
        )
    }

    // MARK: - Imported schemes

    /// Generates from an imported scheme, reproducing the groups the source
    /// file declared instead of Tower's built-in policy layout.
    func generate(
        nodes: [ProxyNode],
        scheme: RuleScheme,
        target: ClientTarget,
        schemes: RuleSchemeRepository = RuleSchemeRepository(),
        excludedKinds: Set<ProxyKind> = [],
        preferRuleSets: Bool = true,
        supportedKindsOverride: Set<ProxyKind>? = nil
    ) -> GeneratedConfiguration {
        let supported = uniquedNames(
            nodes.filter {
                writes(
                    $0,
                    to: target,
                    excluding: excludedKinds,
                    supportedKindsOverride: supportedKindsOverride
                )
            },
            reservedNames: Set(scheme.groups.map(\.name) + ["DIRECT", "REJECT", "direct", "reject"])
        )
        let resolved = resolveGroups(scheme: scheme, nodes: supported, target: target)
        // Shadowrocket full profiles are emitted as Clash-compatible YAML, so
        // their remote rule resources must use Clash provider semantics too.
        // Planning them as legacy Shadowrocket/Surge resources would inline a
        // valid YAML provider or emit the wrong remote dialect.
        let rulePlanTarget: ClientTarget = target == .shadowrocket ? .clash : target
        let rulePlan = RuleSetEmissionPlanner(repository: schemes).plan(
            for: scheme,
            target: rulePlanTarget,
            preferRuleSets: preferRuleSets
        )
        let content: String
        switch target {
        case .clash, .clashApple:
            content = clashScheme(scheme, groups: resolved, nodes: supported, target: target, rulePlan: rulePlan)
        case .shadowrocket:
            content = clashScheme(scheme, groups: resolved, nodes: supported, target: .shadowrocket, rulePlan: rulePlan)
        case .surge:
            content = surgeLikeScheme(scheme, groups: resolved, nodes: supported, target: target, rulePlan: rulePlan)
        case .loon:
            content = loonScheme(scheme, groups: resolved, nodes: supported, rulePlan: rulePlan)
        case .quanx:
            content = quanXScheme(scheme, groups: resolved, nodes: supported, rulePlan: rulePlan)
        case .hiddify:
            content = singBoxScheme(scheme, groups: resolved, nodes: supported, rulePlan: rulePlan)
        case .egern:
            content = egernScheme(scheme, groups: resolved, nodes: supported, rulePlan: rulePlan)
        case .v2box:
            content = ""
        }

        return GeneratedConfiguration(
            target: target,
            content: content,
            supportedNodeCount: supported.count,
            skippedNodeCount: nodes.count - supported.count,
            ruleCount: ruleCount(for: scheme, schemes: schemes),
            fileExtensionOverride: target == .shadowrocket ? "yaml" : nil
        )
    }

    /// Generates the remote node resource expected by clients that can add a
    /// subscription without replacing their rules and policy groups.
    func generateNodeSubscription(
        nodes: [ProxyNode],
        target: ClientTarget,
        excludedKinds: Set<ProxyKind> = [],
        profileName: String = TowerBrand.localizedName
    ) -> GeneratedConfiguration {
        guard target.supportsNodesOnlyImport else {
            return GeneratedConfiguration(
                target: target,
                content: "",
                supportedNodeCount: 0,
                skippedNodeCount: nodes.count,
                ruleCount: 0,
                profileName: profileName,
                contentMode: .nodesOnly,
                fileExtensionOverride: "txt"
            )
        }

        var supported = uniquedNames(
            nodes.filter { writes($0, to: target, excluding: excludedKinds) },
            reservedNames: []
        )
        // Snell has no subscription URI. WireGuard URI conventions also vary
        // between producers, so Shadowrocket receives both only in the full
        // profile form that carries their complete settings.
        if target == .shadowrocket {
            supported.removeAll { $0.kind == .snell || $0.kind == .wireguard }
        }

        let content: String
        switch target {
        case .shadowrocket:
            let generator = ProxyNodeShareLinkGenerator()
            let links = supported.map { generator.canonicalLink(for: $0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            content = Data(links.joined(separator: "\n").utf8).base64EncodedString()
        case .loon:
            content = supported.map(loonNode).joined(separator: "\n") + (supported.isEmpty ? "" : "\n")
        case .quanx:
            content = supported.map(quanXNode).joined(separator: "\n") + (supported.isEmpty ? "" : "\n")
        case .hiddify:
            let generator = ProxyNodeShareLinkGenerator()
            content = supported.map { generator.canonicalLink(for: $0) }.joined(separator: "\n")
                + (supported.isEmpty ? "" : "\n")
        case .v2box:
            let generator = ProxyNodeShareLinkGenerator()
            let links = supported.map { generator.canonicalLink(for: $0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            content = Data(links.joined(separator: "\n").utf8).base64EncodedString()
        default:
            content = ""
            supported = []
        }

        return GeneratedConfiguration(
            target: target,
            content: content,
            supportedNodeCount: supported.count,
            skippedNodeCount: nodes.count - supported.count,
            ruleCount: 0,
            profileName: profileName,
            contentMode: .nodesOnly,
            fileExtensionOverride: "txt"
        )
    }

    /// A node reaches the configuration when the client can express it and the
    /// user has not excluded that protocol. Excluded nodes stay in the input so
    /// they are reported as skipped rather than vanishing from the counts.
    private func writes(
        _ node: ProxyNode,
        to target: ClientTarget,
        excluding excludedKinds: Set<ProxyKind>,
        supportedKindsOverride: Set<ProxyKind>? = nil
    ) -> Bool {
        let supportsKind = supportedKindsOverride?.contains(node.kind) ?? target.supports(node.kind)
        guard supportsKind, !excludedKinds.contains(node.kind) else { return false }
        // An id that is neither a UUID nor short enough for Xray's name mapping
        // has no faithful form; writing it blank would look fine and never
        // connect.
        if [.vmess, .vless].contains(node.kind), node.exportableUUID == nil { return false }
        // Tower implements TUIC v5. Both parts of its credential are required;
        // a v4 token or half-filled v5 entry may import, but can never
        // authenticate. Skip and count it instead of poisoning the profile.
        if node.kind == .tuic {
            guard node.uuid.flatMap({ UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }) != nil,
                  !(node.password ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }
        if node.kind == .wireguard {
            guard !(node.wireGuardPrivateKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !(node.wireGuardPublicKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !(node.wireGuardAllowedIPs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !((node.wireGuardIPv4 ?? "").isEmpty && (node.wireGuardIPv6 ?? "").isEmpty) else {
                return false
            }
        }
        // REALITY needs the server's public key. A client with no field for it
        // would get plain TLS aimed at a borrowed SNI — the exact "looks right,
        // never connects" outcome, so those nodes are skipped and counted.
        if node.usesReality, !target.expressesReality { return false }
        // Clash and Stash implement Snell only up to version 3, so a v4+ node
        // is skipped there rather than written as a proxy they would reject.
        if node.kind == .snell, [.clash, .clashApple].contains(target), (node.version ?? 4) >= 4 { return false }
        // Surge and Shadowrocket carry Hysteria 2's obfuscator in the key name
        // — `salamander-password` and a bare `obfsParam` — so neither has any
        // way to say "some other obfuscator". (Surge also documents its own
        // `gecko-password`, but nothing Tower parses produces that name.)
        // Writing one anyway would hand the password to Salamander and produce
        // the "looks right, never connects" outcome, so the node is skipped and
        // counted instead.
        if node.kind == .hysteria2, [.surge, .shadowrocket].contains(target),
           let obfs = hysteria2Obfs(node), obfs.type.lowercased() != "salamander" { return false }
        if node.plugin == "v2ray-plugin" {
            // Only the WebSocket mode is modelled. These clients either expose
            // SIP003 directly or have a documented equivalent; the others must
            // skip instead of silently exporting plain Shadowsocks.
            guard node.transport == "ws",
                  [.clash, .clashApple, .shadowrocket, .quanx, .hiddify].contains(target) else { return false }
        }
        if !canExpressTransport(of: node, on: target) { return false }
        return true
    }

    private func canExpressTransport(of node: ProxyNode, on target: ClientTarget) -> Bool {
        guard [.vmess, .vless, .trojan].contains(node.kind) else { return true }
        let transport = node.transport?.lowercased() ?? "tcp"
        if transport == "tcp" || transport.isEmpty { return true }
        switch target {
        case .clash, .clashApple:
            if transport == "xhttp" { return node.kind == .vless }
            return ["ws", "http", "h2", "grpc", "httpupgrade"].contains(transport)
        case .surge:
            return transport == "ws" && [.vmess, .trojan].contains(node.kind)
        case .shadowrocket:
            return ["ws", "http", "h2", "grpc", "httpupgrade", "xhttp"].contains(transport)
                && (transport != "xhttp" || node.kind == .vless)
        case .loon:
            if node.kind == .trojan { return transport == "ws" }
            return ["ws", "http"].contains(transport)
        case .quanx:
            return transport == "ws"
        case .hiddify:
            return ["ws", "http", "h2", "grpc", "httpupgrade"].contains(transport)
        case .egern:
            if node.kind == .trojan { return ["ws", "http"].contains(transport) }
            return ["ws", "http", "h2", "grpc"].contains(transport)
        case .v2box:
            return ["ws", "http", "h2", "grpc", "httpupgrade", "xhttp"].contains(transport)
                && (transport != "xhttp" || node.kind == .vless)
        }
    }

    struct ResolvedSchemeGroup {
        let name: String
        let kind: RuleSchemeGroup.Kind
        /// Group references and node names, in the order the source declared.
        let members: [String]
        /// Only the node names, needed for the Quantumult X tag regex.
        let nodeNames: [String]
        /// Preserve an all-node source regex instead of expanding it into one
        /// very long Quantumult X tag regex.
        let matchesAllNodes: Bool
        let testURL: String
        let interval: Int
        let tolerance: Int
    }

    private func resolveGroups(
        scheme: RuleScheme,
        nodes: [ProxyNode],
        target: ClientTarget
    ) -> [ResolvedSchemeGroup] {
        let groupNames = Set(scheme.groups.map(\.name))
        let displayNames = nodes.map { NodeRegionResolver.displayName(for: $0) }

        return scheme.groups.map { group in
            var members: [String] = []
            var nodeNames: [String] = []
            var matchesAllNodes = false

            for member in group.members {
                switch member {
                case .reference(let name):
                    // DIRECT and REJECT are spelled differently per client; any
                    // other reference points at a sibling group.
                    if groupNames.contains(name) {
                        members.append(name)
                    } else {
                        members.append(builtinPolicyName(name, target: target))
                    }
                case .nodePattern(let pattern):
                    if pattern.trimmingCharacters(in: .whitespacesAndNewlines) == ".*" {
                        matchesAllNodes = true
                    }
                    let matches = matchingNodeNames(pattern, nodes: nodes, displayNames: displayNames)
                    members.append(contentsOf: matches)
                    nodeNames.append(contentsOf: matches)
                }
            }

            // A group whose regex matched nothing would be empty and rejected by
            // every client, so it falls back to a direct connection.
            if members.isEmpty {
                members = [builtinPolicyName("DIRECT", target: target)]
            }

            return ResolvedSchemeGroup(
                name: group.name,
                kind: nodeNames.isEmpty && group.kind == .urlTest ? .select : group.kind,
                members: members.removingDuplicates(),
                nodeNames: nodeNames.removingDuplicates(),
                matchesAllNodes: matchesAllNodes,
                testURL: group.testURLString ?? "http://www.gstatic.com/generate_204",
                interval: group.interval ?? 300,
                tolerance: group.tolerance ?? 50
            )
        }
    }

    /// Matches the source regex against both the original remark and the name
    /// Tower will actually write, since Tower may prepend a flag or add a
    /// de-duplication suffix.
    private func matchingNodeNames(
        _ pattern: String,
        nodes: [ProxyNode],
        displayNames: [String]
    ) -> [String] {
        if pattern == ".*" { return displayNames }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        return zip(nodes, displayNames).compactMap { node, displayName in
            let candidates = [displayName, node.name]
            let matched = candidates.contains { candidate in
                let range = NSRange(candidate.startIndex..., in: candidate)
                return expression.firstMatch(in: candidate, options: [], range: range) != nil
            }
            return matched ? displayName : nil
        }
    }

    private func builtinPolicyName(_ name: String, target: ClientTarget) -> String {
        switch name.uppercased() {
        case "DIRECT": target == .quanx ? "direct" : "DIRECT"
        case "REJECT": target == .quanx ? "reject" : "REJECT"
        default: name
        }
    }

    private func ruleCount(for scheme: RuleScheme, schemes: RuleSchemeRepository) -> Int {
        scheme.rulesets.reduce(0) { $0 + schemes.lines(for: $1.resource).count }
    }

    /// Emits every local rule in declaration order. `FINAL` is held separately
    /// by the planner because each format spells it differently and it must
    /// remain last even when the ordinary rules are remote resources.
    private func localSchemeRules(
        _ plan: RuleSetEmissionPlanner.Plan,
        target: ClientTarget,
        indent: String = ""
    ) -> String {
        var output = ""
        for entry in plan.entries {
            guard case .inline(let rule) = entry else { continue }
            if let mapped = mappedRule(rule.line, policyName: rule.policyName, target: target) {
                output += "\(indent)\(mapped)\n"
            }
        }

        guard let finalGroup = plan.finalGroupName else { return output }
        switch target {
        case .clash, .clashApple: output += "\(indent)MATCH,\(finalGroup)\n"
        case .quanx: output += "\(indent)final, \(finalGroup)\n"
        default: output += "\(indent)FINAL,\(finalGroup)\n"
        }
        return output
    }

    private func schemeHeader(_ scheme: RuleScheme, target: ClientTarget) -> String {
        let origin = scheme.sourceURLString ?? (scheme.isBundled ? "随 App 打包的快照" : "导出")
        return """
        # Generated locally by 塔台 for \(target.name)
        # Rules: \(scheme.name) (\(origin))
        # Subscription credentials never leave this device.

        """
    }

    private func clashScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        target: ClientTarget,
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        var output = schemeHeader(scheme, target: target)
        output += """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: warning
        ipv6: true

        dns:
          enable: true
          enhanced-mode: fake-ip
          fake-ip-range: 198.18.0.1/16
          fake-ip-filter:
            - "*.lan"
            - "+.local"
            - "+.msftconnecttest.com"
            - "+.msftncsi.com"
          default-nameserver:
            - 223.5.5.5
            - 119.29.29.29
          proxy-server-nameserver:
            - https://223.5.5.5/dns-query
          nameserver:
            - https://223.5.5.5/dns-query
            - https://doh.pub/dns-query
          fallback:
            - https://1.1.1.1/dns-query
            - https://dns.google/dns-query
          fallback-filter:
            geoip: true
            geoip-code: CN

        proxies:
        """
        output += "\n"
        output += nodes.isEmpty ? "  []\n" : nodes.map(clashNode).joined(separator: "\n") + "\n"
        output += "\nproxy-groups:\n"
        for group in groups {
            switch group.kind {
            case .select:
                output += clashSelectGroup(name: group.name, nodeNames: group.members)
            case .urlTest:
                var block = "  - name: \(yaml(group.name))\n"
                block += "    type: url-test\n"
                block += "    url: \(group.testURL)\n"
                block += "    interval: \(group.interval)\n"
                block += "    tolerance: \(group.tolerance)\n"
                block += "    proxies:\n"
                for member in group.members { block += "      - \(yaml(member))\n" }
                output += block
            }
        }
        let remoteResources = rulePlan.remoteResources
        if !remoteResources.isEmpty {
            output += "\nrule-providers:\n"
            for resource in remoteResources {
                let isYAML = resource.format == .clashProviderYAML
                output += "  \(resource.identifier):\n"
                output += "    type: http\n"
                output += "    behavior: classical\n"
                output += "    format: \(isYAML ? "yaml" : "text")\n"
                output += "    url: \(yaml(resource.url.absoluteString))\n"
                output += "    path: ./ruleset/\(resource.identifier).\(isYAML ? "yaml" : "list")\n"
                output += "    interval: 86400\n"
            }
        }
        output += "\nrules:\n"
        for entry in rulePlan.entries {
            switch entry {
            case .remote(let resource):
                output += "  - RULE-SET,\(resource.identifier),\(resource.policyName)\n"
            case .inline(let rule):
                if let mapped = mappedRule(rule.line, policyName: rule.policyName, target: .clash) {
                    output += "  - \(mapped)\n"
                }
            }
        }
        if let final = rulePlan.finalGroupName { output += "  - MATCH,\(final)\n" }
        return output
    }

    private func surgeLikeScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        target: ClientTarget,
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        var output = schemeHeader(scheme, target: target)
        output += """
        [General]
        loglevel = notify
        ipv6 = true
        dns-server = 223.5.5.5, 119.29.29.29
        encrypted-dns-server = https://223.5.5.5/dns-query, https://doh.pub/dns-query
        skip-proxy = 127.0.0.1, localhost, *.local
        test-timeout = 5

        [Proxy]
        """
        output += "\n"
        for node in nodes {
            output += surgeNode(node, shadowrocket: target == .shadowrocket) + "\n"
        }
        output += surgeWireGuardSections(nodes)
        output += "\n[Proxy Group]\n"
        for group in groups {
            switch group.kind {
            case .select:
                output += surgeSelect(name: group.name, values: group.members)
            case .urlTest:
                let members = group.members.map(confName).joined(separator: ", ")
                output += "\(confName(group.name)) = url-test, \(members), url=\(group.testURL)"
                output += ", interval=\(group.interval), tolerance=\(group.tolerance)\n"
            }
        }
        output += "\n[Rule]\n"
        for entry in rulePlan.entries {
            switch entry {
            case .remote(let resource):
                output += "RULE-SET,\(resource.url.absoluteString),\(confName(resource.policyName)),update-interval=86400\n"
            case .inline(let rule):
                if let mapped = mappedRule(rule.line, policyName: rule.policyName, target: target) {
                    output += mapped + "\n"
                }
            }
        }
        if let final = rulePlan.finalGroupName { output += "FINAL,\(confName(final))\n" }
        return output
    }

    private func loonScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        var output = schemeHeader(scheme, target: .loon)
        output += """
        [General]
        ipv6 = true
        dns-server = 223.5.5.5, 119.29.29.29

        [Proxy]
        """
        output += "\n"
        for node in nodes { output += loonNode(node) + "\n" }
        output += "\n[Proxy Group]\n"
        for group in groups {
            let members = group.members.map(confName).joined(separator: ",")
            switch group.kind {
            case .select:
                output += "\(confName(group.name)) = select,\(members)\n"
            case .urlTest:
                output += "\(confName(group.name)) = url-test,\(members)"
                output += ",url=\(group.testURL),interval=\(group.interval),tolerance=\(group.tolerance)\n"
            }
        }
        output += "\n[Rule]\n"
        output += localSchemeRules(rulePlan, target: .loon)
        let remoteResources = rulePlan.remoteResources
        if !remoteResources.isEmpty {
            output += "\n[Remote Rule]\n"
            for resource in remoteResources {
                output += "\(resource.url.absoluteString),policy=\(confName(resource.policyName))"
                output += ",tag=\(resource.identifier),enabled=true\n"
            }
        }
        return output
    }

    private func quanXScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        var output = schemeHeader(scheme, target: .quanx)
        output += """
        [general]
        server_check_url = http://www.gstatic.com/generate_204
        server_check_timeout = 5000

        [dns]
        no-system
        server = 223.5.5.5
        server = 1.1.1.1
        """
        // Section order follows subconverter's QuanX template, which is what
        // every working converter emits: `[policy]` comes before the server and
        // filter sections, not after them. Tower used to put the whole node
        // list between `[dns]` and `[policy]`, and Quantumult X imported the
        // rules while dropping every policy group.
        output += "\n\n[policy]\n"
        for group in groups {
            switch group.kind {
            case .select:
                let members = group.members.map(confName).joined(separator: ", ")
                output += "static=\(confName(group.name)), \(members)\n"
            case .urlTest:
                output += "url-latency-benchmark=\(confName(group.name))"
                if group.matchesAllNodes {
                    output += ", \(group.nodeNames.map(confName).joined(separator: ", "))"
                } else {
                    output += ", server-tag-regex=\(quanXServerTagRegex(group.nodeNames))"
                }
                output += ", check-interval=\(group.interval), alive-checking=false"
                output += ", tolerance=\(group.tolerance)\n"
            }
        }
        // Every module is emitted exactly once and in this order. Quantumult X
        // rejects the whole file for either mistake: a missing module is
        // `配置文件缺少模块 [server_remote]`, and a repeated one is
        // `配置文件语法错误, duplicated section, [server_remote]`.
        let remoteRules = rulePlan.remoteResources.map {
            "\($0.url.absoluteString), tag=\($0.identifier), force-policy=\(confName($0.policyName)), enabled=true"
        }
        output += "\n[server_remote]\n"
        output += "\n[filter_remote]\n"
        if !remoteRules.isEmpty { output += remoteRules.joined(separator: "\n") + "\n" }
        output += "\n[rewrite_remote]\n"
        output += "\n[server_local]\n"
        for node in nodes { output += quanXNode(node) + "\n" }
        output += "\n[filter_local]\n"
        output += localSchemeRules(rulePlan, target: .quanx)
        for section in ["rewrite_local", "task_local", "http_backend", "mitm"] {
            output += "\n[\(section)]\n"
        }
        return output
    }

    // MARK: - Built-in presets

    private func clash(
        nodes: [ProxyNode],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup],
        target: ClientTarget
    ) -> String {
        let nodeNames = nodes.map { NodeRegionResolver.displayName(for: $0) }
        let regionGroupNames = regionGroups.map(\.name)
        var output = header(target: target)
        output += """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: warning
        ipv6: true

        dns:
          enable: true
          enhanced-mode: fake-ip
          fake-ip-range: 198.18.0.1/16
          fake-ip-filter:
            - "*.lan"
            - "+.local"
            - "+.msftconnecttest.com"
            - "+.msftncsi.com"
          default-nameserver:
            - 223.5.5.5
            - 119.29.29.29
          proxy-server-nameserver:
            - https://223.5.5.5/dns-query
          nameserver:
            - https://223.5.5.5/dns-query
            - https://doh.pub/dns-query
          fallback:
            - https://1.1.1.1/dns-query
            - https://dns.google/dns-query
          fallback-filter:
            geoip: true
            geoip-code: CN

        proxies:
        """
        output += "\n"
        output += nodes.isEmpty ? "  []\n" : nodes.map(clashNode).joined(separator: "\n") + "\n"
        output += "\nproxy-groups:\n"
        output += clashSelectGroup(
            name: RulePolicy.select.configurationName,
            nodeNames: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
        )
        output += clashSelectGroup(
            name: Self.manualGroupName,
            nodeNames: nodeNames.isEmpty ? ["DIRECT"] : nodeNames
        )
        output += clashURLTestGroup(
            name: RulePolicy.auto.configurationName,
            nodeNames: nodeNames
        )
        output += clashSelectGroup(
            name: Self.nestedSelectGroupName,
            nodeNames: nestedPrimaryChoices(regionGroupNames: regionGroupNames),
            hidden: true
        )
        output += clashSelectGroup(
            name: Self.nestedManualGroupName,
            nodeNames: nodeNames.isEmpty ? [Self.directGroupName] : nodeNames,
            hidden: true
        )
        output += clashURLTestGroup(
            name: Self.nestedAutoGroupName,
            nodeNames: nodeNames,
            hidden: true
        )
        output += clashSelectGroup(
            name: Self.directGroupName,
            nodeNames: ["DIRECT"],
            hidden: true
        )
        for policy in configurablePolicies(preset) {
            output += clashSelectGroup(
                name: policy.configurationName,
                nodeNames: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: "REJECT"
                )
            )
        }
        for group in regionGroups {
            output += clashSelectGroup(
                name: group.name,
                nodeNames: [group.automaticName] + group.nodeNames
            )
            output += clashURLTestGroup(
                name: group.automaticName,
                nodeNames: group.nodeNames,
                hidden: true
            )
        }
        output += "\nrules:\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: .clash) {
                    output += "  - \(mapped)\n"
                }
            }
        }
        if preset.includeGeoIPCN {
            output += "  - GEOIP,CN,DIRECT,no-resolve\n"
        }
        output += "  - MATCH,\(clashPolicyName(preset.finalPolicy))\n"
        return output
    }

    private func clashNode(_ node: ProxyNode) -> String {
        var values: [String] = [
            "  - name: \(yaml(NodeRegionResolver.displayName(for: node)))",
            "    type: \(node.kind.rawValue)",
            "    server: \(yaml(node.server))",
            "    port: \(node.port)"
        ]
        switch node.kind {
        case .shadowsocks:
            values += ["    cipher: \(yaml(node.cipher ?? "aes-256-gcm"))", "    password: \(yaml(node.password ?? ""))", "    udp: true"]
            if node.plugin == "v2ray-plugin" {
                values.append("    plugin: v2ray-plugin")
                values.append("    plugin-opts:")
                values.append("      mode: websocket")
                if node.tls { values.append("      tls: true") }
                if let host = node.hostHeader, !host.isEmpty { values.append("      host: \(yaml(host))") }
                if let path = node.exportablePath { values.append("      path: \(yaml(path))") }
            } else if let mode = simpleObfsMode(node) {
                values.append("    plugin: obfs")
                values.append("    plugin-opts:")
                values.append("      mode: \(yaml(mode))")
                if let host = node.obfsParam, !host.isEmpty {
                    values.append("      host: \(yaml(host))")
                }
            }
        case .shadowsocksR:
            values += [
                "    cipher: \(yaml(node.cipher ?? "aes-256-cfb"))",
                "    password: \(yaml(node.password ?? ""))",
                "    protocol: \(yaml(node.protocolName ?? "origin"))",
                "    obfs: \(yaml(node.obfs ?? "plain"))"
            ]
            if let value = node.protocolParam, !value.isEmpty { values.append("    protocol-param: \(yaml(value))") }
            if let value = node.obfsParam, !value.isEmpty { values.append("    obfs-param: \(yaml(value))") }
        case .vmess:
            values += [
                "    uuid: \(yaml(node.exportableUUID ?? ""))",
                "    alterId: \(node.alterID ?? 0)",
                "    cipher: \(yaml(node.cipher ?? "auto"))",
                "    udp: true"
            ]
            appendClashTransport(node, to: &values)
        case .vless:
            values += ["    uuid: \(yaml(node.exportableUUID ?? ""))", "    udp: true"]
            appendClashTransport(node, to: &values)
        case .trojan:
            values += ["    password: \(yaml(node.password ?? ""))", "    udp: true"]
            appendClashTransport(node, to: &values)
        case .hysteria2:
            values += [
                "    password: \(yaml(node.password ?? ""))",
                "    skip-cert-verify: \(node.skipCertificateVerification)",
                "    udp: true"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
            if let ports = node.portHopping, !ports.isEmpty { values.append("    ports: \(yaml(ports))") }
            appendClashALPN(node, to: &values)
            // Hysteria 2 calls this value `fingerprint`: it is the SHA-256
            // certificate pin, not a browser-style uTLS ClientHello name.
            if let fingerprint = node.certificateFingerprint, !fingerprint.isEmpty {
                values.append("    fingerprint: \(yaml(fingerprint))")
            }
            if let obfs = hysteria2Obfs(node) {
                values.append("    obfs: \(yaml(obfs.type))")
                values.append("    obfs-password: \(yaml(obfs.password))")
            }
        case .hysteria:
            // Hysteria 1's congestion control is rate-based, so `up`/`down`
            // are load-bearing rather than hints. Mihomo's own defaults are
            // what an airport that omitted them expects.
            values += [
                "    auth-str: \(yaml(node.password ?? ""))",
                "    up: \(node.upMbps ?? 50)",
                "    down: \(node.downMbps ?? 100)",
                "    skip-cert-verify: \(node.skipCertificateVerification)"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
            appendClashCertificateFingerprint(node, to: &values)
            if let obfs = node.obfs, !obfs.isEmpty, obfs.lowercased() != "none" {
                values.append("    obfs: \(yaml(obfs))")
            }
            if let name = node.protocolName, !name.isEmpty { values.append("    protocol: \(yaml(name))") }
            appendClashALPN(node, to: &values)
        case .tuic:
            values += [
                "    uuid: \(yaml(node.exportableUUID ?? ""))",
                "    password: \(yaml(node.password ?? ""))",
                "    skip-cert-verify: \(node.skipCertificateVerification)",
                "    udp: true"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
            if let value = node.congestionControl, !value.isEmpty {
                values.append("    congestion-controller: \(yaml(value))")
            }
            if let value = node.udpRelayMode, !value.isEmpty {
                values.append("    udp-relay-mode: \(yaml(value))")
            }
            if let ports = node.portHopping, !ports.isEmpty { values.append("    ports: \(yaml(ports))") }
            appendClashALPN(node, to: &values)
            appendClashCertificateFingerprint(node, to: &values)
            appendClashClientFingerprint(node, to: &values)
        case .wireguard:
            values += [
                "    private-key: \(yaml(node.wireGuardPrivateKey ?? ""))",
                "    public-key: \(yaml(node.wireGuardPublicKey ?? ""))"
            ]
            if let value = node.wireGuardIPv4 { values.append("    ip: \(yaml(value))") }
            if let value = node.wireGuardIPv6 { values.append("    ipv6: \(yaml(value))") }
            values.append("    allowed-ips: \(yamlList(csv(node.wireGuardAllowedIPs)))")
            if let value = node.wireGuardPreSharedKey, !value.isEmpty {
                values.append("    pre-shared-key: \(yaml(value))")
            }
            if let bytes = wireGuardReservedBytes(node), !bytes.isEmpty {
                values.append("    reserved: [\(bytes.map(String.init).joined(separator: ", "))]")
            }
            if let value = node.wireGuardPersistentKeepalive {
                values.append("    persistent-keepalive: \(value)")
            }
            if let value = node.wireGuardMTU { values.append("    mtu: \(value)") }
            if !csv(node.wireGuardDNS).isEmpty {
                values.append("    dns: \(yamlList(csv(node.wireGuardDNS)))")
            }
            values.append("    udp: true")
        case .anytls:
            values += [
                "    password: \(yaml(node.password ?? ""))",
                "    skip-cert-verify: \(node.skipCertificateVerification)",
                "    udp: true"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
            if let value = node.idleSessionCheckInterval { values.append("    idle-session-check-interval: \(value)") }
            if let value = node.idleSessionTimeout { values.append("    idle-session-timeout: \(value)") }
            if let value = node.minIdleSession { values.append("    min-idle-session: \(value)") }
            appendClashALPN(node, to: &values)
            appendClashCertificateFingerprint(node, to: &values)
            appendClashClientFingerprint(node, to: &values)
        case .snell:
            values.append("    psk: \(yaml(node.password ?? ""))")
            if let version = node.version { values.append("    version: \(version)") }
            // Snell only carries UDP from version 3 onwards.
            if (node.version ?? 4) >= 3 { values.append("    udp: true") }
            if let mode = node.obfs, !mode.isEmpty, mode.lowercased() != "none" {
                values.append("    obfs-opts:")
                values.append("      mode: \(yaml(mode))")
                if let host = node.obfsParam, !host.isEmpty {
                    values.append("      host: \(yaml(host))")
                }
            }
        case .socks5, .http:
            if let username = node.username, !username.isEmpty { values.append("    username: \(yaml(username))") }
            if let password = node.password, !password.isEmpty { values.append("    password: \(yaml(password))") }
            values.append("    tls: \(node.tls)")
        case .unknown:
            break
        }
        return values.joined(separator: "\n")
    }

    /// REALITY needs the server's public key and short id; without them the
    /// node is plain TLS to a borrowed SNI and cannot connect.
    private func appendClashReality(_ node: ProxyNode, to values: inout [String]) {
        guard node.usesReality else { return }
        values.append("    reality-opts:")
        values.append("      public-key: \(yaml(node.realityPublicKey ?? ""))")
        if let shortID = node.realityShortID, !shortID.isEmpty {
            values.append("      short-id: \(yaml(shortID))")
        }
        // Clash Meta defaults the fingerprint when REALITY is on but it is
        // absent, so send whatever the airport specified.
        values.append("    client-fingerprint: \(yaml(node.fingerprint ?? "chrome"))")
    }

    /// Writes `alpn` as the YAML list Mihomo expects.
    ///
    /// A URI carries it as one comma-joined string; written back as a scalar
    /// the client reads `h3,h2` as a single protocol name and the handshake
    /// never matches.
    private func appendClashALPN(_ node: ProxyNode, to values: inout [String]) {
        let entries = ALPNList.values(node.alpn)
        guard !entries.isEmpty else { return }
        values.append("    alpn: [\(entries.map(yaml).joined(separator: ", "))]")
    }

    /// Shadowrocket's Clash reader consumes the same uTLS field as Mihomo.
    /// REALITY writes it together with `reality-opts`; ordinary TLS protocols
    /// still need it at the proxy root or their ClientHello differs from the
    /// provider's server expectation.
    private func appendClashClientFingerprint(_ node: ProxyNode, to values: inout [String]) {
        guard !node.usesReality,
              let fingerprint = node.fingerprint,
              !fingerprint.isEmpty else { return }
        values.append("    client-fingerprint: \(yaml(fingerprint))")
    }

    private func appendClashCertificateFingerprint(_ node: ProxyNode, to values: inout [String]) {
        guard let fingerprint = node.certificateFingerprint,
              !fingerprint.isEmpty else { return }
        values.append("    fingerprint: \(yaml(fingerprint))")
    }

    private func appendClashTransport(_ node: ProxyNode, to values: inout [String]) {
        values.append("    tls: \(node.tls)")
        values.append("    skip-cert-verify: \(node.skipCertificateVerification)")
        if let sni = node.sni, !sni.isEmpty { values.append("    servername: \(yaml(sni))") }
        appendClashCertificateFingerprint(node, to: &values)
        appendClashReality(node, to: &values)
        if node.kind == .vless, let flow = node.flow, !flow.isEmpty {
            values.append("    flow: \(yaml(flow))")
        }
        appendClashClientFingerprint(node, to: &values)
        if let transport = node.transport, !transport.isEmpty, transport != "tcp" {
            values.append("    network: \(yaml(transport == "httpupgrade" ? "ws" : transport))")
            switch transport {
            case "ws", "httpupgrade":
                values.append("    ws-opts:")
                values.append("      path: \(yaml(node.exportablePath ?? "/"))")
                if let host = node.hostHeader, !host.isEmpty {
                    values.append("      headers:")
                    values.append("        Host: \(yaml(host))")
                }
                if transport == "httpupgrade" { values.append("      v2ray-http-upgrade: true") }
            case "grpc":
                values.append("    grpc-opts:")
                if let service = node.path, !service.isEmpty {
                    let normalized = service.hasPrefix("/") ? String(service.dropFirst()) : service
                    values.append("      grpc-service-name: \(yaml(normalized))")
                }
            case "http":
                values.append("    http-opts:")
                values.append("      path: [\(yaml(node.exportablePath ?? "/"))]")
                if let host = node.hostHeader, !host.isEmpty {
                    values.append("      headers:")
                    values.append("        Host: [\(yaml(host))]")
                }
            case "h2":
                values.append("    h2-opts:")
                values.append("      path: \(yaml(node.exportablePath ?? "/"))")
                if let host = node.hostHeader, !host.isEmpty {
                    values.append("      host: [\(yaml(host))]")
                }
            case "xhttp":
                values.append("    xhttp-opts:")
                values.append("      path: \(yaml(node.exportablePath ?? "/"))")
                if let host = node.hostHeader, !host.isEmpty { values.append("      host: \(yaml(host))") }
                if let mode = node.transportMode, !mode.isEmpty { values.append("      mode: \(yaml(mode))") }
            default:
                break
            }
        }
    }

    private func clashSelectGroup(
        name: String,
        nodeNames: [String],
        hidden: Bool = false
    ) -> String {
        var output = "  - name: \(yaml(name))\n    type: select\n    proxies:\n"
        for name in nodeNames.removingDuplicates() {
            output += "      - \(yaml(name))\n"
        }
        if hidden { output += "    hidden: true\n" }
        return output
    }

    private func clashURLTestGroup(
        name: String,
        nodeNames: [String],
        hidden: Bool = false
    ) -> String {
        guard !nodeNames.isEmpty else {
            return clashSelectGroup(name: name, nodeNames: ["DIRECT"])
        }
        var output = "  - name: \(yaml(name))\n"
        output += "    type: url-test\n"
        output += "    url: http://www.gstatic.com/generate_204\n"
        output += "    interval: 300\n"
        output += "    tolerance: 50\n"
        output += "    proxies:\n"
        for name in nodeNames { output += "      - \(yaml(name))\n" }
        if hidden { output += "    hidden: true\n" }
        return output
    }

    private func surgeLike(
        nodes: [ProxyNode],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup],
        shadowrocket: Bool
    ) -> String {
        let target: ClientTarget = shadowrocket ? .shadowrocket : .surge
        let names = nodes.map { NodeRegionResolver.displayName(for: $0) }
        let regionGroupNames = regionGroups.map(\.name)
        var output = header(target: target)
        output += """
        [General]
        loglevel = notify
        ipv6 = true
        # `system` first meant the carrier's resolver got every query. Removed.
        # No encrypted-DNS key is written here: Shadowrocket's manual documents
        # none, and this project does not guess a client's field names.
        dns-server = 223.5.5.5, 119.29.29.29
        skip-proxy = 127.0.0.1, localhost, *.local
        test-timeout = 5

        [Proxy]
        """
        output += "\n"
        for node in nodes {
            output += surgeNode(node, shadowrocket: shadowrocket) + "\n"
        }
        output += surgeWireGuardSections(nodes)
        output += "\n[Proxy Group]\n"
        output += surgeSelect(
            name: RulePolicy.select.configurationName,
            values: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
        )
        output += surgeSelect(
            name: Self.manualGroupName,
            values: names.isEmpty ? ["DIRECT"] : names
        )
        output += surgeURLTest(
            name: RulePolicy.auto.configurationName,
            names: names
        )
        output += surgeSelect(
            name: Self.nestedSelectGroupName,
            values: nestedPrimaryChoices(regionGroupNames: regionGroupNames),
            hidden: true
        )
        output += surgeSelect(
            name: Self.nestedManualGroupName,
            values: names.isEmpty ? [Self.directGroupName] : names,
            hidden: true
        )
        output += surgeURLTest(
            name: Self.nestedAutoGroupName,
            names: names,
            hidden: true
        )
        output += surgeSelect(
            name: Self.directGroupName,
            values: ["DIRECT"],
            hidden: true
        )
        for policy in configurablePolicies(preset) {
            output += surgeSelect(
                name: policy.configurationName,
                values: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: "REJECT"
                )
            )
        }
        for group in regionGroups {
            output += surgeSelect(
                name: group.name,
                values: [group.automaticName] + group.nodeNames
            )
            output += surgeURLTest(
                name: group.automaticName,
                names: group.nodeNames,
                hidden: true
            )
        }
        output += "\n[Rule]\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: target) {
                    output += mapped + "\n"
                }
            }
        }
        if preset.includeGeoIPCN { output += "GEOIP,CN,DIRECT,no-resolve\n" }
        output += "FINAL,\(surgePolicyName(preset.finalPolicy))\n"
        return output
    }

    private func surgeNode(_ node: ProxyNode, shadowrocket: Bool) -> String {
        let name = confName(NodeRegionResolver.displayName(for: node))
        var components: [String] = []
        switch node.kind {
        case .shadowsocks:
            components = ["ss", node.server, "\(node.port)", "encrypt-method=\(node.cipher ?? "aes-256-gcm")", "password=\(confValue(node.password ?? ""))", "udp-relay=true"]
            if shadowrocket, node.plugin == "v2ray-plugin" {
                components.append("obfs=\(node.tls ? "wss" : "ws")")
                appendValue(node.hostHeader, key: "obfs-host", to: &components)
                appendValue(node.exportablePath, key: "obfs-uri", to: &components)
            } else if let mode = simpleObfsMode(node) {
                components.append("obfs=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &components)
            }
        case .shadowsocksR:
            components = ["ssr", node.server, "\(node.port)", "encrypt-method=\(node.cipher ?? "aes-256-cfb")", "password=\(confValue(node.password ?? ""))", "protocol=\(node.protocolName ?? "origin")", "obfs=\(node.obfs ?? "plain")"]
            appendValue(node.protocolParam, key: "protocol-param", to: &components)
            appendValue(node.obfsParam, key: "obfs-param", to: &components)
        case .vmess:
            components = [
                "vmess",
                node.server,
                "\(node.port)",
                "username=\(node.exportableUUID ?? "")",
                "vmess-aead=\((node.alterID ?? 0) == 0)"
            ]
            if let cipher = node.cipher,
               ["aes-128-gcm", "chacha20-ietf-poly1305"].contains(cipher.lowercased()) {
                components.append("encrypt-method=\(cipher)")
            }
            appendSurgeTransport(node, includeTLSFlag: true, shadowrocket: shadowrocket, to: &components)
        case .vless:
            components = ["vless", node.server, "\(node.port)", "username=\(node.exportableUUID ?? "")"]
            appendSurgeTransport(node, includeTLSFlag: true, shadowrocket: shadowrocket, to: &components)
            // Shadowrocket only — Surge takes no VLESS and rejects REALITY.
            // Its vocabulary is its own: `pbk`/`sid`/`fingerprint` rather than
            // Loon's public-key/short-id/fp, and the flow is an enum (`xtls=2`
            // for vision) rather than the flow string.
            if shadowrocket, node.usesReality {
                appendValue(node.realityPublicKey, key: "pbk", to: &components)
                appendValue(node.realityShortID, key: "sid", to: &components)
                appendValue(node.fingerprint, key: "fingerprint", to: &components)
                if let xtls = shadowrocketXTLSMode(node) { components.append("xtls=\(xtls)") }
            }
        case .trojan:
            components = ["trojan", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
            appendSurgeTransport(node, includeTLSFlag: false, shadowrocket: shadowrocket, to: &components)
        case .hysteria2:
            // `password=` is deliberate for both clients, even though
            // Shadowrocket's manual writes Hysteria 2 as `auth=`. The manual
            // listing one spelling does not mean the app rejects the other:
            // Shadowrocket was checked on device with a Tower-generated
            // profile, and it fills the password field and connects from
            // `password=`. See docs/HANDOFF.md — do not "fix" this to `auth=`
            // from the manual alone.
            components = ["hysteria2", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
            // The Salamander layer is not optional decoration: a server that
            // runs it drops every packet that arrives unobfuscated, so a node
            // written without this key imports cleanly and never connects.
            // The obfuscator is named by the key rather than carried as a
            // value — `salamander-password` in Surge's manual, a bare
            // `obfsParam` in Shadowrocket's.
            if let obfs = hysteria2Obfs(node) {
                let key = shadowrocket ? "obfsParam" : "salamander-password"
                components.append("\(key)=\(confValue(obfs.password))")
            }
            appendSurgeTLS(node, includeTLSFlag: false, to: &components)
        case .hysteria:
            // Shadowrocket only; Surge has no Hysteria 1 server type and
            // writes(_:to:excluding:) drops these before generation.
            components = ["hysteria", node.server, "\(node.port)", "auth=\(confValue(node.password ?? ""))"]
            if let obfs = node.obfs, !obfs.isEmpty, obfs.lowercased() != "none" {
                components.append("obfsParam=\(confValue(obfs))")
            }
            appendValue(node.protocolName, key: "protocol", to: &components)
            components.append("upmbps=\(node.upMbps ?? 50)")
            components.append("downmbps=\(node.downMbps ?? 100)")
            appendSurgeTLS(node, includeTLSFlag: false, to: &components)
            components.append("udp=1")
        case .tuic:
            if shadowrocket {
                // Shadowrocket's own vocabulary: the UUID is `user`, the SNI is
                // `peer`, and UDP is the numeric `udp=1` rather than Surge's
                // `udp-relay=true`.
                components = ["tuic", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
                appendValue(node.exportableUUID, key: "user", to: &components)
                appendSurgeTLS(node, includeTLSFlag: false, to: &components)
                components.append("udp=1")
            } else {
                // Surge distinguishes the two TUIC versions by server type and
                // only ever gets v5 from a `tuic://uuid:password@` URI.
                components = ["tuic-v5", node.server, "\(node.port)"]
                appendValue(node.exportableUUID, key: "uuid", to: &components)
                components.append("password=\(confValue(node.password ?? ""))")
                appendSurgeTLS(node, includeTLSFlag: false, to: &components)
                components.append("udp-relay=true")
            }
        case .wireguard:
            components = ["wireguard", "section-name=\(wireGuardSectionName(node))"]
        case .anytls:
            components = ["anytls", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
            appendSurgeTLS(node, includeTLSFlag: false, to: &components)
            components.append("udp-relay=true")
        case .snell:
            components = ["snell", node.server, "\(node.port)", "psk=\(confValue(node.password ?? ""))"]
            if let version = node.version { components.append("version=\(version)") }
            if let mode = node.obfs, !mode.isEmpty, mode.lowercased() != "none" {
                components.append("obfs=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &components)
            }
            if (node.version ?? 4) >= 3 { components.append("udp-relay=true") }
        case .socks5:
            components = [node.tls ? "socks5-tls" : "socks5", node.server, "\(node.port)"]
            components += surgeCredentialPair(node)
            components.append("udp-relay=true")
            if node.tls { appendSurgeTLS(node, includeTLSFlag: false, to: &components) }
        case .http:
            components = [node.tls ? "https" : "http", node.server, "\(node.port)"]
            components += surgeCredentialPair(node)
            if node.tls { appendSurgeTLS(node, includeTLSFlag: false, to: &components) }
        case .unknown:
            components = ["direct"]
        }
        if shadowrocket, node.kind == .vless { components.append("udp-relay=true") }
        return "\(name) = \(components.joined(separator: ", "))"
    }

    // Surge and Shadowrocket read username and password as positional fields.
    // Emitting only one of them would move the password into the username slot,
    // so a half-filled credential pair is written as an explicit empty username.
    private func surgeCredentialPair(_ node: ProxyNode) -> [String] {
        let username = node.username ?? ""
        let password = node.password ?? ""
        guard !username.isEmpty || !password.isEmpty else { return [] }
        return [confValue(username), confValue(password)]
    }

    private func wireGuardSectionName(_ node: ProxyNode) -> String {
        "tower-\(node.id.uuidString.lowercased())"
    }

    private func surgeWireGuardSections(_ nodes: [ProxyNode]) -> String {
        var output = ""
        for node in nodes where node.kind == .wireguard {
            output += "\n[WireGuard \(wireGuardSectionName(node))]\n"
            output += "private-key = \(node.wireGuardPrivateKey ?? "")\n"
            if let value = node.wireGuardIPv4, !value.isEmpty { output += "self-ip = \(value)\n" }
            if let value = node.wireGuardIPv6, !value.isEmpty { output += "self-ip-v6 = \(value)\n" }
            if let value = node.wireGuardDNS, !value.isEmpty { output += "dns-server = \(value)\n" }
            if let value = node.wireGuardMTU { output += "mtu = \(value)\n" }
            var peer = [
                "public-key = \(node.wireGuardPublicKey ?? "")",
                "allowed-ips = \"\(node.wireGuardAllowedIPs ?? "0.0.0.0/0, ::/0")\"",
                "endpoint = \(node.endpoint)"
            ]
            if let value = node.wireGuardPreSharedKey, !value.isEmpty { peer.append("preshared-key = \(value)") }
            if let value = node.wireGuardPersistentKeepalive { peer.append("keepalive = \(value)") }
            if let bytes = wireGuardReservedBytes(node), bytes.count == 3 {
                peer.append("client-id = \(bytes.map(String.init).joined(separator: "/"))")
            }
            output += "peer = (\(peer.joined(separator: ", ")))\n"
        }
        return output
    }

    private func csv(_ value: String?) -> [String] {
        (value ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "[] \t\r\n\"'"))
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'")) }
            .filter { !$0.isEmpty }
    }

    private func wireGuardReservedBytes(_ node: ProxyNode) -> [Int]? {
        let bytes = csv(node.wireGuardReserved).compactMap(Int.init)
        guard bytes.allSatisfy({ (0 ... 255).contains($0) }) else { return nil }
        return bytes
    }

    private func yamlList(_ values: [String]) -> String {
        "[\(values.map(yaml).joined(separator: ", "))]"
    }

    /// Shadowrocket numbers the XTLS flow instead of naming it: 2 is vision,
    /// 1 the older direct mode.
    private func shadowrocketXTLSMode(_ node: ProxyNode) -> Int? {
        guard let flow = node.flow?.lowercased(), !flow.isEmpty else { return nil }
        if flow.contains("vision") { return 2 }
        if flow.contains("direct") { return 1 }
        return nil
    }

    private func appendSurgeTransport(
        _ node: ProxyNode,
        includeTLSFlag: Bool,
        shadowrocket: Bool,
        to values: inout [String]
    ) {
        appendSurgeTLS(node, includeTLSFlag: includeTLSFlag, to: &values)
        if node.transport == "ws" {
            values.append("ws=true")
            appendValue(node.exportablePath ?? "/", key: "ws-path", to: &values)
            if let host = node.hostHeader, !host.isEmpty { values.append("ws-headers=Host:\(confValue(host))") }
        } else if shadowrocket, let transport = node.transport, transport != "tcp" {
            values.append("obfs=\(transport)")
            if transport == "grpc" {
                appendValue(node.path?.hasPrefix("/") == true ? String(node.path!.dropFirst()) : node.path,
                            key: "serviceName", to: &values)
            } else {
                appendValue(node.exportablePath, key: "path", to: &values)
            }
            appendValue(node.hostHeader, key: "host", to: &values)
            if transport == "xhttp" { appendValue(node.transportMode, key: "mode", to: &values) }
        }
    }

    private func appendSurgeTLS(
        _ node: ProxyNode,
        includeTLSFlag: Bool,
        to values: inout [String]
    ) {
        if includeTLSFlag, node.tls { values.append("tls=true") }
        appendValue(node.sni, key: "sni", to: &values)
        if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
        appendValue(node.alpn, key: "alpn", to: &values)
    }

    private func surgeSelect(
        name: String,
        values: [String],
        hidden: Bool = false
    ) -> String {
        let hiddenParameter = hidden ? ", hidden=true" : ""
        return "\(confName(name)) = select, \(values.removingDuplicates().map(confName).joined(separator: ", "))\(hiddenParameter)\n"
    }

    private func surgeURLTest(
        name: String,
        names: [String],
        hidden: Bool = false
    ) -> String {
        guard !names.isEmpty else { return surgeSelect(name: name, values: ["DIRECT"]) }
        let hiddenParameter = hidden ? ", hidden=true" : ""
        return "\(confName(name)) = url-test, \(names.map(confName).joined(separator: ", ")), url=http://www.gstatic.com/generate_204, interval=300, tolerance=50\(hiddenParameter)\n"
    }

    private func loon(
        nodes: [ProxyNode],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup]
    ) -> String {
        let names = nodes.map { NodeRegionResolver.displayName(for: $0) }
        let regionGroupNames = regionGroups.map(\.name)
        var output = header(target: .loon)
        output += """
        [General]
        ipv6 = true
        dns-server = 223.5.5.5, 119.29.29.29

        [Proxy]
        """
        output += "\n"
        for node in nodes { output += loonNode(node) + "\n" }
        output += "\n[Proxy Group]\n"
        let selectNames = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(RulePolicy.select.configurationName)) = select,\(selectNames)\n"
        let manualNames = (names.isEmpty ? ["DIRECT"] : names).map(confName).joined(separator: ",")
        output += "\(confName(Self.manualGroupName)) = select,\(manualNames)\n"
        if names.isEmpty {
            output += "\(confName(RulePolicy.auto.configurationName)) = select,DIRECT\n"
        } else {
            output += "\(confName(RulePolicy.auto.configurationName)) = url-test,\(names.map(confName).joined(separator: ",")),url=http://www.gstatic.com/generate_204,interval=300,tolerance=50\n"
        }
        let nestedSelectNames = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(Self.nestedSelectGroupName)) = select,\(nestedSelectNames),hidden=true\n"
        let nestedManualNames = (names.isEmpty ? [Self.directGroupName] : names)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(Self.nestedManualGroupName)) = select,\(nestedManualNames),hidden=true\n"
        if names.isEmpty {
            output += "\(confName(Self.nestedAutoGroupName)) = select,\(confName(Self.directGroupName)),hidden=true\n"
        } else {
            output += "\(confName(Self.nestedAutoGroupName)) = url-test,\(names.map(confName).joined(separator: ",")),url=http://www.gstatic.com/generate_204,interval=300,tolerance=50,hidden=true\n"
        }
        output += "\(confName(Self.directGroupName)) = select,DIRECT,hidden=true\n"
        for policy in configurablePolicies(preset) {
            let choices = policyChoices(
                policy,
                regionGroupNames: regionGroupNames,
                reject: "REJECT"
            )
                .map(confName)
                .joined(separator: ",")
            output += "\(confName(policy.configurationName)) = select,\(choices)\n"
        }
        for group in regionGroups {
            output += "\(confName(group.name)) = select,\(([group.automaticName] + group.nodeNames).map(confName).joined(separator: ","))\n"
            output += "\(confName(group.automaticName)) = url-test,\(group.nodeNames.map(confName).joined(separator: ",")),url=http://www.gstatic.com/generate_204,interval=300,tolerance=50,hidden=true\n"
        }
        output += "\n[Rule]\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: .loon) { output += mapped + "\n" }
            }
        }
        // Without `no-resolve` this rule forces a local lookup of every domain
        // no earlier rule matched, purely to test its country — and those are
        // exactly the domains no rule list bothered to cover. With it the rule
        // simply does not match a domain, the request falls through to the
        // final policy, and the node resolves it instead.
        if preset.includeGeoIPCN { output += "GEOIP,CN,DIRECT,no-resolve\n" }
        output += "FINAL,\(surgePolicyName(preset.finalPolicy))\n"
        return output
    }

    private func loonNode(_ node: ProxyNode) -> String {
        let name = confName(NodeRegionResolver.displayName(for: node))
        var values: [String]
        switch node.kind {
        case .shadowsocks:
            values = ["Shadowsocks", node.server, "\(node.port)", node.cipher ?? "aes-256-gcm", loonQuoted(node.password ?? "")]
            if let mode = simpleObfsMode(node) {
                // Loon names the simple-obfs mode obfs-name; plain "obfs" is
                // the ShadowsocksR field and means something else there.
                values.append("obfs-name=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &values)
            }
            values.append("udp=true")
        case .shadowsocksR:
            values = ["ShadowsocksR", node.server, "\(node.port)", node.cipher ?? "aes-256-cfb", loonQuoted(node.password ?? ""), "protocol=\(node.protocolName ?? "origin")", "obfs=\(node.obfs ?? "plain")"]
            appendValue(node.protocolParam, key: "protocol-param", to: &values)
            appendValue(node.obfsParam, key: "obfs-param", to: &values)
            values.append("udp=true")
        case .vmess:
            values = [
                "vmess",
                node.server,
                "\(node.port)",
                node.cipher ?? "auto",
                loonQuoted(node.exportableUUID ?? ""),
                "transport=\(node.transport ?? "tcp")",
                "alterId=\(node.alterID ?? 0)"
            ]
            appendLoonTransportAndTLS(node, to: &values)
        case .vless:
            values = [
                "VLESS",
                node.server,
                "\(node.port)",
                loonQuoted(node.exportableUUID ?? ""),
                "transport=\(node.transport ?? "tcp")"
            ]
            appendLoonTransportAndTLS(node, to: &values)
        case .trojan:
            values = ["trojan", node.server, "\(node.port)", loonQuoted(node.password ?? "")]
            appendValue(node.transport, key: "transport", to: &values)
            appendValue(node.exportablePath, key: "path", to: &values)
            appendValue(node.hostHeader, key: "host", to: &values)
            appendValue(node.alpn, key: "alpn", to: &values)
            if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            appendValue(node.sni, key: "tls-name", to: &values)
            values.append("udp=true")
        case .hysteria2:
            values = ["Hysteria2", node.server, "\(node.port)", loonQuoted(node.password ?? "")]
            if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            appendValue(node.sni, key: "tls-name", to: &values)
            values += ["udp=true", "fast-open=true"]
        case .wireguard:
            values = [
                "wireguard",
                "interface-ip=\(node.wireGuardIPv4 ?? "")",
                "private-key=\(loonQuoted(node.wireGuardPrivateKey ?? ""))"
            ]
            if let value = node.wireGuardIPv6, !value.isEmpty { values.append("interface-ipv6=\(value)") }
            if let value = node.wireGuardMTU { values.append("mtu=\(value)") }
            if let value = node.wireGuardDNS, !value.isEmpty { values.append("dns=\(value)") }
            if let value = node.wireGuardPersistentKeepalive { values.append("keepalive=\(value)") }
            var peer = [
                "public-key=\(loonQuoted(node.wireGuardPublicKey ?? ""))",
                "allowed-ips=\(loonQuoted(node.wireGuardAllowedIPs ?? "0.0.0.0/0,::/0"))",
                "endpoint=\(node.endpoint)"
            ]
            if let value = node.wireGuardReserved, !value.isEmpty { peer.append("reserved=[\(value)]") }
            if let value = node.wireGuardPreSharedKey, !value.isEmpty {
                peer.append("preshared-key=\(loonQuoted(value))")
            }
            values.append("peers=[{\(peer.joined(separator: ","))}]")
            values.append("udp=true")
        case .anytls:
            values = ["anytls", node.server, "\(node.port)", loonQuoted(node.password ?? "")]
            if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            appendValue(node.sni, key: "tls-name", to: &values)
            values.append("udp=true")
        case .socks5:
            values = ["Socks5", node.server, "\(node.port)"]
            values += loonCredentialPair(node)
            values.append("udp=true")
        case .http:
            values = [node.tls ? "https" : "http", node.server, "\(node.port)"]
            values += loonCredentialPair(node)
            if node.tls {
                if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
                appendValue(node.sni, key: "tls-name", to: &values)
            }
        // Loon implements neither, and writes(_:to:excluding:) filters them
        // out before generation, so this branch is defensive only.
        case .hysteria, .tuic, .snell, .unknown:
            values = ["Direct"]
        }
        return "\(name) = \(values.joined(separator: ","))"
    }

    // Loon also reads username and password positionally, so both fields are
    // emitted together or not at all. Empty trailing fields produce a line that
    // Loon rejects when a proxy needs no authentication.
    private func loonCredentialPair(_ node: ProxyNode) -> [String] {
        let username = node.username ?? ""
        let password = node.password ?? ""
        guard !username.isEmpty || !password.isEmpty else { return [] }
        return [loonQuoted(username), loonQuoted(password)]
    }

    private func appendLoonTransportAndTLS(_ node: ProxyNode, to values: inout [String]) {
        if node.usesReality {
            values.append("public-key=\"\(confValue(node.realityPublicKey ?? ""))\"")
            appendValue(node.realityShortID, key: "short-id", to: &values)
        }
        if let flow = node.flow, !flow.isEmpty { values.append("flow=\(confValue(flow))") }
        appendValue(node.exportablePath, key: "path", to: &values)
        appendValue(node.hostHeader, key: "host", to: &values)
        values.append("over-tls=\(node.tls)")
        appendValue(node.sni, key: "tls-name", to: &values)
        if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
    }

    private func quanX(
        nodes: [ProxyNode],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup]
    ) -> String {
        let names = nodes.map { NodeRegionResolver.displayName(for: $0) }
        let regionGroupNames = regionGroups.map(\.name)
        var output = header(target: .quanx)
        output += """
        [general]
        server_check_url = http://www.gstatic.com/generate_204
        server_check_timeout = 5000

        [dns]
        no-system
        server = 223.5.5.5
        server = 1.1.1.1
        """
        // Section order follows subconverter's QuanX template, which is what
        // every working converter emits: `[policy]` comes before the server and
        // filter sections, not after them. Tower used to put the whole node
        // list between `[dns]` and `[policy]`, and Quantumult X imported the
        // rules while dropping every policy group.
        output += "\n\n[policy]\n"
        let selectValues = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ", ")
        output += "static=\(RulePolicy.select.configurationName), \(selectValues)\n"
        let manualValues = (names.isEmpty ? ["direct"] : names).map(confName).joined(separator: ", ")
        output += "static=\(Self.manualGroupName), \(manualValues)\n"
        if names.isEmpty {
            output += "static=\(RulePolicy.auto.configurationName), direct\n"
        } else {
            output += "url-latency-benchmark=\(RulePolicy.auto.configurationName), \(names.map(confName).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50\n"
        }
        let nestedSelectValues = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ", ")
        output += "static=\(Self.nestedSelectGroupName), \(nestedSelectValues)\n"
        let nestedManualValues = (names.isEmpty ? [Self.directGroupName] : names)
            .map(confName)
            .joined(separator: ", ")
        output += "static=\(Self.nestedManualGroupName), \(nestedManualValues)\n"
        if names.isEmpty {
            output += "static=\(Self.nestedAutoGroupName), \(Self.directGroupName)\n"
        } else {
            output += "url-latency-benchmark=\(Self.nestedAutoGroupName), \(names.map(confName).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50\n"
        }
        output += "static=\(Self.directGroupName), direct\n"
        for policy in configurablePolicies(preset) {
            let choices = policyChoices(
                policy,
                regionGroupNames: regionGroupNames,
                reject: "reject"
            )
                .map(confName)
                .joined(separator: ", ")
            output += "static=\(policy.configurationName), \(choices)\n"
        }
        for group in regionGroups {
            output += "static=\(group.name), \(([group.automaticName] + group.nodeNames).map(confName).joined(separator: ", "))\n"
            output += "url-latency-benchmark=\(group.automaticName), server-tag-regex=\(quanXServerTagRegex(group.nodeNames)), check-interval=300, alive-checking=false, tolerance=50\n"
        }
        output += "\n[server_remote]\n\n[filter_remote]\n\n[rewrite_remote]\n"
        output += "\n[server_local]\n"
        for node in nodes { output += quanXNode(node) + "\n" }
        output += "\n[filter_local]\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: .quanx) { output += mapped + "\n" }
            }
        }
        if preset.includeGeoIPCN { output += "geoip, cn, direct, no-resolve\n" }
        output += "final, \(quanXPolicyName(preset.finalPolicy))\n"
        for section in ["rewrite_local", "task_local", "http_backend", "mitm"] {
            output += "\n[\(section)]\n"
        }
        return output
    }

    private func quanXNode(_ node: ProxyNode) -> String {
        var values = [node.endpoint]
        let prefix: String
        switch node.kind {
        case .shadowsocks:
            prefix = "shadowsocks"
            values += ["method=\(node.cipher ?? "aes-256-gcm")", "password=\(confValue(node.password ?? ""))", "udp-relay=true"]
            if node.plugin == "v2ray-plugin" {
                values.append("obfs=\(node.tls ? "wss" : "ws")")
                appendValue(node.hostHeader, key: "obfs-host", to: &values)
                appendValue(node.exportablePath, key: "obfs-uri", to: &values)
            } else if let mode = simpleObfsMode(node) {
                values.append("obfs=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &values)
            }
        case .shadowsocksR:
            prefix = "shadowsocks"
            values += ["method=\(node.cipher ?? "aes-256-cfb")", "password=\(confValue(node.password ?? ""))", "ssr-protocol=\(node.protocolName ?? "origin")", "obfs=\(node.obfs ?? "plain")"]
            appendValue(node.protocolParam, key: "ssr-protocol-param", to: &values)
            appendValue(node.obfsParam, key: "obfs-host", to: &values)
        case .vmess:
            prefix = "vmess"
            values += ["method=\(quanXVMessMethod(node))", "password=\(confValue(node.exportableUUID ?? ""))"]
            appendQuanXTransport(node, to: &values)
        case .vless:
            prefix = "vless"
            values += ["method=none", "password=\(confValue(node.exportableUUID ?? ""))"]
            appendQuanXTransport(node, to: &values)
        case .trojan:
            prefix = "trojan"
            values.append("password=\(confValue(node.password ?? ""))")
            appendQuanXTransport(node, to: &values)
        case .anytls:
            prefix = "anytls"
            values += ["password=\(confValue(node.password ?? ""))", "over-tls=true"]
            appendValue(node.sni, key: "tls-host", to: &values)
            appendQuanXCertificatePolicy(node, to: &values)
            values.append("udp-relay=true")
        case .socks5:
            prefix = "socks5"
            appendValue(node.username, key: "username", to: &values)
            appendValue(node.password, key: "password", to: &values)
        case .http:
            prefix = "http"
            appendValue(node.username, key: "username", to: &values)
            appendValue(node.password, key: "password", to: &values)
            if node.tls { values.append("over-tls=true") }
        // Quantumult X implements none of these, and writes(_:to:excluding:)
        // filters them out before generation, so this is defensive only.
        case .hysteria, .hysteria2, .tuic, .wireguard, .snell, .unknown:
            prefix = "http"
        }
        values.append("tag=\(confName(NodeRegionResolver.displayName(for: node)))")
        return "\(prefix)=\(values.joined(separator: ", "))"
    }

    private func appendQuanXTransport(_ node: ProxyNode, to values: inout [String]) {
        if node.transport == "ws" {
            values.append("obfs=\(node.tls ? "wss" : "ws")")
            appendValue(node.hostHeader ?? node.sni, key: "obfs-host", to: &values)
            appendValue(node.exportablePath ?? "/", key: "obfs-uri", to: &values)
        } else if node.tls {
            values.append("obfs=over-tls")
            appendValue(node.sni, key: "obfs-host", to: &values)
        }
        if node.usesReality {
            appendValue(node.realityPublicKey, key: "reality-base64-pubkey", to: &values)
            appendValue(node.realityShortID, key: "reality-hex-shortid", to: &values)
            if let flow = node.flow, !flow.isEmpty { values.append("vless-flow=\(confValue(flow))") }
        }
        // Only once a TLS layer exists is there a certificate to skip checking.
        // A plain `ws` or bare TCP node has none, and an airport can still ship
        // one flagged insecure — Quantumult X rejects the whole file over the
        // stray key: "配置文件语法错误, line 119".
        if node.tls { appendQuanXCertificatePolicy(node, to: &values) }
    }

    // Trojan and Hysteria 2 always negotiate TLS in Quantumult X, so they need
    // the same certificate escape hatch that the obfs-based protocols get.
    private func appendQuanXCertificatePolicy(_ node: ProxyNode, to values: inout [String]) {
        if node.skipCertificateVerification { values.append("tls-verification=false") }
    }

    // Quantumult X names the VMess cipher with the same method key it uses for
    // Shadowsocks. "auto" is not one of its accepted values, so it is mapped to
    // the AEAD cipher that its VMess implementation negotiates by default.
    /// Hysteria 2's obfs layer, only when both halves of it survived.
    ///
    /// The type and the password are one thing, not two optional ones:
    /// `obfs: salamander` on its own makes Mihomo refuse the entire profile —
    /// "proxy 301: hysteria2 obfs: salamander requires obfs-password" — and
    /// takes every other node in the file down with it. sing-box is the same.
    /// Without the password the node could not have connected either way, so
    /// the obfs layer is dropped rather than half-written.
    func hysteria2Obfs(_ node: ProxyNode) -> (type: String, password: String)? {
        guard node.kind == .hysteria2,
              let type = node.obfs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !type.isEmpty,
              type.lowercased() != "none",
              let password = node.obfsParam?.trimmingCharacters(in: .whitespacesAndNewlines),
              !password.isEmpty else { return nil }
        return (type, password)
    }

    /// The simple-obfs mode of a Shadowsocks node, or nil when it carries no
    /// plugin. `obfs`/`obfsParam` hold the ShadowsocksR obfuscation for SSR
    /// nodes, so this is scoped to plain Shadowsocks, where the same fields
    /// carry the SIP003 plugin's mode and host.
    func simpleObfsMode(_ node: ProxyNode) -> String? {
        guard node.kind == .shadowsocks,
              let mode = node.obfs?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              ["http", "tls"].contains(mode) else { return nil }
        return mode
    }

    private func quanXVMessMethod(_ node: ProxyNode) -> String {
        let accepted = ["aes-128-gcm", "chacha20-poly1305", "chacha20-ietf-poly1305", "none"]
        guard let cipher = node.cipher?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              accepted.contains(cipher) else {
            return "chacha20-ietf-poly1305"
        }
        return cipher
    }

    private func mappedRule(_ rule: String, policy: RulePolicy, target: ClientTarget) -> String? {
        let policyName: String
        switch target {
        case .clash, .clashApple: policyName = clashPolicyName(policy)
        case .quanx: policyName = quanXPolicyName(policy)
        default: policyName = surgePolicyName(policy)
        }
        return mappedRule(rule, policyName: policyName, target: target)
    }

    /// Shared by the built-in presets and by imported schemes, whose policy
    /// names come from the imported file rather than from `RulePolicy`.
    private func mappedRule(_ rule: String, policyName: String, target: ClientTarget) -> String? {
        var parts = rule.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count >= 2 else { return nil }

        let ruleType = parts[0].uppercased()
        // Clash/Mihomo does not implement Surge's URL-REGEX dialect. These
        // expressions may inspect the URL path, so converting them to a domain
        // rule would silently change their meaning; omit them for Clash only.
        if [.clash, .clashApple].contains(target), ruleType == "URL-REGEX" {
            return nil
        }

        if target == .quanx {
            let mappedType: String
            switch ruleType {
            case "DOMAIN": mappedType = "host"
            case "DOMAIN-SUFFIX": mappedType = "host-suffix"
            case "DOMAIN-KEYWORD": mappedType = "host-keyword"
            case "IP-CIDR": mappedType = "ip-cidr"
            case "IP-CIDR6": mappedType = "ip6-cidr"
            case "GEOIP": mappedType = "geoip"
            case "USER-AGENT": mappedType = "user-agent"
            default: return nil
            }
            parts[0] = mappedType
        } else if !Self.surgeFamilyRuleTypes.contains(ruleType) {
            // A future rule snapshot may introduce a type these clients cannot
            // parse. Dropping it keeps the rest of the configuration loadable
            // instead of shipping a line that fails at import time.
            return nil
        }

        if parts.last?.lowercased() == "no-resolve" {
            parts.insert(policyName, at: parts.count - 1)
        } else {
            parts.append(policyName)
            if ruleType == "GEOIP" {
                // A GEOIP rule above later domain rules otherwise makes the
                // client resolve the domain locally just to decide whether it
                // matches — and the domains that reach it are the ones no rule
                // list covered. Every built-in preset already writes the flag
                // for all seven clients; an imported scheme must not route
                // differently on Stash than it does on Surge.
                parts.append("no-resolve")
            }
        }
        let separator = target == .quanx ? ", " : ","
        return parts.joined(separator: separator)
    }

    private func configurablePolicies(_ preset: RulePreset) -> [RulePolicy] {
        preset.policies.filter { ![.direct, .reject, .select, .auto].contains($0) }
    }

    private func makeRegionGroups(
        nodes: [ProxyNode],
        countryCodes: [UUID: String]
    ) -> [RegionStrategyGroup] {
        let preferredCodes = Set(Self.regionDefinitions.map(\.code))
        var nodesByCode: [String: [String]] = [:]
        var otherNodeNames: [String] = []

        for node in nodes {
            // Same order the UI shows: the airport's own name first, the IP
            // database only for names that say nothing about where they are.
            let rawCode = NodeRegionResolver.countryCode(for: node) ?? countryCodes[node.id]
            let normalizedCode = rawCode?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let countryCode = normalizedCode == "UK" ? "GB" : normalizedCode
            let nodeName = NodeRegionResolver.displayName(for: node)

            if let countryCode, preferredCodes.contains(countryCode) {
                nodesByCode[countryCode, default: []].append(nodeName)
            } else {
                otherNodeNames.append(nodeName)
            }
        }

        var groups = Self.regionDefinitions.compactMap { definition -> RegionStrategyGroup? in
            guard let names = nodesByCode[definition.code], !names.isEmpty else { return nil }
            return RegionStrategyGroup(
                name: definition.name,
                nodeNames: names.removingDuplicates()
            )
        }
        if !otherNodeNames.isEmpty {
            groups.append(
                RegionStrategyGroup(
                    name: Self.otherRegionsName,
                    nodeNames: otherNodeNames.removingDuplicates()
                )
            )
        }
        return groups
    }

    private func nestedPrimaryChoices(regionGroupNames: [String]) -> [String] {
        [Self.nestedAutoGroupName, Self.nestedManualGroupName]
            + regionGroupNames
            + [Self.directGroupName]
    }

    private func policyChoices(
        _ policy: RulePolicy,
        regionGroupNames: [String],
        reject: String
    ) -> [String] {
        let select = Self.nestedSelectGroupName
        let auto = Self.nestedAutoGroupName
        let manual = Self.nestedManualGroupName
        let translatedDirect = Self.directGroupName
        return switch policy {
        case .foreignAds:
            [reject, translatedDirect, select]
        case .domestic, .apple, .microsoft:
            [translatedDirect, select, manual] + regionGroupNames + [auto]
        default:
            [select, auto, manual] + regionGroupNames + [translatedDirect]
        }
    }

    private func clashPolicyName(_ policy: RulePolicy) -> String {
        policy.configurationName
    }

    private func surgePolicyName(_ policy: RulePolicy) -> String {
        policy.configurationName
    }

    private func quanXPolicyName(_ policy: RulePolicy) -> String {
        switch policy {
        case .direct: "direct"
        case .reject: "reject"
        default: policy.configurationName
        }
    }

    private func header(target: ClientTarget) -> String {
        """
        # Generated locally by 塔台 for \(target.name)
        # Rules are selected and stored locally on this device.
        # Subscription credentials never leave this device.

        """
    }

    private func reservedProxyNames(for preset: RulePreset) -> Set<String> {
        Set(
            preset.policies.map(\.configurationName)
                + Self.regionDefinitions.map(\.name)
                + Self.regionDefinitions.map { "\($0.name) · 延迟优选" }
                + [
                    Self.manualGroupName,
                    Self.nestedSelectGroupName,
                    Self.nestedAutoGroupName,
                    Self.nestedManualGroupName,
                    Self.directGroupName,
                    Self.otherRegionsName,
                    "\(Self.otherRegionsName) · 延迟优选",
                    "DIRECT",
                    "REJECT",
                    "direct",
                    "reject"
                ]
        )
    }

    private func uniquedNames(
        _ nodes: [ProxyNode],
        reservedNames: Set<String>
    ) -> [ProxyNode] {
        var counts: [String: Int] = [:]
        return nodes.map { node in
            var copy = node
            let displayName = NodeRegionResolver.displayName(for: node)
            var base = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? node.endpoint : displayName
            if reservedNames.contains(base) {
                base += " · 节点"
            }
            let count = (counts[base] ?? 0) + 1
            counts[base] = count
            copy.name = count == 1 ? base : "\(base) · \(count)"
            return copy
        }
    }

    private func appendValue(
        _ value: String?,
        key: String,
        separator: String = "=",
        to values: inout [String]
    ) {
        guard let value, !value.isEmpty else { return }
        values.append("\(key)\(separator)\(confValue(value))")
    }

    /// A raw newline inside a double-quoted YAML scalar ends the value, so it is
    /// folded away before the quote and backslash escapes are applied.
    private func yaml(_ value: String) -> String {
        let escaped = collapsingLineBreaks(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // Node names come from subscription remarks, which are untrusted text. A
    // newline would end the proxy line early and "#" or ";" would turn the rest
    // of it into a comment in the Surge, Loon and Quantumult X formats.
    private func confName(_ value: String) -> String {
        collapsingLineBreaks(value)
            .replacingOccurrences(of: "=", with: "-")
            .replacingOccurrences(of: ",", with: "，")
            .replacingOccurrences(of: "#", with: "＃")
            .replacingOccurrences(of: ";", with: "；")
            // Square brackets open a section in every INI-style config. A node
            // called "[BETA-1] 🇭🇰 HongKong" started one mid-file and orphaned
            // every proxy after it — Shadowrocket showed the five nodes above
            // the line and silently dropped the other twenty-three.
            .replacingOccurrences(of: "[", with: "［")
            .replacingOccurrences(of: "]", with: "］")
            .trimmingCharacters(in: .whitespaces)
    }

    private func quanXServerTagRegex(_ nodeNames: [String]) -> String {
        let alternatives = nodeNames
            .map(confName)
            .removingDuplicates()
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return "^(?:\(alternatives))$"
    }

    private func confValue(_ value: String) -> String {
        collapsingLineBreaks(value)
            .replacingOccurrences(of: ",", with: "%2C")
    }

    /// Loon's positional credential fields are quoted in its documented node
    /// syntax. Escaping here also prevents commas inside credentials from
    /// becoming extra fields.
    private func loonQuoted(_ value: String) -> String {
        let escaped = collapsingLineBreaks(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func collapsingLineBreaks(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private struct RegionDefinition {
    let code: String
    let name: String
}

struct RegionStrategyGroup {
    let name: String
    let nodeNames: [String]

    var automaticName: String { "\(name) · 延迟优选" }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - sing-box

/// sing-box speaks JSON, and Hiddify is a Flutter shell over hiddify-core,
/// which is sing-box — so one document serves both.
///
/// The tree is built as Foundation objects and handed to `JSONSerialization`
/// rather than assembled as text. Node names are airport-controlled and the
/// serialiser escapes them for us, which is the same reason `confName` and
/// `yaml()` exist for the other formats.
extension ConfigurationGenerator {
    struct SingBoxGroup {
        let tag: String
        let isAutomatic: Bool
        let members: [String]
    }

    func singBox(
        nodes: [ProxyNode],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup]
    ) -> String {
        let nodeTags = nodes.map { NodeRegionResolver.displayName(for: $0) }
        let regionGroupNames = regionGroups.map(\.name)

        var groups: [SingBoxGroup] = [
            .init(
                tag: RulePolicy.select.configurationName,
                isAutomatic: false,
                members: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            ),
            .init(tag: RulePolicy.auto.configurationName, isAutomatic: true, members: nodeTags),
            .init(
                tag: Self.manualGroupName,
                isAutomatic: false,
                members: nodeTags.isEmpty ? [Self.singBoxDirectTag] : nodeTags
            ),
            // The four aliases every policy group points at. Clash declares
            // them as hidden groups; sing-box has no hidden flag but still
            // needs them to exist, or it refuses to start on the dangling
            // reference that policyChoices hands out.
            .init(
                tag: Self.nestedSelectGroupName,
                isAutomatic: false,
                members: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            ),
            .init(tag: Self.nestedAutoGroupName, isAutomatic: true, members: nodeTags),
            .init(
                tag: Self.nestedManualGroupName,
                isAutomatic: false,
                members: nodeTags.isEmpty ? [Self.singBoxDirectTag] : nodeTags
            ),
            .init(tag: Self.directGroupName, isAutomatic: false, members: [Self.singBoxDirectTag])
        ]
        for policy in configurablePolicies(preset) where !Self.singBoxRejectingPolicies.contains(policy) {
            groups.append(.init(
                tag: policy.configurationName,
                isAutomatic: false,
                members: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: Self.singBoxRejectTag
                )
            ))
        }
        for group in regionGroups {
            groups.append(.init(
                tag: group.name,
                isAutomatic: false,
                members: [group.automaticName] + group.nodeNames
            ))
            groups.append(.init(tag: group.automaticName, isAutomatic: true, members: group.nodeNames))
        }

        var outbounds: [[String: Any]] = groups.map { group in
            var outbound: [String: Any] = [
                "tag": group.tag,
                "type": group.isAutomatic ? "urltest" : "selector",
                // A group with nothing in it still has to resolve somewhere, or
                // sing-box refuses to start on a dangling reference.
                "outbounds": group.members.isEmpty ? [Self.singBoxDirectTag] : group.members
            ]
            if group.isAutomatic {
                outbound["url"] = "https://www.gstatic.com/generate_204"
                outbound["interval"] = "300s"
                outbound["tolerance"] = 50
            }
            return outbound
        }
        outbounds += nodes.compactMap(singBoxOutbound)
        outbounds.append(["tag": Self.singBoxDirectTag, "type": "direct"])

        let configuration: [String: Any] = [
            "log": ["level": "warn", "timestamp": true],
            "dns": singBoxDNS(),
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true,
                "strict_route": true,
                "stack": "mixed"
            ]],
            "outbounds": outbounds,
            "route": [
                "rules": singBoxRules(preset: preset),
                "final": preset.finalPolicy.configurationName,
                "default_domain_resolver": "local",
                "auto_detect_interface": true
            ],
            "experimental": [
                "cache_file": ["enabled": true, "store_fakeip": false]
            ]
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text + "\n"
    }

    static let singBoxDirectTag = "DIRECT"
    static let singBoxRejectTag = "REJECT"

    /// Current sing-box DNS schema (1.12+). Keeping it in one place prevents
    /// imported rule schemes from falling back to the removed legacy
    /// `address: https://...` server representation.
    ///
    /// These servers use literal IP addresses, so the current typed DoH
    /// dialer can connect directly without a `detour`. Omitting it is also
    /// important for imported schemes: their selector tags are user-defined
    /// and must not be coupled to the built-in "node select" display name.
    private func singBoxDNS() -> [String: Any] {
        [
            "servers": [
                [
                    "type": "https",
                    "tag": "remote",
                    "server": "1.1.1.1",
                    "server_port": 443,
                    "path": "/dns-query",
                    "tls": ["enabled": true, "server_name": "cloudflare-dns.com"]
                ],
                [
                    "type": "https",
                    "tag": "local",
                    "server": "223.5.5.5",
                    "server_port": 443,
                    "path": "/dns-query",
                    "tls": ["enabled": true, "server_name": "dns.alidns.com"]
                ]
            ],
            "final": "local",
            "strategy": "prefer_ipv4"
        ]
    }

    /// Policies whose whole point is to drop traffic.
    ///
    /// The other clients express these as a group the user can flip between
    /// REJECT and DIRECT. sing-box cannot: from 1.11 rejection is a route
    /// action and there is no outbound for a selector to point at. So the
    /// rules carry `action: reject` directly and no group is emitted — which
    /// is what the group defaulted to anyway.
    static let singBoxRejectingPolicies: Set<RulePolicy> = [.reject, .foreignAds]

    /// Route rules, grouped by destination.
    ///
    /// sing-box takes arrays per rule, so every domain heading for the same
    /// policy collapses into one entry instead of one line each — an ACL4SSR
    /// snapshot is twenty thousand rules and the per-line form is unreadable
    /// and slow to parse.
    private func singBoxRules(preset: RulePreset) -> [[String: Any]] {
        var ordered: [String] = []
        var byPolicy: [String: [String: [String]]] = [:]

        for assignment in preset.assignments {
            let policyName = Self.singBoxRejectingPolicies.contains(assignment.policy)
                ? Self.singBoxRejectTag
                : assignment.policy.configurationName
            for rule in rules.lines(for: assignment) {
                let parts = rule.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count >= 2, let field = Self.singBoxRuleFields[parts[0].uppercased()] else {
                    continue
                }
                let value = parts[1]
                guard !value.isEmpty else { continue }
                if byPolicy[policyName] == nil {
                    byPolicy[policyName] = [:]
                    ordered.append(policyName)
                }
                byPolicy[policyName]?[field, default: []].append(value)
            }
        }

        var result: [[String: Any]] = []
        for policyName in ordered {
            guard let fields = byPolicy[policyName], !fields.isEmpty else { continue }
            var rule: [String: Any] = [:]
            for (field, values) in fields.sorted(by: { $0.key < $1.key }) {
                rule[field] = values.removingDuplicates()
            }
            // 1.11 deprecated the block outbound; rejection is a rule action now.
            if policyName == Self.singBoxRejectTag {
                rule["action"] = "reject"
            } else {
                rule["outbound"] = policyName
            }
            result.append(rule)
        }
        if preset.includeGeoIPCN {
            result.append(["ip_is_private": true, "outbound": Self.singBoxDirectTag])
        }
        return result
    }

    private static let singBoxRuleFields: [String: String] = [
        "DOMAIN": "domain",
        "DOMAIN-SUFFIX": "domain_suffix",
        "DOMAIN-KEYWORD": "domain_keyword",
        "IP-CIDR": "ip_cidr",
        "IP-CIDR6": "ip_cidr",
        "IP6-CIDR": "ip_cidr",
        "PROCESS-NAME": "process_name"
    ]
}

extension ConfigurationGenerator {
    /// One outbound object, shaped the way sing-box's own schema documents and
    /// Sub-Store's producer emits.
    func singBoxOutbound(_ node: ProxyNode) -> [String: Any]? {
        var outbound: [String: Any] = [
            "tag": NodeRegionResolver.displayName(for: node),
            "server": node.server,
            "server_port": node.port
        ]

        switch node.kind {
        case .shadowsocks:
            outbound["type"] = "shadowsocks"
            outbound["method"] = node.cipher ?? "aes-256-gcm"
            outbound["password"] = node.password ?? ""
            if node.plugin == "v2ray-plugin" {
                outbound["plugin"] = "v2ray-plugin"
                var options = ["mode=websocket"]
                if node.tls { options.append("tls") }
                if let host = node.hostHeader, !host.isEmpty { options.append("host=\(host)") }
                if let path = node.exportablePath { options.append("path=\(path)") }
                outbound["plugin_opts"] = options.joined(separator: ";")
            } else if let mode = simpleObfsMode(node) {
                outbound["plugin"] = "obfs-local"
                var options = ["obfs=\(mode)"]
                if let host = node.obfsParam, !host.isEmpty { options.append("obfs-host=\(host)") }
                outbound["plugin_opts"] = options.joined(separator: ";")
            }
        case .shadowsocksR:
            outbound["type"] = "shadowsocksr"
            outbound["method"] = node.cipher ?? "aes-256-cfb"
            outbound["password"] = node.password ?? ""
            outbound["protocol"] = node.protocolName ?? "origin"
            if let param = node.protocolParam { outbound["protocol_param"] = param }
            outbound["obfs"] = node.obfs ?? "plain"
            if let param = node.obfsParam { outbound["obfs_param"] = param }
        case .vmess:
            outbound["type"] = "vmess"
            outbound["uuid"] = node.exportableUUID ?? ""
            outbound["security"] = singBoxVMessSecurity(node)
            outbound["alter_id"] = 0
        case .vless:
            outbound["type"] = "vless"
            outbound["uuid"] = node.exportableUUID ?? ""
            if let flow = node.flow, !flow.isEmpty { outbound["flow"] = flow }
        case .trojan:
            outbound["type"] = "trojan"
            outbound["password"] = node.password ?? ""
        case .hysteria2:
            outbound["type"] = "hysteria2"
            outbound["password"] = node.password ?? ""
            if let obfs = hysteria2Obfs(node) {
                outbound["obfs"] = ["type": obfs.type, "password": obfs.password]
            }
        case .hysteria:
            outbound["type"] = "hysteria"
            outbound["auth_str"] = node.password ?? ""
            outbound["up_mbps"] = node.upMbps ?? 50
            outbound["down_mbps"] = node.downMbps ?? 100
            if let obfs = node.obfs, !obfs.isEmpty, obfs.lowercased() != "none" {
                outbound["obfs"] = obfs
            }
        case .tuic:
            outbound["type"] = "tuic"
            outbound["uuid"] = node.exportableUUID ?? ""
            outbound["password"] = node.password ?? ""
            if let value = node.congestionControl, !value.isEmpty {
                outbound["congestion_control"] = value
            }
            if let value = node.udpRelayMode, !value.isEmpty { outbound["udp_relay_mode"] = value }
        case .wireguard:
            outbound["type"] = "wireguard"
            var addresses: [String] = []
            if let value = node.wireGuardIPv4, !value.isEmpty { addresses.append(value) }
            if let value = node.wireGuardIPv6, !value.isEmpty { addresses.append(value) }
            outbound["address"] = addresses
            outbound["private_key"] = node.wireGuardPrivateKey ?? ""
            outbound["peer_public_key"] = node.wireGuardPublicKey ?? ""
            if let value = node.wireGuardPreSharedKey, !value.isEmpty { outbound["pre_shared_key"] = value }
            if let value = wireGuardReservedBytes(node), !value.isEmpty { outbound["reserved"] = value }
            if let value = node.wireGuardMTU { outbound["mtu"] = value }
        case .anytls:
            outbound["type"] = "anytls"
            outbound["password"] = node.password ?? ""
            if let value = node.idleSessionCheckInterval {
                outbound["idle_session_check_interval"] = "\(value)s"
            }
            if let value = node.idleSessionTimeout { outbound["idle_session_timeout"] = "\(value)s" }
            if let value = node.minIdleSession { outbound["min_idle_session"] = value }
        case .snell:
            outbound["type"] = "snell"
            outbound["psk"] = node.password ?? ""
            // writes(_:to:excluding:) already dropped anything below v4, which
            // is where sing-box's Snell support starts.
            outbound["version"] = node.version ?? 4
        case .socks5:
            outbound["type"] = "socks"
            outbound["version"] = "5"
            if let user = node.username, !user.isEmpty { outbound["username"] = user }
            if let password = node.password, !password.isEmpty { outbound["password"] = password }
        case .http:
            outbound["type"] = "http"
            if let user = node.username, !user.isEmpty { outbound["username"] = user }
            if let password = node.password, !password.isEmpty { outbound["password"] = password }
        case .unknown:
            return nil
        }

        if let tls = singBoxTLS(node) { outbound["tls"] = tls }
        if let transport = singBoxTransport(node) { outbound["transport"] = transport }
        return outbound
    }

    /// Trojan, Hysteria 2 and AnyTLS are TLS by definition, so they carry the
    /// block whether or not the node bothered to say `tls=1`.
    private func singBoxTLS(_ node: ProxyNode) -> [String: Any]? {
        // SIP003 plugin TLS belongs to the plugin itself. Emitting a second
        // outbound TLS block would turn a valid Shadowsocks + v2ray-plugin
        // node into a different (and invalid) protocol stack.
        guard node.kind != .shadowsocks else { return nil }
        let alwaysSecure: Set<ProxyKind> = [.trojan, .hysteria, .hysteria2, .tuic, .anytls]
        guard node.tls || alwaysSecure.contains(node.kind) else { return nil }

        var tls: [String: Any] = [
            "enabled": true,
            "server_name": node.sni ?? node.hostHeader ?? node.server,
            "insecure": node.skipCertificateVerification
        ]
        let alpn = ALPNList.values(node.alpn)
        if !alpn.isEmpty {
            tls["alpn"] = alpn
        }
        if node.usesReality {
            var reality: [String: Any] = ["enabled": true, "public_key": node.realityPublicKey ?? ""]
            if let shortID = node.realityShortID, !shortID.isEmpty { reality["short_id"] = shortID }
            tls["reality"] = reality
            // REALITY needs uTLS; sing-box rejects the pair otherwise.
            tls["utls"] = ["enabled": true, "fingerprint": node.fingerprint ?? "chrome"]
        }
        return tls
    }

    private func singBoxTransport(_ node: ProxyNode) -> [String: Any]? {
        guard let transport = node.transport, !transport.isEmpty, transport != "tcp" else { return nil }
        switch transport {
        case "ws":
            var websocket: [String: Any] = ["type": "ws"]
            if let path = node.exportablePath { websocket["path"] = path }
            if let host = node.hostHeader, !host.isEmpty { websocket["headers"] = ["Host": host] }
            return websocket
        case "grpc":
            var grpc: [String: Any] = ["type": "grpc"]
            if let service = node.path, !service.isEmpty {
                grpc["service_name"] = service.hasPrefix("/") ? String(service.dropFirst()) : service
            }
            return grpc
        case "h2", "http":
            var http: [String: Any] = ["type": "http"]
            if let path = node.exportablePath { http["path"] = path }
            if let host = node.hostHeader, !host.isEmpty { http["host"] = [host] }
            return http
        case "httpupgrade":
            var upgrade: [String: Any] = ["type": "httpupgrade"]
            if let path = node.exportablePath { upgrade["path"] = path }
            if let host = node.hostHeader, !host.isEmpty { upgrade["host"] = host }
            return upgrade
        default:
            return nil
        }
    }

    /// sing-box rejects `auto`; it wants a concrete cipher.
    private func singBoxVMessSecurity(_ node: ProxyNode) -> String {
        let accepted: Set<String> = [
            "auto", "none", "zero", "aes-128-gcm", "chacha20-poly1305", "aes-128-ctr"
        ]
        let cipher = node.cipher?.lowercased() ?? ""
        guard accepted.contains(cipher), cipher != "auto" else { return "auto" }
        return cipher
    }
}

extension ConfigurationGenerator {
    /// The imported-scheme path, reproducing the groups the source file
    /// declared instead of Tower's own policy layout — same contract as the
    /// other clients, expressed as sing-box selectors and urltests.
    func singBoxScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        let finalGroup = rulePlan.finalGroupName ?? groups.first?.name ?? Self.singBoxDirectTag
        var outbounds: [[String: Any]] = groups.map { group in
            var outbound: [String: Any] = [
                "tag": group.name,
                "type": group.kind == .urlTest ? "urltest" : "selector",
                "outbounds": group.members.isEmpty ? [Self.singBoxDirectTag] : group.members
            ]
            if group.kind == .urlTest {
                outbound["url"] = group.testURL
                outbound["interval"] = "\(group.interval)s"
                outbound["tolerance"] = group.tolerance
            }
            return outbound
        }
        outbounds += nodes.compactMap(singBoxOutbound)

        // A route-level `action: reject` is sufficient for direct blocking
        // rules, but selectors cannot reference an action. Imported schemes
        // commonly expose choices such as [REJECT, DIRECT], so provide the
        // concrete dependency only when the imported graph actually needs it.
        let needsRejectOutbound = groups.contains { group in
            group.members.contains { $0.uppercased() == Self.singBoxRejectTag }
        } || finalGroup.uppercased() == Self.singBoxRejectTag
        let alreadyDefinesReject = outbounds.contains {
            ($0["tag"] as? String)?.uppercased() == Self.singBoxRejectTag
        }
        if needsRejectOutbound && !alreadyDefinesReject {
            outbounds.append(["tag": Self.singBoxRejectTag, "type": "block"])
        }
        outbounds.append(["tag": Self.singBoxDirectTag, "type": "direct"])

        var rules: [[String: Any]] = []
        var pendingGroup: String?
        var pendingFields: [String: [String]] = [:]

        func rule(policyName: String, fields: [String: [String]]) -> [String: Any] {
            var rule: [String: Any] = [:]
            for (field, values) in fields.sorted(by: { $0.key < $1.key }) {
                rule[field] = values.removingDuplicates()
            }
            if policyName.uppercased() == "REJECT" {
                rule["action"] = "reject"
            } else {
                rule["outbound"] = policyName
            }
            return rule
        }

        func flushPending() {
            guard let group = pendingGroup, !pendingFields.isEmpty else { return }
            rules.append(rule(policyName: group, fields: pendingFields))
            pendingGroup = nil
            pendingFields = [:]
        }

        for entry in rulePlan.entries {
            switch entry {
            case .remote(let resource):
                flushPending()
                var remoteRule: [String: Any] = ["rule_set": [resource.identifier]]
                if resource.policyName.uppercased() == "REJECT" {
                    remoteRule["action"] = "reject"
                } else {
                    remoteRule["outbound"] = resource.policyName
                }
                rules.append(remoteRule)
            case .inline(let inline):
                let parts = inline.line.split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count >= 2,
                      let field = Self.singBoxRuleFields[parts[0].uppercased()],
                      !parts[1].isEmpty else { continue }
                if pendingGroup != inline.policyName {
                    flushPending()
                    pendingGroup = inline.policyName
                }
                pendingFields[field, default: []].append(parts[1])
            }
        }
        flushPending()

        let remoteRuleSets: [[String: Any]] = rulePlan.remoteResources.map {
            [
                "type": "remote",
                "tag": $0.identifier,
                "format": "source",
                "url": $0.url.absoluteString,
                "update_interval": "1d"
            ]
        }

        var route: [String: Any] = [
            "rules": rules,
            "final": finalGroup,
            "default_domain_resolver": "local",
            "auto_detect_interface": true
        ]
        if !remoteRuleSets.isEmpty { route["rule_set"] = remoteRuleSets }

        let configuration: [String: Any] = [
            "log": ["level": "warn", "timestamp": true],
            "dns": singBoxDNS(),
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true,
                "strict_route": true,
                "stack": "mixed"
            ]],
            "outbounds": outbounds,
            "route": route,
            "experimental": ["cache_file": ["enabled": true, "store_fakeip": false]]
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text + "\n"
    }
}

// MARK: - Egern

/// Egern's YAML nests by type: every proxy, policy group and rule is a
/// single-key mapping whose key names the kind, unlike Clash's flat `type:`.
///
///     proxies:
///       - shadowsocks:
///           name: HK 01
///     policy_groups:
///       - select:
///           name: 节点选择
///           policies: [...]
///     rules:
///       - domain_suffix:
///           match: google.com
///           policy: 节点选择
extension ConfigurationGenerator {
    static let egernDirect = "DIRECT"
    static let egernReject = "REJECT"

    func egern(
        nodes: [ProxyNode],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup]
    ) -> String {
        let nodeNames = nodes.map { NodeRegionResolver.displayName(for: $0) }
        let regionGroupNames = regionGroups.map(\.name)

        var output = header(target: .egern)
        output += "\nproxies:\n"
        output += nodes.isEmpty ? "  []\n" : nodes.compactMap(egernProxy).joined()

        output += "\npolicy_groups:\n"
        output += egernSelect(
            name: RulePolicy.select.configurationName,
            policies: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
        )
        output += egernAutoTest(name: RulePolicy.auto.configurationName, policies: nodeNames)
        output += egernSelect(
            name: Self.manualGroupName,
            policies: nodeNames.isEmpty ? [Self.egernDirect] : nodeNames
        )
        // The four aliases every policy group points at, declared here the way
        // the other formats declare them.
        output += egernSelect(
            name: Self.nestedSelectGroupName,
            policies: nestedPrimaryChoices(regionGroupNames: regionGroupNames)
        )
        output += egernAutoTest(name: Self.nestedAutoGroupName, policies: nodeNames)
        output += egernSelect(
            name: Self.nestedManualGroupName,
            policies: nodeNames.isEmpty ? [Self.egernDirect] : nodeNames
        )
        output += egernSelect(name: Self.directGroupName, policies: [Self.egernDirect])

        for policy in configurablePolicies(preset) {
            output += egernSelect(
                name: policy.configurationName,
                policies: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: Self.egernReject
                )
            )
        }
        for group in regionGroups {
            output += egernSelect(name: group.name, policies: [group.automaticName] + group.nodeNames)
            output += egernAutoTest(name: group.automaticName, policies: group.nodeNames)
        }

        output += "\nrules:\n"
        for assignment in preset.assignments {
            let policyName = assignment.policy == .reject
                ? Self.egernReject
                : assignment.policy.configurationName
            for rule in rules.lines(for: assignment) {
                if let line = egernRule(rule, policy: policyName) { output += line }
            }
        }
        if preset.includeGeoIPCN {
            output += "  - geoip:\n      match: CN\n      no_resolve: true\n      policy: \(Self.egernDirect)\n"
        }
        output += "  - default:\n      policy: \(yaml(preset.finalPolicy.configurationName))\n"
        return output
    }

    func egernScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        rulePlan: RuleSetEmissionPlanner.Plan
    ) -> String {
        var output = schemeHeader(scheme, target: .egern)
        output += "\nproxies:\n"
        output += nodes.isEmpty ? "  []\n" : nodes.compactMap(egernProxy).joined()

        output += "\npolicy_groups:\n"
        for group in groups {
            switch group.kind {
            case .select: output += egernSelect(name: group.name, policies: group.members)
            case .urlTest: output += egernAutoTest(name: group.name, policies: group.members)
            }
        }

        output += "\nrules:\n"
        let finalGroup = rulePlan.finalGroupName ?? groups.first?.name ?? Self.egernDirect
        for entry in rulePlan.entries {
            switch entry {
            case .remote(let resource):
                output += "  - rule_set:\n"
                output += "      match: \(yaml(resource.url.absoluteString))\n"
                output += "      policy: \(yaml(resource.policyName))\n"
                output += "      update_interval: 86400\n"
            case .inline(let rule):
                if let mapped = egernRule(rule.line, policy: rule.policyName) { output += mapped }
            }
        }
        output += "  - default:\n      policy: \(yaml(finalGroup))\n"
        return output
    }

    private func egernSelect(name: String, policies: [String]) -> String {
        var block = "  - select:\n      name: \(yaml(name))\n      policies:\n"
        for policy in (policies.isEmpty ? [Self.egernDirect] : policies) {
            block += "        - \(yaml(policy))\n"
        }
        return block
    }

    private func egernAutoTest(name: String, policies: [String]) -> String {
        var block = "  - auto_test:\n      name: \(yaml(name))\n      policies:\n"
        for policy in (policies.isEmpty ? [Self.egernDirect] : policies) {
            block += "        - \(yaml(policy))\n"
        }
        return block + "      interval: 600\n      tolerance: 100\n      timeout: 5\n"
    }

    /// One rule per entry: Egern's `match` takes a single value, so a rule list
    /// is one mapping each rather than an array per policy.
    private func egernRule(_ rule: String, policy: String) -> String? {
        let parts = rule.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 2,
              let matcher = Self.egernRuleMatchers[parts[0].uppercased()],
              !parts[1].isEmpty else { return nil }

        // Egern spells the flag as a neighbouring key rather than a trailing
        // field, which is why it used to be dropped here. GEOIP always skips
        // resolution, matching the built-in presets and the other six clients;
        // an IP rule keeps whatever the source file asked for.
        let isIPMatcher = matcher == "geoip" || matcher == "ip_cidr"
        let skipsResolution = isIPMatcher
            && (parts[0].uppercased() == "GEOIP"
                || parts.dropFirst().contains { $0.lowercased() == "no-resolve" })

        var line = "  - \(matcher):\n      match: \(yaml(parts[1]))\n"
        if skipsResolution { line += "      no_resolve: true\n" }
        return line + "      policy: \(yaml(policy))\n"
    }

    private static let egernRuleMatchers: [String: String] = [
        "DOMAIN": "domain",
        "DOMAIN-SUFFIX": "domain_suffix",
        "DOMAIN-KEYWORD": "domain_keyword",
        "IP-CIDR": "ip_cidr",
        "IP-CIDR6": "ip_cidr",
        "IP6-CIDR": "ip_cidr",
        "GEOIP": "geoip",
        "URL-REGEX": "url_regex",
        "DEST-PORT": "dest_port",
        "PROTOCOL": "protocol"
    ]

    /// One `- <type>:` entry with the snake_case keys Egern uses.
    func egernProxy(_ node: ProxyNode) -> String? {
        var body: [String] = ["      name: \(yaml(NodeRegionResolver.displayName(for: node)))"]
        func endpoint() {
            body.append("      server: \(yaml(node.server))")
            body.append("      port: \(node.port)")
        }

        let type: String
        switch node.kind {
        case .shadowsocks:
            type = "shadowsocks"
            // Egern spells this one without the `-ietf` infix.
            let cipher = node.cipher ?? "aes-256-gcm"
            body.append("      method: \(yaml(cipher == "chacha20-ietf-poly1305" ? "chacha20-poly1305" : cipher))")
            body.append("      password: \(yaml(node.password ?? ""))")
            endpoint()
            if let mode = simpleObfsMode(node) {
                body.append("      obfs: \(yaml(mode))")
                if let host = node.obfsParam, !host.isEmpty {
                    body.append("      obfs_host: \(yaml(host))")
                }
            }
        case .trojan, .anytls:
            type = node.kind == .trojan ? "trojan" : "anytls"
            endpoint()
            body.append("      password: \(yaml(node.password ?? ""))")
            if let sni = node.sni, !sni.isEmpty { body.append("      sni: \(yaml(sni))") }
        case .hysteria2:
            // Egern names this one `auth`, not `password`, and treats it as
            // required: "missing field `auth`" rejects the whole profile.
            type = "hysteria2"
            endpoint()
            body.append("      auth: \(yaml(node.password ?? ""))")
            if let sni = node.sni, !sni.isEmpty { body.append("      sni: \(yaml(sni))") }
        case .tuic:
            type = "tuic"
            endpoint()
            body.append("      uuid: \(yaml(node.exportableUUID ?? ""))")
            body.append("      password: \(yaml(node.password ?? ""))")
            if let sni = node.sni, !sni.isEmpty { body.append("      sni: \(yaml(sni))") }
            // Egern wants a list here even for the single value a URI carries.
            let alpn = ALPNList.values(node.alpn)
            body.append("      alpn: [\((alpn.isEmpty ? ["h3"] : alpn).map(yaml).joined(separator: ", "))]")
        case .wireguard:
            type = "wireguard"
            endpoint()
            body.append("      private_key: \(yaml(node.wireGuardPrivateKey ?? ""))")
            body.append("      peer_public_key: \(yaml(node.wireGuardPublicKey ?? ""))")
            if let value = node.wireGuardIPv4 { body.append("      local_ipv4: \(yaml(value))") }
            if let value = node.wireGuardIPv6 { body.append("      local_ipv6: \(yaml(value))") }
            if let value = node.wireGuardPreSharedKey, !value.isEmpty {
                body.append("      preshared_key: \(yaml(value))")
            }
            if let bytes = wireGuardReservedBytes(node), !bytes.isEmpty {
                body.append("      reserved: [\(bytes.map(String.init).joined(separator: ", "))]")
            }
            if !csv(node.wireGuardDNS).isEmpty { body.append("      dns_servers: \(yamlList(csv(node.wireGuardDNS)))") }
            if let value = node.wireGuardMTU { body.append("      mtu: \(value)") }
            if let value = node.wireGuardPersistentKeepalive { body.append("      keepalive: \(value)") }
        case .vmess:
            type = "vmess"
            endpoint()
            body.append("      user_id: \(yaml(node.exportableUUID ?? ""))")
            body.append("      security: \(yaml(egernVMessSecurity(node)))")
            body.append("      legacy: false")
        case .vless:
            type = "vless"
            endpoint()
            body.append("      user_id: \(yaml(node.exportableUUID ?? ""))")
        case .snell:
            type = "snell"
            endpoint()
            body.append("      psk: \(yaml(node.password ?? ""))")
            body.append("      version: \(node.version ?? 4)")
        case .socks5, .http:
            let secure = node.tls
            type = node.kind == .socks5 ? (secure ? "socks5_tls" : "socks5") : (secure ? "https" : "http")
            endpoint()
            if let user = node.username, !user.isEmpty { body.append("      username: \(yaml(user))") }
            if let password = node.password, !password.isEmpty {
                body.append("      password: \(yaml(password))")
            }
        case .hysteria, .shadowsocksR, .unknown:
            // supports(_:) filters these out; this keeps the switch total.
            return nil
        }

        body.append("      udp_relay: true")
        if node.usesReality {
            body.append("      reality:")
            body.append("        public_key: \(yaml(node.realityPublicKey ?? ""))")
            if let shortID = node.realityShortID, !shortID.isEmpty {
                body.append("        short_id: \(yaml(shortID))")
            }
        }
        if node.skipCertificateVerification, node.kind != .shadowsocks {
            body.append("      skip_tls_verify: true")
        }
        if let transport = egernTransport(node) { body.append(contentsOf: transport) }
        return "  - \(type):\n" + body.joined(separator: "\n") + "\n"
    }

    /// Websocket nests under `transport`, keyed `ws` or `wss` by whether the
    /// node negotiates TLS.
    private func egernTransport(_ node: ProxyNode) -> [String]? {
        guard let transport = node.transport, transport != "tcp" else { return nil }
        var lines = ["      transport:"]
        switch transport {
        case "ws":
            lines.append("        \(node.tls ? "wss" : "ws"):")
            if let path = node.exportablePath { lines.append("          path: \(yaml(path))") }
            if let host = node.hostHeader, !host.isEmpty {
                lines.append("          headers:")
                lines.append("            Host: \(yaml(host))")
            }
            if node.tls, let sni = node.sni, !sni.isEmpty { lines.append("          sni: \(yaml(sni))") }
        case "http":
            lines.append("        http1:")
            lines.append("          path: \(yaml(node.exportablePath ?? "/"))")
            if let host = node.hostHeader, !host.isEmpty {
                lines.append("          headers:")
                lines.append("            Host: \(yaml(host))")
            }
        case "h2":
            lines.append("        http2:")
            lines.append("          path: \(yaml(node.exportablePath ?? "/"))")
            if let host = node.hostHeader, !host.isEmpty {
                lines.append("          headers:")
                lines.append("            Host: \(yaml(host))")
            }
            if let sni = node.sni, !sni.isEmpty { lines.append("          sni: \(yaml(sni))") }
        case "grpc":
            lines.append("        grpc:")
            if let service = node.path, !service.isEmpty {
                lines.append("          service_name: \(yaml(service.hasPrefix("/") ? String(service.dropFirst()) : service))")
            }
            if let sni = node.sni, !sni.isEmpty { lines.append("          sni: \(yaml(sni))") }
        default:
            return nil
        }
        if node.skipCertificateVerification { lines.append("          skip_tls_verify: true") }
        return lines
    }

    private func egernVMessSecurity(_ node: ProxyNode) -> String {
        let cipher = node.cipher?.lowercased() ?? "auto"
        if cipher == "chacha20-ietf-poly1305" { return "chacha20-poly1305" }
        let accepted: Set<String> = ["auto", "none", "aes-128-gcm", "chacha20-poly1305"]
        return accepted.contains(cipher) ? cipher : "auto"
    }
}
