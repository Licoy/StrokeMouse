import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum GestureInputCategory: String, CaseIterable, Identifiable {
    case all
    case drawn
    case mouseButton
    case mouseCombination
    case trackpad

    var id: String { rawValue }
    var titleKey: String { "gestures.inputFilter.\(rawValue)" }
}

extension GestureInput {
    var category: GestureInputCategory {
        switch self {
        case .drawn: return .drawn
        case .trackpad: return .trackpad
        case .mouseButton: return .mouseButton
        case .mouseCombination: return .mouseCombination
        }
    }

    var displaySummary: String {
        switch self {
        case .drawn(let drawn):
            switch drawn.activation {
            case .mouse(let trigger):
                if let key = drawn.trackpadModifierKey {
                    return String(
                        format: L10n.string(
                            "input.mouseDraw.trackpadModifier.summary"
                        ),
                        locale: L10n.locale,
                        L10n.string(trigger.button.displayKey),
                        L10n.string(key.displayKey)
                    )
                }
                return String(
                    format: L10n.string("input.mouseDraw.summary"),
                    locale: L10n.locale,
                    L10n.string(trigger.button.displayKey)
                )
            case .modifier(let key):
                return String(
                    format: L10n.string("input.modifierDraw.summary"),
                    locale: L10n.locale,
                    L10n.string(key.displayKey)
                )
            }
        case .trackpad(let gesture):
            return gesture.displaySummary
        case .mouseCombination(let gesture):
            return gesture.displaySummary
        case .mouseButton(let gesture):
            if let key = gesture.modifier {
                return String(
                    format: L10n.string("input.mouseButton.modifier.summary"),
                    locale: L10n.locale,
                    L10n.string(key.displayKey),
                    L10n.string(gesture.button.displayKey)
                )
            }
            return String(
                format: L10n.string("input.mouseButton.summary"),
                locale: L10n.locale,
                L10n.string(gesture.button.displayKey)
            )
        }
    }

    var systemImage: String {
        switch self {
        case .drawn(let drawn):
            switch drawn.activation {
            case .mouse: return "computermouse"
            case .modifier: return "keyboard.badge.ellipsis"
            }
        case .trackpad(let gesture):
            return gesture.systemImage
        case .mouseButton:
            return "button.programmable"
        case .mouseCombination:
            return "computermouse.fill"
        }
    }
}

extension GestureModifierKey {
    var displayKey: String { "modifier.\(rawValue)" }
}

extension DirectTrackpadGesture {
    var displaySummary: String {
        let detail: String
        switch self {
        case .tap(_, let count):
            detail = L10n.string("trackpad.tap.\(count.rawValue)")
        case .click(_, let count):
            detail = L10n.string("trackpad.click.\(count.rawValue)")
        case .swipe(_, let direction):
            detail = L10n.string("trackpad.swipe.\(direction.rawValue)")
        case .pinch(_, let direction):
            detail = L10n.string("trackpad.pinch.\(direction.rawValue)")
        case .rotate(_, let direction):
            detail = L10n.string("trackpad.rotate.\(direction.rawValue)")
        }
        return String(
            format: L10n.string("trackpad.gesture.summary"),
            locale: L10n.locale,
            fingerCount,
            detail
        )
    }

    var systemImage: String {
        switch self {
        case .tap: return "hand.tap"
        case .click: return "cursorarrow.click"
        case .swipe(_, .up): return "arrow.up"
        case .swipe(_, .down): return "arrow.down"
        case .swipe(_, .left): return "arrow.left"
        case .swipe(_, .right): return "arrow.right"
        case .pinch(_, .inward): return "arrow.down.right.and.arrow.up.left"
        case .pinch(_, .outward): return "arrow.up.left.and.arrow.down.right"
        case .rotate(_, .clockwise): return "rotate.right"
        case .rotate(_, .counterclockwise): return "rotate.left"
        }
    }
}

struct GesturePreset: Identifiable {
    let id: String
    let nameKey: String
    let input: GestureInput
    let action: GestureAction

    func profile(scope: AppScope) -> GestureProfile {
        GestureProfile(
            name: L10n.string(nameKey),
            input: input,
            action: action,
            scope: scope
        )
    }
}

