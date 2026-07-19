import XCTest
@testable import StrokeMouse

final class GestureSidebarCatalogTests: XCTestCase {
    private let safari = "com.apple.Safari"
    private let chrome = "com.google.Chrome"

    private func profile(
        name: String,
        scope: AppScope,
        enabled: Bool = true
    ) -> GestureProfile {
        GestureProfile(
            name: name,
            isEnabled: enabled,
            pattern: .freePath([
                CodablePoint(x: 0, y: 0),
                CodablePoint(x: 10, y: 0),
            ]),
            scope: scope
        )
    }

    func testSidebarAppIdsUnionsPinnedAndReferencedApps() {
        let gestures = [
            profile(name: "Global", scope: .global),
            profile(name: "Safari only", scope: .apps([safari])),
            profile(name: "Multi", scope: .apps([safari, chrome])),
        ]
        let ids = GestureSidebarCatalog.sidebarAppBundleIds(
            gestures: gestures,
            pinnedBundleIds: ["com.apple.Notes", "  ", safari]
        )
        XCTAssertEqual(ids, [chrome, "com.apple.Notes", safari].sorted())
    }

    func testGlobalFilterExcludesAppScopedGestures() {
        let gestures = [
            profile(name: "G1", scope: .global),
            profile(name: "S1", scope: .apps([safari])),
        ]
        let filtered = GestureSidebarCatalog.gestures(in: .global, from: gestures)
        XCTAssertEqual(filtered.map(\.name), ["G1"])
    }

    func testAppFilterIncludesMultiAppGestures() {
        let gestures = [
            profile(name: "G1", scope: .global),
            profile(name: "Safari", scope: .apps([safari])),
            profile(name: "Both", scope: .apps([safari, chrome])),
            profile(name: "Chrome", scope: .apps([chrome])),
        ]
        let safariOnly = GestureSidebarCatalog.gestures(in: .app(safari), from: gestures)
        XCTAssertEqual(Set(safariOnly.map(\.name)), ["Safari", "Both"])

        let chromeOnly = GestureSidebarCatalog.gestures(in: .app(chrome), from: gestures)
        XCTAssertEqual(Set(chromeOnly.map(\.name)), ["Chrome", "Both"])
    }

    func testAppFilterNormalizesWhitespaceBundleIds() {
        let gestures = [
            profile(name: "S", scope: .apps(["  \(safari)  "])),
        ]
        let filtered = GestureSidebarCatalog.gestures(in: .app(safari), from: gestures)
        XCTAssertEqual(filtered.map(\.name), ["S"])
    }

    func testDefaultScopeForSidebarSelection() {
        XCTAssertEqual(GestureSidebarCatalog.defaultScope(for: .global), .global)
        XCTAssertEqual(
            GestureSidebarCatalog.defaultScope(for: .app(safari)),
            .apps([safari])
        )
        XCTAssertEqual(
            GestureSidebarCatalog.defaultScope(for: .app("  ")),
            .global
        )
    }

    func testPreferredSidebarItemAfterSave() {
        XCTAssertEqual(
            GestureSidebarCatalog.preferredSidebarItem(for: .global),
            .global
        )
        XCTAssertEqual(
            GestureSidebarCatalog.preferredSidebarItem(for: .apps([chrome, safari])),
            .app(chrome)
        )
        XCTAssertEqual(
            GestureSidebarCatalog.preferredSidebarItem(for: .apps(["", "  "])),
            .global
        )
    }

    func testPlanRemoveAppDeletesOnlySingleAppGesturesAndStripsMultiApp() {
        let single = profile(name: "S", scope: .apps([safari]))
        let multi = profile(name: "Both", scope: .apps([safari, chrome]))
        let chromeOnly = profile(name: "C", scope: .apps([chrome]))
        let global = profile(name: "G", scope: .global)
        let gestures = [single, multi, chromeOnly, global]

        let plan = GestureSidebarCatalog.planRemoveApp(safari, from: gestures)

        XCTAssertEqual(plan.idsToDelete, [single.id])
        XCTAssertEqual(plan.profilesToUpdate.count, 1)
        XCTAssertEqual(plan.profilesToUpdate[0].id, multi.id)
        XCTAssertEqual(plan.profilesToUpdate[0].scope, .apps([chrome]))

        // Chrome-only and global untouched.
        XCTAssertFalse(plan.idsToDelete.contains(chromeOnly.id))
        XCTAssertFalse(plan.idsToDelete.contains(global.id))
    }

    func testPlanRemoveAppWithNoRelatedGesturesIsEmpty() {
        let gestures = [
            profile(name: "C", scope: .apps([chrome])),
            profile(name: "G", scope: .global),
        ]
        let plan = GestureSidebarCatalog.planRemoveApp(safari, from: gestures)
        XCTAssertTrue(plan.isEmpty)
    }
}
