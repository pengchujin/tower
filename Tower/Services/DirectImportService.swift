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
            "\(target.name) 暂不支持完整配置的一键导入"
        case .invalidSchemeURL:
            "无法生成客户端导入链接"
        case .localServerFailed:
            "无法启动本机临时导入服务"
        }
    }
}

struct ClientImportURLBuilder {
    static func make(
        target: ClientTarget,
        configurationURL: URL,
        displayName: String = "塔台"
    ) throws -> URL {
        let encodedURL = encode(configurationURL.absoluteString)
        let encodedName = encode(displayName)
        let value: String

        switch target {
        case .surge:
            value = "surge:///install-config?url=\(encodedURL)"
        case .clash:
            value = "clash://install-config?url=\(encodedURL)&name=\(encodedName)"
        case .shadowrocket:
            value = "shadowrocket://config/add/\(configurationURL.absoluteString)"
        case .loon:
            value = "loon://import?sub=\(encodedURL)"
        // Quantumult X publishes no install scheme, and neither Hiddify nor
        // Egern documents one; those reach the client through the share sheet.
        case .quanx, .hiddify, .egern:
            throw DirectImportError.unsupportedTarget(target)
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

@MainActor
final class DirectImportService {
    private var server: LocalConfigurationServer?
    private var expirationTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func prepare(_ configuration: GeneratedConfiguration) async throws -> URL {
        stop()
        guard configuration.target.supportsDirectConfigurationImport else {
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
                configurationURL: localURL
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
    private let queue = DispatchQueue(label: "com.jzb.tower.direct-import")
    private let body: Data
    private let fileName: String
    private let contentType: String
    private let token = UUID().uuidString.lowercased()
    private var listener: NWListener?
    private var didResumeStart = false

    init(configuration: GeneratedConfiguration) {
        body = Data(configuration.content.utf8)
        fileName = configuration.target == .clash ? "tower.yaml" : "tower.conf"
        contentType = configuration.target == .clash
            ? "application/yaml; charset=utf-8"
            : "text/plain; charset=utf-8"
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = .hostPort(
                    host: NWEndpoint.Host("127.0.0.1"),
                    port: .any
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
                        guard !self.didResumeStart, let port = listener.port else { return }
                        self.didResumeStart = true
                        continuation.resume(
                            returning: URL(string: "http://127.0.0.1:\(port.rawValue)/\(self.token)/\(self.fileName)")!
                        )
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
            let expectedPath = "/\(self.token)/\(self.fileName)"
            let isHead = firstLine.hasPrefix("HEAD \(expectedPath) ")
            let isGet = firstLine.hasPrefix("GET \(expectedPath) ")

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
            Content-Disposition: attachment; filename=\"\(self.fileName)\"\r
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
