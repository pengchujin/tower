import Foundation

/// The three concepts that proxy clients keep separate even though Tower
/// persists them together for backward compatibility:
/// - a ruleset describes what traffic matches;
/// - a policy group describes the available routes;
/// - a binding sends the matching ruleset to that policy group.
struct CustomRuleSetDefinition: Hashable {
    let id: UUID
    let name: String
    let remoteURL: URL?
    let inlineRules: [String]
}

struct RuleSetPolicyBinding: Hashable {
    let ruleSetID: UUID
    let policyGroupName: String
}

struct CustomRuleFlowExpansion: Hashable {
    let ruleSet: CustomRuleSetDefinition
    let policyGroup: RuleSchemeGroup?
    let binding: RuleSetPolicyBinding
}

/// A user-owned ruleset stored on this device. It is deliberately independent
/// from any imported scheme: saving it does not make it active until the user
/// explicitly adds it to a scheme.
struct LocalRuleSet: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var rulesText: String
    var sourceURLString: String?

    init(
        id: UUID = UUID(),
        name: String,
        rulesText: String,
        sourceURLString: String? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rulesText = rulesText
        self.sourceURLString = sourceURLString
        if sourceURLString == nil {
            setRuleInput(rulesText)
        }
    }

    var remoteRuleURL: URL? {
        guard let sourceURLString,
              let url = URL(string: sourceURLString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    var ruleInputText: String {
        remoteRuleURL?.absoluteString ?? rulesText
    }

    var normalizedRules: [String] {
        RuleSetInput.normalizedRules(from: rulesText)
    }

    var hasRuleContent: Bool {
        remoteRuleURL != nil || !normalizedRules.isEmpty
    }

    mutating func setRuleInput(_ input: String) {
        if let url = RuleSetInput.userProvidedURL(from: input) {
            sourceURLString = url.absoluteString
            rulesText = ""
        } else {
            sourceURLString = nil
            rulesText = input
        }
    }
}

/// A user-authored set of rules kept separately from an imported or bundled
/// scheme. Refreshing the upstream scheme therefore cannot overwrite it.
struct CustomRuleFlow: Identifiable, Codable, Hashable {
    var id: UUID
    var schemeID: String
    var name: String
    var policyName: String
    var rulesText: String
    var isEnabled: Bool
    /// References the user-owned library item whose content this placement
    /// uses. Missing means a catalog item or a legacy standalone rule.
    var localRuleSetID: UUID?
    /// Stable identifier for items installed from Tower's searchable catalog.
    /// Older hand-written flows leave this empty.
    var catalogID: String?
    /// A catalog item may reference a maintained remote list instead of
    /// copying thousands of lines into the app snapshot.
    var sourceURLString: String?
    /// Service rules can bring their own policy group when the selected scheme
    /// does not already declare one. The generator still consumes an ordinary
    /// `RuleScheme`, so this remains backward-compatible with every client.
    var generatedPolicyGroup: RuleSchemeGroup?

    init(
        id: UUID = UUID(),
        schemeID: String,
        name: String,
        policyName: String,
        rulesText: String,
        isEnabled: Bool = true,
        localRuleSetID: UUID? = nil,
        catalogID: String? = nil,
        sourceURLString: String? = nil,
        generatedPolicyGroup: RuleSchemeGroup? = nil
    ) {
        self.id = id
        self.schemeID = schemeID
        self.name = name
        self.policyName = policyName
        self.rulesText = rulesText
        self.isEnabled = isEnabled
        self.localRuleSetID = localRuleSetID
        self.catalogID = catalogID
        self.sourceURLString = sourceURLString
        self.generatedPolicyGroup = generatedPolicyGroup
    }

    /// Creates a reusable, user-owned ruleset with its own policy group.
    /// The ruleset can be edited independently from the maintained catalog,
    /// while its candidates stay limited to routing targets such as regions,
    /// automatic selection, DIRECT and REJECT.
    static func userCreatedRuleSet(
        id: UUID = UUID(),
        schemeID: String,
        name: String,
        rulesText: String,
        kind: RuleSchemeGroup.Kind,
        policyNames: [String],
        isEnabled: Bool = true
    ) -> CustomRuleFlow {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteURL = RuleSetInput.userProvidedURL(from: rulesText)
        var seen = Set<String>()
        let members = policyNames.compactMap { rawName -> RuleSchemeGroupMember? in
            let policyName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !policyName.isEmpty, seen.insert(policyName).inserted else { return nil }
            return .reference(policyName)
        }
        let group = RuleSchemeGroup(name: trimmedName, kind: kind, members: members)
        return CustomRuleFlow(
            id: id,
            schemeID: schemeID,
            name: trimmedName,
            policyName: trimmedName,
            rulesText: remoteURL == nil ? rulesText : "",
            isEnabled: isEnabled,
            sourceURLString: remoteURL?.absoluteString,
            generatedPolicyGroup: group
        )
    }

    /// The creation sheet only collects the ruleset itself. Routing remains a
    /// property of the generated group and can be refined from Custom Rules
    /// after the ruleset has been added.
    static func userCreatedRuleSet(
        id: UUID = UUID(),
        schemeID: String,
        name: String,
        rulesText: String,
        defaultPolicyName: String
    ) -> CustomRuleFlow {
        userCreatedRuleSet(
            id: id,
            schemeID: schemeID,
            name: name,
            rulesText: rulesText,
            kind: .select,
            policyNames: [defaultPolicyName],
            isEnabled: true
        )
    }

    var remoteRuleURL: URL? {
        guard let sourceURLString,
              let url = URL(string: sourceURLString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    /// The editor presents a remote ruleset URL and inline rules in the same
    /// field. Keep the persisted representation explicit so generators never
    /// accidentally treat a URL as an ordinary Clash rule line.
    var ruleInputText: String {
        remoteRuleURL?.absoluteString ?? rulesText
    }

    var hasRuleContent: Bool {
        remoteRuleURL != nil || !normalizedRules.isEmpty
    }

    mutating func setRuleInput(_ input: String) {
        if let url = RuleSetInput.userProvidedURL(from: input) {
            sourceURLString = url.absoluteString
            rulesText = ""
        } else {
            sourceURLString = nil
            rulesText = input
        }
        // Editing an installed catalog item creates a user-owned copy whose
        // source and contents will no longer be overwritten by catalog updates.
        catalogID = nil
    }

    /// Expands the backward-compatible persisted DTO into the explicit model
    /// consumed by configuration generation. Callers should use this view
    /// instead of guessing whether `name` or `policyName` is the ruleset name.
    var expansion: CustomRuleFlowExpansion {
        let ruleSet = CustomRuleSetDefinition(
            id: id,
            name: name,
            remoteURL: remoteRuleURL,
            inlineRules: normalizedRules
        )
        return CustomRuleFlowExpansion(
            ruleSet: ruleSet,
            policyGroup: generatedPolicyGroup,
            binding: RuleSetPolicyBinding(
                ruleSetID: ruleSet.id,
                policyGroupName: policyName
            )
        )
    }

    /// Accepts either `TYPE,value` or a line copied from a client config that
    /// already carries an old policy. Tower owns the policy picker, so pasted
    /// policies are removed while `no-resolve` is preserved.
    var normalizedRules: [String] {
        RuleSetInput.normalizedRules(from: rulesText)
    }
}

private enum RuleSetInput {
    static func userProvidedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isNewline }),
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    static func normalizedRules(from rulesText: String) -> [String] {
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
