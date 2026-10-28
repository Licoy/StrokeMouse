import Carbon.HIToolbox
import Foundation

enum SystemCommand: String, Codable, CaseIterable, Identifiable, Sendable {
    case missionControl, applicationWindows, spaceLeft, spaceRight

    var id: String { rawValue }
    var displayKey: String { "system.\(rawValue)" }
    var requiresCapturedTarget: Bool { self == .applicationWindows }

    var defaultChord: ShortcutChord {
        let keyCode: Int
        switch self {
        case .missionControl: keyCode = kVK_UpArrow
        case .applicationWindows: keyCode = kVK_DownArrow
        case .spaceLeft: keyCode = kVK_LeftArrow
        case .spaceRight: keyCode = kVK_RightArrow
        }
        return ShortcutChord(modifiers: [.control], keyCode: UInt16(keyCode))
    }
}

struct SystemAction: Codable, Equatable, Sendable {
    var command: SystemCommand
    var shortcutOverride: ShortcutChord?

    init(command: SystemCommand, shortcutOverride: ShortcutChord? = nil) {
        self.command = command
        self.shortcutOverride = shortcutOverride
    }

    var effectiveChord: ShortcutChord { shortcutOverride ?? command.defaultChord }
}
