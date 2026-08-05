import Foundation

/// A rule scheme imported from a subconverter-style `.ini` remote config, such
/// as the ACL4SSR presets. Unlike `RulePreset`, whose policy groups are fixed in
/// Swift, an imported scheme carries whatever groups the file declared, so the
/// generated configuration reproduces the source faithfully.
struct RuleScheme: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var summary: String
    var sourceURLString: String?
    var groups: [RuleSchemeGroup]
    var rulesets: [RuleSchemeRuleset]
    var updatedAt: Date?
    /// True for the schemes shipped inside the app bundle, which work offline
    /// and cannot be deleted.
    var isBundled: Bool

    init(
        id: String,
        name: String,
        summary: String,
        sourceURLString: String? = nil,
        groups: [RuleSchemeGroup],
        rulesets: [RuleSchemeRuleset],
        updatedAt: Date? = nil,
        isBundled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.sourceURLString = sourceURLString
        self.groups = groups
        self.rulesets = rulesets
        self.updatedAt = updatedAt
        self.isBundled = isBundled
    }

    /// Every remote list the scheme references, de-duplicated in first-use order.
    var remoteRulesetURLs: [URL] {
        var seen = Set<String>()
        return rulesets.compactMap { ruleset in
            guard case .remote(let url) = ruleset.resource,
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }

    /// The group a client should fall back to, taken from the `[]FINAL` ruleset.
    var finalGroupName: String? {
        rulesets.first { ruleset in
            if case .inline(let rule) = ruleset.resource {
                return rule.uppercased() == "FINAL"
            }
            return false
        }?.groupName
    }
}

struct RuleSchemeGroup: Codable, Hashable {
    enum Kind: String, Codable {
        case select
        case urlTest
    }

    let name: String
    let kind: Kind
    /// Members in their declared order; the order decides how the client lists
    /// them, so it must survive parsing.
    let members: [RuleSchemeGroupMember]
    let testURLString: String?
    let interval: Int?
    let tolerance: Int?

    init(
        name: String,
        kind: Kind,
        members: [RuleSchemeGroupMember],
        testURLString: String? = nil,
        interval: Int? = nil,
        tolerance: Int? = nil
    ) {
        self.name = name
        self.kind = kind
        self.members = members
        self.testURLString = testURLString
        self.interval = interval
        self.tolerance = tolerance
    }
}

enum RuleSchemeGroupMember: Codable, Hashable {
    /// A `[]`-prefixed member: another group, or a builtin such as DIRECT.
    case reference(String)
    /// A bare member: a regular expression matched against node names. `.*`
    /// selects every node.
    case nodePattern(String)
}

struct RuleSchemeRuleset: Codable, Hashable {
    enum Resource: Codable, Hashable {
        case remote(URL)
        /// A `[]`-prefixed rule written directly in the config, such as
        /// `[]GEOIP,CN` or `[]FINAL`.
        case inline(String)
    }

    let groupName: String
    let resource: Resource
}
