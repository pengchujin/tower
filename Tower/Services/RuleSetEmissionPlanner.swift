import Foundation

/// Chooses the smallest native representation that is still accepted by the
/// target client. A remote URL is never emitted merely because it ends in
/// `.list`: the cached payload must use that client's rule-set dialect.
struct RuleSetEmissionPlanner {
    enum NativeFormat: Equatable {
        case classicalText
        case clashProviderYAML
        case clashDomainMRS
        case clashIPCIDRMRS
        case quanXFilter
        case singBoxSource
        case singBoxBinarySRS
        case egernYAML
    }

    struct RemoteResource: Equatable {
        let identifier: String
        let url: URL
        let policyName: String
        let format: NativeFormat
        var options: [String] = []
        var provider: RuleProviderMetadata? = nil
        /// sing-box: the domain-only SRS of the same list, for DNS rules.
        var dnsDomainURL: URL? = nil
        /// The rule lines this reference stands for, where Tower knows them.
        /// DNS projection and Quantumult X's no-resolve check read them.
        var localLines: [String] = []
    }

    struct InlineRule: Equatable {
        let policyName: String
        let line: String
    }

    /// Consecutive rules from one of the user's own rule sets that has no URL
    /// to fetch, written once as the client's inline rule set: a `[Ruleset]`
    /// section in Surge, a `type: inline` provider in mihomo and Stash. Only
    /// plain `TYPE,value` lines qualify, so nothing is lost on the way.
    struct InlineRuleSet: Equatable {
        enum Behavior: Equatable { case domain, ipcidr, classical }

        let identifier: String
        let policyName: String
        let behavior: Behavior
        let rules: [InlineRule]
        /// Written on the `RULE-SET` line, as the same rules would carry it
        /// one by one: Surge adds it to every IP rule, mihomo and Stash only
        /// keep what the source wrote, so a set never mixes the two.
        let noResolve: Bool
    }

    enum Entry: Equatable {
        case remote(RemoteResource)
        case inline(InlineRule)
        case inlineSet(InlineRuleSet)

        /// The rules this entry writes into the profile itself.
        var localRules: [InlineRule] {
            switch self {
            case .remote: []
            case .inline(let rule): [rule]
            case .inlineSet(let set): set.rules
            }
        }

        var isLocal: Bool {
            if case .remote = self { return false }
            return true
        }

        /// For formats without inline sets: the set's rules, one by one.
        var expandingInlineSet: [Entry] {
            guard case .inlineSet(let set) = self else { return [self] }
            return set.rules.map(Entry.inline)
        }
    }

    /// A binary MRS rule set the target cannot read or reference.
    struct UnreadableResource: Equatable {
        let policyName: String
        let url: URL
    }

    struct Plan: Equatable {
        let entries: [Entry]
        let finalGroupName: String?
        var finalOptions: [String] = []
        var unreadableResources: [UnreadableResource] = []

        var remoteResources: [RemoteResource] {
            entries.compactMap {
                guard case .remote(let resource) = $0 else { return nil }
                return resource
            }
        }

        var inlineRules: [InlineRule] {
            entries.flatMap(\.localRules)
        }

        var inlineSets: [InlineRuleSet] {
            entries.compactMap {
                guard case .inlineSet(let set) = $0 else { return nil }
                return set
            }
        }
    }

    private let repository: RuleSchemeRepository

    init(repository: RuleSchemeRepository) {
        self.repository = repository
    }

