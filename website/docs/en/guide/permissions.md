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

1. StrokeMouse **Settings → Permissions**
2. Jump to **Privacy & Security → Accessibility**
3. Enable StrokeMouse
4. If missing, run the app once or add it from the UI prompt

### Common cases

- **Upgrade / re-sign / new path**: re-authorize
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
