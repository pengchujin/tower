import Foundation

/// One enabled tailnet with the auth key this device holds for it, if any.
struct TailnetExport: Hashable, Sendable {
    let connection: TailnetConnection
    let authKey: String?
}

/// Adds tailnets to a finished complete profile. It works on the generated
/// text rather than inside each writer so the built-in presets and imported
/// rule schemes get identical output from one place.
///
/// Each tailnet becomes one policy that no group references, plus rules placed
/// before every other rule: the Tailscale address ranges, the MagicDNS domain
/// and the user's subnets. Clients that route a tailnet on their own (Surge
/// 5.21+, Stash 3.6+) still get the rules — Stash 3.4 does not, mihomo and
/// sing-box never do, and subnet routes always need one.
///
/// The auth key goes to every client except Surge. Surge signs in from its
/// policy editor and keys its state to the auth key when one is present, so
/// writing it there would register a new machine beside the one the user
/// already signed in. Stash documents a web sign-in, but it is not available
/// yet (StashAppDev, 2026-04-17: OAuth still in development; confirmed on
/// device), and mihomo / sing-box only print the sign-in link to their logs.
///
/// Verified end to end against a Headscale control server on Surge iOS,
/// Stash 3.4, Clash Mi and sing-box MT, and the mihomo 1.19.31 / sing-box
/// 1.14.2 cores; Surge and Stash also against the official control server.
/// Shadowrocket ignored the node in both Clash and Surge syntax; Hiddify and
/// Karing have no Tailscale outbound.
struct TailnetConfigurationWriter {
    enum Flavor: Equatable {
        case surge, stash, mihomo, singBox
    }

    static func flavor(for target: ClientTarget) -> Flavor? {
        switch target {
        case .surge, .surgeMac: .surge
        case .clash: .stash
        case .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi: .mihomo
        case .singBox: .singBox
        case .shadowrocket, .loon, .quanx, .hiddify, .egern, .v2box, .anywhere, .karing: nil
        }
    }

    static func supports(_ target: ClientTarget) -> Bool { flavor(for: target) != nil }

    /// Appended to the device name so every client registers its own machine.
    static func clientSlug(for target: ClientTarget) -> String {
        target == .clash ? "stash" : target.rawValue
    }

    func apply(_ exports: [TailnetExport], to configuration: GeneratedConfiguration) -> GeneratedConfiguration {
        guard !exports.isEmpty, configuration.contentMode == .fullConfiguration,
              !configuration.content.isEmpty else { return configuration }
        let target = configuration.target
        guard let flavor = Self.flavor(for: target) else {
            guard target != .v2box, target != .anywhere else { return configuration }
            let names = exports.map(\.connection.policyName).joined(separator: "、")
            return configuration.replacing(
                content: configuration.content,
                appendingDiagnostics: [String(localized: "\(target.name) 不支持 Tailscale，已跳过“\(names)”。")]
            )
        }
        var content = configuration.content
        var taken = existingNames(in: content, flavor: flavor)
        var diagnostics: [String] = []
        let slug = Self.clientSlug(for: target)
        for export in exports {
            let name = uniqueName(export.connection.policyName, taken: &taken)
            let hostname = export.connection.hostname(for: slug)
            switch flavor {
            case .surge:
                content = surge(content, export: export, name: name, hostname: hostname)
            case .stash, .mihomo:
                content = clash(content, export: export, name: name, hostname: hostname, flavor: flavor)
            case .singBox:
                content = singBox(content, export: export, name: name, hostname: hostname)
            }
            diagnostics += notes(flavor: flavor, target: target, export: export, name: name)
        }
        return configuration.replacing(content: content, appendingDiagnostics: diagnostics)
    }

    private func notes(flavor: Flavor, target: ClientTarget, export: TailnetExport, name: String) -> [String] {
        // Signing in from Surge's policy editor is the normal path, not a problem.
        guard flavor != .surge else { return [] }
        var notes: [String] = []
        if export.authKey == nil {
            notes.append(String(localized: "“\(name)”没有 Auth Key：\(target.name) 暂时不能在客户端里登录 Tailscale，请在塔台里填写 Auth Key。"))
        }
        if flavor == .stash {
            notes.append(stashNote(export: export, name: name))
        }
        return notes
    }

