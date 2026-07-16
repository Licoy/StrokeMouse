# StrokeMouse Release Guide

StrokeMouse publishes architecture-specific macOS applications and Sparkle appcasts from GitHub Actions. The canonical public repository is `Licoy/StrokeMouse`.

## Release contract

- Tags use `vX.Y.Z`; `project.yml` remains the application version source.
- Release assets are `StrokeMouse-macos-{arm64|x86_64}.{zip,app.tar.gz,dmg}`.
- Sparkle reads `appcast-{arm64|x86_64}.xml` from the latest GitHub Release.
- Release applications are ad-hoc signed with Hardened Runtime and are not notarized.
- The ZIP is the Sparkle update archive. DMG is the recommended manual download.

## One-time repository setup

1. Create or migrate to the public repository `https://github.com/Licoy/StrokeMouse`.
2. Generate the Xcode project and resolve package artifacts:

   ```bash
   ./scripts/generate_project.sh
   xcodebuild \
     -resolvePackageDependencies \
     -project StrokeMouse.xcodeproj \
     -scheme StrokeMouse \
     -clonedSourcePackagesDirPath build/SourcePackages
   ```

3. Generate a dedicated Sparkle EdDSA key pair and export the private key:

   ```bash
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys \
     --account com.strokemouse.app
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys \
     --account com.strokemouse.app \
     -x /secure/offline/location/strokemouse-sparkle-private-key
   ```

4. Configure the printed public key and exported private key as repository Actions secrets:

   ```bash
   gh secret set SPARKLE_PUBLIC_KEY --repo Licoy/StrokeMouse
   gh secret set SPARKLE_PRIVATE_KEY \
     --repo Licoy/StrokeMouse \
     < /secure/offline/location/strokemouse-sparkle-private-key
   ```

Keep an encrypted offline backup of the private key. Do not commit it, paste it into logs, or delete the only copy. Existing installations trust this key; rotating it requires a planned Sparkle key migration released with the old key.

## Local release verification

Package both architectures with the public key injected:

```bash
SPARKLE_PUBLIC_KEY="..." EXPECTED_MACOS_SDK_MAJOR=26 \
  ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." EXPECTED_MACOS_SDK_MAJOR=26 \
  ARCH=x86_64 ./scripts/package-app.sh
```

The script validates the architecture, deployment target, SDK, Info.plist, entitlements, code signature, ZIP, TAR.GZ, and DMG. Outputs are written to `dist/`.

## Publish a version

Start from a clean tracked worktree on the branch that should be released:

```bash
./bump.sh -v 0.1.0
git push --atomic origin HEAD v0.1.0
```

Or let the bump script perform the atomic push:

```bash
./bump.sh -v 0.1.0 -p
```

The annotated tag triggers `.github/workflows/release.yml`. The workflow tests the app, builds both architectures, signs both update archives with Sparkle, generates release notes, and creates the GitHub Release only after all required assets exist.

## Failure recovery

- If a job fails before the Release is created, fix the cause or repository secret and rerun the failed workflow for the same immutable tag.
- Do not move or overwrite a published version tag. Publish corrections as a newer version.
- If a workflow created an incomplete Release, remove that incomplete Release without deleting the tag, then rerun the workflow.
- A public repository is required for anonymous appcast and update downloads. Built-in updates will not work while the canonical Release repository is private or absent.

## End-to-end update acceptance

After repository migration, publish and install one version, then publish a newer version. Verify manual and background checks, skip-version behavior, download cancellation, progress and extraction UI, signature validation, installation, relaunch, and the new displayed version on both Apple Silicon and Intel.
