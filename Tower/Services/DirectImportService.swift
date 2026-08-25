import Foundation
import Network
import UIKit

enum DirectImportError: LocalizedError, Equatable {
    case unsupportedTarget(ClientTarget)
    case invalidSchemeURL
    case localServerFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedTarget(let target):
            String(localized: "\(target.name) 暂不支持完整配置的一键导入")
        case .invalidSchemeURL:
            String(localized: "无法生成客户端导入链接")
        case .localServerFailed:
            String(localized: "无法启动本机临时导入服务")
        }
    }
}

struct ClientImportURLBuilder {
    static func make(
        target: ClientTarget,
        configurationURL: URL,
        displayName: String = TowerBrand.localizedName,
        contentMode: ExportContentMode = .fullConfiguration,
        importRevision: String = UUID().uuidString
    ) throws -> URL {
        let encodedURL = encode(configurationURL.absoluteString)
        let encodedName = encode(displayName)
        let value: String

        switch target {
        case .surge:
            value = "surge:///install-config?url=\(encodedURL)"
        case .clash:
            value = "stash://install-config?url=\(encodedURL)"
        case .clashApple:
            value = "clashmeta://install-config?url=\(encodedURL)"
        case .shadowrocket:
            value = contentMode == .nodesOnly
                ? "shadowrocket://add/\(configurationURL.absoluteString)#\(displayName)"
                : "shadowrocket://config/add/\(configurationURL.absoluteString)"
        case .loon:
            if contentMode == .nodesOnly {
                var components = URLComponents(url: configurationURL, resolvingAgainstBaseURL: false)
                let existingItems = components?.queryItems ?? []
                components?.queryItems = existingItems + [
                    URLQueryItem(name: "tower-import", value: importRevision)
                ]
                let refreshableURL = components?.url ?? configurationURL
                value = "loon://import?nodelist=\(encode(refreshableURL.absoluteString))"
            } else {
                value = "loon://import?sub=\(encodedURL)"
            }
        // A single slash, not two: Egern's documented form is `egern:/…`, so
        // the path carries no authority component.
        case .egern:
            value = "egern:/profiles/new?url=\(encodedURL)&name=\(encodedName)"
        // Two slashes here, unlike Egern: Hiddify's parser rejects any link
        // with no authority component (`!uri.hasAuthority` returns nil), so the
        // host segment has to be present even though it goes unread.
        case .hiddify:
            // Current Hiddify releases use one import route for v2ray node
            // subscriptions, Clash YAML and sing-box JSON. The title belongs
            // in Profile-Title; a percent-encoded fragment is displayed
            // literally by current Hiddify releases.
            value = "hiddify://import/\(configurationURL.absoluteString)"
        case .v2box:
            guard contentMode == .nodesOnly else {
                throw DirectImportError.unsupportedTarget(target)
            }
            value = "v2box://install-sub?url=\(encodedURL)&name=\(encodedName)"
        case .quanx:
            guard contentMode == .nodesOnly else {
                throw DirectImportError.unsupportedTarget(target)
            }
            let resource: [String: [String]] = [
                "server_remote": ["\(configurationURL.absoluteString), tag=\(displayName), as-policy=static"]
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: resource, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else {
                throw DirectImportError.invalidSchemeURL
            }
            value = "quantumult-x:///add-resource?remote-resource=\(encode(json))"
        }

        guard let url = URL(string: value) else {
            throw DirectImportError.invalidSchemeURL
        }
        return url
    }

    private static func encode(_ value: String) -> String {
        let unreserved = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

enum DirectImportAccessTokenStore {
    private static let key = "direct-import-access-token"

    static func loadOrCreate(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key), existing.count >= 24 {
            return existing
        }
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(token, forKey: key)
        return token
    }
}

@MainActor
final class DirectImportService {
    private var server: LocalConfigurationServer?
    private var expirationTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func prepare(_ configuration: GeneratedConfiguration) async throws -> URL {
        stop()
        guard configuration.target.supportsDirectImport(mode: configuration.contentMode) else {
            throw DirectImportError.unsupportedTarget(configuration.target)
        }

        let server = LocalConfigurationServer(configuration: configuration)
        let localURL = try await server.start()
        self.server = server
        beginBackgroundExecution()

        expirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(45))
            } catch {
                return
            }
            self?.stop()
        }

