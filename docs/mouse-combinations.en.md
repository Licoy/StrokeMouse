# Mouse Combinations

Configure these under **Settings → Gestures → Add → Mouse Combinations**; no stroke recording is needed. Each combination uses the existing action picker, target window, and global / app / app group scopes, and is included in import, export, and backups.

## Supported triggers

| Trigger | Options | When it runs |
| --- | --- | --- |
| Hold the right button | Scroll up, scroll down | Every valid wheel event, so it can repeat |
| Hold the right button | Left click | The first left click during this right-button hold |
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
