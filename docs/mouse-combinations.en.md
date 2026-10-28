# Mouse Combinations

Configure these under **Settings → Gestures → Add → Mouse Combinations**; no stroke recording is needed. Ordinary combinations use the existing action picker and target window; all combinations support global / app / app group scopes, and is included in import, export, and backups.

## Supported triggers

| Trigger | Options | When it runs |
| --- | --- | --- |
| Hold the right button | Scroll up, scroll down | Every valid wheel event, so it can repeat |
| Hold the right button | Left click | The first left click during this right-button hold |
| Hold the right button | Drag to scroll | Continuous horizontal / vertical scrolling while moving; release to stop |
| Top / bottom / left / right screen edge | Right click | The right button is pressed and released at the same chosen edge without starting a stroke |
| Top / bottom / left / right screen edge | Scroll up, scroll down | Valid wheel events, at most once every 100 ms, with no right button held |

For example, set "hold right + scroll up" to switch to the previous tab, "hold right + left click" to close the tab, and "right edge + wheel" to change the volume. The action starts empty for you to choose.

## How they interact with other input

- While the right button is held, wheel / left-click combinations run first; releasing the right button afterwards neither recognizes a stroke nor opens the context menu.
- A plain right press and release that triggers no combination still opens the context menu.
- Wheel directions without a combination keep scrolling normally, and apps without a combination keep their original input.
- When a "right + left click" combination and a drawn gesture's left-click secondary action both apply, the combination wins; without that combination the secondary action behaves as before.
- For the same trigger, app combinations take precedence over app groups, then global ones. Several matches at the same level show a conflict toast and run nothing.
- Combinations follow the gesture master switch, pause, permissions, and input suppression while recording / editing; an app policy can turn off global "Mouse Combinations" on its own.

## Drag to scroll

Select **Drag to scroll** in the held-right mode, then adjust sensitivity (0.25–4×) and reverse direction if needed. Content follows the pointer by default, scrolling the content under the pointer when scrolling begins without activating a window. App-scope matching still uses the target frozen at right-button down. This mode uses no ordinary or secondary action; save and test by holding right and moving outside the editor.

Releasing stops immediately, with no inertia, pointer lock, or recentering; screen edges therefore limit available travel. A short press below the movement threshold still replays a right click. Once dragging starts, release neither replays a click nor recognizes a stroke.

Drag scrolling and right-button drawing share movement input. The most specific scope wins: app, app group, then global, so app drag scrolling can override global drawing and vice versa. A drag-scroll profile together with right-button drawing, or several drag-scroll profiles at the same tier, causes a conflict and runs nothing. The editor blocks definite conflicts between global scopes, intersecting app lists, or the same app group; it never disables or deletes existing drawings. Dynamic overlaps between different groups are resolved at runtime.

Exports and backups containing drag scrolling or system actions use v4; Fn-only shortcuts use v3, and ordinary configurations remain v2.

## Edges and the wheel

- An edge is the 3 logical points inside each display's actual bounds, in Quartz display coordinates, including displays above or left of the main display; the seam between adjacent displays also counts as an edge.
- A corner may satisfy two edge combinations; several matches at the same level are treated as a conflict.
- Regular wheels and native high-precision pixel wheels (such as Logitech devices) are supported; trackpad gestures, system momentum scrolling, and smoothing frames posted by other scroll tools never trigger a new action.
- An edge wheel runs its action at most once every 100 ms, for regular and high-precision wheels alike; scrolling in an unconfigured direction does not run the action.
- While the right button is held, smooth-wheel actions are at least 120 ms apart; reversing direction or pressing the right button again triggers immediately, so the many smoothing frames of one scroll cannot flip through tabs.
- Up / down follows the system wheel event direction and is recognized before the app's scroll reversal and smooth scrolling.
- Wheel ticks used by a combination do not scroll the page; edge ticks outside every matching scope are replayed with a re-entry marker and still go through scroll enhancement.

## Implementation and verification

`GestureInput.mouseCombination` stores the combination. Mouse buttons and held-right combinations reuse the existing session and frozen target. An edge wheel does not occupy the gesture session: the tick is swallowed first and the target app and window are resolved on a separate queue; the callback only reads locked state and never calls AX, NSWorkspace, or the main thread synchronously. When no scope matches, or the conditions no longer hold when the tick is delivered, a new wheel event with the original deltas is replayed, without reusing the pointer location from when it was swallowed.

The mouse and scroll-enhancement event taps coordinate through one wheel entry point, so tap installation order cannot change combination precedence; no continuous mouse-movement events are monitored. Existing configurations need no migration; combinations use their own input type.

Automated regression tests cover multi-display edge coordinates, config round trips, discrete / continuous / synthetic event filtering, precedence over scroll enhancement, held-right repetition and exclusivity, normal right-click replay, scope precedence / conflicts, app exclusion, and pause.

For manual testing, start with a harmless shortcut or media action, then check the context menu, browser scrolling, multi-display edges, and the chosen app scope. The development build "StrokeMouse Dev" needs its own Accessibility permission.

Drag scrolling and system actions still need real-app checks for both axes, screen-edge limits, stopping on release, and target semantics. Automated checks do not establish real-app scrolling or native trackpad-animation acceptance.
