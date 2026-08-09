import Foundation

/// Self-Configuration is intentionally not part of the app bundle. The user
/// chooses whether to download it, and the importer then keeps the selected
/// configuration and its provider rules in Application Support.
enum SelfConfigurationSource {
    static let name = "Self-Configuration"
    static var summary: String {
        String(localized: "AI、流媒体、广告和国内外流量精细分流。")
    }
    static let projectURL = URL(
        string: "https://github.com/ClashConnectRules/Self-Configuration"
    )!
    static let downloadURL = URL(
        string: "https://raw.githubusercontent.com/ClashConnectRules/Self-Configuration/main/Clash.yaml"
    )!

    static func matches(_ scheme: RuleScheme) -> Bool {
        scheme.sourceURLString == downloadURL.absoluteString
    }
}
