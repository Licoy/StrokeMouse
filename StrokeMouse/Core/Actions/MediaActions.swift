import AppKit
import Foundation

enum MediaActions {
    /// NX media key codes (same family used by system media keys).
    private enum NXKey: Int {
        case play = 16
        case next = 17
        case previous = 18
        case soundUp = 0
        case soundDown = 1
        case mute = 7
    }

    static func perform(_ command: MediaCommand) {
        switch command {
        case .playPause:
            postMediaKey(.play)
        case .nextTrack:
            postMediaKey(.next)
        case .previousTrack:
            postMediaKey(.previous)
        case .volumeUp:
            postMediaKey(.soundUp)
        case .volumeDown:
            postMediaKey(.soundDown)
        case .mute:
            postMediaKey(.mute)
        }
    }

    private static func postMediaKey(_ key: NXKey) {
        func post(keyDown: Bool) {
            let flags = keyDown ? 0xA00 : 0xB00
            let data1 = (key.rawValue << 16) | flags
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ), let cgEvent = event.cgEvent else {
                return
            }
            cgEvent.post(tap: .cghidEventTap)
        }
        post(keyDown: true)
        post(keyDown: false)
    }
}
