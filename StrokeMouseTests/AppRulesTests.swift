import ApplicationServices
import XCTest
@testable import StrokeMouse

final class AppRulesTests: XCTestCase {
    // MARK: - Bundle identifier patterns

    func testPatternMatchesWholeBundleIdentifierIgnoringCase() {
        XCTAssertTrue(AppMatching.matches(pattern: "com.adobe.*", bundleIdentifier: "com.adobe.Photoshop"))
        XCTAssertTrue(AppMatching.matches(pattern: "COM.ADOBE.*", bundleIdentifier: "com.adobe.illustrator"))
        XCTAssertTrue(AppMatching.matches(pattern: "unity.*", bundleIdentifier: "unity.DefaultCompany.MyGame"))
        XCTAssertTrue(AppMatching.matches(pattern: "*.godot", bundleIdentifier: "org.example.godot"))
        XCTAssertTrue(AppMatching.matches(pattern: "com.parallels.*", bundleIdentifier: "com.parallels.winapp.notepad"))
        XCTAssertTrue(AppMatching.matches(pattern: "com.*.game", bundleIdentifier: "com.studio.best.game"))
        XCTAssertTrue(AppMatching.matches(pattern: "com.apple.Safari", bundleIdentifier: "com.apple.safari"))

        XCTAssertFalse(AppMatching.matches(pattern: "com.adobe.*", bundleIdentifier: "com.adobe"))
        XCTAssertFalse(AppMatching.matches(pattern: "com.adobe.*", bundleIdentifier: "org.com.adobe.Photoshop"))
        XCTAssertFalse(AppMatching.matches(pattern: "*.godot", bundleIdentifier: "org.godot.editor"))
        XCTAssertFalse(AppMatching.matches(pattern: "com.apple.Safari", bundleIdentifier: "com.apple.SafariTechnologyPreview"))
    }

    func testPatternWildcardsNeverOverlapLiteralParts() {
        XCTAssertTrue(AppMatching.matches(pattern: "a*a", bundleIdentifier: "aa"))
        XCTAssertFalse(AppMatching.matches(pattern: "ab*ba", bundleIdentifier: "aba"))
        XCTAssertTrue(AppMatching.matches(pattern: "a*b*c", bundleIdentifier: "a.x.b.y.c"))
        XCTAssertFalse(AppMatching.matches(pattern: "a*c*b", bundleIdentifier: "a.b.c"))
    }

    func testPatternNormalization() {
        XCTAssertNil(AppMatching.normalizedPattern("   "))
        XCTAssertNil(AppMatching.normalizedPattern("com.adobe .*"))
        XCTAssertEqual(AppMatching.normalizedPattern("  com.adobe.**  "), "com.adobe.*")
        XCTAssertTrue(AppMatching.isWildcardOnly("**"))
        XCTAssertTrue(AppMatching.matches(pattern: "*", bundleIdentifier: "anything.at.all"))
    }

    // MARK: - Directories

    func testDirectoryMatchIsComponentWiseAndCaseInsensitive() {
        let games = "/Users/test/Library/Application Support/Steam/steamapps/common"
        XCTAssertTrue(AppMatching.path(
            "/Users/test/Library/Application Support/Steam/steamapps/common/Game/Game.app",
            isInside: games
        ))
        XCTAssertTrue(AppMatching.path(
            "/users/TEST/library/application support/steam/steamapps/COMMON/Game.app",
            isInside: games + "/"
        ))
        XCTAssertFalse(AppMatching.path("/Games2/App.app", isInside: "/Games"))
        XCTAssertFalse(AppMatching.path("/Games", isInside: "/Games"))
        XCTAssertFalse(AppMatching.path("relative/App.app", isInside: "/Games"))
        XCTAssertTrue(AppMatching.path("/Games/Sub/../App.app", isInside: "/Games"))
        XCTAssertNil(AppMatching.normalizedDirectory("relative/folder"))
        XCTAssertEqual(
            AppMatching.normalizedDirectory("~/Games"),
            NSHomeDirectory() + "/Games/"
        )
    }

