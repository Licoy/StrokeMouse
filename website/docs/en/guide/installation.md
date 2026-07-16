---
title: "Install & build"
description: "Install StrokeMouse or build from source. macOS 14+, CLI build, Xcode, code signing, and tests."
titleTemplate: "StrokeMouse"
---

# Install & build

Prefer the [download page](/en/download) for **Apple Silicon / Intel** production builds. To compile yourself, follow the source build steps below.

## Requirements

| Item | Requirement |
|------|-------------|
| OS | macOS 14 Sonoma or later |
| Dev build | Xcode 16+ |
| Project gen | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |

## Clone

```bash
git clone https://github.com/Licoy/StrokeMouse.git
cd StrokeMouse
```

## Recommended: CLI build

Stable output path `output/StrokeMouse.app` reduces repeated Accessibility prompts:

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app
./scripts/build.sh --open    # open when done
./scripts/build.sh --release # Release
```

After changing `project.yml` or adding/removing sources:

```bash
./scripts/generate_project.sh
```

## Run in Xcode

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

Scheme **StrokeMouse** → Run.

## Code signing

| Item | Value |
|------|--------|
| Bundle ID | `com.strokemouse.app` |
| Dev identity | **`StrokeMouse Dev`** in your keychain (self-signed; trust for code signing) |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` |
| GitHub Release | ad-hoc + Hardened Runtime; currently not Apple-notarized |

::: warning
Changing signing identity or app path often makes macOS treat it as a **new** app — re-check Accessibility.

If Gatekeeper blocks a GitHub Release on first launch, right-click the app and choose Open, or use System Settings → Privacy & Security → Open Anyway.
:::

## Release artifacts

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

Each architecture produces ZIP, TAR.GZ, and DMG assets. The ZIP also powers Sparkle in-app updates. See `RELEASING.md` at the repository root for version and tagged-release operations.

## Tests

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## Dependencies

- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) — launch at login
- [Sparkle](https://github.com/sparkle-project/Sparkle) — update signing and in-app installation
- System: `CGEventTap`, Accessibility, optional Apple Events

## Next

After a successful build, continue with [Permissions](./permissions) and [Quick start](./getting-started).
