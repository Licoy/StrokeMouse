import XCTest
@testable import StrokeMouse

final class AppleScriptPresetTests: XCTestCase {
    func testBuiltInPresetsHaveNonEmptySource() {
        let builtIns = AppleScriptPreset.allCases.filter { $0 != .custom }
        XCTAssertGreaterThanOrEqual(builtIns.count, 10)
        for preset in builtIns {
            let source = preset.source
            XCTAssertNotNil(source, "\(preset.rawValue) should have a source")
            XCTAssertFalse(
                source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                "\(preset.rawValue) source should not be blank"
            )
        }
    }

    func testCustomHasNoSource() {
        XCTAssertNil(AppleScriptPreset.custom.source)
    }

    func testMatchingExactSource() {
        for preset in AppleScriptPreset.allCases where preset != .custom {
            guard let source = preset.source else {
                XCTFail("missing source for \(preset.rawValue)")
                continue
            }
            XCTAssertEqual(AppleScriptPreset.matching(source: source), preset)
        }
    }

    func testMatchingTrimsWhitespace() {
        guard let source = AppleScriptPreset.sleep.source else {
            return XCTFail("sleep source missing")
        }
        let padded = "\n  \(source)  \n"
        XCTAssertEqual(AppleScriptPreset.matching(source: padded), .sleep)
    }

    func testMatchingUnknownIsCustom() {
        XCTAssertEqual(
            AppleScriptPreset.matching(source: "display dialog \"hello\""),
            .custom
        )
        XCTAssertEqual(AppleScriptPreset.matching(source: ""), .custom)
    }

    func testGestureActionDetailUsesPresetDisplayKeyForBuiltIns() {
        guard let source = AppleScriptPreset.emptyTrash.source else {
            return XCTFail("emptyTrash source missing")
        }
        let action = GestureAction.appleScript(source)
        XCTAssertEqual(action.detail, L10n.string("applescript.emptyTrash"))
    }

    func testGestureActionDetailTruncatesCustomScript() {
        let long = String(repeating: "a", count: 50)
        let action = GestureAction.appleScript(long)
        XCTAssertTrue(action.detail.hasSuffix("…"))
        XCTAssertEqual(action.detail.count, 41)
    }
}
