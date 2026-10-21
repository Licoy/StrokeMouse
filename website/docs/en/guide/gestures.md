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

## Short-click replay

After the engine captures trigger-down:

- Distance **below** `minStrokeDistance`: marked synthetic down/up **replays** a normal click (menus work); if the target app maps that button, the mapping runs instead
- Once a real stroke starts: the down/drag/up group is **gesture-only**, not delivered to the front app

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
