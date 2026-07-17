# Release code signing material (local only)

This directory holds the **StrokeMouse Release** self-signed Code Signing identity used so Accessibility (TCC) grants survive Sparkle updates.

| File | Purpose |
|------|---------|
| `strokemouse-release.p12` | Private key + cert (CI secret source) |
| `strokemouse-release.password` | PKCS#12 password |
| `strokemouse-release.p12.b64` | Base64 of the p12 for `CODE_SIGN_P12_BASE64` |
| `strokemouse-release.crt` | Public certificate only |
| `strokemouse-release.key` | PEM private key (re-export) |

**Do not commit** these files (gitignored). **Do not rotate** the certificate unless you accept that every user must re-grant Accessibility once.

## One-time setup

```bash
# If you do not already have material:
./scripts/generate-codesign-cert.sh --import

# Or import existing p12:
./scripts/import-codesign-p12.sh \
  --p12 certs/strokemouse-release.p12 \
  --password-file certs/strokemouse-release.password
```

## GitHub Actions secrets

| Secret | Value |
|--------|--------|
| `CODE_SIGN_P12_BASE64` | contents of `strokemouse-release.p12.b64` |
| `CODE_SIGN_P12_PASSWORD` | contents of `strokemouse-release.password` |
| `SPARKLE_PUBLIC_KEY` / `SPARKLE_PRIVATE_KEY` | existing Sparkle Ed25519 keys |

Optional: `CODE_SIGN_IDENTITY` defaults to `StrokeMouse Release` in packaging scripts.

## End users

Users **never** install this certificate. They only authorize Accessibility for the app as usual.
