---
title: "Actions"
description: "StrokeMouse actions: shortcuts, system commands, open app, URL, media keys, window commands, Shell, and AppleScript."
titleTemplate: "StrokeMouse"
---

# Actions

On a successful match, `ActionExecutor` dispatches the configured action.

## Overview

| Type | What it does | Notes |
|------|----------------|-------|
| None | Match-only / testing | — |
| **Shortcut** | Inject key chord | Needs Accessibility |
| **System** | Mission Control, Application Windows, Previous / Next Space | Needs Accessibility; must match system shortcuts |
| **Open app** | Pick an installed app by icon and launch | Stored as bundle id |
| **Open URL** | Default browser / handler | — |
| **Media** | Play/pause, tracks, volume, mute | — |
| **Window** | Close, minimize, zoom, maximize, fullscreen, hide, center | Needs AX |
| **Shell** | Run a shell command (syntax-highlighted editor) | **High privilege** |
| **AppleScript** | Built-in presets or custom script (syntax-highlighted) | **High privilege**; may need Automation |

## Shortcut

Shortcuts are configured by recording only; the display field is read-only. Click **Record**, press the keys in the intended order, then release all keys to finish. Press Esc by itself to cancel.

Both shortcuts with a regular key (for example, `⌘⌥Q`) and modifier-only shortcuts (for example, `⌘⌥`) are supported. The result is displayed in the order the keys were pressed. Supported modifier keys are Command, Option, Control, Shift, and Fn/Globe. Fn can be used alone or combined with other keys, for example `fn⌃⇧←`, which arranges windows left and right on macOS 15 and later.

Release all modifier keys before you start recording, then press the keys in the order you want them replayed. Fn must be pressed physically; a key remapped to Fn in System Settings, such as Caps Lock, also works. Caps Lock may remain enabled once its key is released.

After recording a shortcut, click **Add Follow-up Key** to record up to 3 more chords. They are pressed in order in the same target, about 50 ms apart, and the sequence stops at the first failure. For example, `⌘V` followed by `↩` pastes and sends in a chat app. Older versions run only the first chord.

## System

Choose the **System** action type to run one of these commands:

| Command | Default shortcut | Target |
|---------|------------------|--------|
| Mission Control | ⌃↑ | Current desktop; the captured window is not activated |
| Application Windows | ⌃↓ | Activates the captured app and window first |
| Previous Space | ⌃← | Current desktop; the captured window is not activated |
| Next Space | ⌃→ | Current desktop; the captured window is not activated |

System commands send the matching shortcut from System Settings › Keyboard › Keyboard Shortcuts › Mission Control; the defaults are the macOS defaults. If you changed them in macOS, record a different shortcut in the editor to override the default, or click **Restore default shortcut**. The editor reads those system settings and warns when the matching system shortcut is turned off or differs from the one configured here; **Use System Shortcut** adopts the system setting. StrokeMouse never changes system settings.

If a command uses its default binding but that shortcut is turned off in System Settings, running it shows an error instead of silently doing nothing.

These are discrete commands that run once per trigger, not the native interactive four-finger animations that follow your fingers. The four-finger swipe up / down Touch Gesture presets use the Mission Control and Application Windows system commands.

Libraries and exports containing system commands or drag to scroll use format **v4**; Fn shortcuts alone use **v3**, and everything else stays **v2**. Older versions cannot read v3 / v4 files.

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
| zoom | Zoom to the app’s preferred size |
| maximize | Maximize Window |
| fullscreen | Full screen |
| hide | Hide app |
| center | Center window |

Window actions use the exact window captured when the gesture begins, rather than whichever window is frontmost when the action runs; Hide App uses the captured app. Missing or unsupported windows and unavailable Accessibility access produce a failure message.

**Maximize Window** fills the available area of the screen containing the captured window, respecting the menu bar and Dock. Repeating it keeps the window maximized; it does not restore the previous size. Unlike `zoom`, which uses the app’s preferred size, it aims to fill that available area; unlike `fullscreen`, it stays in the desktop. It does not exit full screen before maximizing, so leave full screen first. If the window cannot be moved or resized, or does not reach the required bounds (for example due to app restrictions), the action shows a failure.

Libraries and exports with Maximize Window as a primary or secondary action use format **v5** and require a compatible version; configurations without it keep the existing v2/v3/v4 rules.

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
| Mission Control / Spaces | System |
| Launch software | Open app |
| Bookmark-like jump | Open URL |
| Music & volume | Media |
| Window management | Window |
| Heavy automation | Shell / AppleScript (carefully) |

Persistence: [Config file](./config-file).