    /// Stash keeps 100.64.0.0/10 and the private ranges in its default
    /// skip-proxy and skip-route lists (StashAppDev, 2026-04-17), so an
    /// address never reaches the rules. A MagicDNS name is resolved to a fake
    /// IP first and does.
    private func stashNote(export: TailnetExport, name: String) -> String {
        guard let suffix = export.connection.magicDNSSuffix else {
            return String(localized: "“\(name)”没有填 MagicDNS 后缀：Stash 默认跳过 Tailscale 地址段，只能通过设备名访问，请在塔台里填写后缀。")
        }
        return String(localized: "Stash 默认跳过 Tailscale 地址段和局域网网段：请用“设备名.\(suffix)”访问“\(name)”；按 IP 或访问家里子网，需要先在 Stash 的跳过代理和跳过路由中移除对应网段。")
    }

    private func routes(for connection: TailnetConnection) -> (domains: [String], ipv4: [String], ipv6: [String]) {
        let subnets = connection.subnets
        return (
            connection.magicDNSSuffix.map { [$0] } ?? [],
            [TailnetConnection.tailnetIPv4Range] + subnets.filter { !TailnetConnection.isIPv6CIDR($0) },
            [TailnetConnection.tailnetIPv6Range] + subnets.filter(TailnetConnection.isIPv6CIDR)
        )
    }

    // MARK: - Surge

    private func surge(_ content: String, export: TailnetExport, name: String, hostname: String) -> String {
        let connection = export.connection
        var lines = content.components(separatedBy: "\n")
        let policy = "\(name) = tailscale, section-name=\(connection.stableSlug)"
        if let index = lines.firstIndex(of: "[Proxy]") {
            lines.insert(policy, at: index + 1)
        } else if let index = lines.firstIndex(of: "[Proxy Group]") ?? lines.firstIndex(of: "[Rule]") {
            lines.insert(contentsOf: ["[Proxy]", policy, ""], at: index)
        }
        let route = routes(for: connection)
        let rules = route.domains.map { "DOMAIN-SUFFIX,\($0),\(name)" }
            + route.ipv4.map { "IP-CIDR,\($0),\(name),no-resolve" }
            + route.ipv6.map { "IP-CIDR6,\($0),\(name),no-resolve" }
        if let index = lines.firstIndex(of: "[Rule]") {
            lines.insert(contentsOf: rules, at: index + 1)
        }
        var section = ["", "[Tailscale \(connection.stableSlug)]", "interactive-login = true"]
        if let url = connection.customControlURL { section.append("control-url = \(url)") }
        section.append("hostname = \(hostname)")
        while lines.last == "" { lines.removeLast() }
        return (lines + section).joined(separator: "\n") + "\n"
    }

    // MARK: - Stash and mihomo

