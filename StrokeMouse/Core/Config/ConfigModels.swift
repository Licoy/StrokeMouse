import Carbon.HIToolbox
import CoreGraphics
import Foundation

// MARK: - Trigger

enum MouseTriggerButton: String, Codable, CaseIterable, Identifiable, Sendable {
    case middle
    case sideBack
    case sideForward
    case right

    var id: String { rawValue }

    var displayKey: String {
        switch self {
        case .middle: return "trigger.middle"
        case .sideBack: return "trigger.sideBack"
        case .sideForward: return "trigger.sideForward"
        case .right: return "trigger.right"
        }
    }

    /// CGEvent mouse button number used for otherMouse* events.
    var cgButtonNumber: Int64? {
        switch self {
        case .middle: return 2
        case .sideBack: return 3
        case .sideForward: return 4
        case .right: return nil
        }
    }

    var usesRightMouseEvents: Bool { self == .right }
}

struct GestureTrigger: Codable, Equatable, Sendable {
    var button: MouseTriggerButton
    /// Retained for v1 compatibility. New modifier drawing uses `DrawActivation`.
    var requireFlags: UInt = 0

    static let `default` = GestureTrigger(button: .right)

    init(button: MouseTriggerButton, requireFlags: UInt = 0) {
        self.button = button
        self.requireFlags = requireFlags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        button = try container.decode(MouseTriggerButton.self, forKey: .button)
        requireFlags = try container.decodeIfPresent(UInt.self, forKey: .requireFlags) ?? 0
    }
}

// MARK: - Pattern

enum Direction: String, Codable, CaseIterable, Sendable {
    case up, down, left, right
    case upLeft, upRight, downLeft, downRight

    var symbol: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .upLeft: return "↖"
        case .upRight: return "↗"
        case .downLeft: return "↙"
        case .downRight: return "↘"
        }
    }

    var angleDegrees: Double {
        switch self {
        case .right: return 0
        case .upRight: return 45
        case .up: return 90
        case .upLeft: return 135
        case .left: return 180
        case .downLeft: return 225
        case .down: return 270
        case .downRight: return 315
        }
    }
}

enum GesturePattern: Codable, Equatable, Sendable {
    /// Legacy — still decoded from older configs; engine converts to free-path templates.
    case directions([Direction])
    case freePath([CodablePoint])

    var summary: String {
        switch self {
        case .directions(let dirs):
            return dirs.map(\.symbol).joined(separator: " ")
        case .freePath(let points):
            return "✦ \(points.count)"
        }
    }

    var freePathPoints: [CodablePoint] {
        switch self {
        case .freePath(let points):
            return points
        case .directions(let dirs):
            return PathTemplates.fromDirections(dirs).map(CodablePoint.init)
        }
    }
}

struct CodablePoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - Input

enum GestureModifierKey: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case function
    case control
    case option
    case shift
    case command

    var id: String { rawValue }
}

enum StandardFingerCount: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case three = 3
    case four = 4
    case five = 5

    var id: Int { rawValue }
}

enum TransformFingerCount: Int, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var id: Int { rawValue }
}

enum TapCount: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case single
    case double

    var id: String { rawValue }
}

enum CardinalDirection: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case up
    case down
    case left
    case right

    var id: String { rawValue }
}

enum PinchDirection: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case inward
    case outward

    var id: String { rawValue }
}

enum RotationDirection: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case clockwise
    case counterclockwise

    var id: String { rawValue }
}

enum DrawActivation: Codable, Equatable, Sendable {
    case mouse(GestureTrigger)
    case modifier(GestureModifierKey)

    private enum CodingKeys: String, CodingKey {
        case type
        case trigger
        case key
    }

    private enum Kind: String, Codable {
        case mouse
        case modifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .mouse:
            self = .mouse(try container.decode(GestureTrigger.self, forKey: .trigger))
        case .modifier:
            self = .modifier(try container.decode(GestureModifierKey.self, forKey: .key))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mouse(let trigger):
            try container.encode(Kind.mouse, forKey: .type)
            try container.encode(trigger, forKey: .trigger)
        case .modifier(let key):
            try container.encode(Kind.modifier, forKey: .type)
            try container.encode(key, forKey: .key)
        }
    }
}

