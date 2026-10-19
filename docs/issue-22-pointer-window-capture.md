# Pointer window capture compatibility

Some macOS applications expose their windows through Accessibility but return
`kAXErrorNotImplemented` from the system-wide point hit test. StrokeMouse uses a
restricted compatibility path for that exact failure so application-scoped
gestures and exact frozen-window actions can still target the window under the
pointer.

The normal Accessibility path remains authoritative. The compatibility path is
entered only for `hitTest / notImplemented`; `cannotComplete`, `apiDisabled`,
and other Accessibility failures remain visible errors.

The compatibility path reads the on-screen Core Graphics window list in its
front-to-back order and uses Quartz coordinates throughout. The first normal
layer window containing the pointer is the candidate. A nonzero layer in front
normally makes capture fail because StrokeMouse cannot prove which window would
receive the pointer event.

Visual alpha does not imply pointer transparency, so alpha-zero records remain
in the same Z-order and bounds checks instead of exposing a window behind them.

One narrowly verified macOS system carrier is exempted. A record can be skipped
only when all of these conditions hold:

- its owner bundle is `com.apple.dock`;
- its layer equals `CGWindowLevelForKey(.dockWindow)`;
- its bounds exactly equal one active display's `CGDisplayBounds`;
- a point hit test limited to that Dock process returns `noValue` with no element.

Any missing condition, unknown owner, successful Dock hit, or other AX result
stops capture. The code does not read window titles and does not skip arbitrary
floating windows.

Full capture then reads `AXWindows` only for the candidate PID. Every candidate
must retain that PID and the `AXWindow` role. StrokeMouse compares standardized
AX position and size with the Core Graphics bounds exactly, requires one unique
match, and re-reads the original CG window number before freezing the AX window.
Zero matches, duplicate geometry, a changed PID/layer/bounds, or a vanished
window all fail explicitly. Identity capture uses the same process locator but
does not read `AXWindows`.

Diagnostic logs contain the operation, AX code, result, PID, and, when known,
the window number and layer. They do not contain window titles, scripts, or user
content.
