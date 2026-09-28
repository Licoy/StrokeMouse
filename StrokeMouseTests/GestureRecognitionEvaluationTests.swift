import XCTest
@testable import StrokeMouse

final class GestureRecognitionEvaluationTests: XCTestCase {
    func testCandidateSelectorUsesEachProfilesFrozenTargetForAppScope() {
        let frontmost = targetContext(
            policy: .frontmostWindow,
            processIdentifier: 101,
            bundleIdentifier: "com.apple.Safari"
        )
        let underPointer = targetContext(
            policy: .windowUnderPointer,
            processIdentifier: 202,
            bundleIdentifier: "com.apple.dt.Xcode"
        )
        let snapshot = GestureTargetSnapshot(
            frontmostWindow: .resolved(frontmost),
            windowUnderPointer: .resolved(underPointer)
        )
        let profiles = [
            GestureProfile(
                name: "Global Active",
                pattern: .freePath(PathTemplates.up),
                scope: .global,
                targetPolicy: .frontmostWindow
            ),
            GestureProfile(
                name: "Global Hover",
                pattern: .freePath(PathTemplates.up),
                scope: .global,
                targetPolicy: .windowUnderPointer
            ),
            GestureProfile(
                name: "Safari Active",
                pattern: .freePath(PathTemplates.down),
                scope: .apps(["com.apple.Safari"]),
                targetPolicy: .frontmostWindow
            ),
            GestureProfile(
                name: "Xcode Active",
                pattern: .freePath(PathTemplates.right),
                scope: .apps(["com.apple.dt.Xcode"]),
                targetPolicy: .frontmostWindow
            ),
            GestureProfile(
                name: "Xcode Hover",
                pattern: .freePath(PathTemplates.left),
                scope: .apps(["com.apple.dt.Xcode"]),
                targetPolicy: .windowUnderPointer
            ),
            GestureProfile(
                name: "Safari Hover",
                pattern: .freePath(PathTemplates.right),
                scope: .apps(["com.apple.Safari"]),
                targetPolicy: .windowUnderPointer
            ),
        ]

        let targeted = GestureCandidateSelector.prepare(
            profiles: profiles,
            snapshot: snapshot
        )

        XCTAssertEqual(targeted.map(\.profile.name), [
            "Global Active",
            "Global Hover",
            "Safari Active",
            "Xcode Hover",
        ])
        XCTAssertEqual(targeted.map(\.target.processIdentifier), [101, 202, 101, 202])
    }

    func testCandidateSelectorDoesNotFallBackToAnotherPolicy() {
        let underPointer = targetContext(
            policy: .windowUnderPointer,
            processIdentifier: 202,
            bundleIdentifier: "com.apple.dt.Xcode"
        )
        let snapshot = GestureTargetSnapshot(
            frontmostWindow: .unavailable(.noFrontmostApplication),
            windowUnderPointer: .resolved(underPointer)
        )
        let global = GestureProfile(
            name: "Global",
            pattern: .freePath(PathTemplates.up),
            targetPolicy: .frontmostWindow
        )
        let appScoped = GestureProfile(
            name: "Scoped",
            pattern: .freePath(PathTemplates.down),
            scope: .apps(["com.apple.Safari"]),
            targetPolicy: .frontmostWindow
        )
        let hoverScoped = GestureProfile(
            name: "Hover Scoped",
            pattern: .freePath(PathTemplates.left),
            scope: .apps(["com.apple.dt.Xcode"]),
            targetPolicy: .windowUnderPointer
        )

        let targeted = GestureCandidateSelector.prepare(
            profiles: [global, appScoped, hoverScoped],
            snapshot: snapshot
        )

        XCTAssertEqual(targeted.map(\.profile.id), [global.id, hoverScoped.id])
        XCTAssertNil(targeted.first?.target.processIdentifier)
    }

    func testCandidateSelectorUsesApplicationOnlyTargetForAppScope() throws {
        let context = GestureTargetContext(
            policy: .frontmostWindow,
            identity: GestureTargetIdentity(
                processIdentifier: 303,
                bundleIdentifier: "com.apple.finder"
            ),
            application: nil,
            window: nil
        )
        let profile = GestureProfile(
            name: "Finder Desktop",
            pattern: .freePath(PathTemplates.up),
            scope: .apps(["com.apple.finder"]),
            targetPolicy: .frontmostWindow
        )
        let snapshot = GestureTargetSnapshot(
            frontmostWindow: .resolved(context),
            windowUnderPointer: .unavailable(.targetNotCaptured(.windowUnderPointer))
        )

        let targeted = GestureCandidateSelector.prepare(
            profiles: [profile],
            snapshot: snapshot
        )

        let selected = try XCTUnwrap(targeted.first)
        XCTAssertEqual(targeted.count, 1)
        XCTAssertEqual(selected.profile.id, profile.id)
        XCTAssertEqual(selected.target.processIdentifier, 303)
        XCTAssertNil(try selected.target.requireContext().window)
    }

