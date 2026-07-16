---
title: "Quick start"
description: "Get started with StrokeMouse: grant Accessibility, enable gestures, and draw your first stroke in minutes."
titleTemplate: "StrokeMouse"
---

# Quick start

Get StrokeMouse running and verify your first gesture in a few steps.

## Requirements

- **macOS 14 Sonoma** or later
- Any mouse (default trigger is the **right** button; change per gesture if you want)
- Willingness to grant **Accessibility**

## Five steps

### 1. Launch the app

A StrokeMouse icon appears in the menu bar. The app is menu-bar first; you can hide the Dock icon in settings.

### 2. Grant Accessibility

Open **Settings → Permissions**, jump to **System Settings → Privacy & Security → Accessibility**, and enable StrokeMouse.

::: tip
Without trust, the engine will **not** pretend to listen. Status is visible in the menu bar and the Permissions page — no silent failure.
:::

### 3. Ensure gestures are enabled

From the menu bar, confirm gestures are active / resume if paused.

### 4. Open the gesture list

**Settings → Gestures** shows defaults (e.g. stroke up → Mission Control). Create your own anytime.

### 5. Draw the first stroke

1. Hold the gesture **trigger** (default **right** button)
2. Drag a path (e.g. upward)
3. Release

On match, the bound action runs. While holding the trigger, a **live stroke HUD** draws on screen.

## Click vs gesture

| Behavior | Result |
|----------|--------|
| Press trigger, **almost no move**, release | Short click: synthetic click is replayed — **context menu still works** |
| Move beyond min stroke distance, release | Gesture mode: the down/drag/up sequence is for gestures only — **no** context menu |

Left button and unmonitored buttons always pass through.

## Next

- [Install & build](./installation) — compile to `output/StrokeMouse.app`
- [Permissions](./permissions) — Accessibility vs Automation
- [Gestures](./gestures) — triggers, matching, scope
- [Actions](./actions) — shortcuts, windows, scripts
