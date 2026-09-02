import CryptoKit
import Darwin
import Foundation

/// Loads the ACL4SSR schemes shipped in the app bundle and resolves the rule
/// lines a scheme references, whether those come from the bundled snapshot or
/// from a list the user downloaded.
struct RuleSchemeRepository {
    struct ClashMRSResource: Equatable {
        enum Behavior: String {
            case domain
            case ipcidr
        }

        let behavior: Behavior
        let url: URL
    }

    struct SingBoxSRSResource: Equatable {
        let url: URL
        let coveredRuleTypes: Set<String>
    }

    /// Stable prefix used by `Scripts/update_acl4ssr_rules.py` after Xcode
    /// flattens the snapshot into the bundle resource directory.
    static let resourcePrefix = "ACL4SSR_"

    private let bundle: Bundle
    private let downloadStore: RuleDownloadStore?
    private let clashMRSResourcesOverride: [String: [ClashMRSResource]]?
    private let singBoxSRSResourcesOverride: [String: SingBoxSRSResource]?

    init(
        bundle: Bundle = .main,
        downloadStore: RuleDownloadStore? = nil,
        clashMRSResources: [URL: [ClashMRSResource]]? = nil,
        singBoxSRSResources: [URL: SingBoxSRSResource]? = nil
    ) {
        self.bundle = bundle
        self.downloadStore = downloadStore
        clashMRSResourcesOverride = clashMRSResources?.reduce(into: [:]) { result, item in
            result[item.key.absoluteString] = item.value
        }
        singBoxSRSResourcesOverride = singBoxSRSResources?.reduce(into: [:]) { result, item in
            result[item.key.absoluteString] = item.value
        }
    }

    func bundledSchemes() -> [RuleScheme] {
        RuleSchemeSnapshotCache.shared.schemes(in: bundle)
    }

    /// Rule lines for one ruleset, comments and blank lines already removed.
    func lines(for resource: RuleSchemeRuleset.Resource) -> [String] {
        switch resource {
        case .inline(let rule):
            return [rule]
        case .remote(let url):
            if let downloaded = downloadStore?.lines(for: url) { return downloaded }
            return RuleSchemeSnapshotCache.shared.lines(
                named: Self.bundledResourceName(for: url),
                in: bundle
            )
        }
    }

    /// `payload:` is part of the remote resource contract. Removing it is
    /// useful while mapping rules locally, but a client fetching the original
    /// URL still receives YAML and must support that container explicitly.
    func isClashProviderYAML(_ resource: RuleSchemeRuleset.Resource) -> Bool {
        guard case .remote(let url) = resource else { return false }
        // Answered from the same cached parse as `lines(for:)`, so deciding
        // what a downloaded list *is* no longer costs a second full read of it.
        if let downloaded = downloadStore?.isClashProvider(for: url) { return downloaded }
        guard let content = bundledContent(named: Self.bundledResourceName(for: url)) else {
            return false
        }
        return content.components(separatedBy: .newlines).contains { rawLine in
            rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")) == "payload:"
        }
    }

    /// Binary rule-set alternatives generated from the exact bundled source.
    /// Unknown and user-provided URLs deliberately have no implicit fallback:
    /// declaring arbitrary text as MRS would make the client silently miss rules.
    func clashMRSResources(
        for resource: RuleSchemeRuleset.Resource,
        matching resolvedLines: [String]
    ) -> [ClashMRSResource] {
        guard case .remote(let url) = resource else { return [] }
        if let clashMRSResourcesOverride {
            return clashMRSResourcesOverride[url.absoluteString] ?? []
        }
        guard let verified = RuleSchemeSnapshotCache.shared
            .clashMRSResources(in: bundle)[url.absoluteString],
              verified.sourceRulesSHA256 == RuleSetSourceFingerprint.sha256(for: resolvedLines) else {
            return []
        }
        return verified.resources
    }

