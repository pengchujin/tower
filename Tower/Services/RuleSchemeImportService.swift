import Foundation

enum RuleImportError: LocalizedError, Equatable {
    case invalidURL
    case insecureURL
    case badResponse
    case httpStatus(Int)
    case emptyBody
    case noRulesetsDownloaded
    case receivedWebPage
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: String(localized: "配置文件过大，请使用不超过 8 MB 的文本配置。")
        case .invalidURL: String(localized: "规则地址无效")
        case .insecureURL: String(localized: "请使用 HTTPS 规则地址")
        case .badResponse: String(localized: "服务器返回了无法识别的响应")
        case .httpStatus(let status): String(localized: "服务器返回 HTTP \(status)")
        case .emptyBody: String(localized: "规则内容为空")
        case .noRulesetsDownloaded: String(localized: "配置里引用的规则列表都没有下载成功")
        case .receivedWebPage: String(localized: "这个地址返回的是网页，不是配置文件。请使用规则文件本身的地址。")
        }
    }
}

/// Progress carries only display-safe source names, never URL credentials or query strings.
struct RuleImportProgress: Sendable, Equatable {
    enum Stage: Sendable { case configuration, parsing, rules }
    let stage: Stage
    var completed = 0
    var total = 0
    var sources: [String] = []

    var title: String {
        switch stage {
        case .configuration: String(localized: "正在下载配置…")
        case .parsing: String(localized: "正在解析配置…")
        case .rules: String(localized: "正在下载引用的规则（\(completed)/\(total)）")
        }
    }
}

typealias RuleImportProgressHandler = @MainActor @Sendable (RuleImportProgress) -> Void

struct RuleImportDownloadFailure: Sendable, Equatable {
    let url: URL
    let reason: String

