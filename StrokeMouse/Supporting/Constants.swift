import Foundation

enum Constants {
    static let appName = "StrokeMouse"
    static let bundleID = "com.strokemouse.app"
    static let supportDirectoryName = "StrokeMouse"
    /// Previous Application Support folder name (pre-rename migration).
    static let legacySupportDirectoryName = "BetterMouse"
    static let configFileName = "gestures.json"
    static let gestureTestLogFileName = "gesture-test-log.jsonl"
    static let configVersion = 1

    /// Public repository (About → GitHub).
    static let githubURL = URL(string: "https://github.com/Licoy/StrokeMouse")!
    /// Latest release page for manual download fallback when in-app update fails.
    static let githubReleasesURL = URL(string: "https://github.com/Licoy/StrokeMouse/releases/latest")!
    /// Base URL for Sparkle appcast assets on GitHub Releases.
    static let githubReleasesLatestDownloadBase =
        "https://github.com/Licoy/StrokeMouse/releases/latest/download"

    /// GitHub Issues 新建页
    static let githubIssuesURL = URL(string: "https://github.com/Licoy/StrokeMouse/issues/new")!
    /// License 文件（GitHub blob 页面）
    static let licenseURL = URL(string: "https://github.com/Licoy/StrokeMouse/blob/main/LICENSE")!

    /// Minimum path length (points) before a gesture is considered intentional.
    static let defaultMinStrokeDistance: CGFloat = 40
    /// Douglas–Peucker simplification epsilon in normalized space.
    static let pathSimplifyEpsilon: CGFloat = 0.02
    /// Free-path template match acceptance threshold (0...1, higher is better).
    static let freePathMatchThreshold: Double = 0.70
    static let freePathMatchThresholdRange: ClosedRange<Double> = 0.60...0.85
    static let freePathMatchThresholdStep: Double = 0.01
    /// Minimum score lead over second-best to accept (when ≥2 candidates).
    static let freePathMinLeadOverSecond: Double = 0.06
    /// Resample free-path templates to this many points.
    static let freePathSampleCount = 32
    /// Structural signature sampling and simplification in normalized space.
    static let freePathStructureSampleCount = 64
    static let freePathStructureSimplifyEpsilon: CGFloat = 0.04
    static let freePathTerminalProbeEpsilon: CGFloat = 0.015
    static let freePathShortSegmentFraction: CGFloat = 0.09
    static let freePathSegmentProportionRange: ClosedRange<CGFloat> = 0.5...2.0
    static let freePathMergeAngleDegrees = 20.0
    static let freePathStartAngleDegrees = 30.0
    static let freePathLineAngleDegrees = 15.0
    static let freePathEndAngleDegrees = 45.0
    static let freePathTurnAngleDegrees = 55.0

    static let defaultHUDLineWidth: CGFloat = 4
    static let defaultHUDStartPointRadius: CGFloat = 7
    static let defaultHUDLineColorHex = "#3B82F6FF" // blue
}

enum PreferenceKey {
    static let gesturesEnabled = "gesturesEnabled"
    static let triggerButton = "triggerButton"
    static let minStrokeDistance = "minStrokeDistance"
    static let matchThreshold = "matchThreshold"
    static let appearance = "appearanceMode"
    static let menuBarIconStyle = "menuBarIconStyle"
    static let language = "languageOverride"
    static let hideDockIcon = "hideDockIcon"
    static let hideMenuBarIcon = "hideMenuBarIcon"
    /// Bundle IDs pinned in the gestures sidebar (may have zero gestures yet).
    static let pinnedGestureAppBundleIds = "pinnedGestureAppBundleIds"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let showGestureHUD = "showGestureHUD"
    static let hudLineColor = "hudLineColor"
    static let hudLineWidth = "hudLineWidth"
    static let hudShowStartPoint = "hudShowStartPoint"
    static let hudStartPointRadius = "hudStartPointRadius"
    static let automaticallyChecksForUpdates = "automaticallyChecksForUpdates"
}