    private func clash(_ content: String, export: TailnetExport, name: String, hostname: String, flavor: Flavor) -> String {
        let connection = export.connection
        var lines = content.components(separatedBy: "\n")
        var entry = [
            "  - name: \(yaml(name))",
            "    type: tailscale",
        ]
        if let key = export.authKey { entry.append("    auth-key: \(yaml(key))") }
        if let url = connection.customControlURL { entry.append("    control-url: \(yaml(url))") }
        entry.append("    hostname: \(yaml(hostname))")
        if flavor == .mihomo {
            entry.append("    state-dir: \(yaml(connection.stableSlug))")
            entry.append("    udp: true")
            entry.append("    accept-routes: true")
        }
        if let index = lines.firstIndex(of: "proxies:") {
            var next = index + 1
            while next < lines.count, lines[next].isEmpty { next += 1 }
            if next < lines.count, lines[next] == "  []" {
                lines.replaceSubrange(next...next, with: entry)
            } else {
                lines.insert(contentsOf: entry, at: index + 1)
            }
        } else if let index = lines.firstIndex(of: "proxy-groups:") ?? lines.firstIndex(of: "rules:") {
            lines.insert(contentsOf: ["proxies:"] + entry + [""], at: index)
        }
        let route = routes(for: connection)
        let rules = route.domains.map { "DOMAIN-SUFFIX,\($0),\(name)" }
            + route.ipv4.map { "IP-CIDR,\($0),\(name),no-resolve" }
            + route.ipv6.map { "IP-CIDR6,\($0),\(name),no-resolve" }
        if let index = lines.firstIndex(of: "rules:") {
            lines.insert(contentsOf: rules.map { "  - \(yaml($0))" }, at: index + 1)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - sing-box

    private func singBox(_ content: String, export: TailnetExport, name: String, hostname: String) -> String {
        guard let data = content.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return content }
        let connection = export.connection
        var endpoint: [String: Any] = [
            "type": "tailscale",
            "tag": name,
            "state_directory": connection.stableSlug,
            "hostname": hostname,
            "accept_routes": true,
        ]
        if let key = export.authKey { endpoint["auth_key"] = key }
        if let url = connection.customControlURL { endpoint["control_url"] = url }
        root["endpoints"] = ((root["endpoints"] as? [[String: Any]]) ?? []) + [endpoint]

        let route = routes(for: connection)
        if !route.domains.isEmpty {
            var dns = root["dns"] as? [String: Any] ?? [:]
            let serverTag = name + " DNS"
            dns["servers"] = ((dns["servers"] as? [[String: Any]]) ?? [])
                + [["type": "tailscale", "tag": serverTag, "endpoint": name]]
            dns["rules"] = [["action": "route", "domain_suffix": route.domains, "server": serverTag]]
                + ((dns["rules"] as? [[String: Any]]) ?? [])
            root["dns"] = dns
        }

        var routing = root["route"] as? [String: Any] ?? [:]
        var rules = routing["rules"] as? [[String: Any]] ?? []
        var rule: [String: Any] = ["action": "route", "ip_cidr": route.ipv4 + route.ipv6, "outbound": name]
        if !route.domains.isEmpty { rule["domain_suffix"] = route.domains }
        // After sniffing and DNS hijacking, before `resolve` and every policy
        // rule: a MagicDNS name must still be a name when it is matched.
        let position = rules.firstIndex { item in
            let action = item["action"] as? String
            return action != "sniff" && action != "hijack-dns"
        } ?? rules.count
        rules.insert(rule, at: position)
        routing["rules"] = rules
        root["route"] = routing

        guard let output = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: output, encoding: .utf8) else { return content }
        return text + "\n"
    }

    // MARK: - Names

    private func existingNames(in content: String, flavor: Flavor) -> Set<String> {
        var names: Set<String> = ["DIRECT", "REJECT", "direct", "reject"]
        switch flavor {
        case .surge:
            var inPolicySection = false
            for line in content.components(separatedBy: "\n") {
                if line.hasPrefix("[") {
                    inPolicySection = line == "[Proxy]" || line == "[Proxy Group]"
                } else if inPolicySection, let range = line.range(of: " = ") {
                    names.insert(String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces))
                }
            }
        case .stash, .mihomo:
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- name: ") else { continue }
                var value = String(trimmed.dropFirst("- name: ".count))
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\\\", with: "\\")
                } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                names.insert(value)
            }
        case .singBox:
            if let data = content.data(using: .utf8),
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                for key in ["outbounds", "endpoints"] {
                    for item in root[key] as? [[String: Any]] ?? [] {
                        if let tag = item["tag"] as? String { names.insert(tag) }
                    }
                }
            }
        }
        return names
    }

    private func uniqueName(_ base: String, taken: inout Set<String>) -> String {
        var candidate = base
        var counter = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        taken.insert(candidate)
        return candidate
    }

    private func yaml(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

extension GeneratedConfiguration {
    func replacing(content: String, appendingDiagnostics extra: [String]) -> GeneratedConfiguration {
        GeneratedConfiguration(
            target: target,
            content: content,
            supportedNodeCount: supportedNodeCount,
            skippedNodeCount: skippedNodeCount,
            ruleCount: ruleCount,
            profileName: profileName,
            contentMode: contentMode,
            fileExtensionOverride: fileExtensionOverride,
            remoteSourceCount: remoteSourceCount,
            diagnostics: diagnostics + extra,
            hasInvalidPolicyReferences: hasInvalidPolicyReferences,
            skippedNodes: skippedNodes,
            anywhereAJSON: anywhereAJSON
        )
    }
}
