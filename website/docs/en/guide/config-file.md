---
title: "Config file"
description: "StrokeMouse config: UI import/export of JSON gesture packages, plus full-library backup of gestures.json."
titleTemplate: "StrokeMouse"
---

# Config file

Gestures and related prefs persist as **JSON**. Prefer the UI to **import / export** selected gestures; copy the local file for a full-library backup.

## UI import / export

**Settings → Gestures**:

1. **Export** — multi-select gestures → save a JSON package (same version field as the config format)
2. **Import** — pick a JSON file; if content already exists, **skip duplicates** or **force import** (forced duplicates are disabled by default)

Good for sharing a few favorite gestures or syncing a subset across machines without replacing the whole library.

## Full library path

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

Settings can **Show in Finder**.

## Tips

| Scenario | Approach |
|----------|----------|
| Share / sync some gestures | **Settings → Gestures → Export / Import** |
| Full backup | Copy the `StrokeMouse` folder or just `gestures.json` |
| New machine | Install + authorize, then import a package **or** replace `gestures.json` and relaunch |
| Hand-edit | Keep valid JSON; prefer backward-compatible optional fields |
| Corrupt | Delete the file to regenerate defaults (custom data lost) |

::: warning
The app may rewrite the file while running. Exit the app (or avoid concurrent writes) before overwriting the full library file.
:::

## What’s inside

Each profile typically has:

- id, name, enabled
- **trigger** (right / middle / side…)
- **pattern** (free-path points; legacy direction lists still decode)
- **action** (shortcut, app, URL, media, window, shell, AppleScript…)
- **scope** (global or bundle ids)
- notes

Exact fields follow the app’s `Codable` models; upgrades should remain readable when possible. Import migrates legacy direction lists to free-path.

## UI vs JSON

Prefer **Settings → Gestures** for day-to-day editing and package import/export. Full-library JSON is for:

- complete backups and machine migrations
- storing personal configs in git (strip private scripts)
- repairing broken files

## Privacy

Shell / AppleScript may contain paths or tokens. Redact before sharing export packages or config files.
