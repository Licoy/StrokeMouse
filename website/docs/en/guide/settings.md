---
title: "Settings & menu bar"
description: "StrokeMouse settings and menu bar: gesture library search/filter/import-export, editor, appearance, login launch, and permissions."
titleTemplate: "StrokeMouse"
---

# Settings & menu bar

## Menu bar

Day-to-day controls:

- **Start / stop gestures**
- **Open settings**
- **Permission / status hints**
- **Quit**

Optional login launch and hidden Dock icon for a pure menu-bar tool.

## Settings sections

| Section | Content |
|---------|---------|
| **Gestures** | Library: search / filter / multi-select batch ops, import/export, editor |
| **General** | Appearance (system / light / dark), login item, Dock |
| **Permissions** | Accessibility / Automation status + deep links |
| **About** | Version and product info |

## Gesture list

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
- Copy: EN / 中文 via String Catalog; follows system language

## Onboarding

First launch may show a short guide. Permissions and this site remain the long-term reference.

## Backup & share

- **Day to day**: Settings → Gestures → export selection as JSON; import on another Mac
- **Full library**: **Show in Finder** to copy `gestures.json`. See [Config file](./config-file)
