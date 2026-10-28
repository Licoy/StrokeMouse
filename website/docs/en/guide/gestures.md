---
title: "Gestures"
description: "StrokeMouse gesture system: triggers, short-click replay, free-path matching, visual app scope, and default gestures."
titleTemplate: "StrokeMouse"
---

# Gestures

Triggers, sampling, and matching rules for reliable custom strokes. Scroll reverse and smoothing are not in the gesture library; see [Settings & menu bar](./settings#scroll-enhancement).

## Pipeline

```text
Hold trigger → sample path → distance ≥ min stroke
     → release → match among same-trigger candidates → run action
```

1. **Trigger lives on each gesture profile** (default right button)
2. Engine monitors only buttons used by **enabled** gestures
3. On release, **app scope** + frontmost `bundleIdentifier` filter candidates

## Triggers

Per gesture:

| Trigger | Notes |
|---------|--------|
| Right | Default; short-click still opens context menu |
| Middle | Wheel click |
| Side back / forward | Typical thumb buttons |

Unmonitored buttons **always** pass through. The left button passes through too, except as described in [Secondary action](#secondary-action).

## Secondary action

A mouse-drawn gesture can enable a **secondary action** in the editor: while holding the trigger to draw, click the left button once and only the secondary action runs on release; without the click, the primary action runs.

- Left down/up are consumed as a pair only while you hold the trigger and a gesture available in the target app has a secondary action; otherwise left clicks pass through as usual
- Recognition still considers every candidate; the left click only chooses which action runs. If the matched gesture has no secondary action, nothing runs and a notice appears
- A left click without a valid stroke cancels the gesture; no trigger click is replayed
- Trackpad Draw and Touch Gestures do not support secondary actions and always run the primary action

## Mouse button mappings

Choose **Add → Mouse Buttons** to map a side button (back / forward) or the middle button. A single click runs the action, with no drawing needed. The menu includes two presets: “Back Side Button · Go Back” (⌘[) and “Forward Side Button · Go Forward” (⌘]).

- The action runs on release. When the same button also draws gestures, a press that stays under `minStrokeDistance` runs the mapping and a longer one is recognized as a drawing, so one press never triggers both
- When the target app has a mapping but no drawn gesture for that button, moving while holding it still counts as a click
- Turn on **Require Modifier Key** and pick one of Fn / Control / Option / Shift / Command to trigger only while exactly that key is held (e.g. ⌘ + back side button); a mapping without it never fires while any modifier is held, so one button can carry both a plain and a modified mapping. If the chosen modifier also starts Trackpad Draw, Trackpad Draw takes over and the mapping won't run
- Global, app-group and selected-app scopes apply as usual, and only the most specific tier counts; several mappings in that tier are a conflict, so nothing runs and a notice appears
- When the target app has no gesture or mapping for the button, the click passes through untouched, for example to keep the browser's native back / forward
- The right button cannot be mapped, so context menus keep working; a successful mapping shows no match toast

## Mouse combinations

Choose **Add → Mouse Combinations** to create one. No stroke recording is needed, and every action, target window and scope applies.

| Trigger | Mouse action | When it runs |
|--------|------|------|
| Hold right button | Scroll up / down | Once per wheel tick, so it can repeat |
| Hold right button | Left click | The first left click of each right-button hold |
| Hold right button | Drag to scroll | Scrolls horizontally / vertically once the pointer moves at least 10 points; stops on release |
| Screen edge (top / bottom / left / right) | Right click | The right button is pressed and released at the chosen edge without starting a stroke |
| Screen edge (top / bottom / left / right) | Scroll up / down | No right button needed; at most once every 100 ms |

- A right-button hold or click that runs a combination neither opens the context menu nor counts as a drawing; a right click that triggers nothing still opens the menu
- “Hold right + left click” takes precedence over a secondary action; without that combination the secondary action works as before
- Unconfigured wheel directions and apps without a combination scroll normally; ticks a combination uses do not scroll the page
- While the right button is held, a high-precision wheel runs the action at most every 120 ms, so one scroll cannot flip through many tabs; trackpads, momentum scrolling and smoothing frames from other scroll tools never trigger actions
- An edge is the 3 points inside each display’s bounds, including the seam between adjacent displays; a corner that matches two configurations in the same tier is a conflict
- Scopes and conflicts work like button mappings: only the most specific tier counts, and several entries there are a conflict, so nothing runs and a notice appears; an app policy can turn off global “Mouse Combinations” on its own

**Drag to scroll**: choose **Drag to scroll** in the **Hold right button** mode, then adjust **Sensitivity** (0.25–4×, in 0.05 steps) and **Reverse direction** if needed; by default content follows the pointer. Scrolling starts only after the pointer moves at least a fixed 10 points from where the right button was pressed, regardless of the minimum stroke distance; releasing earlier replays a normal right click, so the context menu still works, and once scrolling starts, release neither replays a click nor recognizes a stroke. It scrolls the content under the pointer when scrolling begins without activating any window, while app scope still uses the target frozen at right-button down. Release stops immediately, with no inertia, pointer lock, or recentering, so screen edges limit travel. Drag to scroll has no ordinary or secondary action; save it and test by holding right and moving outside the editor.

Within the most specific matching scope tier (app > app group > global), a drag-scroll gesture cannot coexist with right-button drawing or another drag-scroll gesture; at runtime such a conflict runs nothing and shows a dedicated notice. Definite conflicts (global vs. global, intersecting app lists, or the same app group) are blocked everywhere: saving in the editor, enabling with the checkbox or in a batch, **Move To**, and deleting an app group while keeping its gestures as global are refused with a message naming the conflicting gestures; **Duplicate** creates the copy disabled if it would conflict; importing brings conflicting gestures in disabled and lists them; and enabled gestures that already conflict (for example after restoring a backup) show a warning icon in the gesture list. Existing gestures are never deleted or disabled automatically; dynamic overlaps between different app groups are still resolved at runtime.

## Short-click replay

After the engine captures trigger-down:

- Distance **below** `minStrokeDistance`: marked synthetic down/up **replays** a normal click (menus work); if the target app maps that button, the mapping runs instead; where right-button **Drag to scroll** applies, the threshold is a fixed 10 points instead
- Once a real stroke or drag scrolling starts: the down/drag/up group is **gesture-only**, not delivered to the front app

## Free-path matching

Primary recognizer:

- Ordered arc-length resample
- 1D / 2D normalization
- **±12°** limited rotation search
- Score ≥ threshold
- **Segment count / turn structure** as hard gates (not score-compensable)
- **No** mirror, reverse, or near-miss fallbacks

Record clean strokes at a moderate speed; re-record ornate shapes until stable.

## Live HUD

While holding the trigger, the current path is drawn on screen so you can align with the template.

## App scope

| Scope | Behavior |
|-------|----------|
| Global | Match in any front app |
| Specific apps | Only when the frontmost app is in the list |

In the editor, pick **installed apps by icon** (search, multi-select, or browse a `.app`)—no need to type bundle ids by hand (matching still uses bundle identifiers under the hood). Use for browser-only or IDE-only gestures.

The gesture list scope column shows “Global” or a compact set of app icons. Under **Settings → Gestures**, the left sidebar browses Global and per-app groups; creating a gesture under a node pre-fills that scope.

## Enable / disable

Per-gesture toggle. Disabled profiles leave the monitor set and matching pool.

## Default examples

Built-in gestures (trigger is editable per profile):

<DefaultGestures />

## Editing

**Settings → Gestures** to add, edit, delete, record paths, pick actions. See [Settings & menu bar](./settings) and [Actions](./actions).