struct DrawnGesture: Codable, Equatable, Sendable {
    static let maximumSampleCount = 5

    var activation: DrawActivation
    var points: [CodablePoint]
    /// Optional shared activation for mouse-drawn profiles. Missing legacy
    /// values decode as `nil`, keeping existing profiles mouse-only.
    var trackpadModifierKey: GestureModifierKey?
    /// Additional recordings of the same gesture. The primary `points` path
    /// remains stable for compatibility with older versions.
    var additionalPaths: [[CodablePoint]]

    var allPaths: [[CodablePoint]] {
        [points] + additionalPaths
    }

    init(
        activation: DrawActivation,
        points: [CodablePoint],
        trackpadModifierKey: GestureModifierKey? = nil,
        additionalPaths: [[CodablePoint]] = []
    ) {
        self.activation = activation
        self.points = points
        self.trackpadModifierKey = trackpadModifierKey
        self.additionalPaths = additionalPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activation = try container.decode(DrawActivation.self, forKey: .activation)
        points = try container.decode([CodablePoint].self, forKey: .points)
        trackpadModifierKey = try container.decodeIfPresent(
            GestureModifierKey.self,
            forKey: .trackpadModifierKey
        )
        additionalPaths = try container.decodeIfPresent(
            [[CodablePoint]].self,
            forKey: .additionalPaths
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activation, forKey: .activation)
        try container.encode(points, forKey: .points)
        try container.encodeIfPresent(
            trackpadModifierKey,
            forKey: .trackpadModifierKey
        )
        if !additionalPaths.isEmpty {
            try container.encode(additionalPaths, forKey: .additionalPaths)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case activation, points, trackpadModifierKey, additionalPaths
    }
}

enum DirectTrackpadGesture: Codable, Equatable, Hashable, Sendable {
    case tap(StandardFingerCount, TapCount)
    case swipe(StandardFingerCount, CardinalDirection)
    case pinch(TransformFingerCount, PinchDirection)
    case rotate(TransformFingerCount, RotationDirection)

    private enum CodingKeys: String, CodingKey {
        case type
        case fingers
        case tapCount
        case direction
    }

    private enum Kind: String, Codable {
        case tap
        case swipe
        case pinch
        case rotate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .tap:
            self = .tap(
                try container.decode(StandardFingerCount.self, forKey: .fingers),
                try container.decode(TapCount.self, forKey: .tapCount)
            )
        case .swipe:
            self = .swipe(
                try container.decode(StandardFingerCount.self, forKey: .fingers),
                try container.decode(CardinalDirection.self, forKey: .direction)
            )
        case .pinch:
            self = .pinch(
                try container.decode(TransformFingerCount.self, forKey: .fingers),
                try container.decode(PinchDirection.self, forKey: .direction)
            )
        case .rotate:
            self = .rotate(
                try container.decode(TransformFingerCount.self, forKey: .fingers),
                try container.decode(RotationDirection.self, forKey: .direction)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tap(let fingers, let count):
            try container.encode(Kind.tap, forKey: .type)
            try container.encode(fingers, forKey: .fingers)
            try container.encode(count, forKey: .tapCount)
        case .swipe(let fingers, let direction):
            try container.encode(Kind.swipe, forKey: .type)
            try container.encode(fingers, forKey: .fingers)
            try container.encode(direction, forKey: .direction)
        case .pinch(let fingers, let direction):
            try container.encode(Kind.pinch, forKey: .type)
            try container.encode(fingers, forKey: .fingers)
            try container.encode(direction, forKey: .direction)
        case .rotate(let fingers, let direction):
            try container.encode(Kind.rotate, forKey: .type)
            try container.encode(fingers, forKey: .fingers)
            try container.encode(direction, forKey: .direction)
        }
    }

