import CoreGraphics
import XCTest
@testable import StrokeMouse

@MainActor
final class ScrollEngineTests: XCTestCase {
    func testTapStartsOnlyWhenRequirementFlips() {
        let harness = Harness()
        harness.permission.isAccessibilityTrusted = true
        var configuration = requiringConfiguration(step: 80)

        harness.engine.apply(configuration)
        XCTAssertEqual(harness.source.startCount, 1)
        XCTAssertEqual(harness.engine.status, .listening)

        configuration.customSmoothParameters.stepPixels = 120
        harness.engine.apply(configuration)
        XCTAssertEqual(harness.source.startCount, 1)
        XCTAssertEqual(harness.source.stopCount, 0)
        XCTAssertEqual(harness.source.snapshot.smoothStepPixels, 120)

        configuration.smoothEnabled = false
        harness.engine.apply(configuration)
        XCTAssertEqual(harness.source.stopCount, 1)
        XCTAssertEqual(harness.engine.status, .notNeeded)
        XCTAssertGreaterThan(harness.driver.cancelCount, 0)
    }

    func testTrustLossAndLatchedCreationFailure() {
        let harness = Harness()
        harness.engine.apply(requiringConfiguration())
        XCTAssertEqual(harness.source.startCount, 0)
        XCTAssertEqual(harness.engine.status, .failed(.accessibilityRequired))

        harness.permission.isAccessibilityTrusted = true
        harness.engine.accessibilityTrustDidChange(true)
        XCTAssertEqual(harness.source.startCount, 1)
        XCTAssertEqual(harness.engine.status, .listening)

        harness.permission.isAccessibilityTrusted = false
        harness.engine.accessibilityTrustDidChange(false)
        XCTAssertFalse(harness.source.isActive)
        XCTAssertEqual(harness.engine.status, .failed(.accessibilityRequired))

        harness.permission.isAccessibilityTrusted = true
        harness.source.startResult = .failure(.eventTapCreationFailed)
        harness.engine.accessibilityTrustDidChange(true)
        XCTAssertEqual(harness.engine.status, .failed(.eventTapCreationFailed))
        let starts = harness.source.startCount
        harness.engine.apply(requiringConfiguration(step: 100))
        XCTAssertEqual(harness.source.startCount, starts)

        harness.source.startResult = .success(())
        harness.engine.retry()
        XCTAssertEqual(harness.source.startCount, starts + 1)
        XCTAssertEqual(harness.engine.status, .listening)
    }

    func testSleepCancelsAnimationAndExclusionReachesSnapshot() {
        let harness = Harness()
        harness.permission.isAccessibilityTrusted = true
        var configuration = requiringConfiguration()
        configuration.excludedBundleIds = ["com.apple.Safari"]
        harness.frontmost.value = "com.apple.Safari"
        harness.engine.apply(configuration)
        XCTAssertTrue(harness.source.snapshot.frontmostExcluded)

        let cancels = harness.driver.cancelCount
        harness.engine.handleSleep()
        XCTAssertEqual(harness.driver.cancelCount, cancels + 1)
        XCTAssertTrue(harness.source.isActive)

        harness.engine.frontmostApplicationDidChange("com.apple.Terminal")
        XCTAssertFalse(harness.source.snapshot.frontmostExcluded)
    }

    func testWakeRebuildsADeadTap() {
        let harness = Harness()
        harness.permission.isAccessibilityTrusted = true
        harness.engine.apply(requiringConfiguration())
        harness.source.reassertResult = false
        let starts = harness.source.startCount
        harness.engine.handleWake()
        XCTAssertEqual(harness.source.startCount, starts + 1)
        XCTAssertEqual(harness.engine.status, .listening)
    }

    func testListeningDoesNotDependOnGesturePause() {
        let harness = Harness()
        harness.permission.isAccessibilityTrusted = true
        harness.engine.apply(requiringConfiguration())
        XCTAssertEqual(harness.engine.status, .listening)
        XCTAssertEqual(harness.source.startCount, 1)
    }

    func testPreferencesLoadClampsAndSeedOnlyWritesTheMasterSwitch() {
        let defaults = UserDefaults(
            suiteName: "ScrollEngineTests-\(UUID().uuidString)"
        )!
        defaults.set(
            ["com.example.B", "com.example.A", "com.example.A", " "],
            forKey: PreferenceKey.scrollExcludedBundleIds
        )
        defaults.set(9_999.0, forKey: PreferenceKey.scrollSmoothCustomStep)
        defaults.set("nope", forKey: PreferenceKey.scrollSmoothPreset)

        let loaded = ScrollPreferences.load(from: defaults)
        XCTAssertTrue(loaded.isEnabled)
        XCTAssertEqual(loaded.smoothPreset, .standard)
        XCTAssertEqual(
            loaded.customSmoothParameters.stepPixels,
            Constants.scrollStepRange.upperBound
        )
        XCTAssertEqual(
            loaded.excludedBundleIds,
            ["com.example.A", "com.example.B"]
        )

        let seeded = UserDefaults(
            suiteName: "ScrollEngineSeed-\(UUID().uuidString)"
        )!
        ScrollPreferences.seedMissingDefaults(in: seeded)
        XCTAssertEqual(
            seeded.bool(forKey: PreferenceKey.scrollEnhancementEnabled),
            true
        )
        XCTAssertNil(seeded.object(forKey: PreferenceKey.scrollSmoothEnabled))
        XCTAssertNil(seeded.object(forKey: PreferenceKey.scrollReverseMouseVertical))
    }

    private func requiringConfiguration(
        step: Double = 80
    ) -> ScrollEnhancementConfiguration {
        var configuration = ScrollEnhancementConfiguration.dormant
        configuration.smoothEnabled = true
        configuration.smoothPreset = .custom
        configuration.customSmoothParameters.stepPixels = step
        return configuration
    }
}

@MainActor
private final class FakeScrollPermission: GesturePermissionProviding {
    var isAccessibilityTrusted = false
    func refresh() {}
}

private final class FakeScrollSource: ScrollEventSource {
    var snapshot = ScrollTapSnapshot()
    var onImpulse: (@Sendable (ScrollImpulse) -> Void)?
    var onAnimationCancelRequested: (@Sendable () -> Void)?
    private(set) var isActive = false
    var startResult: Result<Void, ScrollEventTapError> = .success(())
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var reassertResult = true

    func start() -> Result<Void, ScrollEventTapError> {
        startCount += 1
        if case .success = startResult {
            isActive = true
        }
        return startResult
    }

    func stop() {
        stopCount += 1
        isActive = false
    }

    func reassertEnabled() -> Bool {
        reassertResult && isActive
    }
}

private final class FakeScrollDriver: SmoothScrollDriving {
    private(set) var cancelCount = 0

    func submit(_ impulse: ScrollImpulse) {}

    func cancel() {
        cancelCount += 1
    }
}

private final class FrontmostBox: @unchecked Sendable {
    var value: String?
}

@MainActor
private final class Harness {
    let permission: FakeScrollPermission
    let source: FakeScrollSource
    let driver: FakeScrollDriver
    let frontmost: FrontmostBox
    let engine: ScrollEngine

    init() {
        let permission = FakeScrollPermission()
        let source = FakeScrollSource()
        let driver = FakeScrollDriver()
        let frontmost = FrontmostBox()
        self.permission = permission
        self.source = source
        self.driver = driver
        self.frontmost = frontmost
        engine = ScrollEngine(
            permissionManager: permission,
            eventSource: source,
            driver: driver,
            frontmostBundleIdentifier: { frontmost.value },
            installsWorkspaceObservers: false
        )
    }
}
