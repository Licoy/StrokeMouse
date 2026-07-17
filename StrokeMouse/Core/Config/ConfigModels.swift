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
    /// Reserved for future modifier-key requirements.
    var requireFlags: UInt = 0

    static let `default` = GestureTrigger(button: .right)
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

// MARK: - Actions

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
    case shortcut(keyCode: UInt16, modifiers: UInt, display: String)
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
        case .shortcut(_, _, let display):
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

// MARK: - Profile

struct GestureProfile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var trigger: GestureTrigger
    var pattern: GesturePattern
    var action: GestureAction
    var scope: AppScope
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        trigger: GestureTrigger = .default,
        pattern: GesturePattern,
        action: GestureAction = .none,
        scope: AppScope = .global,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.pattern = pattern
        self.action = action
        self.scope = scope
        self.notes = notes
    }

    /// Custom decode so older configs missing `trigger` default to right button.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        trigger = try container.decodeIfPresent(GestureTrigger.self, forKey: .trigger) ?? .default
        pattern = try container.decode(GesturePattern.self, forKey: .pattern)
        action = try container.decodeIfPresent(GestureAction.self, forKey: .action) ?? .none
        scope = try container.decodeIfPresent(AppScope.self, forKey: .scope) ?? .global
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    /// Content equality ignoring `id` (used for import duplicate detection).
    func isContentEqual(to other: GestureProfile) -> Bool {
        name == other.name
            && isEnabled == other.isEnabled
            && trigger == other.trigger
            && pattern == other.pattern
            && action == other.action
            && scope == other.scope
            && notes == other.notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, trigger, pattern, action, scope, notes
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
