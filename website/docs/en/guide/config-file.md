---
title: "Config file"
description: "StrokeMouse config path and backup: ~/Library/Application Support/StrokeMouse/gestures.json."
titleTemplate: "StrokeMouse"
---

# Config file

Gestures and related prefs persist as **JSON** for backup, manual sync, and power editing.

## Path

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

Settings can **Show in Finder**.

## Tips

| Scenario | Approach |
|----------|----------|
| Backup | Copy the `StrokeMouse` folder or just `gestures.json` |
| New machine | Install + authorize, then replace the file and relaunch |
| Hand-edit | Keep valid JSON; prefer backward-compatible optional fields |
| Corrupt | Delete the file to regenerate defaults (custom data lost) |

::: warning
The app may rewrite the file while running. Exit the app (or avoid concurrent writes) before overwriting.
:::

## What’s inside

Each profile typically has:

- id, name, enabled
- **trigger** (right / middle / side…)
- **pattern** (free-path points; legacy direction lists still decode)
- **action** (shortcut, app, URL, media, window, shell, AppleScript…)
- **scope** (global or bundle ids)
- notes

Exact fields follow the app’s `Codable` models; upgrades should remain readable when possible.

## UI vs JSON

Prefer **Settings → Gestures** day to day. JSON is for:

- bulk backup
- storing personal configs in git (strip private scripts)
- repairing broken files

## Privacy

Shell / AppleScript may contain paths or tokens. Redact before sharing.