    /// `isExpressible` tells which local rules the target can write at all.
    /// A rule it drops does not count as a local rule that a remote list in
    /// Loon or Quantumult X would have to stay in front of.
    func plan(
        for scheme: RuleScheme,
        target: ClientTarget,
        preferRuleSets: Bool,
        isExpressible: (String) -> Bool = { _ in true }
    ) -> Plan {
        var entries: [Entry] = []
        var finalGroupName: String?
        var finalOptions: [String] = []
        var remoteIndex = 0
        // What each generic remote entry expands to if it has to be inlined.
        var inlineFallbacks: [Int: [Entry]] = [:]
        var unreadable: [UnreadableResource] = []
        var pendingSet: (key: String, rules: [InlineRule], noResolve: Bool)?
        var inlineSetIndex = 0
        func flushPendingSet() {
            guard let run = pendingSet else { return }
            pendingSet = nil
            // One rule gains nothing from a set of its own.
            guard run.rules.count >= 2, let first = run.rules.first else {
                entries.append(contentsOf: run.rules.map(Entry.inline))
                return
            }
            inlineSetIndex += 1
            entries.append(.inlineSet(InlineRuleSet(
                identifier: "tower-local-\(inlineSetIndex)",
                policyName: first.policyName,
                behavior: Self.inlineSetBehavior(run.rules),
                rules: run.rules,
                noResolve: run.noResolve
            )))
        }

        for ruleset in scheme.rulesets {
            let setKey = preferRuleSets ? inlineSetKey(ruleset, target: target) : nil
            if pendingSet?.key != setKey { flushPendingSet() }
            if let setKey, case .inline(let line) = ruleset.resource {
                if pendingSet == nil {
                    let isIP = Self.inlineSetIPTypes.contains(Self.ruleType(in: line))
                    let wroteNoResolve = line.lowercased().hasSuffix(",no-resolve")
                    pendingSet = (setKey, [], isIP && ([.surge, .surgeMac].contains(target) || wroteNoResolve))
                }
                pendingSet?.rules.append(InlineRule(policyName: ruleset.groupName, line: line))
                continue
            }
            // Only mihomo and Stash read MRS, and they can only fetch it: there
            // are no lines to write locally, whatever the rule-set preference.
            if ruleset.isBinaryRuleSet, let url = ruleset.resource.downloadURL {
                let behavior = ruleset.provider?.behavior?.lowercased()
                if Self.mrsTargets.contains(target), behavior == "domain" || behavior == "ipcidr" {
                    remoteIndex += 1
                    entries.append(.remote(RemoteResource(
                        identifier: identifier(for: url, index: remoteIndex, suffix: behavior == "ipcidr" ? "ip" : "domain"),
                        url: url,
                        policyName: ruleset.groupName,
                        format: behavior == "ipcidr" ? .clashIPCIDRMRS : .clashDomainMRS,
                        options: ruleset.options ?? [],
                        provider: ruleset.provider
                    )))
                } else {
                    unreadable.append(UnreadableResource(policyName: ruleset.groupName, url: url))
                }
                continue
            }
            if ruleset.resource.domainSetURL != nil, !([.surge, .surgeMac].contains(target) && preferRuleSets) {
                let options: [String]
                if case .inline(let body) = ruleset.resource {
                    options = RoutingRuleSyntax.condition(body)?.options ?? []
                } else { options = ruleset.options ?? [] }
                entries.append(contentsOf: repository.lines(for: ruleset.resource).map {
                    .inline(InlineRule(policyName: ruleset.groupName, line: RuleResourceContent.applying(options, to: $0)))
                })
                continue
            }
            switch ruleset.resource {
            case .inline(let line):
                if line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "FINAL" {
                    finalGroupName = ruleset.groupName
                    finalOptions = ruleset.options ?? []
                } else if preferRuleSets, ruleset.origin == nil, ruleset.options == nil,
                          let dialect = RuleSchemeRepository.RuleListDialect(target: target),
                          dialect != .egern,
                          let url = repository.publishedLocalRule(line, dialect: dialect) {
                    // Loon and Quantumult X match every local rule before any
                    // remote list, so the scheme's own trailing GEOIP rule
                    // would jump ahead of every list. As a list it keeps its place.
                    remoteIndex += 1
                    let rule = InlineRule(policyName: ruleset.groupName, line: line)
                    inlineFallbacks[entries.count] = [.inline(rule)]
                    entries.append(.remote(RemoteResource(
                        identifier: identifier(for: url, index: remoteIndex),
                        url: url,
                        policyName: ruleset.groupName,
                        format: dialect == .quanx ? .quanXFilter : .classicalText,
                        localLines: [line]
                    )))
                } else {
                    entries.append(.inline(InlineRule(policyName: ruleset.groupName, line: line)))
                }

            case .remote(let url):
                let lines = repository.lines(for: ruleset.resource)
                // What the downloaded list holds decides how a client reads
                // it; the declaration only says what the source expected.
                let provider = RuleResourceContent.provider(ruleset.provider, for: lines)
                if preferRuleSets, ruleset.options == nil, ruleset.provider == nil,
                   [.clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi].contains(target),
                   let optimized = optimizedClashEntries(
                    resource: ruleset.resource,
                    sourceURL: url,
                    lines: lines,
                    policyName: ruleset.groupName,
                    startingRemoteIndex: remoteIndex
                   ) {
                    entries.append(contentsOf: optimized.entries)
                    remoteIndex = optimized.finalRemoteIndex
                } else if preferRuleSets, ruleset.options == nil, ruleset.provider == nil,
                          // Hiddify 4.0 embeds sing-box 1.13, which reads SRS v2.
                          [.singBox, .hiddify].contains(target),
                          let optimized = optimizedSingBoxEntries(
                            resource: ruleset.resource,
                            sourceURL: url,
                            lines: lines,
                            policyName: ruleset.groupName,
                            startingRemoteIndex: remoteIndex
                          ) {
                    entries.append(contentsOf: optimized.entries)
                    remoteIndex = optimized.finalRemoteIndex
                } else if preferRuleSets, ruleset.options == nil, ruleset.provider == nil,
                          let dialect = RuleSchemeRepository.RuleListDialect(target: target),
                          let alternative = repository.dialectResource(dialect, for: ruleset.resource, matching: lines) {
                    // The bundled list rewritten in this client's own format.
                    // The types it could not carry stay right behind it.
                    remoteIndex += 1
                    let covered = lines.filter { alternative.coveredRuleTypes.contains(ruleType(in: $0)) }
                    inlineFallbacks[entries.count] = covered.map {
                        .inline(InlineRule(policyName: ruleset.groupName, line: $0))
                    }
                    entries.append(.remote(RemoteResource(
                        identifier: identifier(for: url, index: remoteIndex, suffix: dialect.rawValue),
                        url: alternative.url,
                        policyName: ruleset.groupName,
                        format: dialect == .quanx ? .quanXFilter : dialect == .egern ? .egernYAML : .classicalText,
                        localLines: covered
                    )))
                    entries.append(contentsOf: lines.compactMap { line in
                        guard !alternative.coveredRuleTypes.contains(ruleType(in: line)) else { return nil }
                        return .inline(InlineRule(policyName: ruleset.groupName, line: line))
                    })
                } else if preferRuleSets,
                   RoutingRuleCapabilities.optionsSupported((ruleset.options ?? []).filter { !$0.hasPrefix("update-interval=") }, target: target),
                   let format = providerFormat(provider, target: target, resource: ruleset.resource, lines: lines) ?? nativeFormat(
                    for: target,
                    url: url,
                    lines: lines,
                    isClashProviderYAML: repository.isClashProviderYAML(ruleset.resource)
                   ) {
                    remoteIndex += 1
                    inlineFallbacks[entries.count] = RuleResourceContent.normalized(lines, behavior: ruleset.provider?.behavior).map {
                        .inline(InlineRule(policyName: ruleset.groupName, line: RuleResourceContent.applying(ruleset.options ?? [], to: $0)))
                    }
                    entries.append(.remote(RemoteResource(
                        identifier: identifier(for: url, index: remoteIndex),
                        url: url,
                        policyName: ruleset.groupName,
                        format: format,
                        options: ruleset.options ?? [], provider: provider,
                        localLines: RuleResourceContent.normalized(lines, behavior: ruleset.provider?.behavior)
                    )))
                } else {
                    entries.append(contentsOf: RuleResourceContent.normalized(lines, behavior: ruleset.provider?.behavior).map {
                        .inline(InlineRule(policyName: ruleset.groupName, line: RuleResourceContent.applying(ruleset.options ?? [], to: $0)))
                    })
                }
            }
        }

        flushPendingSet()

        // Loon and Quantumult X keep remote rule lists in their own section
        // and match every local rule before any of them (Loon: local > plugin
        // > remote; Quantumult X: filter_local > filter_remote). A list that
        // came before a local rule would lose to it, so it is inlined instead.
        if [.loon, .quanx].contains(target),
           let lastInline = entries.lastIndex(where: { entry in
               entry.localRules.contains { isExpressible($0.line) }
           }) {
            entries = entries.indices.flatMap { index -> [Entry] in
                guard index < lastInline, let fallback = inlineFallbacks[index] else { return [entries[index]] }
                return fallback
            }
        }

        return Plan(entries: entries, finalGroupName: finalGroupName, finalOptions: finalOptions, unreadableResources: unreadable)
    }

