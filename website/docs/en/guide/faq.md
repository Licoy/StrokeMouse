---
title: "FAQ"
description: "StrokeMouse FAQ: gestures not working, right-click menu, false matches, permissions, backups, and more."
titleTemplate: "StrokeMouse"
---

# FAQ

## Gestures do nothing?

Check in order:

1. **Accessibility** for **this** app copy (path / re-sign resets trust)
2. Menu bar status for pause or permission errors
3. Gesture **enabled**
4. Holding the configured **trigger** (default right, not left)
5. Stroke long enough (short clicks replay as normal clicks)

See [Permissions](./permissions) and [Quick start](./getting-started).

## Right-click menu gone?

A short right-click (almost no drag) should still open the menu. Once you exceed min distance, events are for the gesture only — expected.

Use light clicks for menus; draw long enough for gestures. Or bind gestures to **middle / side** buttons and leave right-click to the system.

## Wrong gesture or too many false hits?

- Differentiate similar paths
- Disable unused candidates on the same trigger
- Re-record cleaner templates
- Narrow with app scope

## Too strict / too loose?

Matching uses score thresholds and structure gates. Too strict: re-record closer to the template; too loose: reshape templates, drop lookalikes.

## Window actions fail?

Confirm Accessibility. Some apps expose weak AX trees — try an equivalent shortcut action.

## Shell / AppleScript silent?

- Does the command / script work alone in Terminal / Script Editor?
- For controlling other apps, is **Automation** granted?
- Any system prompt hidden behind windows?

## No launch at login?

Enable in **Settings → General**. Also check **System Settings → Login Items** if macOS disabled it.

## Wrong light / dark?

Force appearance under General, or return to “follow system”.

## Config lost?

Check `~/Library/Application Support/StrokeMouse/gestures.json`. Restore from backup after quitting the app. See [Config file](./config-file).

## Which mouse do I need?

Any mouse with a usable trigger button. Default is the **right** button; change per gesture to middle or side buttons. Trackpad clicks can work as mouse buttons; multi-finger trackpad gestures are not the intended workflow.

## How do I back up settings?

Copy `~/Library/Application Support/StrokeMouse/` or just `gestures.json`. After installing and authorizing on a new Mac, restore the file.
