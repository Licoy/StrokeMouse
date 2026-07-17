---
title: "Permissions"
description: "StrokeMouse permissions: Accessibility for global mouse listening, Automation for AppleScript."
titleTemplate: "StrokeMouse"
---

# Permissions

StrokeMouse needs global mouse listening and optional automation. Failures are visible in the **menu bar** and **Settings → Permissions**, not silent.

## Overview

| Permission | Required? | Purpose |
|------------|-----------|---------|
| **Accessibility** | **Yes** | Global mouse (`CGEventTap`), shortcut injection, window AX |
| **Automation** | Optional | AppleScript controlling other apps |

## Accessibility

### Why

The engine intercepts mouse sequences for **configured triggers**. If `AXIsProcessTrusted()` is false, the app must **not** pretend to listen.

### How to enable

Prefer the in-app **Guide Me** flow (first-run onboarding and **Settings → Permissions**):

1. Click **Guide Me** — opens **Privacy & Security → Accessibility** and a floating panel that follows the System Settings window
2. Drag **StrokeMouse** (Debug builds appear as **StrokeMouse Dev**) from the panel into the list
3. Turn the toggle on; the app detects trust within a few seconds and starts the gesture engine

You can also complete the same steps manually in System Settings.

### Common cases

- **In-app updates of official builds** (stable `StrokeMouse Release` self-signed identity): Accessibility usually **does not** need re-granting
- **Migrating from old ad-hoc builds, rotating the signing cert, or a new install path**: re-authorize **once**
- **Toggle on but dead**: off/on, or remove and re-add, then relaunch
- **Multiple copies**: authorize the binary you actually launch

## Automation

Only needed for **AppleScript** actions that control other apps. macOS prompts on first use, per target app.

## Safety

- Global event taps are powerful — build or download from sources you trust
- **Shell / AppleScript** can do anything your user can; the UI keeps risk warnings — **only add trusted scripts**
- Engineering policy: do not dump full user scripts to public logs

## Self-check

If nothing works:

1. Menu bar showing permission / engine issues?
2. Accessibility checked for **this** app instance?
3. Gestures paused?
4. Using a mouse button that is **not** a configured trigger?

See also [FAQ](./faq).
