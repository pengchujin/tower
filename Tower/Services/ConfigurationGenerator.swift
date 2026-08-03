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

    private let rules: RuleRepository

    init(rules: RuleRepository = RuleRepository()) {
        self.rules = rules
    }

    func generate(
        nodes: [ProxyNode],
        preset: RulePreset,
        target: ClientTarget,
        countryCodes: [UUID: String] = [:]
    ) -> GeneratedConfiguration {
        let supported = uniquedNames(
            nodes.filter { target.supports($0.kind) },
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
        case .socks5:
            components = [node.tls ? "socks5-tls" : "socks5", node.server, "\(node.port)"]
            if let username = node.username { components.append(confValue(username)) }
            if let password = node.password { components.append(confValue(password)) }
            components.append("udp-relay=true")
            if node.tls { appendSurgeTLS(node, includeTLSFlag: false, to: &components) }
        case .http:
            components = [node.tls ? "https" : "http", node.server, "\(node.port)"]
            if let username = node.username { components.append(confValue(username)) }
            if let password = node.password { components.append(confValue(password)) }
            if node.tls { appendSurgeTLS(node, includeTLSFlag: false, to: &components) }
        case .unknown:
            components = ["direct"]
        }
        if shadowrocket, node.kind == .vless { components.append("udp-relay=true") }
        return "\(name) = \(components.joined(separator: ", "))"
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
            values = ["Shadowsocks", node.server, "\(node.port)", node.cipher ?? "aes-256-gcm", confValue(node.password ?? ""), "udp=true"]
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
        case .socks5:
            values = ["Socks5", node.server, "\(node.port)", node.username ?? "", node.password ?? ""]
        case .http:
            values = [node.tls ? "https" : "http", node.server, "\(node.port)"]
            if node.username != nil || node.password != nil {
                values += [confValue(node.username ?? ""), confValue(node.password ?? "")]
            }
            if node.tls {
                if node.skipCertificateVerification { values.append("skip-cert-verify=true") }
                appendValue(node.sni, key: "tls-name", to: &values)
            }
        case .unknown:
            values = ["Direct"]
        }
        return "\(name) = \(values.joined(separator: ","))"
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
            .map(confValue)
            .joined(separator: ", ")
        output += "static=\(RulePolicy.select.configurationName), \(selectValues), img-url=\(iconURL(for: .select))\n"
        let manualValues = (names.isEmpty ? ["direct"] : names).map(confValue).joined(separator: ", ")
        output += "static=\(Self.manualGroupName), \(manualValues), img-url=\(qureIconURL("Static.png"))\n"
        if names.isEmpty {
            output += "static=\(RulePolicy.auto.configurationName), direct, img-url=\(iconURL(for: .auto))\n"
        } else {
            output += "url-latency-benchmark=\(RulePolicy.auto.configurationName), \(names.map(confValue).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50, img-url=\(iconURL(for: .auto))\n"
        }
        let nestedSelectValues = nestedPrimaryChoices(regionGroupNames: regionGroupNames)
            .map(confValue)
            .joined(separator: ", ")
        output += "static=\(Self.nestedSelectGroupName), \(nestedSelectValues), img-url=\(iconURL(for: .select))\n"
        let nestedManualValues = (names.isEmpty ? [Self.directGroupName] : names)
            .map(confValue)
            .joined(separator: ", ")
        output += "static=\(Self.nestedManualGroupName), \(nestedManualValues), img-url=\(qureIconURL("Static.png"))\n"
        if names.isEmpty {
            output += "static=\(Self.nestedAutoGroupName), \(Self.directGroupName), img-url=\(iconURL(for: .auto))\n"
        } else {
            output += "url-latency-benchmark=\(Self.nestedAutoGroupName), \(names.map(confValue).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50, img-url=\(iconURL(for: .auto))\n"
        }
        output += "static=\(Self.directGroupName), direct, img-url=\(iconURL(for: .direct))\n"
        for policy in configurablePolicies(preset) {
            let choices = policyChoices(
                policy,
                regionGroupNames: regionGroupNames,
                reject: "reject"
            )
                .map(confValue)
                .joined(separator: ", ")
            output += "static=\(policy.configurationName), \(choices), img-url=\(iconURL(for: policy))\n"
        }
        for group in regionGroups {
            output += "static=\(group.name), \(([group.automaticName] + group.nodeNames).map(confValue).joined(separator: ", "))\n"
            output += "url-latency-benchmark=\(group.automaticName), \(group.nodeNames.map(confValue).joined(separator: ", ")), check-interval=300, alive-checking=false, tolerance=50\n"
        }
        output += "\n[filter_local]\n"
        for assignment in preset.assignments {
            for rule in rules.lines(for: assignment) {
                if let mapped = mappedRule(rule, policy: assignment.policy, target: .quanx) { output += mapped + "\n" }
            }
        }
        if preset.includeGeoIPCN { output += "geoip, cn, direct\n" }
        output += "final, \(quanXPolicyName(preset.finalPolicy))\n"
        return output
    }

    private func quanXNode(_ node: ProxyNode) -> String {
        var values = ["\(node.server):\(node.port)"]
        let prefix: String
        switch node.kind {
        case .shadowsocks:
            prefix = "shadowsocks"
            values += ["method=\(node.cipher ?? "aes-256-gcm")", "password=\(confValue(node.password ?? ""))", "udp-relay=true"]
        case .shadowsocksR:
            prefix = "shadowsocks"
            values += ["method=\(node.cipher ?? "aes-256-cfb")", "password=\(confValue(node.password ?? ""))", "ssr-protocol=\(node.protocolName ?? "origin")", "obfs=\(node.obfs ?? "plain")"]
        case .vmess:
            prefix = "vmess"
            values += ["method=chacha20-poly1305", "password=\(node.uuid ?? "")"]
            appendQuanXTransport(node, to: &values)
        case .vless:
            prefix = "vless"
            values += ["method=none", "password=\(node.uuid ?? "")"]
            appendQuanXTransport(node, to: &values)
        case .trojan:
            prefix = "trojan"
            values += ["password=\(confValue(node.password ?? ""))", "over-tls=true"]
            appendValue(node.sni, key: "tls-host", to: &values)
        case .hysteria2:
            prefix = "hysteria2"
            values += ["password=\(confValue(node.password ?? ""))", "over-tls=true"]
            appendValue(node.sni, key: "tls-host", to: &values)
        case .socks5:
            prefix = "socks5"
            appendValue(node.username, key: "username", to: &values)
            appendValue(node.password, key: "password", to: &values)
        case .http:
            prefix = "http"
            appendValue(node.username, key: "username", to: &values)
            appendValue(node.password, key: "password", to: &values)
            if node.tls { values.append("over-tls=true") }
        case .unknown:
            prefix = "http"
        }
        values.append("tag=\(confValue(NodeRegionResolver.displayName(for: node)))")
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
        if node.skipCertificateVerification { values.append("tls-verification=false") }
    }

    private func mappedRule(_ rule: String, policy: RulePolicy, target: ClientTarget) -> String? {
        var parts = rule.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count >= 2 else { return nil }

        let policyName: String
        switch target {
        case .clash: policyName = clashPolicyName(policy)
        case .quanx: policyName = quanXPolicyName(policy)
        default: policyName = surgePolicyName(policy)
        }

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
            let rawCode = countryCodes[node.id] ?? NodeRegionResolver.countryCode(for: node)
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

    private func yaml(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func confName(_ value: String) -> String {
        value.replacingOccurrences(of: "=", with: "-").replacingOccurrences(of: ",", with: "，")
    }

    private func confValue(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: "%2C").replacingOccurrences(of: "\n", with: "")
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