    func testDirectoryMatchFollowsSymlinkedFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppRulesTests-\(UUID().uuidString)", isDirectory: true)
        let real = root.appendingPathComponent("RealLibrary", isDirectory: true)
        let link = root.appendingPathComponent("LinkedLibrary")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: root) }

        let appPath = real.resolvingSymlinksInPath()
            .appendingPathComponent("Game.app").path
        let linkedApp = link.appendingPathComponent("Game.app").path

        XCTAssertTrue(AppMatching.path(appPath, isInside: link.path))
        XCTAssertTrue(AppMatching.path(linkedApp, isInside: real.path))

        let group = AppGroup(name: "Library", matchers: [.directory(real.path)])
        let rules = GestureAppRules(policies: [], groups: [group])
        XCTAssertTrue(rules.groupContains(
            group.id,
            bundleIdentifier: nil,
            path: linkedApp
        ))
    }

    // MARK: - Compiled rules

    func testSuppressionUnionsApplicationPolicyAndMatchingGroups() {
        let rules = GestureAppRules(
            policies: [
                AppGesturePolicy(
                    bundleIdentifier: "com.blender.Blender",
                    suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.mouseDrawing])
                ),
                AppGesturePolicy(
                    bundleIdentifier: "com.example.Inherit",
                    suppressedGlobalInputs: .none
                ),
            ],
            groups: [
                AppGroup(
                    name: "Engines",
                    matchers: [.bundleIdentifierPattern("com.blender.*")],
                    suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.touchGesture])
                ),
                AppGroup(
                    name: "Shares only",
                    matchers: [.bundleIdentifier("com.blender.Blender")]
                ),
            ]
        )

        XCTAssertEqual(
            rules.suppressedGlobalInputs(bundleIdentifier: "COM.BLENDER.BLENDER", path: nil),
            [.mouseDrawing, .touchGesture]
        )
        XCTAssertEqual(
            rules.suppressedGlobalInputs(bundleIdentifier: "com.example.Inherit", path: nil),
            []
        )
        XCTAssertEqual(
            rules.suppressedGlobalInputs(bundleIdentifier: nil, path: "/Applications/Blender.app"),
            []
        )
    }

    func testGroupsMatchByExactIdentifierPatternOrDirectory() {
        let steam = AppGroup(
            name: "Steam",
            matchers: [.directory("/Users/test/Steam/steamapps/common")]
        )
        let adobe = AppGroup(
            name: "Adobe",
            matchers: [
                .bundleIdentifierPattern("com.adobe.*"),
                .bundleIdentifier("com.figma.Desktop"),
            ]
        )
        let rules = GestureAppRules(policies: [], groups: [steam, adobe])

        XCTAssertEqual(
            rules.matchingGroupIDs(
                bundleIdentifier: nil,
                path: "/Users/test/Steam/steamapps/common/Hades/Hades.app"
            ),
            [steam.id]
        )
        XCTAssertTrue(rules.groupContains(
            adobe.id,
            bundleIdentifier: "com.adobe.AfterEffects",
            path: nil
        ))
        XCTAssertTrue(rules.groupContains(
            adobe.id,
            bundleIdentifier: "com.figma.desktop",
            path: nil
        ))
        XCTAssertFalse(rules.groupContains(
            adobe.id,
            bundleIdentifier: "com.figma.agent",
            path: nil
        ))
        XCTAssertFalse(rules.groupContains(
            UUID(),
            bundleIdentifier: "com.adobe.Photoshop",
            path: nil
        ))
    }

    // MARK: - Candidate selection

    func testSelectorDropsSuppressedGlobalsForThatInputKindOnly() {
        let rules = GestureAppRules(
            policies: [AppGesturePolicy(
                bundleIdentifier: "com.blender.Blender",
                suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.mouseDrawing])
            )],
            groups: []
        )
        let global = GestureProfile(name: "Global", pattern: .freePath(PathTemplates.up))
        let scoped = GestureProfile(
            name: "Blender",
            pattern: .freePath(PathTemplates.down),
            scope: .apps(["com.blender.Blender"])
        )
        let snapshot = snapshot(bundleIdentifier: "com.blender.Blender")

        let mouse = GestureCandidateSelector.prepare(
            profiles: [global, scoped],
            snapshot: snapshot,
            inputKind: .mouseDrawing,
            rules: rules
        )
        let modifier = GestureCandidateSelector.prepare(
            profiles: [global, scoped],
            snapshot: snapshot,
            inputKind: .trackpadDrawing,
            rules: rules
        )

        XCTAssertEqual(mouse.map(\.profile.id), [scoped.id])
        XCTAssertEqual(modifier.map(\.profile.id), [global.id, scoped.id])
    }

    func testSelectorKeepsGlobalsWhenTargetIsUnavailable() {
        let rules = GestureAppRules(
            policies: [AppGesturePolicy(bundleIdentifier: "com.blender.Blender")],
            groups: []
        )
        let global = GestureProfile(name: "Global", pattern: .freePath(PathTemplates.up))
        let snapshot = GestureTargetSnapshot(
            frontmostWindow: .unavailable(.noFrontmostApplication),
            windowUnderPointer: .unavailable(.noElementAtPointer)
        )

        let targeted = GestureCandidateSelector.prepare(
            profiles: [global],
            snapshot: snapshot,
            inputKind: .mouseDrawing,
            rules: rules
        )

        XCTAssertEqual(targeted.map(\.profile.id), [global.id])
    }

    func testSelectorKeepsGroupProfilesOnlyForMatchingTargets() {
        let group = AppGroup(name: "Unity", matchers: [.bundleIdentifierPattern("unity.*")])
        let rules = GestureAppRules(policies: [], groups: [group])
        let profile = GestureProfile(
            name: "Unity",
            pattern: .freePath(PathTemplates.up),
            scope: .group(group.id)
        )

        let inGroup = GestureCandidateSelector.prepare(
            profiles: [profile],
            snapshot: snapshot(bundleIdentifier: "unity.Studio.Game"),
            inputKind: .mouseDrawing,
            rules: rules
        )
        let outside = GestureCandidateSelector.prepare(
            profiles: [profile],
            snapshot: snapshot(bundleIdentifier: "com.apple.Safari"),
            inputKind: .mouseDrawing,
            rules: rules
        )
        let withoutRules = GestureCandidateSelector.prepare(
            profiles: [profile],
            snapshot: snapshot(bundleIdentifier: "unity.Studio.Game")
        )

        XCTAssertEqual(inGroup.map(\.profile.id), [profile.id])
        XCTAssertTrue(outside.isEmpty)
        XCTAssertTrue(withoutRules.isEmpty)
    }

    // MARK: - Tier precedence

    func testDrawnPrecedenceIsApplicationThenGroupThenGlobal() {
        let group = AppGroup(name: "Group", matchers: [])
        let global = GestureProfile(name: "Global", pattern: .freePath(PathTemplates.up))
        let grouped = GestureProfile(
            name: "Group",
            pattern: .freePath(PathTemplates.up),
            scope: .group(group.id)
        )
        let application = GestureProfile(
            name: "App",
            pattern: .freePath(PathTemplates.up),
            scope: .apps(["com.example.App"])
        )
        let path = PathTemplates.up.map(\.cgPoint)
        let policy = GestureRecognitionPolicy.standard(minimumPathLength: 0)

        let all = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [global, grouped, application],
            policy: policy
        )
        let withoutApplication = GestureRecognitionEvaluator.evaluateDrawn(
            path: path,
            profiles: [global, grouped],
            policy: policy
        )

        XCTAssertEqual(all.acceptedCandidate?.profile.id, application.id)
        XCTAssertEqual(withoutApplication.acceptedCandidate?.profile.id, grouped.id)
    }

    func testDrawnGroupMissFallsThroughToGlobal() {
        let group = AppGroup(name: "Group", matchers: [])
        let global = GestureProfile(name: "Global Right", pattern: .freePath(PathTemplates.right))
        let grouped = GestureProfile(
            name: "Group Up",
            pattern: .freePath(PathTemplates.up),
            scope: .group(group.id)
        )
        let application = GestureProfile(
            name: "App Down",
            pattern: .freePath(PathTemplates.down),
            scope: .apps(["com.example.App"])
        )

        let result = GestureRecognitionEvaluator.evaluateDrawn(
            path: PathTemplates.right.map(\.cgPoint),
            profiles: [global, grouped, application],
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(result.decision, .accepted)
        XCTAssertEqual(result.acceptedCandidate?.profile.id, global.id)
    }

    func testTrackpadPrecedenceAndSuppression() throws {
        let gesture = DirectTrackpadGesture.swipe(.three, .left)
        let group = AppGroup(
            name: "Adobe",
            matchers: [.bundleIdentifierPattern("com.adobe.*")],
            suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.touchGesture])
        )
        let rules = GestureAppRules(policies: [], groups: [group])
        let global = GestureProfile(name: "Global", input: .trackpad(gesture))
        let grouped = GestureProfile(name: "Group", input: .trackpad(gesture), scope: .group(group.id))
        let application = GestureProfile(
            name: "App",
            input: .trackpad(gesture),
            scope: .apps(["com.adobe.Photoshop"])
        )
        let matcher = DirectTrackpadGestureMatcher()
        let photoshop = snapshot(bundleIdentifier: "com.adobe.Photoshop")

        guard case .selected(let first) = matcher.match(
            gesture,
            profiles: [global, grouped, application],
            snapshot: photoshop,
            rules: rules
        ) else {
            return XCTFail("Expected the application gesture")
        }
        XCTAssertEqual(first.profile.id, application.id)

        guard case .selected(let second) = matcher.match(
            gesture,
            profiles: [global, grouped],
            snapshot: photoshop,
            rules: rules
        ) else {
            return XCTFail("Expected the group gesture")
        }
        XCTAssertEqual(second.profile.id, grouped.id)

        guard case .none = matcher.match(
            gesture,
            profiles: [global],
            snapshot: photoshop,
            rules: rules
        ) else {
            return XCTFail("Suppressed global gesture must not match")
        }

        guard case .selected(let elsewhere) = matcher.match(
            gesture,
            profiles: [global, grouped],
            snapshot: snapshot(bundleIdentifier: "com.apple.finder"),
            rules: rules
        ) else {
            return XCTFail("Global gesture must still match outside the group")
        }
        XCTAssertEqual(elsewhere.profile.id, global.id)
    }

    func testTrackpadConflictInsideGroupTierExecutesNothing() {
        let gesture = DirectTrackpadGesture.tap(.three, .double)
        let group = AppGroup(name: "Group", matchers: [.bundleIdentifier("com.example.App")])
        let rules = GestureAppRules(policies: [], groups: [group])
        let first = GestureProfile(name: "A", input: .trackpad(gesture), scope: .group(group.id))
        let second = GestureProfile(name: "B", input: .trackpad(gesture), scope: .group(group.id))
        let global = GestureProfile(name: "Global", input: .trackpad(gesture))

        let result = DirectTrackpadGestureMatcher().match(
            gesture,
            profiles: [global, first, second],
            snapshot: snapshot(bundleIdentifier: "com.example.App"),
            rules: rules
        )

        guard case .conflict(let ids) = result else {
            return XCTFail("Expected a conflict inside the group tier")
        }
        XCTAssertEqual(ids, [first.id, second.id])
    }

    // MARK: - Persistence shape

    func testGroupScopeUsesV2ReadableWireShape() throws {
        let groupID = UUID()
        let profile = GestureProfile(
            name: "Grouped",
            pattern: .freePath(PathTemplates.up),
            scope: .group(groupID)
        )

        let data = try JSONEncoder().encode(profile)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let scope = try XCTUnwrap(object["scope"] as? [String: Any])
        let apps = try XCTUnwrap(scope["apps"] as? [String: Any])
        XCTAssertEqual((apps["_0"] as? [String]), [])
        XCTAssertEqual(object["appGroup"] as? String, groupID.uuidString)

        let decoded = try JSONDecoder().decode(GestureProfile.self, from: data)
        XCTAssertEqual(decoded.scope, .group(groupID))
    }

    func testConfigFileOmitsEmptyRuleCollections() throws {
        let file = GestureConfigFile(version: Constants.configVersion, gestures: [])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["version", "gestures"])

        let decoded = try JSONDecoder().decode(
            GestureConfigFile.self,
            from: Data(#"{"version": 2, "gestures": []}"#.utf8)
        )
        XCTAssertEqual(decoded.appPolicies, [])
        XCTAssertEqual(decoded.appGroups, [])
    }

    func testSuppressedInputsEncodeSortedAndIgnoreUnknownKinds() throws {
        let policy = AppGesturePolicy(
            bundleIdentifier: "com.example.App",
            suppressedGlobalInputs: SuppressedGlobalInputs(kinds: [.touchGesture, .mouseDrawing])
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(policy)) as? [String: Any]
        )
        XCTAssertEqual(
            object["suppressedGlobalInputs"] as? [String],
            ["mouseDrawing", "touchGesture"]
        )

        let future = Data(
            #"{"bundleIdentifier": "com.example.App", "suppressedGlobalInputs": ["mouseDrawing", "eyeTracking"]}"#.utf8
        )
        let decoded = try JSONDecoder().decode(AppGesturePolicy.self, from: future)
        XCTAssertEqual(decoded.suppressedGlobalInputs.kinds, [.mouseDrawing])
    }

    // MARK: - Helpers

    private func snapshot(bundleIdentifier: String) -> GestureTargetSnapshot {
        let context = GestureTargetContext(
            policy: .frontmostWindow,
            identity: GestureTargetIdentity(
                processIdentifier: 42,
                bundleIdentifier: bundleIdentifier
            ),
            application: nil,
            window: nil
        )
        return GestureTargetSnapshot(
            frontmostWindow: .resolved(context),
            windowUnderPointer: .resolved(context)
        )
    }
}
