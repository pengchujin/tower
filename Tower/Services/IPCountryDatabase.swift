import Darwin
import Foundation

struct IPCountryDatabase: @unchecked Sendable {
    private static let ipv4RecordSize = 10
    private static let ipv6RecordSize = 34

    private let ipv4Data: Data
    private let ipv6Data: Data

    init(bundle: Bundle = .main) {
        ipv4Data = Self.loadResource(named: "IPCountryIPv4", bundle: bundle)
        ipv6Data = Self.loadResource(named: "IPCountryIPv6", bundle: bundle)
    }

    init(ipv4Data: Data, ipv6Data: Data) {
        self.ipv4Data = ipv4Data
        self.ipv6Data = ipv6Data
    }

    func countryCode(forIPAddress address: String) -> String? {
        var ipv4Address = in_addr()
        if inet_pton(AF_INET, address, &ipv4Address) == 1 {
            return countryCode(forIPv4: UInt32(bigEndian: ipv4Address.s_addr))
        }

        var ipv6Address = in6_addr()
        if inet_pton(AF_INET6, address, &ipv6Address) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6Address) { Array($0) }
            return countryCode(forIPv6: bytes)
        }
        return nil
    }

    private func countryCode(forIPv4 address: UInt32) -> String? {
        var lowerBound = 0
        var upperBound = ipv4Data.count / Self.ipv4RecordSize - 1

        while lowerBound <= upperBound {
            let record = lowerBound + (upperBound - lowerBound) / 2
            let offset = record * Self.ipv4RecordSize
            let start = readUInt32(from: ipv4Data, at: offset)
            let end = readUInt32(from: ipv4Data, at: offset + 4)

            if address < start {
                upperBound = record - 1
            } else if address > end {
                lowerBound = record + 1
            } else {
                return readCountryCode(from: ipv4Data, at: offset + 8)
            }
        }
        return nil
    }

    private func countryCode(forIPv6 address: [UInt8]) -> String? {
        guard address.count == 16 else { return nil }
        var lowerBound = 0
        var upperBound = ipv6Data.count / Self.ipv6RecordSize - 1

        while lowerBound <= upperBound {
            let record = lowerBound + (upperBound - lowerBound) / 2
            let offset = record * Self.ipv6RecordSize
            if compare(address, with: ipv6Data, at: offset) == .orderedAscending {
                upperBound = record - 1
            } else if compare(address, with: ipv6Data, at: offset + 16) == .orderedDescending {
                lowerBound = record + 1
            } else {
                return readCountryCode(from: ipv6Data, at: offset + 32)
            }
        }
        return nil
    }

    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return (UInt32(data[start]) << 24)
            | (UInt32(data[start + 1]) << 16)
            | (UInt32(data[start + 2]) << 8)
            | UInt32(data[start + 3])
    }

    private func compare(_ address: [UInt8], with data: Data, at offset: Int) -> ComparisonResult {
        let start = data.startIndex + offset
        for index in 0..<16 {
            if address[index] < data[start + index] { return .orderedAscending }
            if address[index] > data[start + index] { return .orderedDescending }
        }
        return .orderedSame
    }

    private func readCountryCode(from data: Data, at offset: Int) -> String? {
        let start = data.startIndex + offset
        let bytes = [data[start], data[start + 1]]
        guard bytes.allSatisfy({ (65...90).contains($0) }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }

    private static func loadResource(named name: String, bundle: Bundle) -> Data {
        let url = bundle.url(forResource: name, withExtension: "bin", subdirectory: "IPCountry")
            ?? bundle.url(forResource: name, withExtension: "bin")
        guard let url else { return Data() }
        return (try? Data(contentsOf: url, options: [.mappedIfSafe])) ?? Data()
    }
}

actor IPCountryLookupService {
    private enum CachedResult: Sendable {
        case found(String)
        case missing

        var countryCode: String? {
            switch self {
            case .found(let code): code
            case .missing: nil
            }
        }
    }

    private let database: IPCountryDatabase
    private var cache: [String: CachedResult] = [:]

    init(database: IPCountryDatabase = IPCountryDatabase()) {
        self.database = database
    }

    func countryCode(forHost host: String) async -> String? {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else { return nil }
        if let cached = cache[normalizedHost] { return cached.countryCode }

        if let direct = database.countryCode(forIPAddress: normalizedHost) {
            cache[normalizedHost] = .found(direct)
            return direct
        }

        let addresses = await Task.detached(priority: .utility) {
            Self.resolveIPAddresses(for: normalizedHost)
        }.value
        for address in addresses {
            if let countryCode = database.countryCode(forIPAddress: address) {
                cache[normalizedHost] = .found(countryCode)
                return countryCode
            }
        }

        cache[normalizedHost] = .missing
        return nil
    }

    nonisolated private static func resolveIPAddresses(for host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                info.pointee.ai_addr,
                info.pointee.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let address = String(cString: buffer)
                if !addresses.contains(address) { addresses.append(address) }
            }
            current = info.pointee.ai_next
        }
        return addresses
    }
}
