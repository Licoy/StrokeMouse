import XCTest
@testable import StrokeMouse

final class L10nTests: XCTestCase {
    override func tearDown() {
        L10n.apply(.system)
        super.tearDown()
    }

    func testEnglishAndChineseDifferForKnownKey() {
        L10n.apply(.english)
        let en = L10n.string("tab.gestures")
        L10n.apply(.simplifiedChinese)
        let zh = L10n.string("tab.gestures")

        XCTAssertEqual(en, "Gestures")
        XCTAssertEqual(zh, "手势")
        XCTAssertNotEqual(en, zh)
    }

    func testEnableGesturesKey() {
        L10n.apply(.english)
        XCTAssertEqual(L10n.string("general.enableGestures"), "Enable Mouse Gestures")
        L10n.apply(.simplifiedChinese)
        XCTAssertEqual(L10n.string("general.enableGestures"), "启用鼠标手势")
    }

    func testHUDCaptureSettingStringsAreLocalized() {
        let keys = [
            "general.includeHUDInCaptures",
            "general.includeHUDInCapturesHint",
        ]
        L10n.apply(.english)
        let english = keys.map(L10n.string)
        L10n.apply(.simplifiedChinese)
        let chinese = keys.map(L10n.string)

        for (key, value) in zip(keys, english) {
            XCTAssertFalse(value.isEmpty, "Missing EN for \(key)")
            XCTAssertNotEqual(value, key, "Unresolved EN key \(key)")
        }
        for (key, value) in zip(keys, chinese) {
            XCTAssertFalse(value.isEmpty, "Missing ZH for \(key)")
            XCTAssertNotEqual(value, key, "Unresolved ZH key \(key)")
        }
        XCTAssertEqual(zip(english, chinese).filter { $0 == $1 }.count, 0)
    }

    func testEngineFooterPunctuationChinese() {
        L10n.apply(.simplifiedChinese)
        let s = L10n.string("general.engineFooter")
        XCTAssertTrue(s.contains("。"), "Expected Chinese period in: \(s)")
        XCTAssertFalse(s.isEmpty)
    }

    func testPerGestureTriggerHint() {
        L10n.apply(.english)
        let en = L10n.string("editor.triggerPerGestureHint")
        XCTAssertFalse(en.isEmpty)
        L10n.apply(.simplifiedChinese)
        let zh = L10n.string("editor.triggerPerGestureHint")
        XCTAssertFalse(zh.isEmpty)
        XCTAssertNotEqual(en, zh)
    }

    func testGestureTestDiagnosticStringsAreLocalized() {
        let keys = [
            "gestures.test",
            "gestureTest.title",
            "gestureTest.decision.accepted",
            "gestureTest.matchMode.elasticPath",
            "gestureTest.policyMetrics",
            "gestureTest.structure.segmentCount",
            "gestureTest.structure.segmentProportion",
            "gestureTest.structure.terminalOverrun",
            "gestureTest.logSaved",
            "input.mouseDraw.trackpadModifier.summary",
            "gestureTest.inputMode",
            "gestureTest.input.mouseDraw",
            "gestureTest.input.modifierDraw",
            "gestureTest.input.directTrackpad",
            "gestureTest.modifierInstruction",
            "gestureTest.directInstruction",
            "gestureTest.trackpadDrawCanvas",
            "gestureTest.trackpadDrawWaiting",
            "gestureTest.trackpadDrawSource",
            "editor.trackpadModifierSupport",
            "editor.trackpadModifierKey",
            "editor.trackpadModifierHint",
            "general.matchThreshold",
            "general.matchThresholdHint",
        ]
        L10n.apply(.english)
        let english = keys.map(L10n.string)
        L10n.apply(.simplifiedChinese)
        let chinese = keys.map(L10n.string)

        XCTAssertFalse(english.contains(where: \.isEmpty))
        XCTAssertFalse(chinese.contains(where: \.isEmpty))
        XCTAssertEqual(zip(english, chinese).filter { $0 == $1 }.count, 0)
    }

    func testIssue2StringsAreLocalized() {
        let keys = [
            "general.hideMenuBarIcon",
            "general.hideChromeFooter",
            "general.runtimeStatus",
            "general.doubleHideTitle",
            "general.quitApp",
            "general.quitAppFooter",
            "gestures.sidebarTitle",
            "gestures.sidebarAddApp",
            "gestures.emptyAppSubtitle",
        ]
        L10n.apply(.english)
        let english = keys.map(L10n.string)
        L10n.apply(.simplifiedChinese)
        let chinese = keys.map(L10n.string)

        for (key, value) in zip(keys, english) {
            XCTAssertFalse(value.isEmpty, "Missing EN for \(key)")
            XCTAssertNotEqual(value, key, "Unresolved EN key \(key)")
        }
        for (key, value) in zip(keys, chinese) {
            XCTAssertFalse(value.isEmpty, "Missing ZH for \(key)")
            XCTAssertNotEqual(value, key, "Unresolved ZH key \(key)")
        }
        XCTAssertEqual(zip(english, chinese).filter { $0 == $1 }.count, 0)
    }

