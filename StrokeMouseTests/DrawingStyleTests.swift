import XCTest
@testable import StrokeMouse

final class DrawingStyleTests: XCTestCase {
    private var previousIncludeHUDInCaptures: Any?
    private var previousShowMatchToast: Any?
    private var previousShowMissToast: Any?
    private var previousShowLiveMismatch: Any?
    private var previousMismatchColor: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        previousIncludeHUDInCaptures = defaults.object(
            forKey: PreferenceKey.includeGestureHUDInCaptures
        )
        previousShowMatchToast = defaults.object(forKey: PreferenceKey.showMatchToast)
        previousShowMissToast = defaults.object(forKey: PreferenceKey.showMissToast)
        previousShowLiveMismatch = defaults.object(
            forKey: PreferenceKey.showLiveMismatchFeedback
        )
        previousMismatchColor = defaults.object(
            forKey: PreferenceKey.hudMismatchLineColor
        )
        defaults.removeObject(forKey: PreferenceKey.includeGestureHUDInCaptures)
        defaults.removeObject(forKey: PreferenceKey.showMatchToast)
        defaults.removeObject(forKey: PreferenceKey.showMissToast)
        defaults.removeObject(forKey: PreferenceKey.showLiveMismatchFeedback)
        defaults.removeObject(forKey: PreferenceKey.hudMismatchLineColor)
    }

    override func tearDown() {
        restore(previousIncludeHUDInCaptures, key: PreferenceKey.includeGestureHUDInCaptures)
        restore(previousShowMatchToast, key: PreferenceKey.showMatchToast)
        restore(previousShowMissToast, key: PreferenceKey.showMissToast)
        restore(previousShowLiveMismatch, key: PreferenceKey.showLiveMismatchFeedback)
        restore(previousMismatchColor, key: PreferenceKey.hudMismatchLineColor)
        super.tearDown()
    }

    private func restore(_ value: Any?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testHUDIsExcludedFromCapturesByDefault() {
        XCTAssertFalse(DrawingStyle.includeHUDInCaptures)
    }

    func testHUDCapturePreferencePersistsEnabledAndDisabledValues() {
        DrawingStyle.includeHUDInCaptures = true
        XCTAssertTrue(DrawingStyle.includeHUDInCaptures)

        DrawingStyle.includeHUDInCaptures = false
        XCTAssertFalse(DrawingStyle.includeHUDInCaptures)
    }

    func testToastPreferencesDefaultOn() {
        XCTAssertTrue(DrawingStyle.showMatchToast)
        XCTAssertTrue(DrawingStyle.showMissToast)
    }

    func testToastPreferencesPersist() {
        DrawingStyle.showMatchToast = false
        DrawingStyle.showMissToast = false
        XCTAssertFalse(DrawingStyle.showMatchToast)
        XCTAssertFalse(DrawingStyle.showMissToast)

        DrawingStyle.showMatchToast = true
        DrawingStyle.showMissToast = true
        XCTAssertTrue(DrawingStyle.showMatchToast)
        XCTAssertTrue(DrawingStyle.showMissToast)
    }

    func testLiveMismatchFeedbackDefaultsOff() {
        XCTAssertFalse(DrawingStyle.showLiveMismatchFeedback)
    }

    func testMismatchColorDefaultsToAmber() {
        XCTAssertEqual(
            DrawingStyle.mismatchLineColorHex,
            Constants.defaultHUDMismatchLineColorHex
        )
        DrawingStyle.mismatchLineColorHex = "#FF0000FF"
        XCTAssertEqual(DrawingStyle.mismatchLineColorHex, "#FF0000FF")
    }
}
