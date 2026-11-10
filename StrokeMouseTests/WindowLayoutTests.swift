import XCTest
@testable import StrokeMouse

final class WindowLayoutTests: XCTestCase {
    func testPercentagesUseUsableAreaOriginOnSecondaryDisplay() throws {
        let usable = CGRect(x: -1600, y: -800, width: 1600, height: 900)
        XCTAssertEqual(try WindowLayout().frame(in: usable),
                       CGRect(x: -1440, y: -710, width: 1280, height: 720))
        XCTAssertEqual(try WindowLayout(x: 50, y: 0, width: 50, height: 100).frame(in: usable),
                       CGRect(x: -800, y: -800, width: 800, height: 900))
    }

    func testRejectsInvalidAndNonFiniteLayouts() throws {
        for layout in [WindowLayout(x: -1), WindowLayout(width: 0), WindowLayout(height: -10),
                       WindowLayout(x: 50, width: 60), WindowLayout(y: 99),
                       WindowLayout(x: .nan), WindowLayout(width: .infinity)] {
            XCTAssertFalse(layout.isValid)
            XCTAssertThrowsError(try layout.frame(in: CGRect(x: 0, y: 0, width: 100, height: 100)))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(WindowLayout.self,
            from: Data(#"{"x":90,"y":0,"width":80,"height":100}"#.utf8)))
    }

    func testActionsRoundTripWithoutLosingPercentages() throws {
        let actions: [GestureAction] = [.customWindow(.init(x: 12.5, y: 0, width: 75, height: 100))]
            + WindowCommand.allCases.map { .window($0) }
        for action in actions {
            XCTAssertEqual(try JSONDecoder().decode(GestureAction.self,
                from: JSONEncoder().encode(action)), action)
        }
    }

    func testNewActionsRequireVersionEightIncludingSecondaryActions() {
        for action in [GestureAction.customWindow(WindowLayout())]
            + WindowCommand.allCases.filter(\.isExtended).map({ .window($0) }) {
            var profile = GestureProfile(name: "Layout", pattern: .freePath(PathTemplates.up), action: action)
            XCTAssertEqual(GestureConfigFile.requiredVersion(for: [profile]), 8)
            profile.action = .window(.center)
            profile.secondaryAction = action
            XCTAssertEqual(GestureConfigFile.requiredVersion(for: [profile]), 8)
        }
        XCTAssertEqual(GestureConfigFile.requiredVersion(for: [GestureProfile(
            name: "Old", pattern: .freePath(PathTemplates.up), action: .window(.center))]), 2)
    }
}
