---
title: "Install & build"
description: "Install StrokeMouse or build from source. macOS 14+, CLI build, Xcode, code signing, and tests."
keywords: "StrokeMouse install,build from source,xcodebuild,code signing,macOS 14"
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
| Release identity | **Developer ID Application** + Hardened Runtime (Accessibility pins to the Team ID; **users never install a cert**) |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` or package (smoke only; **Accessibility will not survive updates**) |
| Notarization | Apple-notarized and stapled since 0.0.40 (0.0.39 and earlier were self-signed) |

::: warning
Releases since 0.0.40 are notarized, so Gatekeeper opens them without extra steps.

**Accessibility**: in-app updates keep the grant because it pins to the developer's Team ID. Upgrading from 0.0.39 or earlier (self-signed) requires **one** re-authorization: StrokeMouse opens the Permissions page, click **Reset Authorization**, then switch StrokeMouse on again. End users do **not** install any certificate.
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
