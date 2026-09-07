import Darwin
import Foundation

struct NetworkOrganization: Hashable, Sendable {
    let asn: UInt32
    let name: String
}

/// Fixed-size sorted range records and a shared UTF-8 name pool, memory mapped.
/// Names are decoded only for a matched range, never into a whole-database dictionary.
struct IPASNDatabase: Sendable {
    private let ipv4: Data
    private let ipv6: Data
    private let names: Data

    init(bundle: Bundle = .main) {
        func load(_ name: String) -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "bin", subdirectory: "IPCountry")
                ?? bundle.url(forResource: name, withExtension: "bin") else { return Data() }
            return (try? Data(contentsOf: url, options: .mappedIfSafe)) ?? Data()
        }
        self.init(ipv4: load("IPASNIPv4"), ipv6: load("IPASNIPv6"), names: load("IPASNNames"))
    }

    init(ipv4: Data, ipv6: Data, names: Data) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.names = names
    }

    func organization(forIPAddress address: String) -> NetworkOrganization? {
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            return withUnsafeBytes(of: &v4) { lookup(Array($0), in: ipv4) }
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, address, &v6) == 1 {
            return withUnsafeBytes(of: &v6) { lookup(Array($0), in: ipv6) }
        }
        return nil
    }

    private func lookup(_ address: [UInt8], in data: Data) -> NetworkOrganization? {
        let width = address.count
        let stride = width * 2 + 10
        guard data.count.isMultiple(of: stride) else { return nil }
        var low = 0
        var high = data.count / stride
        while low < high {
            let mid = (low + high) / 2
            let offset = mid * stride
            let start = data[offset ..< offset + width]
            let end = data[offset + width ..< offset + width * 2]
            if address.lexicographicallyPrecedes(start) {
                high = mid
            } else if end.lexicographicallyPrecedes(address) {
                low = mid + 1
            } else {
                let metadata = offset + width * 2
                let asn = uint32(data, metadata)
                let nameOffset = Int(uint32(data, metadata + 4))
                let length = Int(data[metadata + 8]) * 256 + Int(data[metadata + 9])
                guard asn > 0, nameOffset <= names.count, length <= names.count - nameOffset,
                      let name = String(data: names[nameOffset ..< nameOffset + length], encoding: .utf8),
                      !name.isEmpty else { return nil }
                return NetworkOrganization(asn: asn, name: name)
            }
        }
        return nil
    }

    private func uint32(_ data: Data, _ index: Int) -> UInt32 {
        data[index ..< index + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
