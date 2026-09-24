---
title: "Settings & menu bar"
description: "StrokeMouse settings and menu bar: gesture library, scroll reverse and smoothing, search/filter/import-export, editor, appearance, login launch, and permissions."
titleTemplate: "StrokeMouse"
---

# Settings & menu bar

## Menu bar

Day-to-day controls:

- **Start / stop gestures**
- **Pause / resume scroll enhancement** — appears once any scroll feature is on, and is independent of gesture pause
- **Open settings**
- **Status tint** — normal; **yellow** when gestures are paused; **red** when Accessibility is missing
- **Quit**

Optional login launch, hidden Dock icon, and **hidden menu bar icon**. With the menu bar icon hidden, click StrokeMouse in the Dock or relaunch the app to open settings; if the Dock is also hidden, relaunch the app. General settings can restore the menu bar icon and **quit the app**.

Hiding both Dock and menu bar icons requires a confirmation so you do not lose every visible entry point.

## Settings sections

| Section | Content |
|---------|---------|
| **Gestures** | Sidebar (Global / per-app) + list: search / filter / multi-select batch ops, import/export, editor |
| **Scrolling** | Per-axis reverse, smooth notched wheels, frontmost-app exclusions; stays on this Mac |
| **General** | Appearance, login item, hide Dock / menu bar, quit |
| **Permissions** | Accessibility / Automation status, guided authorize, deep links |
| **About** | Version and product info |

## Scroll enhancement {#scroll-enhancement}

**Settings → Scrolling** is separate from gestures. macOS Natural Scrolling is still one switch shared by mouse and trackpad; here you can reverse again per device and axis, and give a notched wheel some inertia.

- The **master switch** defaults on, while reverse and smoothing default off. With no feature enabled, no scroll listener is installed and existing gestures are unchanged
- **Reverse** splits the mouse wheel from the trackpad and Magic Mouse, each with vertical and horizontal toggles. It stacks on top of Natural Scrolling. Reversing trackpad horizontal scrolling can affect swipe-to-navigate in browsers. Shift-scroll horizontal movement follows the vertical setting
- **Smooth scrolling** applies only to a notched wheel, not to a trackpad and not to a high-resolution wheel that has no gesture phase. Presets are Gentle, Standard, and Responsive; dragging speed, duration, or acceleration under Advanced switches to Custom. Speed and acceleration apply only while smoothing is on. Holding Command, Option, Control, or Shift keeps native scrolling
- **Excluded apps** match the **frontmost app**, not the window under the pointer. Use this for games, remote desktops, virtual machines, and apps that only read whole-line ticks and therefore scroll too little while smoothing is on
- Pausing gestures does not pause scrolling, and you can try it while Settings is open. Once any feature is on, the menu bar shows Pause / Resume Scroll Enhancement. The menu bar icon still reflects gesture status only
- These settings stay on this Mac. They are not in gesture export, `gestures.json`, or backup sync. Another scroll utility running at the same time may process events twice

The scroll listener also needs Accessibility. Without it, scrolling stays native, and **Settings → Permissions** shows the scroll status on its own row.

## Gesture list

- Left sidebar groups by **Global** and **scoped apps** (similar to system shortcut scopes); **New** under an app pre-fills that scope
- Name, trigger, action, **scope (global or app icons)**, enabled state
- **Search** by name / action / notes; filter **All / Enabled / Disabled**; column sort
- Create / edit / delete; **multi-select** to batch enable, disable, delete, or export
- **Import / export** JSON packages: export the selection; on import, skip or force-import duplicates (forced duplicates are disabled by default)
- Defaults are editable and removable

## Gesture editor

Typical fields on a profile:

1. **Name** and notes
2. **Trigger**
3. **Path** — record free-path points (or direction-based templates)
4. **Action** — see [Actions](./actions)
5. **Scope** — global, or add apps by icon (search installed apps / multi-select / browse `.app`; stored as bundle ids)
6. **Enabled**

Hold the trigger to record; release to finish. Re-record until happy.

## Theme & language

- Appearance: follow system or force light / dark
- Copy: English, Simplified Chinese, Traditional Chinese, Korean, Japanese, Russian, and French (or follow the system language)

## Onboarding

First launch may show a short guide. Permissions and this site remain the long-term reference.

## Backup & share

- **Day to day**: Settings → Gestures → export selection as JSON; import on another Mac
- **Full library**: **Show in Finder** to copy `gestures.json`. See [Config file](./config-file)
