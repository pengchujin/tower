import Darwin
import Foundation
import Network

enum NodeProbeMethod: String, Equatable, Sendable {
    case icmp = "ICMP"
    case tcp = "TCP"
    case http = "HTTP"
}

enum NodeLatencyTestMode: String, CaseIterable, Identifiable, Sendable {
    case automatic = "自动"
    case icmp = "ICMP"
    case tcp = "TCP"
    case http = "HTTP"

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: String(localized: "自动")
        case .icmp: "ICMP"
        case .tcp: "TCP"
        case .http: "HTTP"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: "gauge.with.dots.needle.50percent"
        case .icmp: "dot.radiowaves.left.and.right"
        case .tcp: "cable.connector"
        case .http: "globe"
        }
    }
}

struct NodeLatencyMeasurement: Equatable, Sendable {
    let milliseconds: Int?
    let method: NodeProbeMethod?
    let testedAt: Date
    let errorMessage: String?

    static func success(milliseconds: Int, method: NodeProbeMethod) -> Self {
        .init(
            milliseconds: max(milliseconds, 1),
            method: method,
            testedAt: .now,
            errorMessage: nil
        )
    }

    static func unavailable(_ message: String) -> Self {
        .init(milliseconds: nil, method: nil, testedAt: .now, errorMessage: message)
    }
}

enum LatencyProbeError: LocalizedError {
    case invalidHost
    case invalidPort
    case resolutionFailed(Int32)
    case socketFailed(Int32)
    case sendFailed(Int32)
    case timeout
    case connectionFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidHost: String(localized: "节点地址无效")
        case .invalidPort: String(localized: "节点端口无效")
        case .resolutionFailed(let status):
            String(localized: "无法解析节点地址（\(String(cString: gai_strerror(status)))）")
        case .socketFailed: String(localized: "无法创建 ICMP 探测")
        case .sendFailed: String(localized: "无法发送 ICMP 探测")
        case .timeout: String(localized: "探测超时")
        case .connectionFailed: String(localized: "节点端口不可达")
        case .invalidResponse: String(localized: "没有收到 HTTP 响应")
        }
    }
}