    private func targetContext(
        policy: GestureTargetPolicy,
        processIdentifier: pid_t,
        bundleIdentifier: String
    ) -> GestureTargetContext {
        GestureTargetContext(
            policy: policy,
            identity: GestureTargetIdentity(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier
            ),
            application: nil,
            window: GestureWindowTarget(
                element: AXUIElementCreateApplication(processIdentifier)
            )
        )
    }

    func testAcceptsMatchingEnabledProfileForSelectedTrigger() {
        let template = GestureRecognitionTestSupport.recordedNarrowPeak
        let matching = GestureProfile(
            name: "Peak",
            trigger: GestureTrigger(button: .middle),
            pattern: .freePath(template.map(CodablePoint.init))
        )
        let wrongTrigger = GestureProfile(
            name: "Wrong Trigger",
            trigger: GestureTrigger(button: .right),
            pattern: .freePath(template.map(CodablePoint.init))
        )

        let result = GestureRecognitionEvaluator.evaluate(
            path: template,
            profiles: [matching, wrongTrigger],
            button: .middle,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(result.decision, .accepted)
        XCTAssertEqual(result.acceptedCandidate?.profile.id, matching.id)
        XCTAssertEqual(result.candidates.map(\.profile.id), [matching.id])
    }

    func testRejectsDisabledProfilesAndReportsNoCandidates() {
        let disabled = GestureProfile(
            name: "Disabled",
            isEnabled: false,
            pattern: .freePath(PathTemplates.up)
        )

        let result = GestureRecognitionEvaluator.evaluate(
            path: PathTemplates.up.map(\.cgPoint),
            profiles: [disabled],
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(result.decision, .noCandidates)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testBelowThresholdCannotBeAcceptedEvenWithClearLead() {
        let peak = GestureProfile(
            name: "Peak",
            pattern: .freePath(GestureRecognitionTestSupport.recordedNarrowPeak.map(CodablePoint.init))
        )
        let horizontal = GestureProfile(
            name: "Horizontal",
            pattern: .freePath(PathTemplates.right)
        )
        let unrelated = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 20, y: -10),
            CGPoint(x: 10, y: 30),
            CGPoint(x: 40, y: 5),
        ]

        let result = GestureRecognitionEvaluator.evaluate(
            path: unrelated,
            profiles: [peak, horizontal],
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertNotEqual(result.decision, .accepted)
        XCTAssertNil(result.acceptedCandidate)
    }

    func testEqualScoresSortByProfileID() {
        let template = PathTemplates.up
        let later = GestureProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Later",
            pattern: .freePath(template)
        )
        let earlier = GestureProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Earlier",
            pattern: .freePath(template)
        )

        let result = GestureRecognitionEvaluator.evaluate(
            path: template.map(\.cgPoint),
            profiles: [later, earlier],
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(result.candidates[0].score, result.candidates[1].score)
        XCTAssertEqual(result.candidates.map(\.profile.id), [earlier.id, later.id])
    }

    func testRepeatedEvaluationWithTemplateCacheIsDeterministic() {
        let profiles = [
            GestureProfile(name: "Up", pattern: .freePath(PathTemplates.up)),
            GestureProfile(name: "Down", pattern: .freePath(PathTemplates.down)),
            GestureProfile(
                name: "Peak",
                pattern: .freePath(GestureRecognitionTestSupport.recordedNarrowPeak.map(CodablePoint.init))
            ),
        ]
        let path = (0..<40).map { CGPoint(x: 200, y: 100 + CGFloat($0) * 8) }

        let first = GestureRecognitionEvaluator.evaluate(
            path: path,
            profiles: profiles,
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )
        let second = GestureRecognitionEvaluator.evaluate(
            path: path,
            profiles: profiles,
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(first.decision, second.decision)
        XCTAssertEqual(first.candidates.map(\.score), second.candidates.map(\.score))
        XCTAssertEqual(first.candidates.map(\.shapeScore), second.candidates.map(\.shapeScore))
    }

    func testTemplateCacheInvalidatesWhenTemplatePointsChange() {
        let id = UUID()
        let up = PathTemplates.up.map(\.cgPoint)
        let down = PathTemplates.down.map(\.cgPoint)

        let first = GestureTemplateCache.shared.prepared(id: id, points: up)
        XCTAssertEqual(first.points, up)

        let edited = GestureTemplateCache.shared.prepared(id: id, points: down)
        XCTAssertEqual(edited.points, down)
        XCTAssertEqual(edited.profile?.points, TemplateMatcher.prepare(down).profile?.points)

        let cached = GestureTemplateCache.shared.prepared(id: id, points: down)
        XCTAssertEqual(cached.points, down)
        XCTAssertEqual(cached.profile?.points, edited.profile?.points)
    }

    func testInvalidTemplateMismatchIsAvailableForDiagnostics() {
        let profile = GestureProfile(
            name: "Collapsed",
            pattern: .freePath([CodablePoint(x: 0.5, y: 0.5), CodablePoint(x: 0.5, y: 0.5)])
        )

        let result = GestureRecognitionEvaluator.evaluate(
            path: GestureRecognitionTestSupport.recordedNarrowPeak,
            profiles: [profile],
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(result.decision, .belowThreshold)
        XCTAssertEqual(result.candidates.first?.score, 0)
        XCTAssertEqual(result.candidates.first?.structuralMismatch, .invalidTemplate)
        XCTAssertNil(result.candidates.first?.diagnostics)
    }

    func testIdenticalTopCandidatesAreRejectedAsAmbiguous() {
        let template = GestureRecognitionTestSupport.recordedNarrowPeak
        let profiles = ["First", "Second"].map { name in
            GestureProfile(
                name: name,
                pattern: .freePath(template.map(CodablePoint.init))
            )
        }

        let result = GestureRecognitionEvaluator.evaluate(
            path: template,
            profiles: profiles,
            button: .right,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(result.decision, .ambiguous)
        XCTAssertNil(result.acceptedCandidate)
        XCTAssertEqual(result.candidates.count, 2)
    }

    func testDrawnApplicationSpecificDirectionsOverrideMatchingGlobals() {
        let globalUp = GestureProfile(
            name: "Global Up",
            pattern: .freePath(PathTemplates.up)
        )
        let globalDown = GestureProfile(
            name: "Global Down",
            pattern: .freePath(PathTemplates.down)
        )
        let chromeUp = GestureProfile(
            name: "Chrome Up",
            pattern: .freePath(PathTemplates.up),
            scope: .apps(["com.google.Chrome"])
        )
        let chromeDown = GestureProfile(
            name: "Chrome Down",
            pattern: .freePath(PathTemplates.down),
            scope: .apps(["com.google.Chrome"])
        )
        let profiles = [globalUp, globalDown, chromeUp, chromeDown]

        for (path, expected) in [
            (PathTemplates.up, chromeUp),
            (PathTemplates.down, chromeDown),
        ] {
            let result = GestureRecognitionEvaluator.evaluateDrawn(
                path: path.map(\.cgPoint),
                profiles: profiles,
                policy: .standard(minimumPathLength: 0)
            )

            XCTAssertEqual(result.decision, .accepted)
            XCTAssertEqual(result.acceptedCandidate?.profile.id, expected.id)
        }
    }

    func testDrawnFallsBackToGlobalWhenApplicationSpecificDoesNotMatch() {
        let global = GestureProfile(
            name: "Global Right",
            pattern: .freePath(PathTemplates.right)
        )
        let chrome = GestureProfile(
            name: "Chrome Up",
            pattern: .freePath(PathTemplates.up),
            scope: .apps(["com.google.Chrome"])
        )
        let appOnly = GestureRecognitionEvaluator.evaluateDrawn(
            path: PathTemplates.right.map(\.cgPoint),
            profiles: [chrome],
            policy: .standard(minimumPathLength: 0)
        )

        let result = GestureRecognitionEvaluator.evaluateDrawn(
            path: PathTemplates.right.map(\.cgPoint),
            profiles: [global, chrome],
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(appOnly.decision, .belowThreshold)
        XCTAssertEqual(result.decision, .accepted)
        XCTAssertEqual(result.acceptedCandidate?.profile.id, global.id)
        XCTAssertEqual(result.candidates.map(\.profile.id), [global.id])
    }

    func testDrawnApplicationSpecificAmbiguityDoesNotFallBackToGlobal() {
        let template = GestureRecognitionTestSupport.recordedNarrowPeak
        let global = GestureProfile(
            name: "Global",
            pattern: .freePath(template.map(CodablePoint.init))
        )
        let applicationSpecific = ["First", "Second"].map { name in
            GestureProfile(
                name: name,
                pattern: .freePath(template.map(CodablePoint.init)),
                scope: .apps(["com.google.Chrome"])
            )
        }

        let result = GestureRecognitionEvaluator.evaluateDrawn(
            path: template,
            profiles: [global] + applicationSpecific,
            policy: .standard(minimumPathLength: 0)
        )

        XCTAssertEqual(result.decision, .ambiguous)
        XCTAssertNil(result.acceptedCandidate)
        XCTAssertEqual(
            Set(result.candidates.map(\.profile.id)),
            Set(applicationSpecific.map(\.id))
        )
    }

    func testInvalidAndTooShortPathsHaveExplicitDecisions() {
        let invalid = GestureRecognitionEvaluator.evaluate(
            path: [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 1, y: 1)],
            profiles: [],
            button: .right,
            policy: .standard(minimumPathLength: 40)
        )
        let tooShort = GestureRecognitionEvaluator.evaluate(
            path: [CGPoint.zero, CGPoint(x: 5, y: 0)],
            profiles: [],
            button: .right,
            policy: .standard(minimumPathLength: 40)
        )

        XCTAssertEqual(invalid.decision, .invalidPath)
        XCTAssertEqual(tooShort.decision, .tooShort)
    }
}