    static func sourceName(_ url: URL) -> String {
        // Mirrors embed a second URL in their path; show the actual file's basename.
        let filename = url.lastPathComponent
        return [url.host ?? "", filename].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct RuleImportDownloadError: LocalizedError, Sendable {
    let failures: [RuleImportDownloadFailure]
    var isRulesetFailure = true
    var errorDescription: String? {
        let detail = failures.map { "\(RuleImportDownloadFailure.sourceName($0.url))：\($0.reason)" }.joined(separator: "\n")
        return String(localized: "下载未完成，尚未导入。") + "\n" + detail
    }
    var retryableMirrorURLs: Set<URL> {
        guard isRulesetFailure else { return [] }
        return Set(failures.map(\.url).filter { RuleSchemeImportService.originalGitHubURL(for: $0) != nil })
    }
}

struct RuleImportResult {
    let scheme: RuleScheme
    /// Successful imports have no missing lists. Kept for existing callers.
    let failedRulesetCount: Int
}

/// Downloads a supported rule config and every rule list it references,
/// storing the lists locally so the scheme works offline afterwards.
struct RuleSchemeImportService {
    private let store: RuleDownloadStore
    private let parser = RuleSchemeParser()
    private let session: URLSession
    private static let batchSize = 6

    init(store: RuleDownloadStore = RuleDownloadStore(), session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    static func defaultName(for url: URL) -> String {
        let fileURL = rawFileURL(for: url)
        let filename = fileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fileURL.hasDirectoryPath, !filename.isEmpty, filename != "/" { return filename }
        return fileURL.host ?? String(localized: "导入的规则")
    }

    func importScheme(from urlString: String, name: String, originalRulesetURLs: Set<URL> = [], progress: RuleImportProgressHandler? = nil) async throws -> RuleImportResult {
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

        let generation = store.writeGeneration
        try Task.checkCancellation()
        await progress?(RuleImportProgress(stage: .configuration, sources: [RuleImportDownloadFailure.sourceName(url)]))
        let payload: Data
        do { payload = try await fetch(url) }
        catch {
            try Task.checkCancellation()
            throw RuleImportDownloadError(failures: [downloadFailure(url, error: error)], isRulesetFailure: false)
        }
        await progress?(RuleImportProgress(stage: .parsing))
        guard !Self.looksLikeWebPage(payload) else {
            throw RuleImportError.receivedWebPage
        }
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var scheme = try parser.parse(
            data: payload,
            id: "imported-\(UUID().uuidString)",
            name: resolvedName.isEmpty ? Self.defaultName(for: url) : resolvedName,
            summary: String(localized: "从 \(url.host ?? trimmed) 导入"),
            sourceURLString: trimmed,
            isBundled: false,
            useSelectedNodes: true
        )
        if scheme.groups.contains(where: { $0.sourceFormat == "clash" }) {
            scheme = persistableRuleTemplate(scheme)
        }

        scheme = replacingMirrors(in: scheme, urls: originalRulesetURLs)
        try await downloadRequiredRulesets(scheme.remoteRulesetURLs, generation: generation, progress: progress)
        return RuleImportResult(scheme: scheme, failedRulesetCount: 0)
    }

    /// Imports a local configuration without retaining node credentials or its file path.
    func importScheme(text: String, name: String, fileName: String? = nil, originalRulesetURLs: Set<URL> = [], progress: RuleImportProgressHandler? = nil) async throws -> RuleImportResult {
        try Task.checkCancellation()
        guard text.utf8.count <= Self.maximumLocalBytes else { throw RuleImportError.fileTooLarge }
        let content = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RuleImportError.emptyBody }
        guard !Self.looksLikeWebPage(Data(content.prefix(1_024).utf8)) else { throw RuleImportError.receivedWebPage }
        let generation = store.writeGeneration
        await progress?(RuleImportProgress(stage: .parsing))
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = fileName.map { URL(fileURLWithPath: $0).lastPathComponent }
        var scheme = try parser.parse(text: content, id: "imported-\(UUID().uuidString)",
            name: title.isEmpty ? (filename ?? String(localized: "导入的规则")) : title,
            summary: String(localized: "从本地配置导入"), useSelectedNodes: true)
        scheme = persistableRuleTemplate(scheme)
        scheme = replacingMirrors(in: scheme, urls: originalRulesetURLs)
        try await downloadRequiredRulesets(scheme.remoteRulesetURLs, generation: generation, progress: progress)
        return RuleImportResult(scheme: scheme, failedRulesetCount: 0)
    }

    /// Only a known mirror wrapping an HTTPS GitHub file is eligible. No arbitrary
    /// nested URLs, credentials or extra query parameters are forwarded to another host.
    static func originalGitHubURL(for url: URL) -> URL? {
        guard url.scheme == "https", url.host?.lowercased() == "ghp.ci",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/https://"),
              let original = URL(string: String(url.path.dropFirst())),
              original.scheme == "https", original.user == nil, original.password == nil,
              original.port == nil, original.query == nil, original.fragment == nil,
              ["raw.githubusercontent.com", "gist.githubusercontent.com"].contains(original.host?.lowercased() ?? ""),
              original.pathComponents.count >= 4 else { return nil }
        return original
    }

    private func replacingMirrors(in original: RuleScheme, urls: Set<URL>) -> RuleScheme {
        guard !urls.isEmpty else { return original }
        var scheme = original
        scheme.rulesets = scheme.rulesets.map { ruleset in
            guard let url = ruleset.resource.downloadURL, urls.contains(url),
                  let replacement = Self.originalGitHubURL(for: url) else { return ruleset }
            let resource: RuleSchemeRuleset.Resource
            switch ruleset.resource {
            case .remote: resource = .remote(replacement)
            case .inline(let line):
                var fields = line.components(separatedBy: ",")
                fields[1] = replacement.absoluteString
                resource = .inline(fields.joined(separator: ","))
            }
            return RuleSchemeRuleset(groupName: ruleset.groupName, resource: resource,
                options: ruleset.options, provider: ruleset.provider)
        }
        // Reopening, refreshing and exporting must use the same successful address.
        return persistableRuleTemplate(scheme)
    }

    private func downloadFailure(_ url: URL, error: Error) -> RuleImportDownloadFailure {
        let reason = (error as? URLError)?.code == .timedOut
            ? String(localized: "连接超时，请检查网络或重试。")
            : error.localizedDescription
        return RuleImportDownloadFailure(url: url, reason: reason)
    }

    private func downloadRequiredRulesets(_ urls: [URL], generation: UUID, progress: RuleImportProgressHandler?) async throws {
        var failures: [RuleImportDownloadFailure] = []
        var completed = 0
        for start in stride(from: 0, to: urls.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = Array(urls[start..<min(start + Self.batchSize, urls.count)])
            var pending = batch
            await progress?(RuleImportProgress(stage: .rules, completed: completed, total: urls.count,
                sources: pending.map(RuleImportDownloadFailure.sourceName)))
            await withTaskGroup(of: (URL, RuleImportDownloadFailure?).self) { group in
                for url in batch {
                    group.addTask {
                        do {
                            let data = try await fetch(url)
                            guard !Self.looksLikeWebPage(data) else { throw RuleImportError.receivedWebPage }
                            guard let content = String(data: data, encoding: .utf8)
                                ?? String(data: data, encoding: .isoLatin1) else { throw RuleSchemeParseError.notReadableText }
                            try Task.checkCancellation()
                            try store.store(content, for: url, generation: generation)
                            return (url, nil)
                        } catch { return (url, downloadFailure(url, error: error)) }
                    }
                }
                for await (url, failure) in group {
                    completed += 1
                    pending.removeAll { $0 == url }
                    if let failure { failures.append(failure) }
                    if !Task.isCancelled {
                        await progress?(RuleImportProgress(stage: .rules, completed: completed, total: urls.count,
                            sources: pending.map(RuleImportDownloadFailure.sourceName)))
                    }
                }
            }
        }
        try Task.checkCancellation()
        guard failures.isEmpty else {
            // Stable source order even when requests finish in a different order.
            throw RuleImportDownloadError(failures: urls.compactMap { url in failures.first { $0.url == url } })
        }
    }

    private func persistableRuleTemplate(_ parsed: RuleScheme) -> RuleScheme {
        // Both URL and local imports retain the converted graph. Retaining the
        // source YAML would restore subscription bindings when editing it again.
        var scheme = parsed
        scheme.rawConfigurationText = nil
        let canonical = RuleSchemeTextEditorService().editableText(for: scheme)
        scheme.rawConfigurationText = RuleSchemeSourceSanitizer.persistableText(canonical)
        return scheme
    }

    static let maximumLocalBytes = 8 * 1_024 * 1_024

    /// Security-scoped access ends immediately after reading; no file bookmark is stored.
    static func readConfigurationFile(at url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumLocalBytes {
            let chunk = try handle.read(upToCount: min(64 * 1_024, maximumLocalBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= maximumLocalBytes else { throw RuleImportError.fileTooLarge }
        guard !data.isEmpty else { throw RuleImportError.emptyBody }
        let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        guard let text = String(data: data, encoding: hasUTF16BOM ? .utf16 : .utf8),
              !text.contains("\0") else { throw RuleSchemeParseError.notReadableText }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
    }

    /// Re-fetches the lists an already-imported scheme references.
    func refreshRulesets(for scheme: RuleScheme) async -> Int {
        await downloadRulesets(scheme.remoteRulesetURLs)
    }

    /// Downloads an explicit set of maintained lists into Tower's offline
    /// cache. Catalog entries use this without pretending they are complete
    /// imported schemes.
    func cacheRulesets(_ urls: [URL]) async -> Int {
        await downloadRulesets(urls)
    }

    /// Returns how many lists failed. Batched for the same reason the latency
    /// probes are: a config can reference dozens of files.
    private func downloadRulesets(_ urls: [URL], generation: UUID? = nil) async -> Int {
        let generation = generation ?? store.writeGeneration
        var failed = 0
        for start in stride(from: 0, to: urls.count, by: Self.batchSize) {
            if Task.isCancelled { return failed + (urls.count - start) }
            let end = min(start + Self.batchSize, urls.count)
            let batch = Array(urls[start ..< end])

            await withTaskGroup(of: Bool.self) { group in
                for url in batch {
                    group.addTask { await download(url, generation: generation) }
                }
                for await succeeded in group where !succeeded {
                    failed += 1
                }
            }
        }
        return failed
    }

    private func download(_ url: URL, generation: UUID) async -> Bool {
        guard let payload = try? await fetch(url),
              let content = String(data: payload, encoding: .utf8)
                ?? String(data: payload, encoding: .isoLatin1) else {
            return false
        }
        do {
            try Task.checkCancellation()
            try store.store(content, for: url, generation: generation)
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
