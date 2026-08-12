import Darwin
import Foundation
import Network

enum LANSubscriptionRoutingError: LocalizedError, Equatable {
    case unsupportedTarget
    case unknownUserAgent

    var errorDescription: String? {
        switch self {
        case .unsupportedTarget:
            String(localized: "不支持这个 target 参数")
        case .unknownUserAgent:
            String(localized: "无法识别客户端，请在链接末尾指定 target=clash、surge、loon、quanx、shadowrocket、hiddify 或 egern")
        }
    }
}

enum LANSubscriptionServerError: LocalizedError {
    case failedToStart
    case noWiFiAddress

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            String(localized: "局域网订阅服务启动失败")
        case .noWiFiAddress:
            // Says "Wi-Fi or wired" because the same message reaches a Mac on
            // Ethernet, where telling the user to connect Wi-Fi sends them
            // looking for a fault that is not there.
            String(localized: "没有找到局域网地址，请先接入 Wi-Fi 或有线网络")
        }
    }
}

enum LANSubscriptionTargetResolver {
    static func resolve(explicitTarget: String?, userAgent: String?) throws -> ClientTarget {
        let explicit = normalized(explicitTarget)
        if let explicit, !explicit.isEmpty, explicit != "auto" {
            guard let target = explicitTargets[explicit] else {
                throw LANSubscriptionRoutingError.unsupportedTarget
            }
            return target
        }

        let agent = normalized(userAgent) ?? ""
        guard !agent.isEmpty else { throw LANSubscriptionRoutingError.unknownUserAgent }

        // More specific names must be checked before generic engine names.
        if agent.contains("shadowrocket") { return .shadowrocket }
        if agent.contains("quantumult") || agent.contains("quanx") { return .quanx }
        if agent.contains("hiddify") || agent.contains("sing-box") || agent.contains("singbox") { return .hiddify }
        if agent.contains("openclash") || agent.contains("clash") || agent.contains("mihomo") || agent.contains("stash") { return .clash }
        if agent.contains("surge") { return .surge }
        if agent.contains("loon") { return .loon }
        if agent.contains("egern") { return .egern }
        throw LANSubscriptionRoutingError.unknownUserAgent
    }

    private static let explicitTargets: [String: ClientTarget] = [
        "clash": .clash,
        "openclash": .clash,
        "mihomo": .clash,
        "stash": .clash,
        "surge": .surge,
        "shadowrocket": .shadowrocket,
        "shadow-rocket": .shadowrocket,
        "loon": .loon,
        "quanx": .quanx,
        "quantumult": .quanx,
        "quantumult-x": .quanx,
        "quantumultx": .quanx,
        "hiddify": .hiddify,
        "sing-box": .hiddify,
        "singbox": .hiddify,
        "egern": .egern
    ]

    private static func normalized(_ value: String?) -> String? {
        value?
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct LANSubscriptionHTTPResponse: Equatable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    func serialized() -> Data {
        let reason = switch statusCode {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
        var lines = ["HTTP/1.1 \(statusCode) \(reason)"]
        lines.append(contentsOf: headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })
        lines.append("Connection: close")
        lines.append("")
        lines.append("")
        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }
}

enum LANSubscriptionHTTPRouter {
    static func response(
        request: String,
        token: String,
        configuration: (ClientTarget) -> GeneratedConfiguration
    ) -> LANSubscriptionHTTPResponse {
        let lines = request.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return error(status: 400, message: "请求格式无效") }

        let method = parts[0].uppercased()
        guard method == "GET" || method == "HEAD" else {
            return LANSubscriptionHTTPResponse(
                statusCode: 405,
                headers: ["Allow": "GET, HEAD", "Content-Length": "0"],
                body: Data()
            )
        }

        guard let components = URLComponents(string: "http://tower.local\(parts[1])") else {
            return error(status: 400, message: "请求地址无效")
        }
        let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard pathParts.count == 2,
              ["sub", "download"].contains(pathParts[0]),
              pathParts[1] == token else {
            return LANSubscriptionHTTPResponse(
                statusCode: 404,
                headers: ["Content-Length": "0", "Cache-Control": "no-store"],
                body: Data()
            )
        }

        let headers = parseHeaders(lines.dropFirst())
        let explicitTarget = components.queryItems?
            .first(where: { $0.name.lowercased() == "target" })?
            .value ?? "auto"

        let target: ClientTarget
        do {
            target = try LANSubscriptionTargetResolver.resolve(
                explicitTarget: explicitTarget,
                userAgent: headers["user-agent"]
            )
        } catch let error as LANSubscriptionRoutingError {
            return self.error(status: 400, message: error.localizedDescription)
        } catch {
            return self.error(status: 400, message: "无法识别客户端")
        }

        let generated = configuration(target)
        let payload = Data(generated.content.utf8)
        let responseBody = method == "HEAD" ? Data() : payload
        return LANSubscriptionHTTPResponse(
            statusCode: 200,
            headers: [
                "Content-Type": contentType(for: target),
                "Content-Length": String(payload.count),
                "Content-Disposition": ExportFilePresentation.contentDisposition(fileName: generated.fileName),
                "Cache-Control": "no-store",
                "Profile-Update-Interval": "24",
                "X-Tower-Target": target.rawValue
            ],
            body: responseBody
        )
    }

    private static func parseHeaders(_ lines: ArraySlice<String>) -> [String: String] {
        lines.reduce(into: [String: String]()) { result, line in
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return }
            result[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                pair[1].trimmingCharacters(in: .whitespaces)
        }
    }

    private static func contentType(for target: ClientTarget) -> String {
        switch target.fileExtension {
        case "yaml": "application/yaml; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        default: "text/plain; charset=utf-8"
        }
    }