    var fingerCount: Int {
        switch self {
        case .tap(let fingers, _), .swipe(let fingers, _):
            return fingers.rawValue
        case .pinch(let fingers, _), .rotate(let fingers, _):
            return fingers.rawValue
        }
    }
}

enum GestureInput: Codable, Equatable, Sendable {
    case drawn(DrawnGesture)
    case trackpad(DirectTrackpadGesture)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum Kind: String, Codable {
        case drawn
        case trackpad
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .drawn:
            self = .drawn(try container.decode(DrawnGesture.self, forKey: .value))
        case .trackpad:
            self = .trackpad(try container.decode(DirectTrackpadGesture.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .drawn(let gesture):
            try container.encode(Kind.drawn, forKey: .type)
            try container.encode(gesture, forKey: .value)
        case .trackpad(let gesture):
            try container.encode(Kind.trackpad, forKey: .type)
            try container.encode(gesture, forKey: .value)
        }
    }
}

// MARK: - Actions

enum ShortcutModifier: String, Codable, Equatable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
}

struct ShortcutChord: Codable, Equatable, Sendable {
    var modifiers: [ShortcutModifier]
    var keyCode: UInt16?

    init(modifiers: [ShortcutModifier], keyCode: UInt16?) {
        precondition(Self.isValid(modifiers: modifiers, keyCode: keyCode))
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modifiers = try container.decode([ShortcutModifier].self, forKey: .modifiers)
        let keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
        guard Self.isValid(modifiers: modifiers, keyCode: keyCode) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid ordered shortcut chord"
            ))
        }
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    private static func isValid(
        modifiers: [ShortcutModifier],
        keyCode: UInt16?
    ) -> Bool {
        guard !modifiers.isEmpty || keyCode != nil,
              Set(modifiers).count == modifiers.count
        else {
            return false
        }
        guard let keyCode else { return true }
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_Shift, kVK_RightShift,
             kVK_Function, kVK_CapsLock:
            return false
        default:
            return true
        }
    }
}

enum MediaCommand: String, Codable, CaseIterable, Identifiable, Sendable {
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case mute

    var id: String { rawValue }

    var displayKey: String { "media.\(rawValue)" }
}

enum WindowCommand: String, Codable, CaseIterable, Identifiable, Sendable {
    case close
    case minimize
    case zoom
    case fullscreen
    case hide
    case center

    var id: String { rawValue }

    var displayKey: String { "window.\(rawValue)" }
}

enum ApplicationSwitchCommand: String, Codable, CaseIterable, Identifiable, Sendable {
    case commandTab
    case shiftCommandTab

    var id: String { rawValue }

    var displayKey: String { "window.applicationSwitch.\(rawValue)" }

    var shortcutChord: ShortcutChord {
        switch self {
        case .commandTab:
            return ShortcutChord(
                modifiers: [.command],
                keyCode: UInt16(kVK_Tab)
            )
        case .shiftCommandTab:
            return ShortcutChord(
                modifiers: [.shift, .command],
                keyCode: UInt16(kVK_Tab)
            )
        }
    }
}

/// Built-in AppleScript snippets for the action editor. Storage remains the raw
/// script string on `GestureAction.appleScript` so custom scripts stay free-form.
enum AppleScriptPreset: String, CaseIterable, Identifiable, Sendable {
    case sleep
    case emptyTrash
    case lockScreen
    case startScreenSaver
    case logOut
    case restart
    case shutDown
    case toggleDarkMode
    case hideOthers
    case muteVolume
    case unmuteVolume
    case openForceQuit
    case screenshotToClipboard
    case openDownloads
    case custom

    var id: String { rawValue }

    var displayKey: String { "applescript.\(rawValue)" }

    /// Stable script source for built-ins. `custom` has no fixed source.
    /// Do not lightly reword these — exact match is used when hydrating the editor.
    var source: String? {
        switch self {
        case .sleep:
            return "tell application \"System Events\" to sleep"
        case .emptyTrash:
            return "tell application \"Finder\" to empty the trash"
        case .lockScreen:
            return "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        case .startScreenSaver:
            return "tell application \"System Events\" to start current screen saver"
        case .logOut:
            return "tell application \"System Events\" to log out"
        case .restart:
            return "tell application \"System Events\" to restart"
        case .shutDown:
            return "tell application \"System Events\" to shut down"
        case .toggleDarkMode:
            return """
            tell application "System Events"
                tell appearance preferences
                    set dark mode to not dark mode
                end tell
            end tell
            """
        case .hideOthers:
            return "tell application \"System Events\" to keystroke \"h\" using {command down, option down}"
        case .muteVolume:
            return "set volume with output muted"
        case .unmuteVolume:
            return "set volume without output muted"
        case .openForceQuit:
            return "tell application \"System Events\" to keystroke escape using {command down, option down}"
        case .screenshotToClipboard:
            return "do shell script \"screencapture -c\""
        case .openDownloads:
            return "tell application \"Finder\" to open (path to downloads folder)"
        case .custom:
            return nil
        }
    }

