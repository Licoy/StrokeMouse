import Foundation

/// Explicit allowlist of settings that are safe and meaningful to move between
/// Macs. Device state, permissions, consent receipts, launch-at-login, update
/// policy, global enablement, and sync credentials are intentionally excluded.
struct PortableSettingsV1: Codable, Equatable, Sendable {
    var minStrokeDistance: Double
    var matchThreshold: Double
    /// Optional so backups written before this setting existed still decode.
    var ambiguityResolution: String?
    var appearance: String
    var menuBarIconStyle: String
    var language: String
    var pinnedGestureAppBundleIds: [String]
    var showGestureHUD: Bool
    var includeGestureHUDInCaptures: Bool
    var directTrackpadEnabled: Bool
    var hudLineColor: String
    var hudLineWidth: Double
    var hudShowStartPoint: Bool
    var hudStartPointRadius: Double
    var showMatchToast: Bool
    var showMissToast: Bool
    var showLiveMismatchFeedback: Bool
    var hudMismatchLineColor: String

    static func capture(from defaults: UserDefaults) -> PortableSettingsV1 {
        PortableSettingsV1(
            minStrokeDistance: positiveDouble(
                in: defaults,
                key: PreferenceKey.minStrokeDistance,
                fallback: Double(Constants.defaultMinStrokeDistance)
            ),
            matchThreshold: double(
                in: defaults,
                key: PreferenceKey.matchThreshold,
                fallback: Constants.freePathMatchThreshold
            ),
            ambiguityResolution: defaults.string(
                forKey: PreferenceKey.ambiguityResolution
            ) ?? GestureAmbiguityResolution.reject.rawValue,
            appearance: defaults.string(forKey: PreferenceKey.appearance)
                ?? AppearanceMode.system.rawValue,
            menuBarIconStyle: defaults.string(
                forKey: PreferenceKey.menuBarIconStyle
            ) ?? MenuBarIconStyle.default.rawValue,
            language: defaults.string(forKey: PreferenceKey.language)
                ?? LanguageOverride.system.rawValue,
            pinnedGestureAppBundleIds: defaults.stringArray(
                forKey: PreferenceKey.pinnedGestureAppBundleIds
            ) ?? [],
            showGestureHUD: bool(
                in: defaults,
                key: PreferenceKey.showGestureHUD,
                fallback: true
            ),
            includeGestureHUDInCaptures: defaults.bool(
                forKey: PreferenceKey.includeGestureHUDInCaptures
            ),
            directTrackpadEnabled: bool(
                in: defaults,
                key: PreferenceKey.directTrackpadEnabled,
                fallback: true
            ),
            hudLineColor: defaults.string(forKey: PreferenceKey.hudLineColor)
                ?? Constants.defaultHUDLineColorHex,
            hudLineWidth: positiveDouble(
                in: defaults,
                key: PreferenceKey.hudLineWidth,
                fallback: Double(Constants.defaultHUDLineWidth)
            ),
            hudShowStartPoint: bool(
                in: defaults,
                key: PreferenceKey.hudShowStartPoint,
                fallback: true
            ),
            hudStartPointRadius: positiveDouble(
                in: defaults,
                key: PreferenceKey.hudStartPointRadius,
                fallback: Double(Constants.defaultHUDStartPointRadius)
            ),
            showMatchToast: bool(
                in: defaults,
                key: PreferenceKey.showMatchToast,
                fallback: true
            ),
            showMissToast: bool(
                in: defaults,
                key: PreferenceKey.showMissToast,
                fallback: true
            ),
            showLiveMismatchFeedback: defaults.bool(
                forKey: PreferenceKey.showLiveMismatchFeedback
            ),
            hudMismatchLineColor: defaults.string(
                forKey: PreferenceKey.hudMismatchLineColor
            ) ?? Constants.defaultHUDMismatchLineColorHex
        )
    }