        do {
            return try ClientImportURLBuilder.make(
                target: configuration.target,
                configurationURL: localURL,
                displayName: configuration.profileName,
                contentMode: configuration.contentMode
            )
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        expirationTask?.cancel()
        expirationTask = nil
        server?.stop()
        server = nil
        endBackgroundExecution()
    }

    private func beginBackgroundExecution() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "TowerDirectImport") { [weak self] in
            Task { @MainActor in
                self?.stop()
            }
        }
    }

    private func endBackgroundExecution() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

final class LocalConfigurationServer: @unchecked Sendable {
    static let fixedLoopbackPort: UInt16 = 65_172

    private let queue = DispatchQueue(label: "com.jzb.tower.direct-import")
    private let body: Data
    private let fileName: String
    private let contentType: String
    private let profileName: String
    private let profileTitle: String
    private let token: String

    /// Exposed for tests: the name and type the client will see.
    var servedFileName: String { fileName }
    var servedContentType: String { contentType }
    /// A stable, app-private endpoint lets clients recognize the next import as
    /// the same Tower profile. The listener still exists for only 45 seconds.
    var configurationURL: URL {
        URL(string: "http://127.0.0.1:\(Self.fixedLoopbackPort)/\(token)")!
            .deletingLastPathComponent()
            .appendingPathComponent(profileName, isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
    private var listener: NWListener?
    private var didResumeStart = false

    init(
        configuration: GeneratedConfiguration,
        token: String = DirectImportAccessTokenStore.loadOrCreate()
    ) {
        body = Data(configuration.content.utf8)
        self.token = token
        // Share sheets and URL-scheme clients receive exactly the same stable,
        // localized profile name instead of creating timestamped duplicates.
        fileName = configuration.fileName
        profileName = configuration.profileName
        profileTitle = "base64:\(Data(configuration.profileName.utf8).base64EncodedString())"
        contentType = switch configuration.fileExtension {
        case "yaml": "application/yaml; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        default: "text/plain; charset=utf-8"
        }
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = .hostPort(
                    host: NWEndpoint.Host("127.0.0.1"),
                    port: NWEndpoint.Port(rawValue: Self.fixedLoopbackPort)!
                )

                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    self?.serve(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !self.didResumeStart, listener.port != nil else { return }
                        self.didResumeStart = true
                        continuation.resume(returning: self.configurationURL)
                    case .failed:
                        guard !self.didResumeStart else { return }
                        self.didResumeStart = true
                        continuation.resume(throwing: DirectImportError.localServerFailed)
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            } catch {
                continuation.resume(throwing: DirectImportError.localServerFailed)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let requestTarget = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let requestPath = requestTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? requestTarget
            let expectedPath = URLComponents(
                url: self.configurationURL,
                resolvingAgainstBaseURL: false
            )?.percentEncodedPath ?? self.configurationURL.path
            let isHead = firstLine.hasPrefix("HEAD ") && requestPath == expectedPath
            let isGet = firstLine.hasPrefix("GET ") && requestPath == expectedPath

            guard isHead || isGet else {
                self.send(
                    Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                    on: connection
                )
                return
            }

            let header = """
            HTTP/1.1 200 OK\r
            Content-Type: \(self.contentType)\r
            Content-Length: \(self.body.count)\r
            Content-Disposition: \(ExportFilePresentation.contentDisposition(fileName: self.fileName))\r
            Profile-Title: \(self.profileTitle)\r
            Cache-Control: no-store\r
            Connection: close\r
            \r

            """
            var response = Data(header.utf8)
            if isGet { response.append(self.body) }
            self.send(response, on: connection)
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