actor NodeLatencyService {
    typealias ICMPProbe = @Sendable (_ host: String, _ timeout: TimeInterval) async throws -> Int
    typealias TCPProbe = @Sendable (_ host: String, _ port: Int, _ timeout: TimeInterval) async throws -> Int
    typealias HTTPProbe = @Sendable (_ node: ProxyNode, _ timeout: TimeInterval) async throws -> Int

    private let icmpTimeout: TimeInterval
    private let tcpTimeout: TimeInterval
    private let httpTimeout: TimeInterval
    private let icmpProbe: ICMPProbe
    private let tcpProbe: TCPProbe
    private let httpProbe: HTTPProbe

    init(
        icmpTimeout: TimeInterval = 1.2,
        tcpTimeout: TimeInterval = 1.8,
        httpTimeout: TimeInterval = 2.5
    ) {
        self.icmpTimeout = icmpTimeout
        self.tcpTimeout = tcpTimeout
        self.httpTimeout = httpTimeout
        icmpProbe = { host, timeout in
            try await ICMPPingProbe.measure(host: host, timeout: timeout)
        }
        tcpProbe = { host, port, timeout in
            try await TCPConnectProbe.measure(host: host, port: port, timeout: timeout)
        }
        httpProbe = { node, timeout in
            try await HTTPResponseProbe.measure(node: node, timeout: timeout)
        }
    }

    init(
        icmpTimeout: TimeInterval = 1.2,
        tcpTimeout: TimeInterval = 1.8,
        httpTimeout: TimeInterval = 2.5,
        icmpProbe: @escaping ICMPProbe,
        tcpProbe: @escaping TCPProbe,
        httpProbe: @escaping HTTPProbe = { node, timeout in
            try await HTTPResponseProbe.measure(node: node, timeout: timeout)
        }
    ) {
        self.icmpTimeout = icmpTimeout
        self.tcpTimeout = tcpTimeout
        self.httpTimeout = httpTimeout
        self.icmpProbe = icmpProbe
        self.tcpProbe = tcpProbe
        self.httpProbe = httpProbe
    }

    func measure(
        _ node: ProxyNode,
        mode: NodeLatencyTestMode = .automatic
    ) async throws -> NodeLatencyMeasurement {
        switch mode {
        case .automatic:
            return try await measureAutomatically(node)
        case .icmp:
            return try await measureICMP(node)
        case .tcp:
            return try await measureTCP(node)
        case .http:
            return try await measureHTTP(node)
        }
    }

    private func measureAutomatically(_ node: ProxyNode) async throws -> NodeLatencyMeasurement {
        do {
            let milliseconds = try await icmpProbe(node.server, icmpTimeout)
            return .success(milliseconds: milliseconds, method: .icmp)
        } catch is CancellationError {
            throw CancellationError()
        } catch let icmpError {
            do {
                let milliseconds = try await tcpProbe(node.server, node.port, tcpTimeout)
                return .success(milliseconds: milliseconds, method: .tcp)
            } catch is CancellationError {
                throw CancellationError()
            } catch let tcpError {
                return .unavailable(
                    "ICMP：\(icmpError.localizedDescription)；端口：\(tcpError.localizedDescription)"
                )
            }
        }
    }

    private func measureICMP(_ node: ProxyNode) async throws -> NodeLatencyMeasurement {
        do {
            return .success(
                milliseconds: try await icmpProbe(node.server, icmpTimeout),
                method: .icmp
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unavailable("ICMP：\(error.localizedDescription)")
        }
    }

    private func measureTCP(_ node: ProxyNode) async throws -> NodeLatencyMeasurement {
        do {
            return .success(
                milliseconds: try await tcpProbe(node.server, node.port, tcpTimeout),
                method: .tcp
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unavailable("TCP：\(error.localizedDescription)")
        }
    }

    private func measureHTTP(_ node: ProxyNode) async throws -> NodeLatencyMeasurement {
        do {
            return .success(
                milliseconds: try await httpProbe(node, httpTimeout),
                method: .http
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unavailable("HTTP：\(error.localizedDescription)")
        }
    }
}

private enum HTTPResponseProbe {
    static func measure(node: ProxyNode, timeout: TimeInterval) async throws -> Int {
        guard !node.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LatencyProbeError.invalidHost
        }
        guard (1 ... 65_535).contains(node.port) else {
            throw LatencyProbeError.invalidPort
        }

        var components = URLComponents()
        components.scheme = node.tls || node.port == 443 ? "https" : "http"
        components.host = node.server
        components.port = node.port
        components.path = "/"
        guard let url = components.url else { throw LatencyProbeError.invalidHost }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let (_, response) = try await session.data(for: request)
        guard response is HTTPURLResponse else { throw LatencyProbeError.invalidResponse }
        return max(Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000), 1)
    }
}

private enum ICMPPingProbe {
    static func measure(host: String, timeout: TimeInterval) async throws -> Int {
        let operation = ICMPPingOperation(host: host, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await operation.start()
        } onCancel: {
            operation.cancel()
        }
    }
}

private final class ICMPPingOperation: @unchecked Sendable {
    private let host: String
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.jzb.tower.icmp-probe")
    private var continuation: CheckedContinuation<Int, Error>?
    private var readSource: DispatchSourceRead?
    private var socketFD: Int32 = -1
    private var identifier = UInt16.random(in: 1 ... .max)
    private var sequence = UInt16.random(in: 1 ... .max)
    private var startedAt: UInt64 = 0
    private var wasCancelled = false

    init(host: String, timeout: TimeInterval) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeout = timeout
    }

    func start() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !wasCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                begin()
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            wasCancelled = true
            finish(.failure(CancellationError()))
        }
    }

    private func begin() {
        guard !host.isEmpty else {
            finish(.failure(LatencyProbeError.invalidHost))
            return
        }

        var hints = addrinfo()
        // AI_ADDRCONFIG rejects valid loopback/numeric IPv4 addresses in some
        // Simulator and Darwin configurations, so resolve the requested IPv4
        // host without filtering it by the machine's active interfaces.
        hints.ai_flags = 0
        hints.ai_family = AF_INET
        // ICMP is not a transport service that getaddrinfo needs to validate.
        // Supplying SOCK_DGRAM + IPPROTO_ICMP is rejected as EAI_BADHINTS on
        // Darwin even though the same pair is valid when creating the socket.
        hints.ai_socktype = 0
        hints.ai_protocol = 0

        var result: UnsafeMutablePointer<addrinfo>?
        let resolutionStatus = getaddrinfo(host, nil, &hints, &result)
        guard resolutionStatus == 0, let addressInfo = result else {
            finish(.failure(LatencyProbeError.resolutionFailed(resolutionStatus)))
            return
        }
        defer { freeaddrinfo(result) }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else {
            finish(.failure(LatencyProbeError.socketFailed(errno)))
            return
        }
        socketFD = fd

        let currentFlags = fcntl(fd, F_GETFL, 0)
        if currentFlags >= 0 {
            _ = fcntl(fd, F_SETFL, currentFlags | O_NONBLOCK)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.receivePacket() }
        source.setCancelHandler { close(fd) }
        readSource = source
        source.resume()

        let packet = makeEchoRequest(identifier: identifier, sequence: sequence)
        startedAt = DispatchTime.now().uptimeNanoseconds
        let sent = packet.withUnsafeBytes { bytes in
            sendto(
                fd,
                bytes.baseAddress,
                bytes.count,
                0,
                addressInfo.pointee.ai_addr,
                addressInfo.pointee.ai_addrlen
            )
        }
        guard sent == packet.count else {
            finish(.failure(LatencyProbeError.sendFailed(errno)))
            return
        }

        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(LatencyProbeError.timeout))
        }
    }

    private func receivePacket() {
        var buffer = [UInt8](repeating: 0, count: 65_535)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                recv(socketFD, bytes.baseAddress, bytes.count, 0)
            }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                finish(.failure(LatencyProbeError.socketFailed(errno)))
                return
            }
            guard count >= 8 else { continue }
            let packet = Array(buffer.prefix(count))
            guard isMatchingEchoReply(packet) else { continue }

            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            let milliseconds = Int((Double(elapsed) / 1_000_000).rounded())
            finish(.success(max(milliseconds, 1)))
            return
        }
    }

    private func isMatchingEchoReply(_ packet: [UInt8]) -> Bool {
        let offset: Int
        if packet[0] >> 4 == 4 {
            offset = Int(packet[0] & 0x0F) * 4
            guard offset >= 20, packet.count >= offset + 8, packet[9] == UInt8(IPPROTO_ICMP) else {
                return false
            }
        } else {
            offset = 0
            guard packet.count >= 8 else { return false }
        }

        guard packet[offset] == 0, packet[offset + 1] == 0 else { return false }
        let receivedSequence = UInt16(packet[offset + 6]) << 8 | UInt16(packet[offset + 7])
        // Darwin may assign its own identifier to SOCK_DGRAM ICMP sockets.
        // The socket receives only replies for this probe, so the sequence is
        // the stable value we use to reject unrelated packets.
        return receivedSequence == sequence
    }

    private func finish(_ result: Result<Int, Error>) {
        guard let continuation else { return }
        self.continuation = nil

        if let source = readSource {
            readSource = nil
            socketFD = -1
            source.cancel()
        } else if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }

        continuation.resume(with: result)
    }

    private func makeEchoRequest(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8
        packet[1] = 0
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xFF)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xFF)

        let payload = Array("Tower latency probe".utf8)
        for (index, byte) in payload.enumerated() where index + 8 < packet.count {
            packet[index + 8] = byte
        }

        let checksum = internetChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xFF)
        return packet
    }

    private func internetChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum & 0xFFFF)
    }
}

