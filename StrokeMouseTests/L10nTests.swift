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
            "gestureTest.matchMode.simpleSegmentCanonical",
            "gestureTest.matchMode.orderedPath",
            "gestureTest.structure.segmentCount",
            "gestureTest.structure.segmentProportion",
            "gestureTest.structure.terminalOverrun",
            "gestureTest.logSaved",
        ]
        L10n.apply(.english)
        let english = keys.map(L10n.string)
        L10n.apply(.simplifiedChinese)
        let chinese = keys.map(L10n.string)

        XCTAssertFalse(english.contains(where: \.isEmpty))
        XCTAssertFalse(chinese.contains(where: \.isEmpty))
        XCTAssertEqual(zip(english, chinese).filter { $0 == $1 }.count, 0)
    }
}
