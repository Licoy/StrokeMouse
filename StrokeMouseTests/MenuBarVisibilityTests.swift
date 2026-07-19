import XCTest
@testable import StrokeMouse

@MainActor
final class MenuBarVisibilityTests: XCTestCase {
    private var previousHide: Bool?

    override func setUp() {
        super.setUp()
        previousHide = UserDefaults.standard.object(forKey: PreferenceKey.hideMenuBarIcon) as? Bool
        UserDefaults.standard.removeObject(forKey: PreferenceKey.hideMenuBarIcon)
    }

    override func tearDown() {
        if let previousHide {
            UserDefaults.standard.set(previousHide, forKey: PreferenceKey.hideMenuBarIcon)
        } else {
            UserDefaults.standard.removeObject(forKey: PreferenceKey.hideMenuBarIcon)
        }
        super.tearDown()
    }

    func testSetHideMenuBarIconUpdatesInsertionPreference() {
        let state = AppState()
        XCTAssertFalse(state.prefersHideMenuBarIcon)
        XCTAssertTrue(state.menuBarExtraInserted)

        state.setHideMenuBarIcon(true)
        XCTAssertTrue(state.prefersHideMenuBarIcon)
        XCTAssertFalse(state.menuBarExtraInserted)

        state.setHideMenuBarIcon(false)
        XCTAssertFalse(state.prefersHideMenuBarIcon)
        XCTAssertTrue(state.menuBarExtraInserted)
    }

    func testHandleMenuBarExtraInsertedChangeWritesPreference() {
        let state = AppState()
        state.handleMenuBarExtraInsertedChange(false)
        XCTAssertTrue(state.prefersHideMenuBarIcon)
        XCTAssertFalse(state.menuBarExtraInserted)

        state.handleMenuBarExtraInsertedChange(true)
        XCTAssertFalse(state.prefersHideMenuBarIcon)
        XCTAssertTrue(state.menuBarExtraInserted)
    }

    func testSyncMenuBarExtraInsertedRespectsHidePreference() {
        let state = AppState()
        state.setHideMenuBarIcon(true)
        state.menuBarExtraInserted = true // simulate stale insertion
        state.syncMenuBarExtraInserted()
        XCTAssertFalse(state.menuBarExtraInserted)
        XCTAssertTrue(state.prefersHideMenuBarIcon)
    }

    func testOpenSettingsDoesNotRemountMenuBarWhenHidden() {
        let state = AppState()
        state.setHideMenuBarIcon(true)
        XCTAssertFalse(state.menuBarExtraInserted)

        // Opening settings uses AppKit SettingsWindowController — menu bar stays hidden.
        state.openSettings(tab: .general)

        XCTAssertTrue(state.prefersHideMenuBarIcon)
        XCTAssertFalse(state.menuBarExtraInserted)
    }
}
