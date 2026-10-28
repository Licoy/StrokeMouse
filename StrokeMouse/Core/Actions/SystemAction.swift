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

/// The binding macOS currently assigns to a system command.
enum SystemShortcutStatus: Equatable, Sendable {
    /// No readable entry, so macOS keeps its built-in default.
    case unknown
    case disabled
    case enabled(ShortcutChord)
}

extension SystemCommand {
    /// Entry in `com.apple.symbolichotkeys` that owns this command's shortcut.
    var symbolicHotKeyID: Int {
        switch self {
        case .missionControl: return 32
        case .applicationWindows: return 33
        case .spaceLeft: return 79
        case .spaceRight: return 81
        }
    }

    /// Reads System Settings › Keyboard Shortcuts › Mission Control.
    func currentSystemShortcut() -> SystemShortcutStatus {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        return Self.shortcutStatus(from: hotKeys?[String(symbolicHotKeyID)])
    }

    static func shortcutStatus(from entry: Any?) -> SystemShortcutStatus {
        guard let entry = entry as? [String: Any] else { return .unknown }
        guard (entry["enabled"] as? NSNumber)?.boolValue ?? false else { return .disabled }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber],
              parameters.count >= 3
        else { return .unknown }
        let keyCode = parameters[1].intValue
        let mask = parameters[2].uint64Value
        let hasKey = keyCode >= 0 && keyCode < 0xFFFF
        var modifiers: [ShortcutModifier] = []
        let bits: [(UInt64, ShortcutModifier)] = [
            (0x800000, .function), (0x40000, .control), (0x80000, .option),
            (0x20000, .shift), (0x100000, .command),
        ]
        for (bit, modifier) in bits where mask & bit != 0 {
            // Arrows and F-keys always carry Fn; only a real Fn press counts.
            if modifier == .function, hasKey, hasIntrinsicFunction(UInt16(keyCode)) { continue }
            modifiers.append(modifier)
        }
        guard hasKey || !modifiers.isEmpty else { return .disabled }
        return .enabled(ShortcutChord(modifiers: modifiers, keyCode: hasKey ? UInt16(keyCode) : nil))
    }

    /// Same keys pressed, regardless of modifier order or an intrinsic Fn bit.
    static func chordsMatch(_ lhs: ShortcutChord, _ rhs: ShortcutChord) -> Bool {
        lhs.keyCode == rhs.keyCode && normalizedModifiers(lhs) == normalizedModifiers(rhs)
    }

    private static func normalizedModifiers(_ chord: ShortcutChord) -> Set<ShortcutModifier> {
        var modifiers = Set(chord.modifiers)
        if let keyCode = chord.keyCode, hasIntrinsicFunction(keyCode) { modifiers.remove(.function) }
        return modifiers
    }

    private static func hasIntrinsicFunction(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
             kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
             kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
             kVK_Help, kVK_ForwardDelete, kVK_Home, kVK_End,
             kVK_PageUp, kVK_PageDown,
             kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow:
            return true
        default:
            return false
        }
    }
}