    /// A binary sing-box alternative generated from the exact bundled source.
    /// The manifest declares the classical types it covers so the planner can
    /// leave every unsupported or partially converted type inline.
    func singBoxSRSResource(
        for resource: RuleSchemeRuleset.Resource,
        matching resolvedLines: [String]
    ) -> SingBoxSRSResource? {
        guard case .remote(let url) = resource else { return nil }
        if let singBoxSRSResourcesOverride {
            return singBoxSRSResourcesOverride[url.absoluteString]
        }
        guard let verified = RuleSchemeSnapshotCache.shared
            .singBoxSRSResources(in: bundle)[url.absoluteString],
              verified.sourceRulesSHA256 == RuleSetSourceFingerprint.sha256(for: resolvedLines) else {
            return nil
        }
        return verified.resource
    }

    private func bundledContent(named name: String) -> String? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext, subdirectory: "ACL4SSR")
            ?? bundle.url(forResource: base, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Mirrors `local_name()` in the update script so a pinned URL resolves to
    /// the file that was vendored for it.
    static func bundledResourceName(for url: URL) -> String {
        let absolute = url.absoluteString
        guard let marker = absolute.range(of: "/Clash/") else {
            return resourcePrefix + url.lastPathComponent
        }
        let tail = String(absolute[marker.upperBound...])
        return resourcePrefix + tail.replacingOccurrences(of: "/", with: "_")
    }

    static func sanitizedLines(from content: String) -> [String] {
        let rawLines = content.components(separatedBy: .newlines)
        let isClashProvider = rawLines.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "payload:"
        }
        guard isClashProvider else {
            return rawLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") && !$0.hasPrefix("//") }
        }

        var inPayload = false
        return rawLines.compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "payload:" {
                inPayload = true
                return nil
            }
            guard inPayload, line.hasPrefix("- ") else { return nil }
            let value = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard value.count >= 2,
                  let first = value.first,
                  let last = value.last,
                  (first == "\"" || first == "'"),
                  first == last else { return value }
            return String(value.dropFirst().dropLast())
        }
    }
}

