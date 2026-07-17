#!/usr/bin/env bash
# Generate a long-lived self-signed Code Signing certificate for StrokeMouse releases.
#
# Usage:
#   ./scripts/generate-codesign-cert.sh
#   ./scripts/generate-codesign-cert.sh --name "StrokeMouse Release" --out certs
#   ./scripts/generate-codesign-cert.sh --import   # also import into login keychain
#
# Outputs (gitignored *.p12; keep private key offline / in CI secrets only):
#   <out>/<slug>.p12
#   <out>/<slug>.crt          (public cert only — safe to keep locally)
#   <out>/<slug>.password     (random export password; treat as secret)
#   <out>/<slug>.p12.b64      (base64 of p12 for GitHub Actions CODE_SIGN_P12_BASE64)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT_NAME="StrokeMouse Release"
OUT_DIR="$ROOT/certs"
DAYS=3650
DO_IMPORT=0

usage() {
  cat <<'EOF'
Usage: ./scripts/generate-codesign-cert.sh [options]

Options:
  --name NAME     Certificate common name (default: StrokeMouse Release)
  --out DIR       Output directory (default: ./certs)
  --days N        Validity in days (default: 3650 ≈ 10 years)
  --import        Import the .p12 into the login keychain for local codesign
  -h, --help      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      CERT_NAME="${2:-}"
      [[ -n "$CERT_NAME" ]] || { echo "--name requires a value" >&2; exit 2; }
      shift 2
      ;;
    --out)
      OUT_DIR="${2:-}"
      [[ -n "$OUT_DIR" ]] || { echo "--out requires a value" >&2; exit 2; }
      shift 2
      ;;
    --days)
      DAYS="${2:-}"
      [[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "--days must be an integer" >&2; exit 2; }
      shift 2
      ;;
    --import)
      DO_IMPORT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required" >&2
  exit 1
}

# Stable slug for filenames
SLUG="$(printf '%s' "$CERT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')"
[[ -n "$SLUG" ]] || SLUG="strokemouse-release"

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

KEY="$OUT_DIR/$SLUG.key"
CRT="$OUT_DIR/$SLUG.crt"
P12="$OUT_DIR/$SLUG.p12"
CNF="$OUT_DIR/$SLUG.openssl.cnf"
PASS_FILE="$OUT_DIR/$SLUG.password"
B64_FILE="$OUT_DIR/$SLUG.p12.b64"

if [[ -f "$P12" || -f "$KEY" ]]; then
  echo "Refusing to overwrite existing cert material in $OUT_DIR" >&2
  echo "  Remove $SLUG.* first if you intentionally want a new identity." >&2
  echo "  WARNING: rotating the release cert forces all users to re-grant Accessibility." >&2
  exit 1
fi

PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"
[[ ${#PASSWORD} -ge 16 ]] || {
  echo "Failed to generate a strong export password" >&2
  exit 1
}

# Self-signed root + codeSigning EKU.
# CA:TRUE lets `sudo security add-trusted-cert -r trustRoot` work on CI;
# CA:FALSE leaves fail with SecTrustSettingsSetTrustSettings "parameters not valid".
cat >"$CNF" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_codesign
prompt = no

[req_distinguished_name]
CN = $CERT_NAME
O = StrokeMouse
C = US

[v3_codesign]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

echo "==> Generating self-signed Code Signing certificate: $CERT_NAME"
openssl req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$KEY" \
  -x509 \
  -days "$DAYS" \
  -out "$CRT" \
  -config "$CNF"

# Prefer modern PKCS#12; fall back if needed for security(1) import.
if ! openssl pkcs12 -export \
  -out "$P12" \
  -inkey "$KEY" \
  -in "$CRT" \
  -name "$CERT_NAME" \
  -passout "pass:$PASSWORD" 2>/dev/null; then
  openssl pkcs12 -export \
    -out "$P12" \
    -inkey "$KEY" \
    -in "$CRT" \
    -name "$CERT_NAME" \
    -passout "pass:$PASSWORD" \
    -legacy
fi

umask 077
printf '%s\n' "$PASSWORD" >"$PASS_FILE"
base64 <"$P12" | tr -d '\n' >"$B64_FILE"
printf '\n' >>"$B64_FILE"

# Private key only needed to re-export; keep it local and restrictive.
chmod 600 "$KEY" "$P12" "$PASS_FILE" "$B64_FILE"
chmod 644 "$CRT"

rm -f "$CNF"

if [[ "$DO_IMPORT" -eq 1 ]]; then
  echo "==> Importing into login keychain"
  "$ROOT/scripts/import-codesign-p12.sh" --p12 "$P12" --password-file "$PASS_FILE"
fi

echo
echo "Created:"
echo "  Public cert:  $CRT"
echo "  PKCS#12:      $P12"
echo "  Password:     $PASS_FILE"
echo "  Base64 p12:   $B64_FILE"
echo
echo "GitHub Actions secrets (do not commit these files):"
echo "  CODE_SIGN_IDENTITY=$CERT_NAME"
echo "  CODE_SIGN_P12_PASSWORD=<contents of $PASS_FILE>"
echo "  CODE_SIGN_P12_BASE64=<contents of $B64_FILE>"
echo
echo "Local package example:"
echo "  CODE_SIGN_IDENTITY=\"$CERT_NAME\" SPARKLE_PUBLIC_KEY=... ARCH=arm64 ./scripts/package-app.sh"
echo
echo "Users never install this certificate. Only build/CI machines need the private key."
echo "Keep the same identity for all future releases so Accessibility grants stick across Sparkle updates."