    /// Match a stored script to a preset (trim both sides). Unknown → `.custom`.
    static func matching(source: String) -> AppleScriptPreset {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        for preset in allCases where preset != .custom {
            if let presetSource = preset.source?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               presetSource == trimmed
            {
                return preset
            }
        }
        return .custom
    }
}

enum GestureAction: Equatable, Sendable {
    case none
    case shortcut(
        keyCode: UInt16,
        modifiers: UInt,
        display: String,
        orderedChord: ShortcutChord? = nil
    )
    case openApp(bundleId: String, name: String)
    case openURL(String)
    case shell(String)
    case media(MediaCommand)
    case window(WindowCommand)
    case applicationSwitch(ApplicationSwitchCommand)
    case appleScript(String)

    var summaryKey: String {
        switch self {
        case .none: return "action.none"
        case .shortcut: return "action.shortcut"
        case .openApp: return "action.openApp"
        case .openURL: return "action.openURL"
        case .shell: return "action.shell"
        case .media: return "action.media"
        case .window: return "action.window"
        case .applicationSwitch: return "action.window"
        case .appleScript: return "action.appleScript"
        }
    }

    var detail: String {
        switch self {
        case .none:
            return "—"
        case .shortcut(_, _, let display, _):
            return display
        case .openApp(_, let name):
            return name
        case .openURL(let url):
            return url
        case .shell(let cmd):
            return cmd
        case .media(let cmd):
            return cmd.rawValue
        case .window(let cmd):
            return cmd.rawValue
        case .applicationSwitch(let command):
            return L10n.string(command.displayKey)
        case .appleScript(let script):
            let preset = AppleScriptPreset.matching(source: script)
            if preset != .custom {
                return L10n.string(preset.displayKey)
            }
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed
        }
    }
}

extension GestureAction: Codable {
    init(from decoder: Decoder) throws {
        self = try PersistedGestureAction(from: decoder).runtimeAction
    }

    func encode(to encoder: Encoder) throws {
        try PersistedGestureAction(runtimeAction: self).encode(to: encoder)
    }
}

/// Keeps the v2 wire format readable by 0.0.18. The application-switch UI was
/// added in 0.0.19, but its commands are existing ordered shortcuts on disk.
private enum PersistedGestureAction: Codable {
    case none
    case shortcut(
        keyCode: UInt16,
        modifiers: UInt,
        display: String,
        orderedChord: ShortcutChord? = nil
    )
    case openApp(bundleId: String, name: String)
    case openURL(String)
    case shell(String)
    case media(MediaCommand)
    case window(WindowCommand)
    case applicationSwitch(ApplicationSwitchCommand)
    case appleScript(String)

    init(runtimeAction action: GestureAction) {
        switch action {
        case .none: self = .none
        case .shortcut(let keyCode, let modifiers, let display, let chord):
            self = .shortcut(
                keyCode: keyCode,
                modifiers: modifiers,
                display: display,
                orderedChord: chord
            )
        case .openApp(let bundleId, let name): self = .openApp(bundleId: bundleId, name: name)
        case .openURL(let url): self = .openURL(url)
        case .shell(let command): self = .shell(command)
        case .media(let command): self = .media(command)
        case .window(let command): self = .window(command)
        case .applicationSwitch(let command):
            let chord = command.shortcutChord
            self = .shortcut(
                keyCode: chord.legacyKeyCode,
                modifiers: chord.legacyModifiers,
                display: KeyCodeNames.shortcutDisplay(chord: chord),
                orderedChord: chord
            )
        case .appleScript(let source): self = .appleScript(source)
        }
    }

