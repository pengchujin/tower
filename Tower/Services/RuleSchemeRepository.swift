import Foundation

/// Loads the ACL4SSR schemes shipped in the app bundle and resolves the rule
/// lines a scheme references, whether those come from the bundled snapshot or
/// from a list the user downloaded.
struct RuleSchemeRepository {
    /// Prefix used by `Scripts/update_acl4ssr_rules.py`. Bundle resources are
    /// flattened into one directory, so this keeps the ACL4SSR lists from
    /// colliding with the Self-Configuration ones.
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
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") && !$0.hasPrefix("//") }
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
                name: name,
                summary: summary,
                sourceURLString: entry["source"] as? String,
                isBundled: true
            )
        }
    }

    /// The Self-Configuration snapshot ships its own `manifest.json`, and the
    /// flattened bundle keeps only one of them under that name, so the ACL4SSR
    /// manifest is located by the resource prefix instead.
    private static func acl4ssrManifestURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: "\(RuleSchemeRepository.resourcePrefix)manifest", withExtension: "json")
    }
}