    /// Surge documents `[Ruleset <name>]` (Mac 5.3.1, editable on iOS from
    /// 5.22); mihomo has `type: inline` providers since 1.19.1 and Stash since
    /// iOS 3.6 / macOS 4.3. Karing, Shadowrocket and the Clash app document
    /// none, and Loon and Quantumult X have no inline set at all.
    private static let inlineSetTargets: Set<ClientTarget> = [
        .surge, .surgeMac, .clash, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi
    ]
    private static let inlineSetDomainTypes: Set<String> = ["DOMAIN", "DOMAIN-SUFFIX"]
    static let inlineSetIPTypes: Set<String> = ["IP-CIDR", "IP-CIDR6"]
    private static let inlineSetTypes = inlineSetDomainTypes.union(inlineSetIPTypes).union(["DOMAIN-KEYWORD"])

    /// Groups rules that came from the same rule set of the user's library
    /// and go to the same policy. Group supplements stay single rules: they
    /// must match first, one by one, from the most specific.
    private func inlineSetKey(_ ruleset: RuleSchemeRuleset, target: ClientTarget) -> String? {
        guard Self.inlineSetTargets.contains(target),
              case .added(let name) = ruleset.origin,
              case .inline(let line) = ruleset.resource,
              ruleset.options == nil, ruleset.provider == nil,
              Self.isPlainSetRule(line) else { return nil }
        // Domain and IP rules never share a set, and in mihomo and Stash IP
        // rules with and without no-resolve do not either.
        let isIP = Self.inlineSetIPTypes.contains(Self.ruleType(in: line))
        let wroteNoResolve = line.lowercased().hasSuffix(",no-resolve") && ![.surge, .surgeMac].contains(target)
        let kind = isIP ? (wroteNoResolve ? "ip-no-resolve" : "ip") : "domain"
        return [name, ruleset.groupName, kind].joined(separator: "\u{1F}")
    }

