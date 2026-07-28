import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum GestureInputCategory: String, CaseIterable, Identifiable {
    case all
    case drawn
    case trackpad

    var id: String { rawValue }
    var titleKey: String { "gestures.inputFilter.\(rawValue)" }
}

extension GestureInput {
    var category: GestureInputCategory {
        switch self {
        case .drawn: return .drawn
        case .trackpad: return .trackpad
        }
    }

    var displaySummary: String {
        switch self {
        case .drawn(let drawn):
            switch drawn.activation {
            case .mouse(let trigger):
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

struct TrackpadGesturePreset: Identifiable {
    let id: String
    let nameKey: String
    let gesture: DirectTrackpadGesture
    let action: GestureAction

    func profile(scope: AppScope) -> GestureProfile {
        GestureProfile(
            name: L10n.string(nameKey),
            input: .trackpad(gesture),
            action: action,
            scope: scope
        )
    }
}

enum TrackpadGesturePresetCatalog {
    static let balanced: [TrackpadGesturePreset] = [
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
    ) -> TrackpadGesturePreset {
        TrackpadGesturePreset(
            id: id,
            nameKey: "trackpad.preset.\(id)",
            gesture: gesture,
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