    var runtimeAction: GestureAction {
        switch self {
        case .none: return .none
        case .shortcut(let keyCode, let modifiers, let display, let chord):
            if let chord,
               let command = ApplicationSwitchCommand.allCases.first(
                   where: { $0.shortcutChord == chord }
               )
            {
                return .applicationSwitch(command)
            }
            return .shortcut(
                keyCode: keyCode,
                modifiers: modifiers,
                display: display,
                orderedChord: chord
            )
        case .openApp(let bundleId, let name): return .openApp(bundleId: bundleId, name: name)
        case .openURL(let url): return .openURL(url)
        case .shell(let command): return .shell(command)
        case .media(let command): return .media(command)
        case .window(let command): return .window(command)
        case .applicationSwitch(let command): return .applicationSwitch(command)
        case .appleScript(let source): return .appleScript(source)
        }
    }
}

// MARK: - Scope

enum AppScope: Codable, Equatable, Sendable {
    case global
    case apps([String]) // bundle identifiers
    /// Shared by every application matched by an `AppGroup`.
    /// `GestureProfile` stores this in a v2-readable wire shape.
    case group(UUID)

    var summaryKey: String {
        switch self {
        case .global: return "scope.global"
        case .apps: return "scope.apps"
        case .group: return "scope.group"
        }
    }

    var groupID: UUID? {
        guard case .group(let id) = self else { return nil }
        return id
    }
}

/// Product-level input families. Runtime sessions map onto these by source,
/// so a mouse-drawn profile that is also reachable by a modifier key counts as
/// trackpad drawing when the modifier started the session.
enum GestureInputKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case mouseDrawing
    case trackpadDrawing
    case touchGesture

    var id: String { rawValue }

    var displayKey: String { "inputKind.\(rawValue)" }
}

/// Global gestures suppressed while the target application matches a rule.
/// Encoded as a sorted array so persisted bytes stay stable; unknown kinds
/// written by newer versions are ignored.
struct SuppressedGlobalInputs: Codable, Equatable, Hashable, Sendable {
    var kinds: Set<GestureInputKind>

    static let none = SuppressedGlobalInputs(kinds: [])
    static let all = SuppressedGlobalInputs(kinds: Set(GestureInputKind.allCases))

    init(kinds: Set<GestureInputKind>) {
        self.kinds = kinds
    }

    var isEmpty: Bool { kinds.isEmpty }

    func contains(_ kind: GestureInputKind) -> Bool {
        kinds.contains(kind)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String].self)
        kinds = Set(raw.compactMap(GestureInputKind.init(rawValue:)))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(
            GestureInputKind.allCases.filter(kinds.contains).map(\.rawValue)
        )
    }
}

/// Per-application override keyed by exact bundle identifier.
struct AppGesturePolicy: Codable, Equatable, Sendable {
    var bundleIdentifier: String
    var suppressedGlobalInputs: SuppressedGlobalInputs

    init(
        bundleIdentifier: String,
        suppressedGlobalInputs: SuppressedGlobalInputs = .all
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.suppressedGlobalInputs = suppressedGlobalInputs
    }
}

struct AppMatcher: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        /// Exact bundle identifier, case-insensitive.
        case bundleIdentifier
        /// Whole-string bundle identifier pattern; `*` matches any run of characters.
        case bundleIdentifierPattern
        /// Application bundle (or executable) located inside this directory tree.
        case directory
    }

    var kind: Kind
    var value: String

    init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    static func bundleIdentifier(_ value: String) -> AppMatcher {
        AppMatcher(kind: .bundleIdentifier, value: value)
    }

    static func bundleIdentifierPattern(_ value: String) -> AppMatcher {
        AppMatcher(kind: .bundleIdentifierPattern, value: value)
    }

    static func directory(_ value: String) -> AppMatcher {
        AppMatcher(kind: .directory, value: value)
    }
}

