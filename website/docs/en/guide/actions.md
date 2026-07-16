---
title: "Actions"
description: "StrokeMouse actions: shortcuts, open app, URL, media keys, window commands, Shell, and AppleScript."
titleTemplate: "StrokeMouse"
---

# Actions

On a successful match, `ActionExecutor` dispatches the configured action.

## Overview

| Type | What it does | Notes |
|------|----------------|-------|
| None | Match-only / testing | — |
| **Shortcut** | Inject key chord | Needs Accessibility |
| **Open app** | Launch by bundle id | Correct id required |
| **Open URL** | Default browser / handler | — |
| **Media** | Play/pause, tracks, volume, mute | — |
| **Window** | Close, minimize, zoom, fullscreen, hide, center | Needs AX |
| **Shell** | Run a shell command | **High privilege** |
| **AppleScript** | Run AppleScript | **High privilege**; may need Automation |

## Shortcut

Record or enter key code + modifiers. Display string (e.g. `⌃↑`) helps in lists.

## Open app

Identify apps by **bundle identifier**, e.g.:

- Safari: `com.apple.Safari`
- Terminal: `com.apple.Terminal`

Name is mainly for UI.

## Open URL

Any URL the system can open. Default “Open GitHub” uses this.

## Media

| Command | Role |
|---------|------|
| playPause | Play / pause |
| nextTrack / previousTrack | Skip |
| volumeUp / volumeDown / mute | Volume |

## Window

| Command | Role |
|---------|------|
| close | Close window |
| minimize | Minimize |
| zoom | Zoom (green-button semantics) |
| fullscreen | Full screen |
| hide | Hide app |
| center | Center window |

Usually targets the front window; fails if AX is unavailable.

## Shell

Runs a local command string.

::: danger Risk
Shell has your user-level power over files and processes. Only paste commands you understand and trust.
:::

## AppleScript

Runs script text. Controlling other apps may require **Automation**.

::: danger Risk
Same class of risk as Shell. Never run untrusted scripts.
:::

## Choosing well

| Goal | Prefer |
|------|--------|
| System / app hotkeys | Shortcut |
| Launch software | Open app |
| Bookmark-like jump | Open URL |
| Music & volume | Media |
| Window management | Window |
| Heavy automation | Shell / AppleScript (carefully) |

Persistence: [Config file](./config-file).
