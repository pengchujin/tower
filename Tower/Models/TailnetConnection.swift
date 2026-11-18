import Foundation

/// A tailnet an exported profile can reach alongside ordinary proxies, so a
/// client that is busy proxying can still open the computers at home.
///
/// It is deliberately not a `ProxyNode`: a destination outside the tailnet
/// fails through it instead of falling back, so it must never join selection,
/// latency or region groups. Only the routes below are sent to it.
///
/// The auth key is not stored here. This value is synced through iCloud; the
/// key can add machines to someone's tailnet and stays in this device's
/// Keychain (`TailnetAuthKeyStore`).
struct TailnetConnection: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Shown in the client as the policy name.
    var name: String
    /// Nil or empty means the official Tailscale control server.
    var controlURLString: String?
    /// Prefix of the machine name each client registers as. The client slug is
    /// appended so Surge and Stash on one phone do not fight over one name.
    var deviceName: String?
    /// LAN ranges behind a subnet router, e.g. the home network.
    var subnets: [String]
    /// The tailnet's MagicDNS domain, e.g. `tail1234.ts.net`.
    var magicDNSSuffix: String?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        controlURLString: String? = nil,
        deviceName: String? = nil,
        subnets: [String] = [],
        magicDNSSuffix: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.controlURLString = controlURLString
        self.deviceName = deviceName
        self.subnets = subnets
        self.magicDNSSuffix = magicDNSSuffix
        self.isEnabled = isEnabled
    }

    static let defaultName = "Tailscale"
    static let defaultDeviceName = "tower"
    /// Tailscale's fixed address ranges. Every peer lives in these, whichever
    /// control server assigned it.
    static let tailnetIPv4Range = "100.64.0.0/10"
    static let tailnetIPv6Range = "fd7a:115c:a1e0::/48"

    /// Stable across exports. Surge ties an interactive sign-in to the section
    /// name and mihomo / sing-box keep their machine key in the state
    /// directory, so a name that changed per export would register a new
    /// device every time the profile is imported again.
    var stableSlug: String {
        "tower-tailnet-" + id.uuidString.prefix(8).lowercased()
    }

    var customControlURL: String? {
        let trimmed = controlURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The same characters the configuration writers escape for node names:
    /// a comma would split a rule line and a bracket would open an INI section.
    var policyName: String {
        let cleaned = name
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "=", with: "-")
            .replacingOccurrences(of: ",", with: "，")
            .replacingOccurrences(of: "#", with: "＃")
            .replacingOccurrences(of: ";", with: "；")
            .replacingOccurrences(of: "//", with: "／／")
            .replacingOccurrences(of: "[", with: "［")
            .replacingOccurrences(of: "]", with: "］")
            .replacingOccurrences(of: "\"", with: "＂")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? Self.defaultName : cleaned
    }

    /// A DNS label per client, e.g. `tower-surge`.
    func hostname(for clientSlug: String) -> String {
        let base = Self.normalizedDeviceName(deviceName) ?? Self.defaultDeviceName
        return String((base + "-" + clientSlug).prefix(63))
    }

    /// Lowercase letters, digits and hyphens: what a machine name can hold
    /// without the control server rewriting it.
    static func normalizedDeviceName(_ value: String?) -> String? {
        let lowered = (value ?? "").lowercased()
        var result = ""
        for scalar in lowered.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty, result.last != "-" {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? nil : String(result.prefix(40))
    }

    // MARK: - Validation

    enum ValidationError: Error, Equatable {
        case controlURL
        case subnet(String)
        case magicDNSSuffix
        case authKey
    }

    /// Only HTTPS: the control server hands out the tailnet's peers and keys.
    static func normalizedControlURL(_ value: String) throws -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace || $0 == "," || $0 == "\"" })
        else { throw ValidationError.controlURL }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// Accepts one CIDR per line or separated by commas / spaces, and masks
    /// host bits so `192.168.1.5/24` is written as `192.168.1.0/24`.
    static func normalizedSubnets(_ text: String) throws -> [String] {
        let parts = text
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace })
            .map(String.init)
        var seen = Set<String>()
        var result: [String] = []
        for part in parts {
            guard let cidr = normalizedCIDR(part) else { throw ValidationError.subnet(part) }
            if seen.insert(cidr).inserted { result.append(cidr) }
        }
        return result
    }

    static func normalizedMagicDNSSuffix(_ value: String) throws -> String? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while trimmed.hasPrefix(".") { trimmed.removeFirst() }
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let valid = labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.unicodeScalars.allSatisfy {
                    ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
                }
        }
        guard valid else { throw ValidationError.magicDNSSuffix }
        return trimmed
    }

    /// Official keys start with `tskey-`, Headscale's with `hskey-`; neither is
    /// required. Whitespace, quotes and commas would break the line it lands in.
    static func normalizedAuthKey(_ value: String) throws -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 512,
              !trimmed.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "," || $0 == "\\" || $0 == "'" })
        else { throw ValidationError.authKey }
        return trimmed
    }

    static func normalizedCIDR(_ value: String) -> String? {
        let pieces = value.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2, let prefix = Int(pieces[1]) else { return nil }
        let address = String(pieces[0])
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            guard (0...32).contains(prefix) else { return nil }
            var bytes = withUnsafeBytes(of: &v4) { Array($0) }
            mask(&bytes, prefix: prefix)
            return bytes.map(String.init).joined(separator: ".") + "/\(prefix)"
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, address, &v6) == 1 {
            guard (0...128).contains(prefix) else { return nil }
            var bytes = withUnsafeBytes(of: &v6) { Array($0) }
            mask(&bytes, prefix: prefix)
            var masked = in6_addr()
            withUnsafeMutableBytes(of: &masked) { $0.copyBytes(from: bytes) }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &masked, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            return String(cString: buffer) + "/\(prefix)"
        }
        return nil
    }

    static func isIPv6CIDR(_ cidr: String) -> Bool { cidr.contains(":") }

    private static func mask(_ bytes: inout [UInt8], prefix: Int) {
        for index in bytes.indices {
            let bitsKept = max(0, min(8, prefix - index * 8))
            bytes[index] &= bitsKept == 0 ? 0 : UInt8(truncatingIfNeeded: 0xFF << (8 - bitsKept))
        }
    }
}