/// Named set of applications that share gestures and a global-gesture policy.
struct AppGroup: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var matchers: [AppMatcher]
    var suppressedGlobalInputs: SuppressedGlobalInputs

    init(
        id: UUID = UUID(),
        name: String,
        matchers: [AppMatcher] = [],
        suppressedGlobalInputs: SuppressedGlobalInputs = .none
    ) {
        self.id = id
        self.name = name
        self.matchers = matchers
        self.suppressedGlobalInputs = suppressedGlobalInputs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        matchers = try container.decodeIfPresent([AppMatcher].self, forKey: .matchers) ?? []
        suppressedGlobalInputs = try container.decodeIfPresent(
            SuppressedGlobalInputs.self,
            forKey: .suppressedGlobalInputs
        ) ?? .none
    }

    /// Content equality ignoring `id` (used for import duplicate detection).
    func isContentEqual(to other: AppGroup) -> Bool {
        name == other.name
            && matchers == other.matchers
            && suppressedGlobalInputs == other.suppressedGlobalInputs
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, matchers, suppressedGlobalInputs
    }
}

enum GestureTargetPolicy: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case frontmostWindow
    case windowUnderPointer

    var id: String { rawValue }

    var displayKey: String { "target.\(rawValue)" }
}

// MARK: - Profile

struct GestureProfile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var input: GestureInput
    var action: GestureAction
    var scope: AppScope
    var targetPolicy: GestureTargetPolicy
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        input: GestureInput,
        action: GestureAction = .none,
        scope: AppScope = .global,
        targetPolicy: GestureTargetPolicy = .frontmostWindow,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.input = input
        self.action = action
        self.scope = scope
        self.targetPolicy = targetPolicy
        self.notes = notes
    }

    /// Source-compatible construction for mouse-drawn profiles. Direction patterns are
    /// converted at the boundary so v2 storage never writes the legacy representation.
    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        trigger: GestureTrigger = .default,
        pattern: GesturePattern,
        action: GestureAction = .none,
        scope: AppScope = .global,
        targetPolicy: GestureTargetPolicy = .frontmostWindow,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        input = .drawn(
            DrawnGesture(
                activation: .mouse(trigger),
                points: pattern.freePathPoints
            )
        )
        self.action = action
        self.scope = scope
        self.targetPolicy = targetPolicy
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        input = try container.decode(GestureInput.self, forKey: .input)
        action = try container.decodeIfPresent(GestureAction.self, forKey: .action) ?? .none
        if let groupID = try container.decodeIfPresent(UUID.self, forKey: .appGroup) {
            scope = .group(groupID)
        } else {
            scope = try container.decodeIfPresent(AppScope.self, forKey: .scope) ?? .global
        }
        targetPolicy = try container.decodeIfPresent(GestureTargetPolicy.self, forKey: .targetPolicy)
            ?? .frontmostWindow
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(input, forKey: .input)
        try container.encode(action, forKey: .action)
        switch scope {
        case .group(let groupID):
            // Older versions only know `global` / `apps`; an empty app list
            // keeps the file readable there and leaves the gesture inert.
            try container.encode(AppScope.apps([]), forKey: .scope)
            try container.encode(groupID, forKey: .appGroup)
        case .global, .apps:
            try container.encode(scope, forKey: .scope)
        }
        try container.encode(targetPolicy, forKey: .targetPolicy)
        try container.encode(notes, forKey: .notes)
    }

    /// Content equality ignoring `id` (used for import duplicate detection).
    func isContentEqual(to other: GestureProfile) -> Bool {
        name == other.name
            && isEnabled == other.isEnabled
            && input == other.input
            && action == other.action
            && scope == other.scope
            && targetPolicy == other.targetPolicy
            && notes == other.notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, input
        case action, scope, appGroup, targetPolicy, notes
    }
}

// MARK: - Root config file

struct GestureConfigFile: Codable, Equatable, Sendable {
    var version: Int
    var gestures: [GestureProfile]
    /// Exact-application overrides. Omitted from the file when empty.
    var appPolicies: [AppGesturePolicy]
    /// Omitted from the file when empty.
    var appGroups: [AppGroup]

    static let empty = GestureConfigFile(version: Constants.configVersion, gestures: [])

