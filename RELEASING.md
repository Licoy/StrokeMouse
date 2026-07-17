# Releasing StrokeMouse

## Prerequisites

1. **Sparkle Ed25519 keys** in GitHub Actions secrets:
   - `SPARKLE_PUBLIC_KEY`
   - `SPARKLE_PRIVATE_KEY`
2. **Stable release code signing** (self-signed; not Apple Developer ID):
   - `CODE_SIGN_P12_BASE64` — base64 of the PKCS#12
   - `CODE_SIGN_P12_PASSWORD` — PKCS#12 password  
   Identity name defaults to **`StrokeMouse Release`**.

### Create / import the release certificate (once)

```bash
# Generate + import into login keychain + Code Signing trust
./scripts/generate-codesign-cert.sh --import

# Material lands in ./certs/ (gitignored). Configure CI secrets from:
#   certs/strokemouse-release.p12.b64  → CODE_SIGN_P12_BASE64
#   certs/strokemouse-release.password → CODE_SIGN_P12_PASSWORD
```

Do **not** rotate this certificate casually: every user will need to re-grant Accessibility once after a rotation.

Users never install the certificate; only build machines and CI need the private key.

### CI trust (headless)

Import scripts mark the self-signed cert trusted for **Code Signing** via admin-domain trust settings:

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
Throwaway smoke only: `CODE_SIGN_IDENTITY=- ... ./scripts/package-app.sh` (Accessibility will not stick across updates).

## Tag release (CI)

1. Bump version: `./bump.sh -v X.Y.Z` (optionally `-p` to push)
2. Push tag `vX.Y.Z` → `.github/workflows/release.yml`
3. Workflow: test → package arm64 + x86_64 with **StrokeMouse Release** → appcast → GitHub Release assets

## Why not ad-hoc for releases?

Ad-hoc signatures pin Accessibility TCC to each binary **cdhash**. Sparkle updates change the hash → users must re-authorize every time.

A fixed self-signed identity pins TCC to the **certificate**, so grants survive updates signed with the same identity.

Still **not** notarized: first launch may need right-click Open / Open Anyway.
