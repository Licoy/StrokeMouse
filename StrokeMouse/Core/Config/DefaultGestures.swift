import AppKit
import Foundation

enum DefaultGestures {
    private static let rightTrigger = GestureTrigger(button: .right)

    static func make() -> [GestureProfile] {
        [
            GestureProfile(
                name: "Mission Control",
                trigger: rightTrigger,
                pattern: .freePath(PathTemplates.up),
                action: .shortcut(
                    keyCode: 126,
                    modifiers: UInt(NSEvent.ModifierFlags.control.rawValue),
                    display: "⌃↑"
                ),
                notes: "上滑"
            ),
            GestureProfile(
                name: "Application Windows",
                trigger: rightTrigger,
                pattern: .freePath(PathTemplates.down),
                action: .shortcut(
                    keyCode: 125,
                    modifiers: UInt(NSEvent.ModifierFlags.control.rawValue),
                    display: "⌃↓"
                ),
                notes: "下滑"
            ),
            GestureProfile(
                name: "Minimize Window",
                trigger: rightTrigger,
                pattern: .freePath(PathTemplates.downLeft),
                action: .window(.minimize),
                notes: "先下再左"
            ),
            GestureProfile(
                name: "Close Window",
                trigger: rightTrigger,
                pattern: .freePath(PathTemplates.downRight),
                action: .window(.close),
                notes: "先下再右"
            ),
            GestureProfile(
                name: "Open Safari",
                trigger: rightTrigger,
                pattern: .freePath(PathTemplates.upRight),
                action: .openApp(bundleId: "com.apple.Safari", name: "Safari"),
                notes: "先上再右"
            ),
            GestureProfile(
                name: "Play / Pause",
                trigger: rightTrigger,
                pattern: .freePath(PathTemplates.rightLeft),
                action: .media(.playPause),
                notes: "左右折返"
            ),
            GestureProfile(
                name: "Open GitHub",
                trigger: rightTrigger,
                pattern: .freePath(PathTemplates.upLeft),
                action: .openURL("https://github.com"),
                notes: "先上再左"
            ),
        ]
    }
}
