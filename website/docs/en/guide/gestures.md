---
title: "Gestures"
description: "StrokeMouse gesture system: triggers, short-click replay, free-path matching, app scope, and default gestures."
titleTemplate: "StrokeMouse"
---

# Gestures

Triggers, sampling, and matching rules for reliable custom strokes.

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

Left button and unmonitored buttons **always** pass through.

## Short-click replay

After the engine captures trigger-down:

- Distance **below** `minStrokeDistance`: marked synthetic down/up **replays** a normal click (menus work)
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
| Specific apps | Only when frontmost bundle id is listed |

Use for browser-only or IDE-only gestures.

## Enable / disable

Per-gesture toggle. Disabled profiles leave the monitor set and matching pool.

## Default examples

Built-in gestures (trigger is editable per profile):

<DefaultGestures />

## Editing

**Settings → Gestures** to add, edit, delete, record paths, pick actions. See [Settings & menu bar](./settings) and [Actions](./actions).
