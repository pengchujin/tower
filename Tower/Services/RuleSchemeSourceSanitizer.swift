import Foundation

/// Keeps the editable rule source without persisting imported proxy secrets.
/// Tower only needs policy groups, rules and network settings after parsing;
/// node-bearing sections are deliberately supplied by subscriptions instead.
struct RuleSchemeSourceSanitizer {
    private static let maximumStoredBytes = 512 * 1_024

    static func persistableText(_ text: String) -> String? {
        let sanitized = removingNodeSections(from: text)
        guard sanitized.lengthOfBytes(using: .utf8) <= maximumStoredBytes else {
            return nil
        }
        return sanitized
    }

    private static func removingNodeSections(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var output: [String] = []
        var skipsINIProxySection = false
        var skipsYAMLNodeSection = false

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.count

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                skipsINIProxySection = trimmed.lowercased() == "[proxy]"
                if skipsINIProxySection { continue }
            }
            if skipsINIProxySection { continue }

            if indent == 0, isYAMLNodeSectionHeader(trimmed) {
                skipsYAMLNodeSection = true
                continue
            }
            if skipsYAMLNodeSection {
                if indent == 0, isYAMLTopLevelMappingEntry(trimmed) {
                    skipsYAMLNodeSection = false
                } else {
                    continue
                }
            }
            output.append(rawLine)
        }

        return output.joined(separator: "\n")
    }

    private static func isYAMLNodeSectionHeader(_ line: String) -> Bool {
        guard let separator = line.firstIndex(of: ":") else { return false }
        let key = line[..<separator]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
        return key == "proxies" || key == "proxy-providers"
    }

    private static func isYAMLTopLevelMappingEntry(_ line: String) -> Bool {
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("-") else {
            return false
        }
        return line.contains(":")
    }
}