    init(
        version: Int,
        gestures: [GestureProfile],
        appPolicies: [AppGesturePolicy] = [],
        appGroups: [AppGroup] = []
    ) {
        self.version = version
        self.gestures = gestures
        self.appPolicies = appPolicies
        self.appGroups = appGroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        gestures = try container.decode([GestureProfile].self, forKey: .gestures)
        appPolicies = try container.decodeIfPresent(
            [AppGesturePolicy].self,
            forKey: .appPolicies
        ) ?? []
        appGroups = try container.decodeIfPresent([AppGroup].self, forKey: .appGroups) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(gestures, forKey: .gestures)
        if !appPolicies.isEmpty {
            try container.encode(appPolicies, forKey: .appPolicies)
        }
        if !appGroups.isEmpty {
            try container.encode(appGroups, forKey: .appGroups)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, gestures, appPolicies, appGroups
    }
}

// MARK: - Appearance / Language preferences (UI)

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayKey: String { "appearance.\(rawValue)" }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable, Sendable {
    case color
    case monochrome

    static let `default`: Self = .monochrome

    var id: String { rawValue }

    var displayKey: String { "menuBarIcon.\(rawValue)" }

    var assetName: String {
        switch self {
        case .color: return "MenuBarIconColor"
        case .monochrome: return "MenuBarIconTemplate"
        }
    }
}

enum LanguageOverride: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case korean = "ko"
    case japanese = "ja"
    case russian = "ru"
    case french = "fr"

    var id: String { rawValue }

    var displayKey: String { "language.\(rawValue)" }

    /// Picker label. Explicit languages always use the target language's own
    /// name; `.system` follows the current UI locale.
    var pickerTitle: String {
        switch self {
        case .system:
            return L10n.string(displayKey)
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .korean:
            return "한국어"
        case .japanese:
            return "日本語"
        case .russian:
            return "Русский"
        case .french:
            return "Français"
        }
    }

    /// Catalog locales the app ships (excludes `.system`).
    static var explicitCatalogLocales: [LanguageOverride] {
        allCases.filter { $0 != .system }
    }

    /// Resolves this override to a shipped catalog locale.
    /// `.system` uses the given preferred-language list (defaults to the OS list).
    func resolvedCatalogLocale(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch self {
        case .system:
            return Self.catalogLocale(matching: preferredLanguages)
        default:
            return rawValue
        }
    }

    /// Maps an OS preferred-language list onto a supported catalog locale.
    /// Unmatched lists fall back to English.
    static func catalogLocale(matching preferredLanguages: [String]) -> String {
        for identifier in preferredLanguages {
            if let matched = matchPreferredLanguage(identifier) {
                return matched
            }
        }
        return english.rawValue
    }

    /// Matches a single BCP-47 / Apple language identifier to a catalog locale.
    static func matchPreferredLanguage(_ identifier: String) -> String? {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-").map(String.init)
        guard let language = parts.first?.lowercased(), !language.isEmpty else {
            return nil
        }

        switch language {
        case "en":
            return english.rawValue
        case "ko":
            return korean.rawValue
        case "ja":
            return japanese.rawValue
        case "ru":
            return russian.rawValue
        case "fr":
            return french.rawValue
        case "zh":
            return matchChinese(normalized: normalized, parts: parts)
        default:
            return nil
        }
    }

    private static func matchChinese(normalized: String, parts: [String]) -> String {
        let tokens = Set(parts.map { $0.lowercased() })
        if tokens.contains("hant") {
            return traditionalChinese.rawValue
        }
        if tokens.contains("hans") {
            return simplifiedChinese.rawValue
        }
        if tokens.contains("tw") || tokens.contains("hk") || tokens.contains("mo") {
            return traditionalChinese.rawValue
        }
        if tokens.contains("cn") || tokens.contains("sg") {
            return simplifiedChinese.rawValue
        }

        let locale = Locale(identifier: normalized)
        if let script = locale.language.script?.identifier.lowercased() {
            if script == "hant" { return traditionalChinese.rawValue }
            if script == "hans" { return simplifiedChinese.rawValue }
        }
        if let region = locale.region?.identifier.lowercased() {
            if ["tw", "hk", "mo"].contains(region) {
                return traditionalChinese.rawValue
            }
            if ["cn", "sg"].contains(region) {
                return simplifiedChinese.rawValue
            }
        }

        // Bare `zh` is treated as Simplified Chinese (Apple's common default).
        return simplifiedChinese.rawValue
    }
}
