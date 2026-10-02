import XCTest
@testable import StrokeMouse

final class PortableSettingsTests: XCTestCase {
    func testCaptureReadsOnlyThePortableWhitelist() throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        seedPortableValues(in: defaults)
        defaults.set(false, forKey: PreferenceKey.gesturesEnabled)
        defaults.set(false, forKey: PreferenceKey.automaticallyChecksForUpdates)
        defaults.set(true, forKey: PreferenceKey.hideDockIcon)

        let settings = PortableSettingsV1.capture(from: defaults)
        let encoded = try JSONEncoder().encode(settings)
        let keys = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        ).keys

        XCTAssertEqual(settings.minStrokeDistance, 75)
        XCTAssertEqual(settings.matchThreshold, 0.77)
        XCTAssertEqual(
            settings.ambiguityResolution,
            GestureAmbiguityResolution.chooseBest.rawValue
        )
        XCTAssertEqual(settings.appearance, AppearanceMode.dark.rawValue)
        XCTAssertEqual(settings.language, LanguageOverride.english.rawValue)
        XCTAssertEqual(
            Set(keys),
            Set([
                "minStrokeDistance", "matchThreshold", "ambiguityResolution",
                "appearance",
                "menuBarIconStyle", "language", "pinnedGestureAppBundleIds",
                "showGestureHUD", "includeGestureHUDInCaptures",
                "directTrackpadEnabled", "hudLineColor", "hudLineWidth",
                "hudShowStartPoint", "hudStartPointRadius", "showMatchToast",
                "showMissToast", "showLiveMismatchFeedback",
                "hudMismatchLineColor",
            ])
        )
        XCTAssertFalse(keys.contains("gesturesEnabled"))
        XCTAssertFalse(keys.contains("automaticallyChecksForUpdates"))
        XCTAssertFalse(keys.contains("hideDockIcon"))
    }

    func testApplyWritesPortableValuesAndPreservesDeviceLocalSettings() throws {
        let source = makeDefaults()
        let destination = makeDefaults()
        defer {
            clear(source)
            clear(destination)
        }
        seedPortableValues(in: source)
        destination.set(true, forKey: PreferenceKey.gesturesEnabled)
        destination.set(false, forKey: PreferenceKey.automaticallyChecksForUpdates)
        destination.set(true, forKey: PreferenceKey.hideMenuBarIcon)
        destination.set(true, forKey: PreferenceKey.acceptedExperimentalTrackpadRisk)

        try PortableSettingsV1.capture(from: source).apply(to: destination)
        let applied = PortableSettingsV1.capture(from: destination)

        XCTAssertEqual(applied, PortableSettingsV1.capture(from: source))
        XCTAssertEqual(
            destination.string(forKey: PreferenceKey.ambiguityResolution),
            GestureAmbiguityResolution.chooseBest.rawValue
        )
        XCTAssertTrue(destination.bool(forKey: PreferenceKey.gesturesEnabled))
        XCTAssertFalse(destination.bool(
            forKey: PreferenceKey.automaticallyChecksForUpdates
        ))
        XCTAssertTrue(destination.bool(forKey: PreferenceKey.hideMenuBarIcon))
        XCTAssertTrue(destination.bool(
            forKey: PreferenceKey.acceptedExperimentalTrackpadRisk
        ))
    }

    func testValidationRunsBeforeAnyDefaultsMutation() throws {
        let source = makeDefaults()
        let destination = makeDefaults()
        defer {
            clear(source)
            clear(destination)
        }
        seedPortableValues(in: source)
        var invalid = PortableSettingsV1.capture(from: source)
        invalid.hudLineWidth = 0
        destination.set("sentinel", forKey: PreferenceKey.appearance)

        XCTAssertThrowsError(try invalid.apply(to: destination)) { error in
            XCTAssertEqual(
                error as? PortableSettingsValidationError,
                .invalidHUDLineWidth(0)
            )
        }
        XCTAssertEqual(
            destination.string(forKey: PreferenceKey.appearance),
            "sentinel"
        )
        XCTAssertNil(destination.object(forKey: PreferenceKey.minStrokeDistance))
    }

    func testValidationRejectsDuplicatePinnedAppsAndInvalidEnums() {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        var settings = PortableSettingsV1.capture(from: defaults)
        settings.pinnedGestureAppBundleIds = ["com.apple.Safari", "com.apple.Safari"]

        XCTAssertThrowsError(try settings.validate()) { error in
            XCTAssertEqual(
                error as? PortableSettingsValidationError,
                .duplicatePinnedBundleIdentifier("com.apple.Safari")
            )
        }

        settings.pinnedGestureAppBundleIds = []
        settings.language = "not-a-language"
        XCTAssertThrowsError(try settings.validate()) { error in
            XCTAssertEqual(
                error as? PortableSettingsValidationError,
                .invalidLanguage("not-a-language")
            )
        }

        settings.language = LanguageOverride.system.rawValue
        settings.ambiguityResolution = "not-a-resolution"
        XCTAssertThrowsError(try settings.validate()) { error in
            XCTAssertEqual(
                error as? PortableSettingsValidationError,
                .invalidAmbiguityResolution("not-a-resolution")
            )
        }

        settings.ambiguityResolution = GestureAmbiguityResolution.reject.rawValue
        for language in LanguageOverride.allCases {
            settings.language = language.rawValue
            XCTAssertNoThrow(
                try settings.validate(),
                "rejected shipped language \(language.rawValue)"
            )
        }
    }

    func testLegacySettingsWithoutAmbiguityResolutionDecodeAndApplyReject()
        throws
    {
        let source = makeDefaults()
        let destination = makeDefaults()
        defer {
            clear(source)
            clear(destination)
        }
        seedPortableValues(in: source)
        let encoded = try JSONEncoder().encode(
            PortableSettingsV1.capture(from: source)
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "ambiguityResolution")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let legacy = try JSONDecoder().decode(
            PortableSettingsV1.self,
            from: legacyData
        )
        XCTAssertNil(legacy.ambiguityResolution)

        destination.set(
            GestureAmbiguityResolution.chooseBest.rawValue,
            forKey: PreferenceKey.ambiguityResolution
        )
        try legacy.apply(to: destination)
        XCTAssertEqual(
            destination.string(forKey: PreferenceKey.ambiguityResolution),
            GestureAmbiguityResolution.reject.rawValue
        )

    }

    func testCaptureDefaultsMissingAmbiguityResolutionToReject() {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        XCTAssertEqual(
            PortableSettingsV1.capture(from: defaults).ambiguityResolution,
            GestureAmbiguityResolution.reject.rawValue
        )
    }

    func testCapturePreservesInvalidAmbiguityResolutionForValidation() {
        let defaults = makeDefaults()
        let destination = makeDefaults()
        defer { clear(defaults) }
        defer { clear(destination) }
        defaults.set(
            "invalid-resolution",
            forKey: PreferenceKey.ambiguityResolution
        )
        destination.set("sentinel", forKey: PreferenceKey.appearance)

        let captured = PortableSettingsV1.capture(from: defaults)
        XCTAssertEqual(captured.ambiguityResolution, "invalid-resolution")
        XCTAssertThrowsError(try captured.apply(to: destination)) { error in
            XCTAssertEqual(
                error as? PortableSettingsValidationError,
                .invalidAmbiguityResolution("invalid-resolution")
            )
        }
        XCTAssertEqual(
            destination.string(forKey: PreferenceKey.appearance),
            "sentinel"
        )
        XCTAssertNil(destination.object(
            forKey: PreferenceKey.ambiguityResolution
        ))
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PortableSettingsTests-\(UUID().uuidString)")!
    }

    private func clear(_ defaults: UserDefaults) {
        if let name = defaults.volatileDomainNames.first(where: {
            $0.hasPrefix("PortableSettingsTests-")
        }) {
            defaults.removePersistentDomain(forName: name)
        }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }

    private func seedPortableValues(in defaults: UserDefaults) {
        defaults.set(75.0, forKey: PreferenceKey.minStrokeDistance)
        defaults.set(0.77, forKey: PreferenceKey.matchThreshold)
        defaults.set(
            GestureAmbiguityResolution.chooseBest.rawValue,
            forKey: PreferenceKey.ambiguityResolution
        )
        defaults.set(AppearanceMode.dark.rawValue, forKey: PreferenceKey.appearance)
        defaults.set(
            MenuBarIconStyle.color.rawValue,
            forKey: PreferenceKey.menuBarIconStyle
        )
        defaults.set(
            LanguageOverride.english.rawValue,
            forKey: PreferenceKey.language
        )
        defaults.set(
            ["com.apple.Safari", "com.apple.Terminal"],
            forKey: PreferenceKey.pinnedGestureAppBundleIds
        )
        defaults.set(false, forKey: PreferenceKey.showGestureHUD)
        defaults.set(true, forKey: PreferenceKey.includeGestureHUDInCaptures)
        defaults.set(false, forKey: PreferenceKey.directTrackpadEnabled)
        defaults.set("#112233FF", forKey: PreferenceKey.hudLineColor)
        defaults.set(6.0, forKey: PreferenceKey.hudLineWidth)
        defaults.set(false, forKey: PreferenceKey.hudShowStartPoint)
        defaults.set(9.0, forKey: PreferenceKey.hudStartPointRadius)
        defaults.set(false, forKey: PreferenceKey.showMatchToast)
        defaults.set(false, forKey: PreferenceKey.showMissToast)
        defaults.set(true, forKey: PreferenceKey.showLiveMismatchFeedback)
        defaults.set("#AABBCCDD", forKey: PreferenceKey.hudMismatchLineColor)
    }
}
