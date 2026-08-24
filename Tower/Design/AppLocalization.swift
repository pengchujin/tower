import Foundation

/// The language selected for Tower can differ from the device language through
/// Settings > Apps > Tower > Language. Foundation's bundle preference is the
/// authoritative value for that per-app choice.
enum AppLocalization {
    static var locale: Locale {
        guard let identifier = Bundle.main.preferredLocalizations.first else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    static func regionName(
        for countryCode: String,
        fallback: String? = nil,
        locale: Locale = AppLocalization.locale
    ) -> String {
        let normalizedCode = countryCode.uppercased()
        let localizedName = locale.localizedString(forRegionCode: normalizedCode)
            ?? fallback
            ?? normalizedCode

        return compactRegionName(localizedName, for: normalizedCode, locale: locale)
    }

    /// Apple can qualify Hong Kong, Macao and Taiwan with a parent country on
    /// some OS/locale combinations. Tower presents these as peer regions, so
    /// their labels stay short anywhere `regionName` is used.
    static func compactRegionName(
        _ localizedName: String,
        for countryCode: String,
        locale: Locale = AppLocalization.locale
    ) -> String {
        let normalizedCode = countryCode.uppercased()
        guard ["HK", "MO", "TW"].contains(normalizedCode) else {
            return localizedName
        }

        let localeIdentifier = locale.identifier.lowercased()
        if localeIdentifier.hasPrefix("zh") {
            let usesTraditionalChinese = localeIdentifier.contains("hant")
                || localeIdentifier.contains("_tw")
                || localeIdentifier.contains("-tw")
                || localeIdentifier.contains("_hk")
                || localeIdentifier.contains("-hk")
                || localeIdentifier.contains("_mo")
                || localeIdentifier.contains("-mo")

            switch normalizedCode {
            case "HK": return "香港"
            case "MO": return usesTraditionalChinese ? "澳門" : "澳门"
            case "TW": return usesTraditionalChinese ? "台灣" : "台湾"
            default: break
            }
        }

        let qualifierStart = localizedName.firstIndex { $0 == "(" || $0 == "（" }
        guard let qualifierStart else { return localizedName }
        return localizedName[..<qualifierStart]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
