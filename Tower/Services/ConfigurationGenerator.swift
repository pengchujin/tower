import Foundation

struct ConfigurationGenerator {
    private static let manualGroupName = "手动切换"
    private static let nestedSelectGroupName = "🚀 节点选择"
    private static let nestedAutoGroupName = "♻️ 自动选择"
    private static let nestedManualGroupName = "🎛️ 手动切换"
    private static let directGroupName = "🎯 直接连接"
    private static let qureIconBaseURL = "https://fastly.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color"
    private static let miniIconBaseURL = "https://fastly.jsdelivr.net/gh/Orz-3/mini@master/Color"
    private static let regionDefinitions = [
        RegionDefinition(code: "HK", name: "🇭🇰 香港", iconFile: "Hong_Kong.png"),
        RegionDefinition(code: "JP", name: "🇯🇵 日本", iconFile: "Japan.png"),
        RegionDefinition(code: "US", name: "🇺🇸 美国", iconFile: "United_States.png"),
        RegionDefinition(code: "SG", name: "🇸🇬 新加坡", iconFile: "Singapore.png"),
        RegionDefinition(code: "TW", name: "🇹🇼 台湾", iconFile: "Taiwan.png"),
        RegionDefinition(code: "KR", name: "🇰🇷 韩国", iconFile: "Korea.png"),
        RegionDefinition(code: "GB", name: "🇬🇧 英国", iconFile: "United_Kingdom.png"),
        RegionDefinition(code: "DE", name: "🇩🇪 德国", iconFile: "Germany.png"),
        RegionDefinition(code: "FR", name: "🇫🇷 法国", iconFile: "France.png")
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
        excludedKinds: Set<ProxyKind> = []
    ) -> GeneratedConfiguration {
        let supported = uniquedNames(
            nodes.filter { writes($0, to: target, excluding: excludedKinds) },
            reservedNames: reservedProxyNames(for: preset)
        )
        let regionGroups = makeRegionGroups(nodes: supported, countryCodes: countryCodes)
        let content: String
        switch target {
        case .clash:
            content = clash(nodes: supported, preset: preset, regionGroups: regionGroups)
        case .surge:
            content = surgeLike(nodes: supported, preset: preset, regionGroups: regionGroups, shadowrocket: false)
        case .shadowrocket:
            content = surgeLike(nodes: supported, preset: preset, regionGroups: regionGroups, shadowrocket: true)
        case .loon:
            content = loon(nodes: supported, preset: preset, regionGroups: regionGroups)
        case .quanx:
            content = quanX(nodes: supported, preset: preset, regionGroups: regionGroups)
        }

        return GeneratedConfiguration(
            target: target,
            content: content,
            supportedNodeCount: supported.count,
            skippedNodeCount: nodes.count - supported.count,
            ruleCount: rules.count(for: preset)
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
        excludedKinds: Set<ProxyKind> = []
    ) -> GeneratedConfiguration {
        let supported = uniquedNames(
            nodes.filter { writes($0, to: target, excluding: excludedKinds) },
            reservedNames: Set(scheme.groups.map(\.name) + ["DIRECT", "REJECT", "direct", "reject"])
        )
        let resolved = resolveGroups(scheme: scheme, nodes: supported, target: target)
        let content: String
        switch target {
        case .clash:
            content = clashScheme(scheme, groups: resolved, nodes: supported, schemes: schemes)
        case .surge, .shadowrocket:
            content = surgeLikeScheme(scheme, groups: resolved, nodes: supported, target: target, schemes: schemes)
        case .loon:
            content = loonScheme(scheme, groups: resolved, nodes: supported, schemes: schemes)
        case .quanx:
            content = quanXScheme(scheme, groups: resolved, nodes: supported, schemes: schemes)
        }

        return GeneratedConfiguration(
            target: target,
            content: content,
            supportedNodeCount: supported.count,
            skippedNodeCount: nodes.count - supported.count,
            ruleCount: ruleCount(for: scheme, schemes: schemes)
        )
    }

    /// A node reaches the configuration when the client can express it and the
    /// user has not excluded that protocol. Excluded nodes stay in the input so
    /// they are reported as skipped rather than vanishing from the counts.
    private func writes(
        _ node: ProxyNode,
        to target: ClientTarget,
        excluding excludedKinds: Set<ProxyKind>
    ) -> Bool {
        guard target.supports(node.kind), !excludedKinds.contains(node.kind) else { return false }
        // Clash and Stash implement Snell only up to version 3, so a v4+ node
        // is skipped there rather than written as a proxy they would reject.
        if node.kind == .snell, target == .clash, (node.version ?? 4) >= 4 { return false }
        return true
    }

    private struct ResolvedSchemeGroup {
        let name: String
        let kind: RuleSchemeGroup.Kind
        /// Group references and node names, in the order the source declared.
        let members: [String]
        /// Only the node names, needed for the Quantumult X tag regex.
        let nodeNames: [String]
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

    /// Emits every ruleset in declaration order. `FINAL` is special: it is the
    /// catch-all each format spells differently and must come last.
    private func schemeRules(
        _ scheme: RuleScheme,
        target: ClientTarget,
        schemes: RuleSchemeRepository,
        indent: String = ""
    ) -> String {
        var output = ""
        var finalGroup: String?

        for ruleset in scheme.rulesets {
            if case .inline(let rule) = ruleset.resource, rule.uppercased() == "FINAL" {
                finalGroup = ruleset.groupName
                continue
            }
            for line in schemes.lines(for: ruleset.resource) {
                if let mapped = mappedRule(line, policyName: ruleset.groupName, target: target) {
                    output += "\(indent)\(mapped)\n"
                }
            }
        }

        guard let finalGroup else { return output }
        switch target {
        case .clash: output += "\(indent)MATCH,\(finalGroup)\n"
        case .quanx: output += "\(indent)final, \(finalGroup)\n"
        default: output += "\(indent)FINAL,\(finalGroup)\n"
        }
        return output
    }

    private func schemeHeader(_ scheme: RuleScheme, target: ClientTarget) -> String {
        let origin = scheme.sourceURLString ?? (scheme.isBundled ? "随 App 打包的快照" : "导入")
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
        schemes: RuleSchemeRepository
    ) -> String {
        var output = schemeHeader(scheme, target: .clash)
        output += """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: warning
        ipv6: true

        proxies:
        """
        output += "\n"
        output += nodes.isEmpty ? "  []\n" : nodes.map(clashNode).joined(separator: "\n") + "\n"
        output += "\nproxy-groups:\n"
        for group in groups {
            switch group.kind {
            case .select:
                output += clashSelectGroup(name: group.name, nodeNames: group.members, iconURL: "")
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
        output += "\nrules:\n"
        output += schemeRules(scheme, target: .clash, schemes: schemes, indent: "  - ")
        return output
    }

    private func surgeLikeScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        target: ClientTarget,
        schemes: RuleSchemeRepository
    ) -> String {
        var output = schemeHeader(scheme, target: target)
        output += """
        [General]
        loglevel = notify
        ipv6 = true
        dns-server = system, 223.5.5.5, 1.1.1.1
        skip-proxy = 127.0.0.1, localhost, *.local
        test-timeout = 5

        [Proxy]
        """
        output += "\n"
        for node in nodes {
            output += surgeNode(node, shadowrocket: target == .shadowrocket) + "\n"
        }
        output += "\n[Proxy Group]\n"
        for group in groups {
            switch group.kind {
            case .select:
                output += surgeSelect(name: group.name, values: group.members, iconURL: "")
            case .urlTest:
                let members = group.members.map(confName).joined(separator: ", ")
                output += "\(confName(group.name)) = url-test, \(members), url=\(group.testURL)"
                output += ", interval=\(group.interval), tolerance=\(group.tolerance)\n"
            }
        }
        output += "\n[Rule]\n"
        output += schemeRules(scheme, target: target, schemes: schemes)
        return output
    }

    private func loonScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        schemes: RuleSchemeRepository
    ) -> String {
        var output = schemeHeader(scheme, target: .loon)
        output += """
        [General]
        ipv6 = true
        dns-server = system, 223.5.5.5, 1.1.1.1

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
        output += schemeRules(scheme, target: .loon, schemes: schemes)
        return output
    }

    private func quanXScheme(
        _ scheme: RuleScheme,
        groups: [ResolvedSchemeGroup],
        nodes: [ProxyNode],
        schemes: RuleSchemeRepository
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

        [server_local]
        """
        output += "\n"
        for node in nodes { output += quanXNode(node) + "\n" }
        output += "\n[policy]\n"
        for group in groups {
            switch group.kind {
            case .select:
                let members = group.members.map(confName).joined(separator: ", ")
                output += "static=\(confName(group.name)), \(members)\n"
            case .urlTest:
                // Latency policies select nodes by tag regex, never by listing
                // tags the way `static` does.
                output += "url-latency-benchmark=\(confName(group.name))"
                output += ", server-tag-regex=\(quanXServerTagRegex(group.nodeNames))"
                output += ", check-interval=\(group.interval), alive-checking=false"
                output += ", tolerance=\(group.tolerance)\n"
            }
        }
        output += "\n[filter_local]\n"
        output += schemeRules(scheme, target: .quanx, schemes: schemes)
        output += quanXTrailingSections()
        return output
    }

    // MARK: - Built-in presets

    private func clash(
        nodes: [ProxyNode],
        preset: RulePreset,
        regionGroups: [RegionStrategyGroup]
    ) -> String {
        let nodeNames = nodes.map { NodeRegionResolver.displayName(for: $0) }
        let regionGroupNames = regionGroups.map(\.name)
        var output = header(target: .clash)
        output += """
        mixed-port: 7890
        allow-lan: false
        mode: rule
        log-level: warning
        ipv6: true

        proxies:
        """
        output += "\n"
        output += nodes.isEmpty ? "  []\n" : nodes.map(clashNode).joined(separator: "\n") + "\n"
        output += "\nproxy-groups:\n"
        output += clashSelectGroup(
            name: RulePolicy.select.configurationName,
            nodeNames: nestedPrimaryChoices(regionGroupNames: regionGroupNames),
            iconURL: iconURL(for: .select)
        )
        output += clashSelectGroup(
            name: Self.manualGroupName,
            nodeNames: nodeNames.isEmpty ? ["DIRECT"] : nodeNames,
            iconURL: qureIconURL("Static.png")
        )
        output += clashURLTestGroup(
            name: RulePolicy.auto.configurationName,
            nodeNames: nodeNames,
            iconURL: iconURL(for: .auto)
        )
        output += clashSelectGroup(
            name: Self.nestedSelectGroupName,
            nodeNames: nestedPrimaryChoices(regionGroupNames: regionGroupNames),
            iconURL: iconURL(for: .select),
            hidden: true
        )
        output += clashSelectGroup(
            name: Self.nestedManualGroupName,
            nodeNames: nodeNames.isEmpty ? [Self.directGroupName] : nodeNames,
            iconURL: qureIconURL("Static.png"),
            hidden: true
        )
        output += clashURLTestGroup(
            name: Self.nestedAutoGroupName,
            nodeNames: nodeNames,
            iconURL: iconURL(for: .auto),
            hidden: true
        )
        output += clashSelectGroup(
            name: Self.directGroupName,
            nodeNames: ["DIRECT"],
            iconURL: iconURL(for: .direct),
            hidden: true
        )
        for policy in configurablePolicies(preset) {
            output += clashSelectGroup(
                name: policy.configurationName,
                nodeNames: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: "REJECT"
                ),
                iconURL: iconURL(for: policy)
            )
        }
        for group in regionGroups {
            output += clashSelectGroup(
                name: group.name,
                nodeNames: [group.automaticName] + group.nodeNames,
                iconURL: ""
            )
            output += clashURLTestGroup(
                name: group.automaticName,
                nodeNames: group.nodeNames,
                iconURL: "",
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
            if let mode = simpleObfsMode(node) {
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
                "    uuid: \(yaml(node.uuid ?? ""))",
                "    alterId: \(node.alterID ?? 0)",
                "    cipher: \(yaml(node.cipher ?? "auto"))",
                "    udp: true"
            ]
            appendClashTransport(node, to: &values)
        case .vless:
            values += ["    uuid: \(yaml(node.uuid ?? ""))", "    udp: true"]
            appendClashTransport(node, to: &values)
        case .trojan:
            values += ["    password: \(yaml(node.password ?? ""))", "    udp: true"]
            appendClashTransport(node, to: &values)
        case .hysteria2:
            values += ["    password: \(yaml(node.password ?? ""))", "    skip-cert-verify: \(node.skipCertificateVerification)"]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
        case .anytls:
            values += [
                "    password: \(yaml(node.password ?? ""))",
                "    skip-cert-verify: \(node.skipCertificateVerification)",
                "    udp: true"
            ]
            if let sni = node.sni, !sni.isEmpty { values.append("    sni: \(yaml(sni))") }
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

    private func appendClashTransport(_ node: ProxyNode, to values: inout [String]) {
        values.append("    tls: \(node.tls)")
        values.append("    skip-cert-verify: \(node.skipCertificateVerification)")
        if let sni = node.sni, !sni.isEmpty { values.append("    servername: \(yaml(sni))") }
        if let transport = node.transport, !transport.isEmpty, transport != "tcp" {
            values.append("    network: \(yaml(transport))")
            if transport == "ws" {
                values.append("    ws-opts:")
                values.append("      path: \(yaml(node.path ?? "/"))")
                if let host = node.hostHeader, !host.isEmpty {
                    values.append("      headers:")
                    values.append("        Host: \(yaml(host))")
                }
            }
        }
    }

    private func clashSelectGroup(
        name: String,
        nodeNames: [String],
        iconURL: String,
        hidden: Bool = false
    ) -> String {
        var output = "  - name: \(yaml(name))\n    type: select\n    proxies:\n"
        for name in nodeNames.removingDuplicates() {
            output += "      - \(yaml(name))\n"
        }
        if !iconURL.isEmpty { output += "    icon: \(yaml(iconURL))\n" }
        if hidden { output += "    hidden: true\n" }
        return output
    }

    private func clashURLTestGroup(
        name: String,
        nodeNames: [String],
        iconURL: String,
        hidden: Bool = false
    ) -> String {
        guard !nodeNames.isEmpty else {
            return clashSelectGroup(name: name, nodeNames: ["DIRECT"], iconURL: iconURL)
        }
        var output = "  - name: \(yaml(name))\n"
        output += "    type: url-test\n"
        output += "    url: http://www.gstatic.com/generate_204\n"
        output += "    interval: 300\n"
        output += "    tolerance: 50\n"
        output += "    proxies:\n"
        for name in nodeNames { output += "      - \(yaml(name))\n" }
        if !iconURL.isEmpty { output += "    icon: \(yaml(iconURL))\n" }
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
        dns-server = system, 223.5.5.5, 1.1.1.1
        skip-proxy = 127.0.0.1, localhost, *.local
        test-timeout = 5

        [Proxy]
        """
        output += "\n"
        for node in nodes {
            output += surgeNode(node, shadowrocket: shadowrocket) + "\n"
        }
        output += "\n[Proxy Group]\n"
        output += surgeSelect(
            name: RulePolicy.select.configurationName,
            values: nestedPrimaryChoices(regionGroupNames: regionGroupNames),
            iconURL: iconURL(for: .select)
        )
        output += surgeSelect(
            name: Self.manualGroupName,
            values: names.isEmpty ? ["DIRECT"] : names,
            iconURL: qureIconURL("Static.png")
        )
        output += surgeURLTest(
            name: RulePolicy.auto.configurationName,
            names: names,
            iconURL: iconURL(for: .auto)
        )
        output += surgeSelect(
            name: Self.nestedSelectGroupName,
            values: nestedPrimaryChoices(regionGroupNames: regionGroupNames),
            iconURL: iconURL(for: .select),
            hidden: true
        )
        output += surgeSelect(
            name: Self.nestedManualGroupName,
            values: names.isEmpty ? [Self.directGroupName] : names,
            iconURL: qureIconURL("Static.png"),
            hidden: true
        )
        output += surgeURLTest(
            name: Self.nestedAutoGroupName,
            names: names,
            iconURL: iconURL(for: .auto),
            hidden: true
        )
        output += surgeSelect(
            name: Self.directGroupName,
            values: ["DIRECT"],
            iconURL: iconURL(for: .direct),
            hidden: true
        )
        for policy in configurablePolicies(preset) {
            output += surgeSelect(
                name: policy.configurationName,
                values: policyChoices(
                    policy,
                    regionGroupNames: regionGroupNames,
                    reject: "REJECT"
                ),
                iconURL: iconURL(for: policy)
            )
        }
        for group in regionGroups {
            output += surgeSelect(
                name: group.name,
                values: [group.automaticName] + group.nodeNames,
                iconURL: ""
            )
            output += surgeURLTest(
                name: group.automaticName,
                names: group.nodeNames,
                iconURL: "",
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
            if let mode = simpleObfsMode(node) {
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
                "username=\(node.uuid ?? "")",
                "vmess-aead=\((node.alterID ?? 0) == 0)"
            ]
            if let cipher = node.cipher,
               ["aes-128-gcm", "chacha20-ietf-poly1305"].contains(cipher.lowercased()) {
                components.append("encrypt-method=\(cipher)")
            }
            appendSurgeTransport(node, includeTLSFlag: true, to: &components)
        case .vless:
            components = ["vless", node.server, "\(node.port)", "username=\(node.uuid ?? "")"]
            appendSurgeTransport(node, includeTLSFlag: true, to: &components)
        case .trojan:
            components = ["trojan", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
            appendSurgeTransport(node, includeTLSFlag: false, to: &components)
        case .hysteria2:
            components = ["hysteria2", node.server, "\(node.port)", "password=\(confValue(node.password ?? ""))"]
            appendSurgeTLS(node, includeTLSFlag: false, to: &components)
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

    private func appendSurgeTransport(
        _ node: ProxyNode,
        includeTLSFlag: Bool,
        to values: inout [String]
    ) {
        appendSurgeTLS(node, includeTLSFlag: includeTLSFlag, to: &values)
        if node.transport == "ws" {
            values.append("ws=true")
            appendValue(node.path ?? "/", key: "ws-path", to: &values)
            if let host = node.hostHeader, !host.isEmpty { values.append("ws-headers=Host:\(confValue(host))") }
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
        iconURL: String,
        hidden: Bool = false
    ) -> String {
        let iconParameter = iconURL.isEmpty ? "" : ", icon-url=\(iconURL)"
        let hiddenParameter = hidden ? ", hidden=true" : ""
        return "\(confName(name)) = select, \(values.removingDuplicates().map(confName).joined(separator: ", "))\(iconParameter)\(hiddenParameter)\n"
    }

    private func surgeURLTest(
        name: String,
        names: [String],
        iconURL: String,
        hidden: Bool = false
    ) -> String {
        guard !names.isEmpty else { return surgeSelect(name: name, values: ["DIRECT"], iconURL: iconURL) }
        let iconParameter = iconURL.isEmpty ? "" : ", icon-url=\(iconURL)"
        let hiddenParameter = hidden ? ", hidden=true" : ""
        return "\(confName(name)) = url-test, \(names.map(confName).joined(separator: ", ")), url=http://www.gstatic.com/generate_204, interval=300, tolerance=50\(iconParameter)\(hiddenParameter)\n"
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
        dns-server = system, 223.5.5.5, 1.1.1.1

        [Proxy]
        """
        output += "\n"
        for node in nodes { output += loonNode(node) + "\n" }
        output += "\n[Proxy Group]\n"
        let selectNames = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(RulePolicy.select.configurationName)) = select,\(selectNames),img-url=\(iconURL(for: .select))\n"
        let manualNames = (names.isEmpty ? ["DIRECT"] : names).map(confName).joined(separator: ",")
        output += "\(confName(Self.manualGroupName)) = select,\(manualNames),img-url=\(qureIconURL("Static.png"))\n"
        if names.isEmpty {
            output += "\(confName(RulePolicy.auto.configurationName)) = select,DIRECT,img-url=\(iconURL(for: .auto))\n"
        } else {
            output += "\(confName(RulePolicy.auto.configurationName)) = url-test,\(names.map(confName).joined(separator: ",")),url=http://www.gstatic.com/generate_204,interval=300,tolerance=50,img-url=\(iconURL(for: .auto))\n"
        }
        let nestedSelectNames = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(Self.nestedSelectGroupName)) = select,\(nestedSelectNames),img-url=\(iconURL(for: .select)),hidden=true\n"
        let nestedManualNames = (names.isEmpty ? [Self.directGroupName] : names)
            .map(confName)
            .joined(separator: ",")
        output += "\(confName(Self.nestedManualGroupName)) = select,\(nestedManualNames),img-url=\(qureIconURL("Static.png")),hidden=true\n"
        if names.isEmpty {
            output += "\(confName(Self.nestedAutoGroupName)) = select,\(confName(Self.directGroupName)),img-url=\(iconURL(for: .auto)),hidden=true\n"
        } else {
            output += "\(confName(Self.nestedAutoGroupName)) = url-test,\(names.map(confName).joined(separator: ",")),url=http://www.gstatic.com/generate_204,interval=300,tolerance=50,img-url=\(iconURL(for: .auto)),hidden=true\n"
        }
        output += "\(confName(Self.directGroupName)) = select,DIRECT,img-url=\(iconURL(for: .direct)),hidden=true\n"
        for policy in configurablePolicies(preset) {
            let choices = policyChoices(
                policy,
                regionGroupNames: regionGroupNames,
                reject: "REJECT"
            )
                .map(confName)
                .joined(separator: ",")
            output += "\(confName(policy.configurationName)) = select,\(choices),img-url=\(iconURL(for: policy))\n"
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
        if preset.includeGeoIPCN { output += "GEOIP,CN,DIRECT\n" }
        output += "FINAL,\(surgePolicyName(preset.finalPolicy))\n"
        return output
    }

    private func loonNode(_ node: ProxyNode) -> String {
        let name = confName(NodeRegionResolver.displayName(for: node))
        var values: [String]
        switch node.kind {
        case .shadowsocks:
            values = ["Shadowsocks", node.server, "\(node.port)", node.cipher ?? "aes-256-gcm", confValue(node.password ?? "")]
            if let mode = simpleObfsMode(node) {
                // Loon names the simple-obfs mode obfs-name; plain "obfs" is
                // the ShadowsocksR field and means something else there.
                values.append("obfs-name=\(mode)")
                appendValue(node.obfsParam, key: "obfs-host", to: &values)
            }
            values.append("udp=true")
        case .shadowsocksR:
            values = ["ShadowsocksR", node.server, "\(node.port)", node.cipher ?? "aes-256-cfb", confValue(node.password ?? ""), "protocol=\(node.protocolName ?? "origin")", "obfs=\(node.obfs ?? "plain")"]
            appendValue(node.protocolParam, key: "protocol-param", to: &values)
            appendValue(node.obfsParam, key: "obfs-param", to: &values)
            values.append("udp=true")
        case .vmess:
            values = [
                "vmess",
                node.server,
                "\(node.port)",
                node.cipher ?? "auto",
                confValue(node.uuid ?? ""),
                "transport=\(node.transport ?? "tcp")",
                "alterId=\(node.alterID ?? 0)"
            ]
            appendLoonTransportAndTLS(node, to: &values)
        case .vless:
            values = [
                "VLESS",
                node.server,
                "\(node.port)",
                confValue(node.uuid ?? ""),
                "transport=\(node.transport ?? "tcp")"
            ]
            appendLoonTransportAndTLS(node, to: &values)
        case .trojan:
            values = ["trojan", node.server, "\(node.port)", confValue(node.password ?? "")]
            appendValue(node.transport, key: "transport", to: &values)
            appendValue(node.path, key: "path", to: &values)
            appendValue(node.hostHeader, key: "host", to: &values)
            appendValue(node.alpn, key: "alpn", to: &values)
            if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            appendValue(node.sni, key: "tls-name", to: &values)
            values.append("udp=true")
        case .hysteria2:
            values = ["Hysteria2", node.server, "\(node.port)", confValue(node.password ?? "")]
            if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
            appendValue(node.sni, key: "tls-name", to: &values)
            values += ["udp=true", "fast-open=true"]
        case .anytls:
            values = ["anytls", node.server, "\(node.port)", "\"\(confValue(node.password ?? ""))\""]
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
        case .snell, .unknown:
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
        return [confValue(username), confValue(password)]
    }

    private func appendLoonTransportAndTLS(_ node: ProxyNode, to values: inout [String]) {
        appendValue(node.path, key: "path", to: &values)
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

        [server_local]
        """
        output += "\n"
        for node in nodes { output += quanXNode(node) + "\n" }
        output += "\n[policy]\n"
        let selectValues = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ", ")
        output += "static=\(RulePolicy.select.configurationName), \(selectValues), img-url=\(iconURL(for: .select))\n"
        let manualValues = (names.isEmpty ? ["direct"] : names).map(confName).joined(separator: ", ")
        output += "static=\(Self.manualGroupName), \(manualValues), img-url=\(qureIconURL("Static.png"))\n"
        if names.isEmpty {
            output += "static=\(RulePolicy.auto.configurationName), direct, img-url=\(iconURL(for: .auto))\n"
        } else {
            output += "url-latency-benchmark=\(RulePolicy.auto.configurationName), server-tag-regex=\(quanXServerTagRegex(names)), check-interval=300, alive-checking=false, tolerance=50, img-url=\(iconURL(for: .auto))\n"
        }
        let nestedSelectValues = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confName)
            .joined(separator: ", ")
        output += "static=\(Self.nestedSelectGroupName), \(nestedSelectValues), img-url=\(iconURL(for: .select))\n"
        let nestedManualValues = (names.isEmpty ? [Self.directGroupName] : names)
            .map(confName)
            .joined(separator: ", ")
        output += "static=\(Self.nestedManualGroupName), \(nestedManualValues), img-url=\(qureIconURL("Static.png"))\n"
        if names.isEmpty {
            output += "static=\(Self.nestedAutoGroupName), \(Self.directGroupName), img-url=\(iconURL(for: .auto))\n"
        } else {
            output += "url-latency-benchmark=\(Self.nestedAutoGroupName), server-tag-regex=\(quanXServerTagRegex(names)), check-interval=300, alive-checking=false, tolerance=50, img-url=\(iconURL(for: .auto))\n"
        }
        output += "static=\(Self.directGroupName), direct, img-url=\(iconURL(for: .direct))\n"
        for policy in configurablePolicies(preset) {
            let choices = policyChoices(
                policy,
                regionGroupNames: regionGroupNames,
                reject: "reject"
            )
                .map(confName)
                .joined(separator: ", ")
            output += "static=\(policy.configurationName), \(choices), img-url=\(iconURL(for: policy))\n"
        }
        for group in regionGroups {
            output += "static=\(group.name), \(([group.automaticName] + group.nodeNames).map(confName).joined(separator: ", "))\n"
            output += "url-latency-benchmark=\(group.automaticName), server-tag-regex=\(quanXServerTagRegex(group.nodeNames)), check-interval=300, alive-checking=false, tolerance=50\n"
        }
        output += "\n[filter_local]\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: .quanx) { output += mapped + "\n" }
            }
        }
        if preset.includeGeoIPCN { output += "geoip, cn, direct\n" }
        output += "final, \(quanXPolicyName(preset.finalPolicy))\n"
        output += quanXTrailingSections()
        return output
    }

    private func quanXNode(_ node: ProxyNode) -> String {
        var values = [node.endpoint]
        let prefix: String
        switch node.kind {
        case .shadowsocks:
            prefix = "shadowsocks"
            values += ["method=\(node.cipher ?? "aes-256-gcm")", "password=\(confValue(node.password ?? ""))", "udp-relay=true"]
            if let mode = simpleObfsMode(node) {
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
            values += ["method=\(quanXVMessMethod(node))", "password=\(confValue(node.uuid ?? ""))"]
            appendQuanXTransport(node, to: &values)
        case .vless:
            prefix = "vless"
            values += ["method=none", "password=\(confValue(node.uuid ?? ""))"]
            appendQuanXTransport(node, to: &values)
        case .trojan:
            prefix = "trojan"
            values += ["password=\(confValue(node.password ?? ""))", "over-tls=true"]
            appendValue(node.sni, key: "tls-host", to: &values)
            appendQuanXCertificatePolicy(node, to: &values)
        case .hysteria2:
            prefix = "hysteria2"
            values += ["password=\(confValue(node.password ?? ""))", "over-tls=true"]
            appendValue(node.sni, key: "tls-host", to: &values)
            appendQuanXCertificatePolicy(node, to: &values)
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
        // Quantumult X implements neither, and writes(_:to:excluding:)
        // filters them out before generation, so this is defensive only.
        case .snell, .unknown:
            prefix = "http"
        }
        values.append("tag=\(confName(NodeRegionResolver.displayName(for: node)))")
        return "\(prefix)=\(values.joined(separator: ", "))"
    }

    private func appendQuanXTransport(_ node: ProxyNode, to values: inout [String]) {
        if node.transport == "ws" {
            values.append("obfs=\(node.tls ? "wss" : "ws")")
            appendValue(node.hostHeader ?? node.sni, key: "obfs-host", to: &values)
            appendValue(node.path ?? "/", key: "obfs-uri", to: &values)
        } else if node.tls {
            values.append("obfs=over-tls")
            appendValue(node.sni, key: "obfs-host", to: &values)
        }
        appendQuanXCertificatePolicy(node, to: &values)
    }

    // Trojan and Hysteria 2 always negotiate TLS in Quantumult X, so they need
    // the same certificate escape hatch that the obfs-based protocols get.
    private func appendQuanXCertificatePolicy(_ node: ProxyNode, to values: inout [String]) {
        if node.skipCertificateVerification { values.append("tls-verification=false") }
    }

    // Quantumult X names the VMess cipher with the same method key it uses for
    // Shadowsocks. "auto" is not one of its accepted values, so it is mapped to
    // the AEAD cipher that its VMess implementation negotiates by default.
    /// Quantumult X validates a complete configuration against its full module
    /// list on import and refuses the file when one is missing — it reported
    /// `配置文件缺少模块 [server_remote]`. Tower has nothing to put in the remote
    /// and rewrite modules, so they are emitted empty rather than omitted.
    private func quanXTrailingSections() -> String {
        let empty = [
            "server_remote",
            "filter_remote",
            "rewrite_local",
            "rewrite_remote",
            "task_local",
            "http_backend",
            "mitm"
        ]
        return empty.map { "\n[\($0)]\n" }.joined()
    }

    /// The simple-obfs mode of a Shadowsocks node, or nil when it carries no
    /// plugin. `obfs`/`obfsParam` hold the ShadowsocksR obfuscation for SSR
    /// nodes, so this is scoped to plain Shadowsocks, where the same fields
    /// carry the SIP003 plugin's mode and host.
    private func simpleObfsMode(_ node: ProxyNode) -> String? {
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
        case .clash: policyName = clashPolicyName(policy)
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

        if target == .quanx {
            let mappedType: String
            switch parts[0].uppercased() {
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
        } else if !Self.surgeFamilyRuleTypes.contains(parts[0].uppercased()) {
            // A future rule snapshot may introduce a type these clients cannot
            // parse. Dropping it keeps the rest of the configuration loadable
            // instead of shipping a line that fails at import time.
            return nil
        }

        if parts.last?.lowercased() == "no-resolve" {
            parts.insert(policyName, at: parts.count - 1)
        } else {
            parts.append(policyName)
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
                nodeNames: names.removingDuplicates(),
                iconURL: qureIconURL(definition.iconFile)
            )
        }
        if !otherNodeNames.isEmpty {
            groups.append(
                RegionStrategyGroup(
                    name: Self.otherRegionsName,
                    nodeNames: otherNodeNames.removingDuplicates(),
                    iconURL: qureIconURL("World_Map.png")
                )
            )
        }
        return groups
    }

    private func iconURL(for policy: RulePolicy) -> String {
        switch policy {
        case .direct:
            qureIconURL("Direct.png")
        case .reject:
            qureIconURL("Reject.png")
        case .select:
            qureIconURL("Proxy.png")
        case .auto:
            qureIconURL("Auto.png")
        case .international:
            qureIconURL("Global.png")
        case .domestic:
            qureIconURL("Domestic.png")
        case .foreignAds:
            qureIconURL("Advertising.png")
        case .ai:
            "\(Self.miniIconBaseURL)/OpenAI.png"
        case .youtube:
            qureIconURL("YouTube.png")
        case .media:
            qureIconURL("Streaming.png")
        case .telegram:
            qureIconURL("Telegram.png")
        case .googleFCM:
            qureIconURL("Gmail.png")
        case .apple:
            qureIconURL("Apple.png")
        case .microsoft:
            qureIconURL("Microsoft.png")
        case .google:
            qureIconURL("Google.png")
        }
    }

    private func qureIconURL(_ file: String) -> String {
        "\(Self.qureIconBaseURL)/\(file)"
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
        # Rules: ClashConnectRules/Self-Configuration, revision \(RuleRepository.sourceRevision)
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
    let iconFile: String
}

private struct RegionStrategyGroup {
    let name: String
    let nodeNames: [String]
    let iconURL: String

    var automaticName: String { "\(name) · 延迟优选" }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
