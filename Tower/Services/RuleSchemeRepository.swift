import Foundation

/// Loads the ACL4SSR schemes shipped in the app bundle and resolves the rule
/// lines a scheme references, whether those come from the bundled snapshot or
/// from a list the user downloaded.
struct RuleSchemeRepository {
    /// Stable prefix used by `Scripts/update_acl4ssr_rules.py` after Xcode
    /// flattens the snapshot into the bundle resource directory.
    static let resourcePrefix = "ACL4SSR_"

    private let bundle: Bundle
    private let downloadStore: RuleDownloadStore?

    init(bundle: Bundle = .main, downloadStore: RuleDownloadStore? = nil) {
        self.bundle = bundle
        self.downloadStore = downloadStore
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

/// Parsing three configs and reading their lists is not work the launch path
/// should do, so it happens once on first use and is shared afterwards.
private final class RuleSchemeSnapshotCache: @unchecked Sendable {
    static let shared = RuleSchemeSnapshotCache()

    private let lock = NSLock()
    private var schemesByBundle: [String: [RuleScheme]] = [:]
    private var linesByName: [String: [String]] = [:]

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
        lock.lock()
        if let cached = linesByName[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = Self.loadLines(named: name, from: bundle)

        lock.lock()
        linesByName[name] = loaded
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

    /// The updater writes a prefixed manifest so it remains unambiguous after
    /// Xcode flattens resources into the application bundle.
    private static func acl4ssrManifestURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "\(RuleSchemeRepository.resourcePrefix)manifest", withExtension: "json")
    }
}
