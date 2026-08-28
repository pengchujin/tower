import Foundation

enum RuleSchemeTextValidationError: LocalizedError, Equatable {
    case invalidConfiguration(message: String)
    case invalidLine(line: Int)
    case duplicatePolicy(name: String, line: Int)
    case unknownPolicy(name: String, line: Int)
    case unknownReference(name: String, line: Int)
    case invalidEncryptedDNS(value: String, line: Int)
    case invalidTestURL(value: String, line: Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            message
        case .invalidLine(let line):
            String(localized: "第 \(line) 行不是可识别的规则配置")
        case .duplicatePolicy(let name, let line):
            String(localized: "第 \(line) 行重复定义了策略组“\(name)”")
        case .unknownPolicy(let name, let line):
            String(localized: "第 \(line) 行引用了不存在的策略组“\(name)”")
        case .unknownReference(let name, let line):
            String(localized: "第 \(line) 行引用了不存在的成员“\(name)”")
        case .invalidEncryptedDNS(let value, let line):
            String(localized: "第 \(line) 行的加密 DNS 地址无效：\(value)")
        case .invalidTestURL(let value, let line):
            String(localized: "第 \(line) 行的测试地址无效：\(value)")
        }
    }
}

/// Converts the editable source into Tower's rule graph and rejects dangling
/// references before that graph reaches any client generator.
struct RuleSchemeTextEditorService {
    private let parser = RuleSchemeParser()

    func editableText(for scheme: RuleScheme) -> String {
        if let source = scheme.rawConfigurationText, !source.isEmpty { return source }
        return canonicalText(for: scheme)
    }

    func validatedScheme(from text: String, replacing scheme: RuleScheme) throws -> RuleScheme {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RuleSchemeTextValidationError.invalidConfiguration(
                message: String(localized: "配置内容不能为空")
            )
        }

        let parsed: RuleScheme
        do {
            parsed = try parser.parse(
                text: text,
                id: scheme.id,
                name: scheme.name,
                summary: scheme.summary,
                sourceURLString: scheme.sourceURLString,
                isBundled: scheme.isBundled
            )
        } catch {
            throw RuleSchemeTextValidationError.invalidConfiguration(
                message: (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "配置无法识别")
            )
        }

        try validateRecognizedINILines(in: text, parsed: parsed)
        try validateNetworkSettings(parsed.networkSettings, in: text)

        var firstDefinition: [String: Int] = [:]
        for group in parsed.groups {
            let line = lineNumber(containing: group.name, in: text)
            if firstDefinition[group.name] != nil {
                throw RuleSchemeTextValidationError.duplicatePolicy(name: group.name, line: line)
            }
            firstDefinition[group.name] = line
        }

        let groupNames = Set(parsed.groups.map(\.name))
        let builtins = Set(["DIRECT", "REJECT"])
        for ruleset in parsed.rulesets where !groupNames.contains(ruleset.groupName) {
            throw RuleSchemeTextValidationError.unknownPolicy(
                name: ruleset.groupName,
                line: lineNumber(containing: ruleset.groupName, in: text)
            )
        }
        for group in parsed.groups {
            for member in group.members {
                guard case .reference(let reference) = member,
                      !groupNames.contains(reference),
                      !builtins.contains(reference.uppercased()) else { continue }
                throw RuleSchemeTextValidationError.unknownReference(
                    name: reference,
                    line: lineNumber(containing: reference, in: text)
                )
            }
        }
        return parsed
    }

    private func validateRecognizedINILines(in text: String, parsed: RuleScheme) throws {
        let lines = text.components(separatedBy: .newlines)
        let rulesetLines = lines.enumerated().filter {
            $0.element.trimmingCharacters(in: .whitespaces).hasPrefix("ruleset=")
        }
        let groupLines = lines.enumerated().filter {
            $0.element.trimmingCharacters(in: .whitespaces).hasPrefix("custom_proxy_group=")
        }
        if !rulesetLines.isEmpty, parsed.rulesets.count < rulesetLines.count,
           let bad = rulesetLines.dropFirst(parsed.rulesets.count).first {
            throw RuleSchemeTextValidationError.invalidLine(line: bad.offset + 1)
        }
        if !groupLines.isEmpty, parsed.groups.count < groupLines.count,
           let bad = groupLines.dropFirst(parsed.groups.count).first {
            throw RuleSchemeTextValidationError.invalidLine(line: bad.offset + 1)
        }
    }

    private func validateNetworkSettings(
        _ settings: RuleSchemeNetworkSettings?,
        in text: String
    ) throws {
        guard let settings else { return }
        for value in settings.encryptedDNSServers {
            guard let url = URL(string: value),
                  ["https", "tls", "quic"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else {
                throw RuleSchemeTextValidationError.invalidEncryptedDNS(
                    value: value,
                    line: lineNumber(containing: value, in: text)
                )
            }
        }
        if let value = settings.proxyTestURLString,
           !(URL(string: value).map {
               ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil
           } ?? false) {
            throw RuleSchemeTextValidationError.invalidTestURL(
                value: value,
                line: lineNumber(containing: value, in: text)
            )
        }
    }

    private func lineNumber(containing value: String, in text: String) -> Int {
        text.components(separatedBy: .newlines).firstIndex { $0.contains(value) }.map { $0 + 1 } ?? 1
    }

    private func canonicalText(for scheme: RuleScheme) -> String {
        var lines: [String] = []
        if let settings = scheme.networkSettings, !settings.isEmpty {
            lines.append("[General]")
            if let ipv6 = settings.ipv6Enabled { lines.append("ipv6 = \(ipv6)") }
            if !settings.dnsServers.isEmpty {
                lines.append("dns-server = \(settings.dnsServers.joined(separator: ", "))")
            }
            if !settings.encryptedDNSServers.isEmpty {
                lines.append(
                    "encrypted-dns-server = \(settings.encryptedDNSServers.joined(separator: ", "))"
                )
            }
            if let url = settings.proxyTestURLString { lines.append("proxy-test-url = \(url)") }
            lines.append("")
        }
        lines.append("[custom]")
        lines += scheme.rulesets.map { ruleset in
            let target: String
            switch ruleset.resource {
            case .remote(let url): target = url.absoluteString
            case .inline(let rule): target = "[]\(rule)"
            }
            return "ruleset=\(ruleset.groupName),\(target)"
        }
        lines += scheme.groups.map { group in
            var fields = [group.name, group.kind == .select ? "select" : "url-test"]
            fields += group.members.map { member in
                switch member {
                case .reference(let name): "[]\(name)"
                case .nodePattern(let pattern): pattern
                }
            }
            if group.kind == .urlTest {
                fields.append(group.testURLString ?? "http://www.gstatic.com/generate_204")
                fields.append("\(group.interval ?? 300),,\(group.tolerance ?? 50)")
            }
            return "custom_proxy_group=\(fields.joined(separator: "`"))"
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
