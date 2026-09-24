import Foundation

struct ScrollSmoothParameters: Equatable, Sendable {
    var stepPixels: Double
    var durationMs: Double
    var acceleration: Double

    func clamped() -> ScrollSmoothParameters {
        ScrollSmoothParameters(
            stepPixels: Self.clamp(
                stepPixels,
                to: Constants.scrollStepRange,
                fallback: ScrollSmoothPreset.standardStep
            ),
            durationMs: Self.clamp(
                durationMs,
                to: Constants.scrollDurationRangeMs,
                fallback: ScrollSmoothPreset.standardDurationMs
            ),
            acceleration: Self.clamp(
                acceleration,
                to: Constants.scrollAccelerationRange,
                fallback: ScrollSmoothPreset.standardAcceleration
            )
        )
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

enum ScrollSmoothPreset: String, CaseIterable, Sendable {
    case gentle
    case standard
    case responsive
    case custom

    static let standardStep = 80.0
    static let standardDurationMs = 260.0
    static let standardAcceleration = 0.5

    var fixedParameters: ScrollSmoothParameters? {
        switch self {
        case .gentle:
            return ScrollSmoothParameters(
                stepPixels: 60,
                durationMs: 360,
                acceleration: 0.3
            )
        case .standard:
            return ScrollSmoothParameters(
                stepPixels: Self.standardStep,
                durationMs: Self.standardDurationMs,
                acceleration: Self.standardAcceleration
            )
        case .responsive:
            return ScrollSmoothParameters(
                stepPixels: 100,
                durationMs: 160,
                acceleration: 0.7
            )
        case .custom:
            return nil
        }
    }

    var displayKey: String {
        switch self {
        case .gentle: return "scroll.preset.gentle"
        case .standard: return "scroll.preset.standard"
        case .responsive: return "scroll.preset.responsive"
        case .custom: return "scroll.preset.custom"
        }
    }
}

struct ScrollEnhancementConfiguration: Equatable, Sendable {
    var isEnabled: Bool
    var reverseMouseVertical: Bool
    var reverseMouseHorizontal: Bool
    var reverseTrackpadVertical: Bool
    var reverseTrackpadHorizontal: Bool
    var smoothEnabled: Bool
    var smoothPreset: ScrollSmoothPreset
    var customSmoothParameters: ScrollSmoothParameters
    var excludedBundleIds: [String]

    static let dormant = ScrollEnhancementConfiguration(
        isEnabled: true,
        reverseMouseVertical: false,
        reverseMouseHorizontal: false,
        reverseTrackpadVertical: false,
        reverseTrackpadHorizontal: false,
        smoothEnabled: false,
        smoothPreset: .standard,
        customSmoothParameters: ScrollSmoothPreset.standard.fixedParameters
            ?? ScrollSmoothParameters(
                stepPixels: ScrollSmoothPreset.standardStep,
                durationMs: ScrollSmoothPreset.standardDurationMs,
                acceleration: ScrollSmoothPreset.standardAcceleration
            ),
        excludedBundleIds: []
    )

    var effectiveSmoothParameters: ScrollSmoothParameters {
        (smoothPreset.fixedParameters ?? customSmoothParameters).clamped()
    }

    /// A configured reverse axis or smooth scrolling, ignoring the master switch.
    var hasActiveFeatures: Bool {
        reverseMouseVertical
            || reverseMouseHorizontal
            || reverseTrackpadVertical
            || reverseTrackpadHorizontal
            || smoothEnabled
    }

    var requiresEventTap: Bool {
        isEnabled && hasActiveFeatures
    }

    func normalized() -> ScrollEnhancementConfiguration {
        var copy = self
        copy.customSmoothParameters = customSmoothParameters.clamped()
        copy.excludedBundleIds = ScrollPreferences.normalizedBundleIds(
            excludedBundleIds
        )
        return copy
    }
}

enum ScrollPreferences {
    static func load(from defaults: UserDefaults) -> ScrollEnhancementConfiguration {
        let presetRaw = defaults.string(forKey: PreferenceKey.scrollSmoothPreset)
            ?? ScrollSmoothPreset.standard.rawValue
        let preset = ScrollSmoothPreset(rawValue: presetRaw) ?? .standard
        let fallback = ScrollSmoothPreset.standard.fixedParameters
            ?? ScrollEnhancementConfiguration.dormant.customSmoothParameters
        return ScrollEnhancementConfiguration(
            isEnabled: bool(
                defaults,
                PreferenceKey.scrollEnhancementEnabled,
                default: true
            ),
            reverseMouseVertical: bool(
                defaults,
                PreferenceKey.scrollReverseMouseVertical,
                default: false
            ),
            reverseMouseHorizontal: bool(
                defaults,
                PreferenceKey.scrollReverseMouseHorizontal,
                default: false
            ),
            reverseTrackpadVertical: bool(
                defaults,
                PreferenceKey.scrollReverseTrackpadVertical,
                default: false
            ),
            reverseTrackpadHorizontal: bool(
                defaults,
                PreferenceKey.scrollReverseTrackpadHorizontal,
                default: false
            ),
            smoothEnabled: bool(
                defaults,
                PreferenceKey.scrollSmoothEnabled,
                default: false
            ),
            smoothPreset: preset,
            customSmoothParameters: ScrollSmoothParameters(
                stepPixels: double(
                    defaults,
                    PreferenceKey.scrollSmoothCustomStep,
                    fallback: fallback.stepPixels
                ),
                durationMs: double(
                    defaults,
                    PreferenceKey.scrollSmoothCustomDurationMs,
                    fallback: fallback.durationMs
                ),
                acceleration: double(
                    defaults,
                    PreferenceKey.scrollSmoothCustomAcceleration,
                    fallback: fallback.acceleration
                )
            ).clamped(),
            excludedBundleIds: normalizedBundleIds(
                defaults.stringArray(forKey: PreferenceKey.scrollExcludedBundleIds)
                    ?? []
            )
        )
    }

    /// Only the master switch has a default that must exist before first launch.
    /// Feature toggles stay absent so an upgrade does not look like a user edit.
    static func seedMissingDefaults(in defaults: UserDefaults) {
        if defaults.object(forKey: PreferenceKey.scrollEnhancementEnabled) == nil {
            defaults.set(true, forKey: PreferenceKey.scrollEnhancementEnabled)
        }
    }

    static func normalizedBundleIds(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in ids {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        result.sort()
        return result
    }

    private static func bool(
        _ defaults: UserDefaults,
        _ key: String,
        default defaultValue: Bool
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func double(
        _ defaults: UserDefaults,
        _ key: String,
        fallback: Double
    ) -> Double {
        guard let object = defaults.object(forKey: key) else { return fallback }
        let value = (object as? NSNumber)?.doubleValue ?? fallback
        return value.isFinite ? value : fallback
    }
}
