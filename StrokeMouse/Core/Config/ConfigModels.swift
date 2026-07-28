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
    var activation: DrawActivation
    var points: [CodablePoint]

    init(activation: DrawActivation, points: [CodablePoint]) {
        self.activation = activation
        self.points = points
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

enum GestureAction: Codable, Equatable, Sendable {
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

// MARK: - Scope

enum AppScope: Codable, Equatable, Sendable {
    case global
    case apps([String]) // bundle identifiers

    var summaryKey: String {
        switch self {
        case .global: return "scope.global"
        case .apps: return "scope.apps"
        }
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
        scope = try container.decodeIfPresent(AppScope.self, forKey: .scope) ?? .global
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
        try container.encode(scope, forKey: .scope)
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
        case action, scope, targetPolicy, notes
    }
}

// MARK: - Root config file

struct GestureConfigFile: Codable, Equatable, Sendable {
    var version: Int
    var gestures: [GestureProfile]

    static let empty = GestureConfigFile(version: Constants.configVersion, gestures: [])
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

    var id: String { rawValue }

    var displayKey: String { "language.\(rawValue)" }
}