    func testIssue3TargetStringsAreLocalized() {
        let keys = [
            "editor.target",
            "editor.targetWindow",
            "target.frontmostWindow",
            "target.windowUnderPointer",
            "editor.targetHelp.frontmostWindow",
            "editor.targetHelp.windowUnderPointer",
            "editor.targetPointerShortcutWarning",
            "editor.testActionNeedsTarget",
            "editor.scopeHelp",
            "engine.actionFailed",
            "action.targetUnavailable",
            "action.targetActivationFailed",
            "action.targetActivationTimedOut",
            "action.targetFocusChanged",
            "action.targetWindowControlUnavailable",
            "action.targetHasNoOperableWindow",
            "action.targetOperationFailed",
            "action.appNotFound",
            "action.invalidURL",
            "action.openFailed",
        ]
        L10n.apply(.english)
        let english = keys.map(L10n.string)
        L10n.apply(.simplifiedChinese)
        let chinese = keys.map(L10n.string)

        for (key, value) in zip(keys, english) {
            XCTAssertFalse(value.isEmpty, "Missing EN for \(key)")
            XCTAssertNotEqual(value, key, "Unresolved EN key \(key)")
        }
        for (key, value) in zip(keys, chinese) {
            XCTAssertFalse(value.isEmpty, "Missing ZH for \(key)")
            XCTAssertNotEqual(value, key, "Unresolved ZH key \(key)")
        }
        XCTAssertEqual(zip(english, chinese).filter { $0 == $1 }.count, 0)
    }

    func testShortcutRecorderGuidanceIsLocalized() {
        let keys = [
            "action.shortcutRecordingHint",
            "action.shortcutUnsupportedModifier",
        ]
        L10n.apply(.english)
        let english = keys.map(L10n.string)
        L10n.apply(.simplifiedChinese)
        let chinese = keys.map(L10n.string)

        XCTAssertFalse(english.contains(where: \.isEmpty))
        XCTAssertFalse(chinese.contains(where: \.isEmpty))
        XCTAssertEqual(zip(english, chinese).filter { $0 == $1 }.count, 0)
    }

    func testApplicationSwitchStringsAreLocalized() {
        let keys = ApplicationSwitchCommand.allCases.map(\.displayKey)
        L10n.apply(.english)
        let english = keys.map(L10n.string)
        L10n.apply(.simplifiedChinese)
        let chinese = keys.map(L10n.string)

        for (key, value) in zip(keys, english) {
            XCTAssertFalse(value.isEmpty, "Missing EN for \(key)")
            XCTAssertNotEqual(value, key, "Unresolved EN key \(key)")
        }
        for (key, value) in zip(keys, chinese) {
            XCTAssertFalse(value.isEmpty, "Missing ZH for \(key)")
            XCTAssertNotEqual(value, key, "Unresolved ZH key \(key)")
        }
        XCTAssertEqual(zip(english, chinese).filter { $0 == $1 }.count, 0)
    }

    func testLanguageAllowlistIncludesSystemAndAllShippedLocales() {
        XCTAssertEqual(
            LanguageOverride.allCases.map(\.rawValue),
            ["system", "en", "zh-Hans", "zh-Hant", "ko", "ja", "ru", "fr"]
        )
        XCTAssertEqual(
            LanguageOverride.explicitCatalogLocales.map(\.rawValue),
            ["en", "zh-Hans", "zh-Hant", "ko", "ja", "ru", "fr"]
        )
    }

    func testPreferredLanguageMapsOntoSupportedCatalogLocales() {
        let cases: [([String], String)] = [
            (["zh-CN"], "zh-Hans"),
            (["zh-SG"], "zh-Hans"),
            (["zh-Hans"], "zh-Hans"),
            (["zh-Hans-CN"], "zh-Hans"),
            (["zh_CN"], "zh-Hans"),
            (["zh-TW"], "zh-Hant"),
            (["zh-HK"], "zh-Hant"),
            (["zh-MO"], "zh-Hant"),
            (["zh-Hant"], "zh-Hant"),
            (["zh-Hant-TW"], "zh-Hant"),
            (["zh_TW"], "zh-Hant"),
            (["ja"], "ja"),
            (["ja-JP"], "ja"),
            (["ko"], "ko"),
            (["ko-KR"], "ko"),
            (["ru"], "ru"),
            (["ru-RU"], "ru"),
            (["fr"], "fr"),
            (["fr-FR"], "fr"),
            (["en"], "en"),
            (["en-US"], "en"),
            (["de-DE"], "en"),
            (["de-DE", "fr-FR"], "fr"),
            (["es-ES", "en-US"], "en"),
        ]
        for (preferred, expected) in cases {
            XCTAssertEqual(
                LanguageOverride.catalogLocale(matching: preferred),
                expected,
                "preferred \(preferred)"
            )
        }
    }

