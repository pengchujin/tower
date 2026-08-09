import Foundation

/// A user-authored set of rules kept separately from an imported or bundled
/// scheme. Refreshing the upstream scheme therefore cannot overwrite it.
struct CustomRuleFlow: Identifiable, Codable, Hashable {
    var id: UUID
    var schemeID: String
    var name: String
    var policyName: String
    var rulesText: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        schemeID: String,
        name: String,
        policyName: String,
        rulesText: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.schemeID = schemeID
        self.name = name
        self.policyName = policyName
        self.rulesText = rulesText
        self.isEnabled = isEnabled
    }

    /// Accepts either `TYPE,value` or a line copied from a client config that
    /// already carries an old policy. Tower owns the policy picker, so pasted
    /// policies are removed while `no-resolve` is preserved.
    var normalizedRules: [String] {
        rulesText.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  !line.hasPrefix(";"),
                  !line.hasPrefix("//") else { return nil }

            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }

            var normalized = [parts[0], parts[1]]
            if parts.dropFirst(2).contains(where: { $0.lowercased() == "no-resolve" }) {
                normalized.append("no-resolve")
            }
            return normalized.joined(separator: ",")
        }
    }
}
