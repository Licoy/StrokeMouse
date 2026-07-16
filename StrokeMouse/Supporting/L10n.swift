import Foundation

/// Runtime localization that supports in-app language override.
///
/// Important: `String(localized:locale:)` does **not** reliably pick translations from
/// String Catalog / .lproj for an arbitrary locale — it still follows the process preferred
/// languages. We load from the matching `*.lproj` bundle instead.
enum L10n {
    nonisolated(unsafe) private static var override: LanguageOverride = .system
    /// Bundle whose Localizable.strings table we read (language-specific .lproj, or main).
    nonisolated(unsafe) private static var stringsBundle: Bundle = .main

    /// Locale for SwiftUI `.environment(\.locale, …)` and number/date formatting.
    static var locale: Locale {
        switch override {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    static func apply(_ newOverride: LanguageOverride) {
        override = newOverride
        switch newOverride {
        case .system:
            stringsBundle = .main
        case .english:
            stringsBundle = lprojBundle(preferred: ["en", "en-US", "en-GB"]) ?? .main
        case .simplifiedChinese:
            stringsBundle = lprojBundle(preferred: ["zh-Hans", "zh_CN", "zh-Hans-CN", "zh"]) ?? .main
        }
    }

    static func string(_ key: String) -> String {
        // `localizedString` on a language-specific .lproj bundle returns that language's value.
        let value = stringsBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        // If the key is missing in the table, Foundation returns the key itself.
        if value != key {
            return value
        }
        // Fallback: try main bundle (development / incomplete catalogs).
        let fallback = Bundle.main.localizedString(forKey: key, value: nil, table: "Localizable")
        return fallback
    }

    static func string(_ key: String.LocalizationValue) -> String {
        // Prefer explicit key lookup when the LocalizationValue is a simple key string.
        // Fall back to Foundation API with our language bundle.
        let description = String(describing: key)
        // LocalizationValue's description is not always the raw key; use bundle API when possible.
        if !description.isEmpty, !description.contains(" ") {
            let fromTable = stringsBundle.localizedString(forKey: description, value: "\u{0}", table: "Localizable")
            if fromTable != "\u{0}" {
                return fromTable
            }
        }
        return String(localized: key, bundle: stringsBundle, locale: locale)
    }

    // MARK: - Bundle helpers

    private static func lprojBundle(preferred names: [String]) -> Bundle? {
        for name in names {
            if let path = Bundle.main.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path)
            {
                return bundle
            }
        }
        // Last resort: scan available localizations.
        for loc in Bundle.main.localizations {
            let normalized = loc.replacingOccurrences(of: "_", with: "-")
            if names.contains(where: { name in
                let n = name.replacingOccurrences(of: "_", with: "-")
                return normalized == n || normalized.hasPrefix(n + "-") || n.hasPrefix(normalized)
            }) {
                if let path = Bundle.main.path(forResource: loc, ofType: "lproj"),
                   let bundle = Bundle(path: path)
                {
                    return bundle
                }
            }
        }
        return nil
    }
}