    /// `TYPE,value`, or an IP rule with `no-resolve`. The value is kept to
    /// characters that cannot end a line or a field in any of the formats.
    private static func isPlainSetRule(_ line: String) -> Bool {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2 || parts.count == 3, inlineSetTypes.contains(parts[0].uppercased()) else { return false }
        if parts.count == 3 {
            guard inlineSetIPTypes.contains(parts[0].uppercased()), parts[2].lowercased() == "no-resolve" else { return false }
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_:/")
        return !parts[1].isEmpty && parts[1].unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func inlineSetBehavior(_ rules: [InlineRule]) -> InlineRuleSet.Behavior {
        let types = Set(rules.map { ruleType(in: $0.line) })
        if types.isSubset(of: inlineSetDomainTypes) { return .domain }
        if types.isSubset(of: inlineSetIPTypes) { return .ipcidr }
        return .classical
    }

    static func ruleType(in line: String) -> String {
        line.split(separator: ",", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    }

    /// Karing is left out: its core is sing-box, which has no MRS reader.
    /// Stash reads domain and ipcidr MRS since 3.1.0 (stash.wiki/en/rules/rule-set).
    private static let mrsTargets: Set<ClientTarget> = [.clash, .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi]

    /// MRS supports compact domain and CIDR tries, not the mixed `classical`
    /// grammar used by ACL4SSR. Tower therefore emits verified binary slices
    /// and keeps every rule that cannot be represented by that slice inline.
    /// Returning `nil` means no binary alternative exists and preserves the
    /// pre-existing classical provider/inline fallback unchanged.
    private func optimizedClashEntries(
        resource: RuleSchemeRuleset.Resource,
        sourceURL: URL,
        lines: [String],
        policyName: String,
        startingRemoteIndex: Int
    ) -> (entries: [Entry], finalRemoteIndex: Int)? {
        let alternatives = repository.clashMRSResources(
            for: resource,
            matching: lines
        )
        guard !alternatives.isEmpty, !lines.isEmpty else { return nil }

        let domainTypes: Set<String> = ["DOMAIN", "DOMAIN-SUFFIX"]
        let ipTypes: Set<String> = ["IP-CIDR", "IP-CIDR6", "IP6-CIDR"]
        let hasDomainRules = lines.contains { domainTypes.contains(ruleType(in: $0)) }
        let hasIPRules = lines.contains { ipTypes.contains(ruleType(in: $0)) }

        var coveredTypes: Set<String> = []
        var entries: [Entry] = []
        var remoteIndex = startingRemoteIndex

        for alternative in alternatives {
            let shouldEmit: Bool
            let format: NativeFormat
        var options: [String] = []
            let suffix: String
            switch alternative.behavior {
            case .domain:
                shouldEmit = hasDomainRules
                format = .clashDomainMRS
                suffix = "domain"
                if shouldEmit { coveredTypes.formUnion(domainTypes) }
            case .ipcidr:
                shouldEmit = hasIPRules
                format = .clashIPCIDRMRS
                suffix = "ip"
                if shouldEmit { coveredTypes.formUnion(ipTypes) }
            }
            guard shouldEmit else { continue }

            remoteIndex += 1
            entries.append(.remote(RemoteResource(
                identifier: identifier(for: sourceURL, index: remoteIndex, suffix: suffix),
                url: alternative.url,
                policyName: policyName,
                format: format
            )))
        }

        guard !entries.isEmpty else { return nil }
        entries.append(contentsOf: lines.compactMap { line in
            guard !coveredTypes.contains(ruleType(in: line)) else { return nil }
            return .inline(InlineRule(policyName: policyName, line: line))
        })
        return (entries, remoteIndex)
    }

    /// sing-box source-format v2 can compile the destination matchers used by
    /// ACL4SSR into one binary SRS. The manifest records exactly which source
    /// types were converted; all other lines remain in their original place.
    private func optimizedSingBoxEntries(
        resource: RuleSchemeRuleset.Resource,
        sourceURL: URL,
        lines: [String],
        policyName: String,
        startingRemoteIndex: Int
    ) -> (entries: [Entry], finalRemoteIndex: Int)? {
        guard let alternative = repository.singBoxSRSResource(
            for: resource,
            matching: lines
        ),
              !lines.isEmpty else { return nil }

        let sourceTypes = Set(lines.map(ruleType(in:)))
        let coveredTypes = alternative.coveredRuleTypes.intersection(sourceTypes)
        guard !coveredTypes.isEmpty else { return nil }

        let remoteIndex = startingRemoteIndex + 1
        var entries: [Entry] = [
            .remote(RemoteResource(
                identifier: identifier(for: sourceURL, index: remoteIndex, suffix: "srs"),
                url: alternative.url,
                policyName: policyName,
                format: .singBoxBinarySRS,
                dnsDomainURL: alternative.dnsDomainURL,
                localLines: lines.filter { coveredTypes.contains(ruleType(in: $0)) }
            ))
        ]
        entries.append(contentsOf: lines.compactMap { line in
            guard !coveredTypes.contains(ruleType(in: line)) else { return nil }
            return .inline(InlineRule(policyName: policyName, line: line))
        })
        return (entries, remoteIndex)
    }

    private func providerFormat(_ provider: RuleProviderMetadata?, target: ClientTarget,
                                resource: RuleSchemeRuleset.Resource, lines: [String]) -> NativeFormat? {
        guard target.usesClashFormat, let metadata = provider,
              ["domain", "ipcidr", "domain-text", "ipcidr-text"].contains(metadata.behavior ?? ""),
              !lines.isEmpty else { return nil }
        return repository.isClashProviderYAML(resource) ? .clashProviderYAML : .classicalText
    }

    private func nativeFormat(
        for target: ClientTarget,
        url: URL,
        lines: [String],
        isClashProviderYAML: Bool
    ) -> NativeFormat? {
        switch target {
        case .clashApple, .clashVerge, .clashMac, .flClash, .mihomoParty, .clashMi:
            // Mihomo accepts this Surge domain flag in classical HTTP providers
            // and ignores it, just as for inline domain rules. This preserves
            // ordinary domain matching; it does not enable Surge-style sniffing.
            guard linesAreClassical(lines, allowedTypes: Self.clashRuleTypes, allowExtendedMatching: true) else { return nil }
            return isClashProviderYAML ? .clashProviderYAML : .classicalText
        case .clash:
            // Stash supports classical text providers. Preserve this resource
            // for client validation; do not claim Surge sniffing semantics.
            guard linesAreClassical(lines, allowedTypes: Self.clashRuleTypes, allowExtendedMatching: true) else { return nil }
            return isClashProviderYAML ? .clashProviderYAML : .classicalText
        case .karing:
            guard linesAreClassical(lines, allowedTypes: Self.clashRuleTypes) else { return nil }
            return isClashProviderYAML ? .clashProviderYAML : .classicalText
        case .surge, .surgeMac:
            return !isClashProviderYAML && linesAreClassical(lines, allowedTypes: Self.surgeRuleTypes, allowExtendedMatching: true)
                ? .classicalText
                : nil
        case .shadowrocket:
            // Shadowrocket receives a Clash-compatible YAML profile, so its
            // remote resources use Clash provider syntax. The lines inside
            // still have to stay within Shadowrocket's own rule vocabulary.
            guard linesAreClassical(lines, allowedTypes: Self.shadowrocketRuleTypes) else { return nil }
            return isClashProviderYAML ? .clashProviderYAML : .classicalText
        case .loon:
            return !isClashProviderYAML && linesAreClassical(lines, allowedTypes: Self.loonRuleTypes)
                ? .classicalText
                : nil
        case .quanx:
            return !isClashProviderYAML && linesAreQuanXFilters(lines) ? .quanXFilter : nil
        case .hiddify, .singBox:
            return isSingBoxSource(url: url, lines: lines) ? .singBoxSource : nil
        case .egern:
            return isEgernRuleSet(lines) ? .egernYAML : nil
        case .v2box, .anywhere:
            return nil
        }
    }

    /// Classical remote lists contain only the matcher and its value. A list
    /// that already embeds policies is a complete rule file, not a reusable
    /// rule set, so Tower keeps mapping it locally.
    private func linesAreClassical(
        _ lines: [String],
        allowedTypes: Set<String>,
        allowExtendedMatching: Bool = false
    ) -> Bool {
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { line in
            let parts = fields(in: line)
            guard parts.count >= 2,
                  parts.count <= 3,
                  allowedTypes.contains(parts[0].uppercased()) else { return false }
            guard parts.count == 3 else { return true }
            if parts[2].lowercased() == "no-resolve" { return true }
            // Surge permits this flag inside external rule sets. Do not apply
            // it to the RULE-SET reference or assume other dialects support it.
            return allowExtendedMatching
                && parts[2].lowercased() == "extended-matching"
                && ["DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "URL-REGEX"]
                    .contains(parts[0].uppercased())
        }
    }

    private func linesAreQuanXFilters(_ lines: [String]) -> Bool {
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { line in
            let parts = fields(in: line)
            guard parts.count >= 2,
                  parts.count <= 3,
                  Self.quanXRuleTypes.contains(parts[0].lowercased()) else { return false }
            // Native QuanX filter resources commonly carry their own policy
            // as field three. Tower's `force-policy` overrides it. In contrast,
            // `no-resolve` is a Surge/Clash option that QuanX does not accept;
            // reject that resource so it is normalized through the local path.
            return parts.count == 2
                || (!parts[2].isEmpty && parts[2].lowercased() != "no-resolve")
        }
    }

    private func isSingBoxSource(url: URL, lines: [String]) -> Bool {
        guard url.pathExtension.lowercased() == "json",
              let data = lines.joined(separator: "\n").data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["rules"] is [[String: Any]] else { return false }
        return true
    }

    private func isEgernRuleSet(_ lines: [String]) -> Bool {
        guard !lines.isEmpty else { return false }
        let keys = Set(lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix("-"), trimmed.hasSuffix(":") else { return nil }
            return String(trimmed.dropLast())
        })
        return !keys.isDisjoint(with: Self.egernRuleSetKeys)
            && keys.subtracting(Self.egernRuleSetKeys.union(["no_resolve"])).isEmpty
    }

    private func fields(in line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func ruleType(in line: String) -> String {
        fields(in: line).first?.uppercased() ?? ""
    }

    private func identifier(for url: URL, index: Int, suffix: String? = nil) -> String {
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        var slug = ""
        var lastWasDash = false
        for scalar in base.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash, !slug.isEmpty {
                slug.append("-")
                lastWasDash = true
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "ruleset" }
        if let suffix { slug += "-\(suffix)" }
        return "tower-\(slug)-\(index)"
    }

    private static let clashRuleTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "IP-CIDR", "IP-CIDR6",
        "IP6-CIDR", "GEOIP", "GEOSITE", "SRC-IP-CIDR", "SRC-PORT", "DST-PORT",
        "PROCESS-NAME", "PROCESS-PATH", "PROCESS-PATH-REGEX", "NETWORK"
    ]

    private static let surgeRuleTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-SET", "DOMAIN-WILDCARD",
        "IP-CIDR", "IP-CIDR6", "IP6-CIDR", "IP-ASN", "GEOIP", "PROCESS-NAME",
        "USER-AGENT", "URL-REGEX", "DEST-PORT", "SRC-IP", "SRC-PORT", "IN-PORT",
        "PROTOCOL", "SUBNET"
    ]

    /// Loon's remote rule lists (nsloon.app/docs/Rule/sub_rule).
    private static let loonRuleTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "IP-CIDR", "IP-CIDR6",
        "GEOIP", "IP-ASN", "USER-AGENT", "URL-REGEX"
    ]

    /// Shadowrocket's documented rule types, without its logical rules.
    private static let shadowrocketRuleTypes: Set<String> = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD", "DOMAIN-WILDCARD", "USER-AGENT",
        "URL-REGEX", "IP-CIDR", "IP-CIDR6", "IP-ASN", "GEOIP", "DST-PORT"
    ]

    private static let quanXRuleTypes: Set<String> = [
        "host", "host-suffix", "host-keyword", "host-wildcard",
        "ip-cidr", "ip6-cidr", "geoip", "ip-asn", "user-agent"
    ]

    private static let egernRuleSetKeys: Set<String> = [
        "domain_set", "domain_keyword_set", "domain_suffix_set", "domain_regex_set",
        "domain_wildcard_set", "geoip_set", "ip_cidr_set", "ip_cidr6_set",
        "url_regex_set", "asn_set", "user_agent_set", "ssid_set", "bssid_set",
        "cellular_set", "protocol_set", "dest_port_set", "and_set", "or_set", "not_set"
    ]
}
