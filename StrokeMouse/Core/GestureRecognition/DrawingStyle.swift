import AppKit
import Foundation
import SwiftUI

/// User-configurable stroke style for live HUD and pattern previews.
enum DrawingStyle {
    static var showHUD: Bool {
        get {
            if UserDefaults.standard.object(forKey: PreferenceKey.showGestureHUD) == nil { return true }
            return UserDefaults.standard.bool(forKey: PreferenceKey.showGestureHUD)
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.showGestureHUD) }
    }

    static var lineWidth: CGFloat {
        get {
            let v = UserDefaults.standard.double(forKey: PreferenceKey.hudLineWidth)
            return v > 0 ? CGFloat(v) : Constants.defaultHUDLineWidth
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: PreferenceKey.hudLineWidth) }
    }

    static var showStartPoint: Bool {
        get {
            if UserDefaults.standard.object(forKey: PreferenceKey.hudShowStartPoint) == nil { return true }
            return UserDefaults.standard.bool(forKey: PreferenceKey.hudShowStartPoint)
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.hudShowStartPoint) }
    }

    static var startPointRadius: CGFloat {
        get {
            let v = UserDefaults.standard.double(forKey: PreferenceKey.hudStartPointRadius)
            return v > 0 ? CGFloat(v) : Constants.defaultHUDStartPointRadius
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: PreferenceKey.hudStartPointRadius) }
    }

    /// Stroke color stored as hex `#RRGGBBAA` or `#RRGGBB`.
    static var lineColorHex: String {
        get {
            UserDefaults.standard.string(forKey: PreferenceKey.hudLineColor)
                ?? Constants.defaultHUDLineColorHex
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.hudLineColor) }
    }

    static var lineNSColor: NSColor {
        get { color(fromHex: lineColorHex) ?? NSColor.systemBlue }
        set { lineColorHex = hex(from: newValue) }
    }

    static var lineSwiftUIColor: Color {
        get { Color(nsColor: lineNSColor) }
        set {
            #if os(macOS)
            lineNSColor = NSColor(newValue)
            #endif
        }
    }

    /// Start marker is always red (product requirement); only size/visibility is configurable.
    static var startNSColor: NSColor { .systemRed }

    static var startSwiftUIColor: Color { .red }

    static func snapshot() -> Snapshot {
        Snapshot(
            lineColor: lineNSColor,
            lineWidth: lineWidth,
            showStartPoint: showStartPoint,
            startPointRadius: startPointRadius,
            startColor: startNSColor
        )
    }

    struct Snapshot: Sendable {
        let lineColor: NSColor
        let lineWidth: CGFloat
        let showStartPoint: Bool
        let startPointRadius: CGFloat
        let startColor: NSColor
    }

    // MARK: - Hex helpers

    static func hex(from color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255)),
            Int(round(a * 255))
        )
    }

    static func color(fromHex hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&value) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value & 0xFF00_0000) >> 24) / 255
            g = CGFloat((value & 0x00FF_0000) >> 16) / 255
            b = CGFloat((value & 0x0000_FF00) >> 8) / 255
            a = CGFloat(value & 0x0000_00FF) / 255
        } else {
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
            a = 1
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
