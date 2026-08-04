---
title: "Install & build"
description: "Install StrokeMouse or build from source. macOS 14+, CLI build, Xcode, code signing, and tests."
titleTemplate: "StrokeMouse"
---

# Install & build

Homebrew is the recommended installation method. You can also get the **Apple Silicon / Intel** production builds from the [download page](/en/download). To compile yourself, follow the source build steps below.

## Requirements

| Item | Requirement |
|------|-------------|
| OS | macOS 14 Sonoma or later |
| Dev build | Xcode 16+ |
| Project gen | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |

## Homebrew (recommended)

Install from the [project-maintained Licoy Homebrew Tap](https://github.com/Licoy/homebrew-tap):

```bash
brew install --cask licoy/tap/strokemouse
```

StrokeMouse also supports in-app updates. To force Homebrew to check and install an upgrade, use:

```bash
brew upgrade --cask --greedy strokemouse
```

Uninstalling keeps your settings by default. Add `--zap` to remove them as well:

```bash
brew uninstall --cask strokemouse
brew uninstall --cask --zap strokemouse
```

Homebrew and manual downloads use the same release packages, so the first-launch Gatekeeper and Accessibility notes below apply to both.

## Clone

```bash
git clone https://github.com/Licoy/StrokeMouse.git
cd StrokeMouse
```

## Recommended: CLI build

Stable output path `output/StrokeMouse.app` reduces repeated Accessibility prompts.  
Debug shows as **StrokeMouse Dev** (Bundle ID `com.strokemouse.app.dev`) so it can be authorized alongside the release **StrokeMouse** app:

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app (Accessibility: StrokeMouse Dev)
./scripts/build.sh --open    # open when done
./scripts/build.sh --release # Release (same display name / Bundle ID as shipping builds)
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
| Bundle ID | Release: `com.strokemouse.app`; Debug: `com.strokemouse.app.dev` (display name StrokeMouse Dev) |
| Dev identity | **`StrokeMouse Dev`** in your keychain (self-signed; local builds) |
| Release identity | **`StrokeMouse Release`** self-signed + Hardened Runtime (stable identity; **users never install the cert**) |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` or package (smoke only; **Accessibility will not survive updates**) |
| Notarization | Not Apple-notarized / no Developer ID currently |

::: warning
If Gatekeeper blocks a GitHub Release on first launch, right-click the app and choose Open, or use System Settings → Privacy & Security → Open Anyway.

**Accessibility**: official packages use a stable self-signed identity, so **in-app updates signed with the same cert usually keep the grant**. Migrating from old ad-hoc builds or rotating the cert still requires **one** re-authorization. End users do **not** install the publisher certificate.
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
