import Foundation

/// Protocol support that depends on the Surge build fetching the profile.
///
/// Exported files and copied text cannot know which Surge will open them, so
/// they keep the App Store baseline (`ClientTarget.supports`). Only a request
/// Surge makes itself — a one-tap import or a LAN subscription refresh —
/// carries a User-Agent, and only then can newer protocols be written.
///
/// Both platforms send `Surge <platform>/<build> SurgeCore/<core>`. The build
/// is the signal: iOS TestFlight 4024 reports `SurgeCore/6011000`, below the
/// 6.12.0 the manual names, so the core version cannot be used.
enum SurgeClientCapabilities {
    /// Surge iOS 6.100.0 TestFlight build 4024 (2026-11-12) is the first with
    /// a `vless` policy (manual: iOS 6.0.0+); 4022 and every 5.x build
    /// (App Store 5.23.0, TestFlight 5.102.0 at 387x) predate it.
    static let firstIOSBuildWithVLESS = 4024

    /// Surge Mac 6.12.0 Beta, Sparkle build 12820 (manual: Mac 6.12.0+).
    /// Captured 2026-11-13 as `Surge Mac/12820 SurgeCore/6012000`; the
    /// release before it is 6.11.0 (12800).
    static let firstMacBuildWithVLESS = 12820

    /// The build after `Surge <platform>/` in the User-Agent.
    static func build(userAgent: String?, platform: String) -> Int? {
        guard let userAgent,
              let range = userAgent.range(of: "Surge \(platform)/", options: .caseInsensitive) else { return nil }
        let digits = userAgent[range.upperBound...].prefix(while: \.isASCIIDigit)
        // `Surge iOS/5.14` is a version, not a build; it reads as 5 and stays
        // on the baseline, which is what any 5.x release needs.
        return Int(digits)
    }

    static func iOSBuild(userAgent: String?) -> Int? { build(userAgent: userAgent, platform: "iOS") }
    static func macBuild(userAgent: String?) -> Int? { build(userAgent: userAgent, platform: "Mac") }

    static func supportsVLESS(userAgent: String?) -> Bool {
        (iOSBuild(userAgent: userAgent) ?? 0) >= firstIOSBuildWithVLESS
            || (macBuild(userAgent: userAgent) ?? 0) >= firstMacBuildWithVLESS
    }

    /// Surge's App Store protocol set plus VLESS. Passing exactly this set
    /// as `supportedKindsOverride` also marks the request as coming from a
    /// beta build, which unlocks the other beta-only fields (TrustTunnel's
    /// `client-random-auth-key` shipped in the same 4024 / 12820 builds).
    static let vlessKinds: Set<ProxyKind> = Set(ProxyKind.allCases.filter { ClientTarget.surge.supports($0) })
        .union([.vless])

    /// Whether a generation request is the beta variant for Surge.
    static func isBetaRequest(target: ClientTarget, supportedKindsOverride: Set<ProxyKind>?) -> Bool {
        [.surge, .surgeMac].contains(target) && supportedKindsOverride?.contains(.vless) == true
    }

    /// The kinds to generate for this request, or nil for the baseline.
    static func supportedKinds(userAgent: String?) -> Set<ProxyKind>? {
        supportsVLESS(userAgent: userAgent) ? vlessKinds : nil
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