    func testSystemOverrideUsesPreferredLanguageResolver() {
        XCTAssertEqual(
            LanguageOverride.system.resolvedCatalogLocale(preferredLanguages: ["zh-TW", "en"]),
            "zh-Hant"
        )
        XCTAssertEqual(
            LanguageOverride.system.resolvedCatalogLocale(preferredLanguages: ["de-DE"]),
            "en"
        )
        XCTAssertEqual(
            LanguageOverride.english.resolvedCatalogLocale(preferredLanguages: ["ja"]),
            "en"
        )
        XCTAssertEqual(
            LanguageOverride.japanese.resolvedCatalogLocale(preferredLanguages: ["fr"]),
            "ja"
        )
    }

    func testExplicitLanguageOverridesResolveShippedCatalogStrings() {
        let keys = [
            "tab.gestures",
            "general.enableGestures",
            "general.language",
        ]
        let properNounAllowlist: Set<String> = ["StrokeMouse"]

        L10n.apply(.english)
        let english = Dictionary(uniqueKeysWithValues: keys.map { ($0, L10n.string($0)) })

        for override in LanguageOverride.explicitCatalogLocales {
            L10n.apply(override)
            for key in keys {
                let value = L10n.string(key)
                XCTAssertFalse(value.isEmpty, "\(override.rawValue) empty for \(key)")
                XCTAssertNotEqual(value, key, "\(override.rawValue) unresolved \(key)")
                guard override != .english else { continue }
                let englishValue = english[key] ?? ""
                if properNounAllowlist.contains(englishValue) { continue }
                XCTAssertNotEqual(
                    value,
                    englishValue,
                    "\(override.rawValue) \(key) should differ from English"
                )
            }
        }
    }

    func testLanguagePickerTitlesStayInTargetLanguageExceptSystem() {
        let expectedNative: [LanguageOverride: String] = [
            .english: "English",
            .simplifiedChinese: "简体中文",
            .traditionalChinese: "繁體中文",
            .korean: "한국어",
            .japanese: "日本語",
            .russian: "Русский",
            .french: "Français",
        ]
        XCTAssertEqual(
            Set(expectedNative.keys),
            Set(LanguageOverride.explicitCatalogLocales)
        )

        for ui in LanguageOverride.explicitCatalogLocales {
            L10n.apply(ui)
            for (lang, name) in expectedNative {
                XCTAssertEqual(
                    lang.pickerTitle,
                    name,
                    "\(lang.rawValue) under UI \(ui.rawValue)"
                )
            }
            let systemTitle = LanguageOverride.system.pickerTitle
            XCTAssertFalse(systemTitle.isEmpty)
            XCTAssertNotEqual(systemTitle, LanguageOverride.system.displayKey)
        }

        L10n.apply(.english)
        XCTAssertEqual(LanguageOverride.system.pickerTitle, "System")
        L10n.apply(.simplifiedChinese)
        XCTAssertEqual(LanguageOverride.system.pickerTitle, "跟随系统")
    }

    func testScrollingStringsAreLocalized() {
        let keys = [
            "tab.scrolling",
            "menu.pauseScrolling",
            "menu.resumeScrolling",
            "permissions.channel.scroll",
            "scroll.section.main",
            "scroll.enabled",
            "scroll.status",
            "scroll.status.listening",
            "scroll.status.paused",
            "scroll.status.notNeeded",
            "scroll.status.needPermission",
            "scroll.status.tapFailed",
            "scroll.main.footer",
            "scroll.section.reverse",
            "scroll.group.mouse",
            "scroll.group.trackpad",
            "scroll.reverse.vertical",
            "scroll.reverse.horizontal",
            "scroll.reverse.footer",
            "scroll.section.smooth",
            "scroll.smooth.enabled",
            "scroll.preset",
            "scroll.preset.gentle",
            "scroll.preset.standard",
            "scroll.preset.responsive",
            "scroll.preset.custom",
            "scroll.advanced",
            "scroll.step",
            "scroll.duration",
            "scroll.acceleration",
            "scroll.unit.px",
            "scroll.unit.ms",
            "scroll.smooth.footer",
            "scroll.section.excluded",
            "scroll.exclude.empty",
            "scroll.exclude.add",
            "scroll.exclude.footer",
        ]
        for locale in LanguageOverride.explicitCatalogLocales {
            L10n.apply(locale)
            for key in keys {
                let value = L10n.string(key)
                XCTAssertFalse(value.isEmpty, "\(locale.rawValue) empty \(key)")
                XCTAssertNotEqual(value, key, "\(locale.rawValue) unresolved \(key)")
            }
        }
    }

    func testAppBundleShipsAllSupportedLocalizations() {
        let shipped = Set(Bundle.main.localizations.map {
            $0.replacingOccurrences(of: "_", with: "-")
        })
        for locale in LanguageOverride.explicitCatalogLocales.map(\.rawValue) {
            XCTAssertTrue(
                shipped.contains(locale),
                "App bundle missing \(locale); have \(shipped.sorted())"
            )
        }
    }
}