/// A binary rule set may replace inline rules only while the rules currently
/// resolved for its source URL are byte-for-byte equivalent after parsing to
/// the bundled source used to compile it. This also covers a downloaded cache
/// that shadows a bundled URL after the upstream list changes.
private enum RuleSetSourceFingerprint {
    static func sha256(for lines: [String]) -> String {
        let canonicalRules = lines.joined(separator: "\n")
        return SHA256.hash(data: Data(canonicalRules.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct VerifiedClashMRSResources {
    let sourceRulesSHA256: String
    let resources: [RuleSchemeRepository.ClashMRSResource]
}

private struct VerifiedSingBoxSRSResource {
    let sourceRulesSHA256: String
    let resource: RuleSchemeRepository.SingBoxSRSResource
}

/// Parsing three configs and reading their lists is not work the launch path
/// should do, so it happens once on first use and is shared afterwards.
private final class RuleSchemeSnapshotCache: @unchecked Sendable {
    static let shared = RuleSchemeSnapshotCache()

    private let lock = NSLock()
    private var schemesByBundle: [String: [RuleScheme]] = [:]
    private var linesByName: [String: [String]] = [:]
    private var clashMRSResourcesByBundle: [String: [String: VerifiedClashMRSResources]] = [:]
    private var singBoxSRSResourcesByBundle: [String: [String: VerifiedSingBoxSRSResource]] = [:]

    func schemes(in bundle: Bundle) -> [RuleScheme] {
        let key = bundle.bundlePath
        lock.lock()
        if let cached = schemesByBundle[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = Self.loadSchemes(from: bundle)

        lock.lock()
        schemesByBundle[key] = loaded
        lock.unlock()
        return loaded
    }

    func lines(named name: String, in bundle: Bundle) -> [String] {
        let key = "\(bundle.bundlePath)::\(name)"
        lock.lock()
        if let cached = linesByName[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = Self.loadLines(named: name, from: bundle)

        lock.lock()
        linesByName[key] = loaded
        lock.unlock()
        return loaded
    }

    func clashMRSResources(
        in bundle: Bundle
    ) -> [String: VerifiedClashMRSResources] {
        let key = bundle.bundlePath
        lock.lock()
        if let cached = clashMRSResourcesByBundle[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = Self.loadClashMRSResources(from: bundle)

        lock.lock()
        clashMRSResourcesByBundle[key] = loaded
        lock.unlock()
        return loaded
    }

    func singBoxSRSResources(
        in bundle: Bundle
    ) -> [String: VerifiedSingBoxSRSResource] {
        let key = bundle.bundlePath
        lock.lock()
        if let cached = singBoxSRSResourcesByBundle[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = Self.loadSingBoxSRSResources(from: bundle)

        lock.lock()
        singBoxSRSResourcesByBundle[key] = loaded
        lock.unlock()
        return loaded
    }

    private static func loadLines(named name: String, from bundle: Bundle) -> [String] {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext, subdirectory: "ACL4SSR")
            ?? bundle.url(forResource: base, withExtension: ext),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return RuleSchemeRepository.sanitizedLines(from: content)
    }

    private static func loadSchemes(from bundle: Bundle) -> [RuleScheme] {
        guard let manifestURL = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "ACL4SSR")
            ?? acl4ssrManifestURL(in: bundle),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configs = manifest["configs"] as? [String: [String: Any]] else {
            return []
        }

        let parser = RuleSchemeParser()
        return configs.keys.sorted().compactMap { id -> RuleScheme? in
            guard let entry = configs[id],
                  let file = entry["file"] as? String,
                  let name = entry["name"] as? String,
                  let summary = entry["summary"] as? String else { return nil }

            let base = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            guard let url = bundle.url(forResource: base, withExtension: ext, subdirectory: "ACL4SSR")
                ?? bundle.url(forResource: base, withExtension: ext),
                  let payload = try? Data(contentsOf: url) else { return nil }

            return try? parser.parse(
                data: payload,
                id: id,
                name: String(localized: String.LocalizationValue(name)),
                summary: String(localized: String.LocalizationValue(summary)),
                sourceURLString: entry["source"] as? String,
                isBundled: true
            )
        }
    }

    private static func loadClashMRSResources(
        from bundle: Bundle
    ) -> [String: VerifiedClashMRSResources] {
        guard let manifest = loadBinaryRulesetManifest(from: bundle) else {
            return [:]
        }

        var result: [String: VerifiedClashMRSResources] = [:]
        for (filename, entry) in manifest.rulesets {
            guard let source = entry["source"] as? String,
                  let sourceSHA256 = entry["sha256"] as? String,
                  bundledSHA256(named: filename, in: bundle) == sourceSHA256.lowercased(),
                  let sourceRuleCount = entry["ruleCount"] as? Int,
                  let sourceAnalysis = analyzeBundledClassicalRules(
                    named: filename,
                    in: bundle
                  ),
                  sourceAnalysis.totalRuleCount == sourceRuleCount,
                  let mrs = entry["mrs"] as? [String: Any] else { continue }

            var resources: [RuleSchemeRepository.ClashMRSResource] = []
            for behavior in [
                RuleSchemeRepository.ClashMRSResource.Behavior.domain,
                .ipcidr
            ] {
                guard let metadata = mrs[behavior.rawValue] as? [String: Any],
                      metadata["sourceSha256"] as? String == sourceSHA256,
                      let compilerVersion = metadata["compilerVersion"] as? String,
                      !compilerVersion.isEmpty,
                      let ruleCount = metadata["ruleCount"] as? Int,
                      ruleCount > 0,
                      let inputRuleCount = metadata["inputRuleCount"] as? Int,
                      inputRuleCount == sourceAnalysis.mrsInputRuleCount(for: behavior),
                      ruleCount <= inputRuleCount,
                      let artifactSHA256 = metadata["sha256"] as? String,
                      artifactSHA256.count == 64,
                      artifactSHA256.allSatisfy({ $0.isHexDigit }),
                      let urlString = metadata["url"] as? String,
                      let url = URL(string: urlString),
                      isValidRemoteArtifactURL(
                        url,
                        revision: manifest.revision,
                        artifactCommit: manifest.artifactCommit,
                        filename: "\((filename as NSString).deletingPathExtension)_\(behavior.rawValue).mrs"
                      ) else { continue }
                if behavior == .ipcidr,
                   metadata["noResolve"] as? Bool != true { continue }
                resources.append(.init(behavior: behavior, url: url))
            }
            let coveredSourceRuleCount = resources.reduce(into: 0) { count, resource in
                count += sourceAnalysis.mrsSourceRuleCount(for: resource.behavior)
            }
            guard !resources.isEmpty,
                  entry["mrsResidualRuleCount"] as? Int
                    == sourceAnalysis.totalRuleCount - coveredSourceRuleCount else { continue }
            result[source] = VerifiedClashMRSResources(
                sourceRulesSHA256: sourceAnalysis.sourceRulesSHA256,
                resources: resources
            )
        }
        return result
    }

    private static func loadSingBoxSRSResources(
        from bundle: Bundle
    ) -> [String: VerifiedSingBoxSRSResource] {
        guard let manifest = loadBinaryRulesetManifest(from: bundle) else {
            return [:]
        }

        let supportedTypes: Set<String> = [
            "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD",
            "IP-CIDR", "IP-CIDR6", "IP6-CIDR"
        ]
        var result: [String: VerifiedSingBoxSRSResource] = [:]
        for (filename, entry) in manifest.rulesets {
            guard let source = entry["source"] as? String,
                  let sourceSHA256 = entry["sha256"] as? String,
                  bundledSHA256(named: filename, in: bundle) == sourceSHA256.lowercased(),
                  let sourceRuleCount = entry["ruleCount"] as? Int,
                  let sourceAnalysis = analyzeBundledClassicalRules(
                    named: filename,
                    in: bundle
                  ),
                  sourceAnalysis.totalRuleCount == sourceRuleCount,
                  let metadata = entry["srs"] as? [String: Any],
                  metadata["sourceSha256"] as? String == sourceSHA256,
                  metadata["sourceFormatVersion"] as? Int == 2,
                  let inputRuleCount = metadata["inputRuleCount"] as? Int,
                  inputRuleCount > 0,
                  let residualRuleCount = metadata["residualRuleCount"] as? Int,
                  residualRuleCount >= 0,
                  inputRuleCount + residualRuleCount == sourceRuleCount,
                  let compilerVersion = metadata["compilerVersion"] as? String,
                  !compilerVersion.isEmpty,
                  let coveredValues = metadata["coveredRuleTypes"] as? [String],
                  !coveredValues.isEmpty,
                  Set(coveredValues).count == coveredValues.count,
                  let artifactSHA256 = metadata["sha256"] as? String,
                  artifactSHA256.count == 64,
                  artifactSHA256.allSatisfy({ $0.isHexDigit }),
                  let urlString = metadata["url"] as? String,
                  let url = URL(string: urlString),
                  isValidRemoteArtifactURL(
                    url,
                    revision: manifest.revision,
                    artifactCommit: manifest.artifactCommit,
                    filename: "\((filename as NSString).deletingPathExtension)_singbox.srs"
                  ) else { continue }

            let coveredTypes = Set(coveredValues.map { $0.uppercased() })
            guard coveredTypes.count == coveredValues.count,
                  coveredTypes.isSubset(of: supportedTypes),
                  coveredTypes == sourceAnalysis.srsCoveredRuleTypes,
                  inputRuleCount == sourceAnalysis.srsInputRuleCount,
                  residualRuleCount == sourceAnalysis.srsResidualRuleCount else { continue }
            result[source] = VerifiedSingBoxSRSResource(
                sourceRulesSHA256: sourceAnalysis.sourceRulesSHA256,
                resource: .init(url: url, coveredRuleTypes: coveredTypes)
            )
        }
        return result
    }

    /// Re-derives the manifest's coverage claims from the exact bundled text.
    /// The planner removes inline rules only after this independent check, so
    /// a stale or hand-edited count/type declaration fails closed.
    private static func analyzeBundledClassicalRules(
        named filename: String,
        in bundle: Bundle
    ) -> BundledClassicalRuleAnalysis? {
        let lines = loadLines(named: filename, from: bundle)
        guard !lines.isEmpty else { return nil }
        return BundledClassicalRuleAnalysis(lines: lines)
    }

    private static func bundledSHA256(named filename: String, in bundle: Bundle) -> String? {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        guard let url = bundle.url(forResource: base, withExtension: ext, subdirectory: "ACL4SSR")
            ?? bundle.url(forResource: base, withExtension: ext),
              let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Binary rules are enabled only by a release manifest bound to the exact
    /// immutable Tower commit that contains them. A staging manifest points at
    /// `main` and intentionally falls back to the bundled text rules at runtime.
    private static func loadBinaryRulesetManifest(
        from bundle: Bundle
    ) -> (
        revision: String,
        artifactCommit: String,
        rulesets: [String: [String: Any]]
    )? {
        guard let manifestURL = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "ACL4SSR"
        ) ?? acl4ssrManifestURL(in: bundle),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let revision = manifest["revision"] as? String,
              isLowercaseGitCommit(revision),
              let artifactCommit = manifest["artifactCommit"] as? String,
              isLowercaseGitCommit(artifactCommit),
              let rulesets = manifest["rulesets"] as? [String: [String: Any]] else {
            return nil
        }
        return (revision, artifactCommit, rulesets)
    }

    private static func isLowercaseGitCommit(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }

    private static func isValidRemoteArtifactURL(
        _ url: URL,
        revision: String,
        artifactCommit: String,
        filename: String
    ) -> Bool {
        url.absoluteString == "https://raw.githubusercontent.com/pengchujin/tower/"
            + "\(artifactCommit)/Rulesets/ACL4SSR/\(revision)/\(filename)"
    }

    /// The updater writes a prefixed manifest so it remains unambiguous after
    /// Xcode flattens resources into the application bundle.
    private static func acl4ssrManifestURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "\(RuleSchemeRepository.resourcePrefix)manifest", withExtension: "json")
    }
}

private struct BundledClassicalRuleAnalysis {
    private static let srsTypeOrder = [
        "DOMAIN", "DOMAIN-SUFFIX", "DOMAIN-KEYWORD",
        "IP-CIDR", "IP-CIDR6", "IP6-CIDR"
    ]
    private static let ipTypes: Set<String> = ["IP-CIDR", "IP-CIDR6", "IP6-CIDR"]

    let totalRuleCount: Int
    let sourceRulesSHA256: String
    let mrsDomainInputRuleCount: Int?
    let mrsIPCIDRInputRuleCount: Int?
    let mrsDomainSourceRuleCount: Int
    let mrsIPCIDRSourceRuleCount: Int
    let srsCoveredRuleTypes: Set<String>
    let srsInputRuleCount: Int
    let srsResidualRuleCount: Int

    init(lines: [String]) {
        totalRuleCount = lines.count
        sourceRulesSHA256 = RuleSetSourceFingerprint.sha256(for: lines)

        var mrsDomainValues: Set<String> = []
        var mrsIPValues: Set<String> = []
        var domainSourceCount = 0
        var ipSourceCount = 0
        var domainComplete = true
        var ipComplete = true

        var srsCounts: [String: Int] = [:]
        var srsComplete = Dictionary(
            uniqueKeysWithValues: Self.srsTypeOrder.map { ($0, true) }
        )

        for line in lines {
            let fields = line.split(
                separator: ",",
                omittingEmptySubsequences: false
            ).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let rawType = fields.first else { continue }
            let ruleType = rawType.uppercased()

            switch ruleType {
            case "DOMAIN", "DOMAIN-SUFFIX":
                domainSourceCount += 1
                guard fields.count == 2, !fields[1].isEmpty else {
                    domainComplete = false
                    break
                }
                if ruleType == "DOMAIN-SUFFIX",
                   fields[1].hasPrefix(".") || fields[1].hasPrefix("+.") {
                    domainComplete = false
                } else {
                    mrsDomainValues.insert(
                        ruleType == "DOMAIN" ? fields[1] : "+.\(fields[1])"
                    )
                }

            case "IP-CIDR", "IP-CIDR6", "IP6-CIDR":
                ipSourceCount += 1
                guard fields.count == 3,
                      fields[2].lowercased() == "no-resolve",
                      let network = Self.canonicalNetwork(fields[1]) else {
                    ipComplete = false
                    break
                }
                mrsIPValues.insert(network)

            default:
                break
            }

            guard Self.srsTypeOrder.contains(ruleType) else { continue }
            srsCounts[ruleType, default: 0] += 1
            guard fields.count >= 2, !fields[1].isEmpty else {
                srsComplete[ruleType] = false
                continue
            }
            if Self.ipTypes.contains(ruleType) {
                if fields.count > 3
                    || (fields.count == 3 && fields[2].lowercased() != "no-resolve")
                    || Self.canonicalNetwork(fields[1]) == nil {
                    srsComplete[ruleType] = false
                }
            } else if fields.count != 2
                || (ruleType == "DOMAIN-SUFFIX"
                    && (fields[1].hasPrefix(".") || fields[1].hasPrefix("+."))) {
                srsComplete[ruleType] = false
            }
        }

        mrsDomainSourceRuleCount = domainSourceCount
        mrsIPCIDRSourceRuleCount = ipSourceCount
        mrsDomainInputRuleCount = domainSourceCount > 0 && domainComplete
            ? mrsDomainValues.count
            : nil
        mrsIPCIDRInputRuleCount = ipSourceCount > 0 && ipComplete
            ? mrsIPValues.count
            : nil

        let completeIPFamily = Self.ipTypes.allSatisfy { srsComplete[$0] == true }
        var coveredTypes: Set<String> = []
        var coveredCount = 0
        for ruleType in Self.srsTypeOrder where srsCounts[ruleType, default: 0] > 0 {
            let isComplete = Self.ipTypes.contains(ruleType)
                ? completeIPFamily
                : srsComplete[ruleType] == true
            if isComplete {
                coveredTypes.insert(ruleType)
                coveredCount += srsCounts[ruleType, default: 0]
            }
        }
        srsCoveredRuleTypes = coveredTypes
        srsInputRuleCount = coveredCount
        srsResidualRuleCount = totalRuleCount - coveredCount
    }

    func mrsInputRuleCount(
        for behavior: RuleSchemeRepository.ClashMRSResource.Behavior
    ) -> Int? {
        switch behavior {
        case .domain: mrsDomainInputRuleCount
        case .ipcidr: mrsIPCIDRInputRuleCount
        }
    }

    func mrsSourceRuleCount(
        for behavior: RuleSchemeRepository.ClashMRSResource.Behavior
    ) -> Int {
        switch behavior {
        case .domain: mrsDomainSourceRuleCount
        case .ipcidr: mrsIPCIDRSourceRuleCount
        }
    }

    private static func canonicalNetwork(_ value: String) -> String? {
        let components = value.split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard components.count <= 2, !components[0].isEmpty else { return nil }
        let address = String(components[0])

        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 {
            let prefix = components.count == 2 ? Int(components[1]) : 32
            guard let prefix, (0...32).contains(prefix) else { return nil }
            var bytes = withUnsafeBytes(of: &ipv4) { Array($0) }
            applyNetworkMask(prefix: prefix, to: &bytes)
            return bytes.map(String.init).joined(separator: ".") + "/\(prefix)"
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, address, &ipv6) == 1 {
            let prefix = components.count == 2 ? Int(components[1]) : 128
            guard let prefix, (0...128).contains(prefix) else { return nil }
            var bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            applyNetworkMask(prefix: prefix, to: &bytes)
            var masked = in6_addr()
            withUnsafeMutableBytes(of: &masked) { buffer in
                buffer.copyBytes(from: bytes)
            }
            var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &masked, &output, socklen_t(output.count)) != nil else {
                return nil
            }
            return String(cString: output) + "/\(prefix)"
        }
        return nil
    }

    private static func applyNetworkMask(prefix: Int, to bytes: inout [UInt8]) {
        for index in bytes.indices {
            let remaining = prefix - (index * 8)
            if remaining >= 8 { continue }
            if remaining <= 0 {
                bytes[index] = 0
            } else {
                bytes[index] &= UInt8(truncatingIfNeeded: 0xFF << (8 - remaining))
            }
        }
    }
}
