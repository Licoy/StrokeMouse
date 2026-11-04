# Releasing StrokeMouse

## Prerequisites

1. **Sparkle Ed25519 keys** in GitHub Actions secrets:
   - `SPARKLE_PUBLIC_KEY`
   - `SPARKLE_PRIVATE_KEY`
2. **Developer ID Application** code signing:
   - `CODE_SIGN_P12_BASE64` — base64 of the Developer ID PKCS#12 exported from Keychain Access (certificate + private key)
   - `CODE_SIGN_P12_PASSWORD` — password set when exporting the PKCS#12  
   Packaging resolves `CODE_SIGN_IDENTITY` (default **`Developer ID Application`**) to exactly one keychain identity; pass the full name or SHA-1 when several match.
3. **Notarization** (App Store Connect API key, Developer access):
   - `NOTARY_KEY_P8_BASE64` — base64 of `AuthKey_XXXXXX.p8`
   - `NOTARY_KEY_ID` — key ID
   - `NOTARY_ISSUER_ID` — issuer ID  
   Tag releases set `REQUIRE_NOTARIZATION=1` and fail without them. Manual CI packages notarize only when they are present.

### Create the Developer ID certificate (once)

1. Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority → Saved to disk.
2. developer.apple.com → Certificates → **Developer ID Application** (G2 Sub-CA) → upload the CSR → install the `.cer`.
3. `security find-identity -v -p codesigning` must list `Developer ID Application: … (TEAMID)`.
4. Export it from **My Certificates** as `.p12`, then `base64 -i DeveloperID.p12 | pbcopy` → `CODE_SIGN_P12_BASE64`.

`import-codesign-p12.sh` imports the Developer ID G2 intermediate when the runner lacks it. Users never install anything.

Keep the **Team ID** stable: Accessibility grants pin to it, so renewing the Developer ID certificate keeps them, but changing teams makes every user re-grant once.

### Migrating from the self-signed identity

Releases up to **0.0.39** were signed with the self-signed **`StrokeMouse Release`** identity. The first Developer ID release changes the designated requirement, so upgrading users must remove StrokeMouse from Accessibility and add it again once (release notes say so). Sparkle accepts the change because the EdDSA key stays the same — never rotate the Sparkle key in the same release as a code signing change.

The old self-signed material (`./scripts/generate-codesign-cert.sh`, `certs/strokemouse-release.*`) remains only as a fallback (`CODE_SIGN_IDENTITY="StrokeMouse Release"`, no notarization).

### CI trust for the legacy self-signed identity (headless)

Import scripts mark a self-signed cert trusted for **Code Signing** via admin-domain trust settings (skipped for Apple-issued certificates):

```bash
# Preferred (works for leaf and CA self-signed certs)
sudo security trust-settings-import -d trust.plist

# Fallback only for CA:TRUE roots
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain cert.crt
```

GitHub-hosted macOS runners provide passwordless `sudo`.  
**Do not** call user-domain `security trust-settings-import` on CI — it waits for SecurityAgent UI and hangs.  
`add-trusted-cert -r trustAsRoot` fails on **CA:FALSE** leaves (`SecTrustSettingsSetTrustSettings: parameters not valid`).

## Local package

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

Outputs under `dist/`: ZIP (Sparkle), TAR.GZ, DMG.  
To notarize locally, save credentials once with `xcrun notarytool store-credentials StrokeMouse-Notary --key AuthKey_XXXXXX.p8 --key-id ... --issuer ...` and add `NOTARY_KEYCHAIN_PROFILE=StrokeMouse-Notary`. The app is notarized and stapled before archiving, then the signed DMG is notarized and stapled.  
Throwaway smoke only: `CODE_SIGN_IDENTITY=- ... ./scripts/package-app.sh` (Accessibility will not stick across updates).

## Tag release (CI)

1. Bump version: `./bump.sh -v X.Y.Z` (optionally `-p` to push)
2. Push tag `vX.Y.Z` → `.github/workflows/release.yml`
3. Workflow: test → package arm64 + x86_64 with **Developer ID** + notarization → appcast → GitHub Release assets

## Why not ad-hoc for releases?

Ad-hoc signatures pin Accessibility TCC to each binary **cdhash**. Sparkle updates change the hash → users must re-authorize every time.

A Developer ID signature pins TCC to the **Team ID**, so grants survive updates and certificate renewals, and notarization lets downloads open without Gatekeeper overrides.

## Configuration compatibility

Gesture profiles with multiple drawn samples remain readable by older StrokeMouse versions because the primary path is unchanged. However, if an older version saves that profile, it does not know about `additionalPaths` and will discard the extra samples. Keep a backup and avoid editing or re-saving multi-sample profiles in older releases.