private enum TCPConnectProbe {
    static func measure(host: String, port: Int, timeout: TimeInterval) async throws -> Int {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(exactly: port) ?? 0), nwPort.rawValue != 0 else {
            throw LatencyProbeError.invalidPort
        }
        let operation = TCPConnectOperation(
            host: NWEndpoint.Host(host),
            port: nwPort,
            timeout: timeout
        )
        return try await withTaskCancellationHandler {
            try await operation.start()
        } onCancel: {
            operation.cancel()
        }
    }
}

private final class TCPConnectOperation: @unchecked Sendable {
    private let connection: NWConnection
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.jzb.tower.tcp-probe")
    private var continuation: CheckedContinuation<Int, Error>?
    private var startedAt: UInt64 = 0
    private var wasCancelled = false

    init(host: NWEndpoint.Host, port: NWEndpoint.Port, timeout: TimeInterval) {
        connection = NWConnection(host: host, port: port, using: .tcp)
        self.timeout = timeout
    }

    func start() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !wasCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                startedAt = DispatchTime.now().uptimeNanoseconds
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
                        let milliseconds = Int((Double(elapsed) / 1_000_000).rounded())
                        finish(.success(max(milliseconds, 1)))
                    case .failed(let error):
                        finish(.failure(LatencyProbeError.connectionFailed(error.localizedDescription)))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(.failure(LatencyProbeError.timeout))
                }
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            wasCancelled = true
            finish(.failure(CancellationError()))
        }
    }

    private func finish(_ result: Result<Int, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(with: result)
    }
}