    func validate() throws {
        guard minStrokeDistance.isFinite,
              (20...120).contains(minStrokeDistance)
        else {
            throw PortableSettingsValidationError.invalidMinStrokeDistance(
                minStrokeDistance
            )
        }
        guard matchThreshold.isFinite,
              Constants.freePathMatchThresholdRange.contains(matchThreshold)
        else {
            throw PortableSettingsValidationError.invalidMatchThreshold(
                matchThreshold
            )
        }
        if let ambiguityResolution,
           GestureAmbiguityResolution(rawValue: ambiguityResolution) == nil
        {
            throw PortableSettingsValidationError.invalidAmbiguityResolution(
                ambiguityResolution
            )
        }
        guard AppearanceMode(rawValue: appearance) != nil else {
            throw PortableSettingsValidationError.invalidAppearance(appearance)
        }
        guard MenuBarIconStyle(rawValue: menuBarIconStyle) != nil else {
            throw PortableSettingsValidationError.invalidMenuBarIconStyle(
                menuBarIconStyle
            )
        }
        guard LanguageOverride(rawValue: language) != nil else {
            throw PortableSettingsValidationError.invalidLanguage(language)
        }
        try validatePinnedBundleIdentifiers()
        guard DrawingStyle.color(fromHex: hudLineColor) != nil else {
            throw PortableSettingsValidationError.invalidColor(hudLineColor)
        }
        guard hudLineWidth.isFinite, (1...16).contains(hudLineWidth) else {
            throw PortableSettingsValidationError.invalidHUDLineWidth(
                hudLineWidth
            )
        }
        guard hudStartPointRadius.isFinite,
              (4...16).contains(hudStartPointRadius)
        else {
            throw PortableSettingsValidationError.invalidHUDStartPointRadius(
                hudStartPointRadius
            )
        }
        guard DrawingStyle.color(fromHex: hudMismatchLineColor) != nil else {
            throw PortableSettingsValidationError.invalidColor(
                hudMismatchLineColor
            )
        }
    }

    /// Validates the complete snapshot before the first mutation. `UserDefaults`
    /// setters do not report per-key persistence failures.
    func apply(to defaults: UserDefaults) throws {
        try validate()
        defaults.set(minStrokeDistance, forKey: PreferenceKey.minStrokeDistance)
        defaults.set(matchThreshold, forKey: PreferenceKey.matchThreshold)
        defaults.set(
            ambiguityResolution
                ?? GestureAmbiguityResolution.reject.rawValue,
            forKey: PreferenceKey.ambiguityResolution
        )
        defaults.set(appearance, forKey: PreferenceKey.appearance)
        defaults.set(menuBarIconStyle, forKey: PreferenceKey.menuBarIconStyle)
        defaults.set(language, forKey: PreferenceKey.language)
        defaults.set(
            pinnedGestureAppBundleIds,
            forKey: PreferenceKey.pinnedGestureAppBundleIds
        )
        defaults.set(showGestureHUD, forKey: PreferenceKey.showGestureHUD)
        defaults.set(
            includeGestureHUDInCaptures,
            forKey: PreferenceKey.includeGestureHUDInCaptures
        )
        defaults.set(
            directTrackpadEnabled,
            forKey: PreferenceKey.directTrackpadEnabled
        )
        defaults.set(hudLineColor, forKey: PreferenceKey.hudLineColor)
        defaults.set(hudLineWidth, forKey: PreferenceKey.hudLineWidth)
        defaults.set(
            hudShowStartPoint,
            forKey: PreferenceKey.hudShowStartPoint
        )
        defaults.set(
            hudStartPointRadius,
            forKey: PreferenceKey.hudStartPointRadius
        )
        defaults.set(showMatchToast, forKey: PreferenceKey.showMatchToast)
        defaults.set(showMissToast, forKey: PreferenceKey.showMissToast)
        defaults.set(
            showLiveMismatchFeedback,
            forKey: PreferenceKey.showLiveMismatchFeedback
        )
        defaults.set(
            hudMismatchLineColor,
            forKey: PreferenceKey.hudMismatchLineColor
        )
    }

    private func validatePinnedBundleIdentifiers() throws {
        var unique = Set<String>()
        for identifier in pinnedGestureAppBundleIds {
            guard !identifier.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                throw PortableSettingsValidationError
                    .invalidPinnedBundleIdentifier(identifier)
            }
            guard unique.insert(identifier).inserted else {
                throw PortableSettingsValidationError
                    .duplicatePinnedBundleIdentifier(identifier)
            }
        }
    }

    private static func bool(
        in defaults: UserDefaults,
        key: String,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil
            ? fallback
            : defaults.bool(forKey: key)
    }

    private static func double(
        in defaults: UserDefaults,
        key: String,
        fallback: Double
    ) -> Double {
        defaults.object(forKey: key) == nil
            ? fallback
            : defaults.double(forKey: key)
    }

    private static func positiveDouble(
        in defaults: UserDefaults,
        key: String,
        fallback: Double
    ) -> Double {
        let value = double(in: defaults, key: key, fallback: fallback)
        return value > 0 ? value : fallback
    }
}

enum PortableSettingsValidationError: Error, Equatable, Sendable {
    case invalidMinStrokeDistance(Double)
    case invalidMatchThreshold(Double)
    case invalidAmbiguityResolution(String)
    case invalidAppearance(String)
    case invalidMenuBarIconStyle(String)
    case invalidLanguage(String)
    case invalidPinnedBundleIdentifier(String)
    case duplicatePinnedBundleIdentifier(String)
    case invalidColor(String)
    case invalidHUDLineWidth(Double)
    case invalidHUDStartPointRadius(Double)
}