    private static func error(status: Int, message: String) -> LANSubscriptionHTTPResponse {
        let body = Data(message.utf8)
        return LANSubscriptionHTTPResponse(
            statusCode: status,
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": String(body.count),
                "Cache-Control": "no-store"
            ],
            body: body
        )
    }
}

enum LANSubscriptionURLBuilder {
    static func make(
        host: String,
        port: UInt16,
        token: String,
        target: String?
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/sub/\(token)"
        components.queryItems = [URLQueryItem(name: "target", value: target ?? "auto")]
        guard let url = components.url else { throw LANSubscriptionServerError.failedToStart }
        return url
    }
}

enum LANSubscriptionAccessTokenStore {
    private static let key = "lan-subscription-access-token"

    static func loadOrCreate(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: key), existing.count >= 24 {
            return existing
        }
        return rotate(defaults: defaults)
    }

    @discardableResult
    static func rotate(defaults: UserDefaults = .standard) -> String {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(token, forKey: key)
        return token
    }
}

struct LANSubscriptionListenerEnvironment {
    static let fixedWiFiPort: UInt16 = 65_171

    let advertisedAddress: () -> String?
    let parameters: () -> NWParameters

    /// Listens on every LAN interface, optionally pinned to Wi-Fi.
    ///
    /// On iPhone the pin is a safety rail: without it the listener can settle
    /// on cellular, where "local network" means the carrier's network. On a Mac
    /// running this same binary the pin is actively wrong — an Ethernet or dock
    /// connection matches no Wi-Fi interface, so the listener advertises an
    /// address nothing can reach.
    static func networkListening(pinnedToWiFi: Bool) -> Self {
        Self(
            advertisedAddress: LANIPv4Address.currentLANAddress,
            parameters: {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                if pinnedToWiFi {
                    parameters.requiredInterfaceType = .wifi
                }
                parameters.requiredLocalEndpoint = .hostPort(
                    host: NWEndpoint.Host("0.0.0.0"),
                    port: NWEndpoint.Port(rawValue: fixedWiFiPort)!
                )
                return parameters
            }
        )
    }

    /// "Designed for iPhone" is not Mac Catalyst — it is this exact iOS binary
    /// under the macOS sandbox — so the platform cannot be told apart at
    /// compile time and this has to be a runtime question.
    static let wifi = networkListening(pinnedToWiFi: !ProcessInfo.processInfo.isiOSAppOnMac)

    static let loopback = Self(
        advertisedAddress: { "127.0.0.1" },
        parameters: {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: .any
            )
            return parameters
        }
    )
}

final class LANSubscriptionServer: @unchecked Sendable {
    typealias ConfigurationProvider = @MainActor (ClientTarget) -> GeneratedConfiguration

    let token: String
    private let queue = DispatchQueue(label: "com.jzb.tower.lan-subscription")
    private let configurationProvider: ConfigurationProvider
    private let listenerEnvironment: LANSubscriptionListenerEnvironment
    private var listener: NWListener?
    private var didCompleteStart = false

    init(
        token: String,
        listenerEnvironment: LANSubscriptionListenerEnvironment = .wifi,
        configurationProvider: @escaping ConfigurationProvider
    ) {
        self.token = token
        self.listenerEnvironment = listenerEnvironment
        self.configurationProvider = configurationProvider
    }

    func start() async throws -> URL {
        guard let address = listenerEnvironment.advertisedAddress() else {
            throw LANSubscriptionServerError.noWiFiAddress
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let parameters = listenerEnvironment.parameters()
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    self?.serve(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !self.didCompleteStart, let port = listener.port else { return }
                        self.didCompleteStart = true
                        do {
                            continuation.resume(returning: try LANSubscriptionURLBuilder.make(
                                host: address,
                                port: port.rawValue,
                                token: self.token,
                                target: nil
                            ))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failed:
                        guard !self.didCompleteStart else { return }
                        self.didCompleteStart = true
                        continuation.resume(throwing: LANSubscriptionServerError.failedToStart)
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            } catch {
                continuation.resume(throwing: LANSubscriptionServerError.failedToStart)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                let response = LANSubscriptionHTTPRouter.response(
                    request: request,
                    token: self.token,
                    configuration: self.configurationProvider
                )
                self.send(response.serialized(), on: connection)
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

enum LANIPv4Address {
    /// The address to hand out for this device on its LAN.
    ///
    /// Named for the LAN rather than for Wi-Fi because the same code answers on
    /// a Mac, where the interface carrying the LAN is usually Ethernet.
    static func currentLANAddress() -> String? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
        defer { freeifaddrs(firstAddress) }

        var candidates: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let interface = pointer?.pointee {
            defer { pointer = interface.ifa_next }
            guard let socketAddress = interface.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else { continue }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: interface.ifa_name)
            // iPhone Wi-Fi and Personal Hotspot LAN interfaces are `en*`, as is
            // Mac Ethernet. Explicitly excludes cellular `pdp_ip*` and VPN
            // `utun*` addresses, neither of which is reachable from the LAN.
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let address = String(cString: host)
            guard isPrivateLANAddress(address) else { continue }
            candidates.append((name, address))
        }

        return candidates.sorted { lhs, rhs in
            if lhs.name == "en0" { return true }
            if rhs.name == "en0" { return false }
            return lhs.name < rhs.name
        }.first?.address
    }

    private static func isPrivateLANAddress(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        if octets[0] == 10 { return true }
        if octets[0] == 172, (16...31).contains(octets[1]) { return true }
        if octets[0] == 192, octets[1] == 168 { return true }
        return false
    }
}
