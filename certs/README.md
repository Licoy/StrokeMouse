# Release code signing material (local only)

Releases are signed with the **Developer ID Application** certificate and notarized by Apple. Accessibility (TCC) grants pin to the Team ID, so they survive Sparkle updates and certificate renewals. See `RELEASING.md` for creating the certificate.

Keep exported material here; everything except this README is gitignored.

| File | Purpose |
|------|---------|
| `DeveloperID.p12` | Developer ID certificate + private key (CI secret source) |
| `DeveloperID.p12.b64` | Base64 of the p12 for `CODE_SIGN_P12_BASE64` |
| `AuthKey_XXXXXX.p8` | App Store Connect API key for notarization (downloadable once) |

**Do not commit** these files.

## GitHub Actions secrets

| Secret | Value |
|--------|--------|
| `CODE_SIGN_P12_BASE64` | `base64 -i DeveloperID.p12` |
| `CODE_SIGN_P12_PASSWORD` | password set when exporting the p12 |
| `NOTARY_KEY_P8_BASE64` | `base64 -i AuthKey_XXXXXX.p8` |
| `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID` | from App Store Connect → Users and Access → Integrations |
| `SPARKLE_PUBLIC_KEY` / `SPARKLE_PRIVATE_KEY` | existing Sparkle Ed25519 keys (never rotate together with the signing identity) |

`CODE_SIGN_IDENTITY` defaults to `Developer ID Application` in packaging scripts.

## Legacy self-signed identity

`strokemouse-release.*` (from `./scripts/generate-codesign-cert.sh`) signed releases up to 0.0.39. Keep it only as a fallback; signing with it again would make users re-grant Accessibility.

## End users

Users **never** install any certificate. They only authorize Accessibility for the app as usual.
