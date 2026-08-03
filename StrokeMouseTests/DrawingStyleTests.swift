import XCTest
@testable import StrokeMouse

final class DrawingStyleTests: XCTestCase {
    private var previousIncludeHUDInCaptures: Bool?

    override func setUp() {
        super.setUp()
        previousIncludeHUDInCaptures = UserDefaults.standard.object(
            forKey: PreferenceKey.includeGestureHUDInCaptures
        ) as? Bool
        UserDefaults.standard.removeObject(
            forKey: PreferenceKey.includeGestureHUDInCaptures
        )
    }

    override func tearDown() {
        if let previousIncludeHUDInCaptures {
            UserDefaults.standard.set(
                previousIncludeHUDInCaptures,
                forKey: PreferenceKey.includeGestureHUDInCaptures
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: PreferenceKey.includeGestureHUDInCaptures
            )
        }
        super.tearDown()
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
}
