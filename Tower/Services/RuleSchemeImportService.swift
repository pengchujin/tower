import Foundation

enum RuleImportError: LocalizedError, Equatable {
    case invalidURL
    case insecureURL
    case badResponse
    case httpStatus(Int)
    case emptyBody
    case noRulesetsDownloaded
    case receivedWebPage

    var errorDescription: String? {
        switch self {
        case .invalidURL: "规则地址无效"
        case .insecureURL: "请使用 HTTPS 规则地址"
        case .badResponse: "服务器返回了无法识别的响应"
        case .httpStatus(let status): "服务器返回 HTTP \(status)"
        case .emptyBody: "规则内容为空"
        case .noRulesetsDownloaded: "配置里引用的规则列表都没有下载成功"
        case .receivedWebPage: "这个地址返回的是网页，不是配置文件。请使用规则文件本身的地址。"
        }
    }
}

struct RuleImportResult {
    let scheme: RuleScheme
    /// Lists that could not be fetched. The scheme is still usable; these
    /// simply contribute no rules, and the count is surfaced to the user rather
    /// than hidden.
    let failedRulesetCount: Int
}

/// Downloads a subconverter-style `.ini` config and every rule list it
/// references, storing the lists locally so the scheme works offline afterwards.
struct RuleSchemeImportService {
    private let store: RuleDownloadStore
    private let parser = RuleSchemeParser()
    private let session: URLSession
    private static let batchSize = 6

    init(store: RuleDownloadStore = RuleDownloadStore(), session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    func importScheme(from urlString: String, name: String) async throws -> RuleImportResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entered = URL(string: trimmed), entered.host != nil else {
            throw RuleImportError.invalidURL
        }
        guard entered.scheme?.lowercased() == "https" else {
            throw RuleImportError.insecureURL
        }
        // People naturally copy the page URL out of the browser address bar.
        // That address serves HTML, so it is rewritten to the raw file instead
        // of failing with a confusing "no policy groups" error.
        let url = Self.rawFileURL(for: entered)

        let payload = try await fetch(url)
        guard !Self.looksLikeWebPage(payload) else {
            throw RuleImportError.receivedWebPage
        }
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = try parser.parse(
            data: payload,
            id: "imported-\(UUID().uuidString)",
            name: resolvedName.isEmpty ? (url.host ?? "导入的规则") : resolvedName,
            summary: "从 \(url.host ?? trimmed) 导入",
            sourceURLString: trimmed,
            isBundled: false
        )

        let failed = await downloadRulesets(scheme.remoteRulesetURLs)
        guard failed < scheme.remoteRulesetURLs.count || scheme.remoteRulesetURLs.isEmpty else {
            throw RuleImportError.noRulesetsDownloaded
        }
        return RuleImportResult(scheme: scheme, failedRulesetCount: failed)
    }

    /// Re-fetches the lists an already-imported scheme references.
    func refreshRulesets(for scheme: RuleScheme) async -> Int {
        await downloadRulesets(scheme.remoteRulesetURLs)
    }

    /// Returns how many lists failed. Batched for the same reason the latency
    /// probes are: a config can reference dozens of files.
    private func downloadRulesets(_ urls: [URL]) async -> Int {
        var failed = 0
        for start in stride(from: 0, to: urls.count, by: Self.batchSize) {
            if Task.isCancelled { return failed + (urls.count - start) }
            let end = min(start + Self.batchSize, urls.count)
            let batch = Array(urls[start ..< end])

            await withTaskGroup(of: Bool.self) { group in
                for url in batch {
                    group.addTask { await download(url) }
                }
                for await succeeded in group where !succeeded {
                    failed += 1
                }
            }
        }
        return failed
    }

    private func download(_ url: URL) async -> Bool {
        guard let payload = try? await fetch(url),
              let content = String(data: payload, encoding: .utf8)
                ?? String(data: payload, encoding: .isoLatin1) else {
            return false
        }
        do {
            try store.store(content, for: url)
            return true
        } catch {
            return false
        }
    }

    /// Rewrites the browser-facing URL of a hosted file to the address that
    /// serves its raw bytes. Anything unrecognised is returned unchanged.
    static func rawFileURL(for url: URL) -> URL {
        let text = url.absoluteString
        guard let host = url.host?.lowercased() else { return url }

        if host == "github.com" || host == "www.github.com" {
            // https://github.com/<owner>/<repo>/blob/<ref>/<path>
            //   -> https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>
            for marker in ["/blob/", "/raw/"] {
                if let range = text.range(of: marker) {
                    let prefix = text[text.startIndex ..< range.lowerBound]
                    let repoPath = prefix.replacingOccurrences(
                        of: "https://www.github.com/",
                        with: ""
                    ).replacingOccurrences(of: "https://github.com/", with: "")
                    let tail = text[range.upperBound...]
                    if let rewritten = URL(string: "https://raw.githubusercontent.com/\(repoPath)/\(tail)") {
                        return rewritten
                    }
                }
            }
            return url
        }

        // GitLab and Gitee both serve raw bytes from the same path with
        // "blob" swapped for "raw".
        if host.hasSuffix("gitlab.com"), let range = text.range(of: "/-/blob/") {
            let rewritten = text.replacingCharacters(in: range, with: "/-/raw/")
            return URL(string: rewritten) ?? url
        }
        if host.hasSuffix("gitee.com"), let range = text.range(of: "/blob/") {
            let rewritten = text.replacingCharacters(in: range, with: "/raw/")
            return URL(string: rewritten) ?? url
        }

        return url
    }

    /// A hosted page returns HTML rather than the config, which would otherwise
    /// surface as a parse error that says nothing about the real mistake.
    static func looksLikeWebPage(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(1_024), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return false }
        return head.hasPrefix("<!doctype html") || head.hasPrefix("<html")
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Tower/1.0 (iOS; local rule importer)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RuleImportError.badResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw RuleImportError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw RuleImportError.emptyBody }
        return data
    }
}