enum MouseButtonPresetCatalog {
    /// ⌘[ / ⌘] navigate back / forward in browsers, Finder and most editors.
    static let navigation: [GesturePreset] = [
        GesturePreset(
            id: "sideBackBack",
            nameKey: "mouseButton.preset.sideBackBack",
            input: .mouseButton(MouseButtonGesture(button: .sideBack)),
            action: commandShortcut(
                keyCode: UInt16(kVK_ANSI_LeftBracket),
                display: "⌘["
            )
        ),
        GesturePreset(
            id: "sideForwardForward",
            nameKey: "mouseButton.preset.sideForwardForward",
            input: .mouseButton(MouseButtonGesture(button: .sideForward)),
            action: commandShortcut(
                keyCode: UInt16(kVK_ANSI_RightBracket),
                display: "⌘]"
            )
        ),
    ]

    private static func commandShortcut(
        keyCode: UInt16,
        display: String
    ) -> GestureAction {
        .shortcut(
            keyCode: keyCode,
            modifiers: UInt(CGEventFlags.maskCommand.rawValue),
            display: display,
            orderedChord: ShortcutChord(
                modifiers: [.command],
                keyCode: keyCode
            )
        )
    }
}

enum TrackpadGesturePresetCatalog {
    static let balanced: [GesturePreset] = [
        preset(
            "rotateCCWVolumeDown",
            .rotate(.two, .counterclockwise),
            .media(.volumeDown)
        ),
        preset(
            "rotateCWVolumeUp",
            .rotate(.two, .clockwise),
            .media(.volumeUp)
        ),
        preset(
            "threeTapPlayPause",
            .tap(.three, .single),
            .media(.playPause)
        ),
        preset(
            "threeDoubleTapMute",
            .tap(.three, .double),
            .media(.mute)
        ),
        preset(
            "fourSwipeUpMissionControl",
            .swipe(.four, .up),
            shortcut(
                keyCode: UInt16(kVK_UpArrow),
                display: "⌃↑"
            )
        ),
        preset(
            "fourSwipeDownAppExpose",
            .swipe(.four, .down),
            shortcut(
                keyCode: UInt16(kVK_DownArrow),
                display: "⌃↓"
            )
        ),
        preset(
            "fourSwipeLeftPrevious",
            .swipe(.four, .left),
            .media(.previousTrack)
        ),
        preset(
            "fourSwipeRightNext",
            .swipe(.four, .right),
            .media(.nextTrack)
        ),
        preset(
            "fiveTapCenter",
            .tap(.five, .single),
            .window(.center)
        ),
        preset(
            "fiveDoubleTapLock",
            .tap(.five, .double),
            .appleScript(AppleScriptPreset.lockScreen.source ?? "")
        ),
        preset(
            "fivePinchHide",
            .pinch(.five, .inward),
            .window(.hide)
        ),
        preset(
            "fiveSpreadFullscreen",
            .pinch(.five, .outward),
            .window(.fullscreen)
        ),
    ]

    private static func preset(
        _ id: String,
        _ gesture: DirectTrackpadGesture,
        _ action: GestureAction
    ) -> GesturePreset {
        GesturePreset(
            id: id,
            nameKey: "trackpad.preset.\(id)",
            input: .trackpad(gesture),
            action: action
        )
    }

    private static func shortcut(
        keyCode: UInt16,
        display: String
    ) -> GestureAction {
        .shortcut(
            keyCode: keyCode,
            modifiers: UInt(CGEventFlags.maskControl.rawValue),
            display: display,
            orderedChord: ShortcutChord(
                modifiers: [.control],
                keyCode: keyCode
            )
        )
    }
}


extension MouseCombinationGesture {
    var displaySummary: String {
        if let edge {
            return String(format: L10n.string("combination.summary.edge"), locale: L10n.locale,
                          L10n.string(edge.displayKey), L10n.string(action.displayKey))
        }
        return String(format: L10n.string("combination.summary.held"), locale: L10n.locale,
                      L10n.string(action.displayKey))
    }
}
