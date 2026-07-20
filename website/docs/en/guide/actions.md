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
| **Open app** | Pick an installed app by icon and launch | Stored as bundle id |
| **Open URL** | Default browser / handler | — |
| **Media** | Play/pause, tracks, volume, mute | — |
| **Window** | Close, minimize, zoom, fullscreen, hide, center | Needs AX |
| **Shell** | Run a shell command (syntax-highlighted editor) | **High privilege** |
| **AppleScript** | Built-in presets or custom script (syntax-highlighted) | **High privilege**; may need Automation |

## Shortcut

Record or enter key code + modifiers. Display string (e.g. `⌃↑`) helps in lists.

## Open app

In the action picker, choose from **installed apps** by icon (search or browse a `.app`)—no need to type a bundle id by hand (launch still uses the bundle identifier). The display name is for the list UI.

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

Runs a local command string. The editor highlights syntax so long commands are easier to review.

::: danger Risk
Shell has your user-level power over files and processes. Only paste commands you understand and trust.
:::

## AppleScript

Use a **built-in preset** (sleep, empty trash, lock screen, screen saver, log out / restart / shut down, toggle dark mode, hide others, mute / unmute, Force Quit panel, screenshot to clipboard, open Downloads) or switch to a **custom** script. Controlling other apps may require **Automation**. The editor highlights syntax as well.

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
