import AppKit
import CoreGraphics

/// Runs the real HUD in a separate process from its full-screen target app.
@MainActor
private final class FullscreenHUDProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let arguments = CommandLine.arguments
    private var originalApp: NSRunningApplication?
    private var target: NSWindow?
    private var child: Process?
    private var result: Int32 = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fail explicitly if full-screen entry, the child, or full-screen exit stalls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print("FAIL: HUD probe timed out")
            if self.child?.isRunning == true { self.child?.terminate() }
            self.result = 2
            self.cleanExit()
        }
        if arguments.contains("--hud") {
            showHUD()
            return
        }
        originalApp = NSWorkspace.shared.frontmostApplication
        let window = NSWindow(
            contentRect: CGRect(x: 180, y: 180, width: 720, height: 480),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "StrokeMouse full-screen HUD regression check"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .darkGray
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        target = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if self.arguments.contains("--desktop") { self.runHUD() }
            else { window.toggleFullScreen(nil) }
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.runHUD() }
    }

    private func runHUD() {
        guard let target, NSApp.isActive,
              target.styleMask.contains(.fullScreen) != arguments.contains("--desktop")
        else {
            print("FAIL: target did not enter the requested state, active=\(NSApp.isActive) "
                + "fullscreen=\(target?.styleMask.contains(.fullScreen) == true) "
                + "desktop=\(arguments.contains("--desktop"))")
            finish(2)
            return
        }
        print("TARGET fullscreen=\(target.styleMask.contains(.fullScreen))")
        fflush(stdout)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
            + ["--hud", String(ProcessInfo.processInfo.processIdentifier)]
        process.terminationHandler = { process in
            DispatchQueue.main.async { self.finish(process.terminationStatus) }
        }
        child = process
        do { try process.run() }
        catch {
            print("FAIL: could not launch HUD process: \(error)")
            finish(2)
        }
    }

    private func showHUD() {
        guard let screen = NSScreen.main else {
            print("FAIL: a logged-in GUI session with a screen is required")
            exit(2)
        }
        let origin = screen.frame.origin
        let first = [CGPoint(x: origin.x + 200, y: origin.y + 200),
                     CGPoint(x: origin.x + 400, y: origin.y + 400)]
        let second = first.map { CGPoint(x: $0.x + 30, y: $0.y + 30) }
        GestureHUDController.shared.showPath(first)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard self.checkHUD(points: first, phase: "initial") else { self.endHUD(1); return }
            GestureHUDController.shared.hide()
            guard self.hudWindows.allSatisfy({
                !$0.isVisible && ($0.contentView as? GesturePathView)?.points.isEmpty == true
            }) else {
                print("FAIL: hide left a visible window or stale points")
                self.endHUD(1)
                return
            }
            GestureHUDController.shared.showPath(second)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.endHUD(self.checkHUD(points: second, phase: "reshown") ? 0 : 1)
            }
        }
    }

    private var hudWindows: [NSWindow] {
        NSApp.windows.filter { $0.contentView is GesturePathView }
    }

    private func checkHUD(points: [CGPoint], phase: String) -> Bool {
        guard let rawPID = arguments.last, let targetPID = Int32(rawPID),
              let screenWindows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]]
        else {
            print("FAIL: could not inspect target or on-screen windows")
            return false
        }
        let windowIDs = Set(screenWindows.compactMap {
            ($0[kCGWindowNumber as String] as? NSNumber)?.intValue
        })
        let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let retainsFocus = foregroundPID == targetPID
        let windows = hudWindows
        var passed = !windows.isEmpty && retainsFocus
        for window in windows {
            let localPoints = points.map {
                CGPoint(x: $0.x - window.frame.minX, y: $0.y - window.frame.minY)
            }
            let pointsMatch = (window.contentView as? GesturePathView)?.points == localPoints
            let onScreen = windowIDs.contains(window.windowNumber)
            passed = passed && pointsMatch && window.isVisible && window.isOnActiveSpace
                && onScreen && !window.isKeyWindow && !window.isMainWindow
            print("HUD phase=\(phase) policy=\(NSApp.activationPolicy().rawValue) "
                + "pointsMatch=\(pointsMatch) activeSpace=\(window.isOnActiveSpace) onScreen=\(onScreen)")
        }
        print("\(passed ? "PASS" : "FAIL") phase=\(phase) targetRetainsFocus=\(retainsFocus)")
        if !retainsFocus {
            print("Target pid=\(targetPID), foreground pid=\(String(describing: foregroundPID))")
        }
        fflush(stdout)
        return passed
    }

    private func endHUD(_ status: Int32) {
        GestureHUDController.shared.tearDown()
        exit(status)
    }

    private func finish(_ status: Int32) {
        result = status
        if let target, target.styleMask.contains(.fullScreen) { target.toggleFullScreen(nil) }
        else { cleanExit() }
    }

    func windowDidExitFullScreen(_ notification: Notification) { cleanExit() }

    private func cleanExit() {
        target?.close()
        originalApp?.activate(options: [])
        exit(result)
    }
}

@main
private struct ProbeMain {
    static func main() {
        let app = NSApplication.shared
        let arguments = CommandLine.arguments
        app.setActivationPolicy(arguments.contains("--hud") && arguments.contains("--accessory")
            ? .accessory : .regular)
        let delegate = FullscreenHUDProbe()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
