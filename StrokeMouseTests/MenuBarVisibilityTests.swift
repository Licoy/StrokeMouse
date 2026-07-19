import XCTest
@testable import StrokeMouse

@MainActor
final class MenuBarVisibilityTests: XCTestCase {
    private var previousHideMenuBar: Bool?
    private var previousHideDock: Bool?

    override func setUp() {
        super.setUp()
        previousHideMenuBar = UserDefaults.standard.object(forKey: PreferenceKey.hideMenuBarIcon) as? Bool
        previousHideDock = UserDefaults.standard.object(forKey: PreferenceKey.hideDockIcon) as? Bool
        UserDefaults.standard.removeObject(forKey: PreferenceKey.hideMenuBarIcon)
        UserDefaults.standard.removeObject(forKey: PreferenceKey.hideDockIcon)
    }

    override func tearDown() {
        if let previousHideMenuBar {
            UserDefaults.standard.set(previousHideMenuBar, forKey: PreferenceKey.hideMenuBarIcon)
        } else {
            UserDefaults.standard.removeObject(forKey: PreferenceKey.hideMenuBarIcon)
        }
        if let previousHideDock {
            UserDefaults.standard.set(previousHideDock, forKey: PreferenceKey.hideDockIcon)
        } else {
            UserDefaults.standard.removeObject(forKey: PreferenceKey.hideDockIcon)
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

        // Stub presentation: mounting real Settings UI writes AppStorage and can race dual-hide
        // confirmations in the shared test-host defaults (CI flakiness).
        var presented: SettingsTab?
        state.presentSettingsWindowHandler = { presented = $0 }

        state.openSettings(tab: .general)

        XCTAssertEqual(presented, .general)
        XCTAssertTrue(state.prefersHideMenuBarIcon)
        XCTAssertFalse(state.menuBarExtraInserted)
    }

    func testOpenSettingsStillPresentsWhenMenuBarVisible() {
        let state = AppState()
        XCTAssertFalse(state.prefersHideMenuBarIcon)
        XCTAssertTrue(state.menuBarExtraInserted)

        var presented: SettingsTab?
        state.presentSettingsWindowHandler = { presented = $0 }

        state.openSettings(tab: .permissions)

        XCTAssertEqual(presented, .permissions)
        XCTAssertFalse(state.prefersHideMenuBarIcon)
        XCTAssertTrue(state.menuBarExtraInserted)
    }
}
