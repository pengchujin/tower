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
        locale.localizedString(forRegionCode: countryCode.uppercased())
            ?? fallback
            ?? countryCode.uppercased()
    }
}
