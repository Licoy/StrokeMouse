#!/usr/bin/env bash
# Import a Code Signing PKCS#12 into a keychain and allow codesign/security to use it
# without GUI prompts (needed for local packaging and GitHub Actions).
#
# Usage:
#   ./scripts/import-codesign-p12.sh --p12 path/to/cert.p12 --password-file path/to.password
#   ./scripts/import-codesign-p12.sh --p12 path/to/cert.p12 --password '...'
#   CODE_SIGN_P12_BASE64=... CODE_SIGN_P12_PASSWORD=... ./scripts/import-codesign-p12.sh --from-env
#
# Options:
#   --keychain PATH   Default: login keychain (local). CI often uses a temp keychain.
#   --create-keychain Create the keychain if missing (CI). Requires --keychain-password.
set -euo pipefail

P12=""
PASSWORD=""
PASSWORD_FILE=""
FROM_ENV=0
KEYCHAIN=""
KEYCHAIN_PASSWORD=""
CREATE_KEYCHAIN=0

usage() {
  cat <<'EOF'
Usage: ./scripts/import-codesign-p12.sh [options]

  --p12 PATH              Path to .p12
  --password PASS         PKCS#12 password
  --password-file PATH    Read password from file (first line)
  --from-env              Read CODE_SIGN_P12_BASE64 + CODE_SIGN_P12_PASSWORD
  --keychain PATH         Target keychain (default: login keychain)
  --keychain-password P   Password for --create-keychain / unlock
  --create-keychain       Create keychain if missing (CI)
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --p12)
      P12="${2:-}"
      shift 2
      ;;
    --password)
      PASSWORD="${2:-}"
      shift 2
      ;;
    --password-file)
      PASSWORD_FILE="${2:-}"
      shift 2
      ;;
    --from-env)
      FROM_ENV=1
      shift
      ;;
    --keychain)
      KEYCHAIN="${2:-}"
      shift 2
      ;;
    --keychain-password)
      KEYCHAIN_PASSWORD="${2:-}"
      shift 2
      ;;
    --create-keychain)
      CREATE_KEYCHAIN=1
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

TMP_P12=""
cleanup() {
  if [[ -n "$TMP_P12" && -f "$TMP_P12" ]]; then
    rm -f "$TMP_P12"
  fi
}
trap cleanup EXIT

echo "==> [1/6] Decode / resolve PKCS#12"
if [[ "$FROM_ENV" -eq 1 ]]; then
  [[ -n "${CODE_SIGN_P12_BASE64:-}" ]] || {
    echo "CODE_SIGN_P12_BASE64 is required with --from-env" >&2
    exit 1
  }
  [[ -n "${CODE_SIGN_P12_PASSWORD:-}" ]] || {
    echo "CODE_SIGN_P12_PASSWORD is required with --from-env" >&2
    exit 1
  }
  PASSWORD="$CODE_SIGN_P12_PASSWORD"
  TMP_P12="$(mktemp -t strokemouse-codesign.XXXXXX.p12)"
  # Accept base64 with or without newlines.
  printf '%s' "$CODE_SIGN_P12_BASE64" | tr -d '\n\r' | base64 -D >"$TMP_P12"
  P12="$TMP_P12"
  echo "    decoded p12 bytes: $(wc -c <"$P12" | tr -d ' ')"
fi

[[ -n "$P12" && -f "$P12" ]] || {
  echo "--p12 path is required (or use --from-env)" >&2
  exit 1
}

if [[ -z "$PASSWORD" && -n "$PASSWORD_FILE" ]]; then
  [[ -f "$PASSWORD_FILE" ]] || {
    echo "Password file not found: $PASSWORD_FILE" >&2
    exit 1
  }
  PASSWORD="$(head -n 1 "$PASSWORD_FILE" | tr -d '\r')"
fi

[[ -n "$PASSWORD" ]] || {
  echo "PKCS#12 password is required (--password, --password-file, or --from-env)" >&2
  exit 1
}

if [[ -z "$KEYCHAIN" ]]; then
  KEYCHAIN="$(security login-keychain | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"
fi

echo "==> [2/6] Prepare keychain: $KEYCHAIN"
if [[ "$CREATE_KEYCHAIN" -eq 1 ]]; then
  [[ -n "$KEYCHAIN_PASSWORD" ]] || {
    echo "--create-keychain requires --keychain-password" >&2
    exit 1
  }
  if [[ ! -f "$KEYCHAIN" ]]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  fi
  # -t lock timeout seconds; avoid auto-lock mid-build. -u is "lock when sleep" off via -lut.
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  # Prefer this keychain for codesign lookups.
  existing="$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')"
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$KEYCHAIN" $existing
  security default-keychain -s "$KEYCHAIN"
fi

if [[ -n "$KEYCHAIN_PASSWORD" && -f "$KEYCHAIN" ]]; then
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" 2>/dev/null || true
fi

echo "==> [3/6] Import PKCS#12 into keychain"
# -A / -T allows codesign without ACL GUI prompts on CI.
security import "$P12" \
  -k "$KEYCHAIN" \
  -P "$PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productbuild \
  -f pkcs12
echo "    import done"

echo "==> [4/6] set-key-partition-list (non-interactive private key use)"
if [[ -n "$KEYCHAIN_PASSWORD" ]]; then
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN" >/dev/null
else
  # Login keychain: may prompt if locked; best-effort.
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    "$KEYCHAIN" >/dev/null 2>&1 || true
fi
echo "    partition list done"

# Self-signed identities need an explicit Code Signing trust entry or
# find-identity reports CSSMERR_TP_NOT_TRUSTED (and codesign can hang on CI).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> [5/6] Trust certificate for Code Signing policy"
if [[ -x "$SCRIPT_DIR/trust-codesign-cert.sh" ]]; then
  "$SCRIPT_DIR/trust-codesign-cert.sh" --from-p12 "$P12" --password "$PASSWORD"
else
  echo "WARNING: trust-codesign-cert.sh missing; identity may be untrusted" >&2
fi

echo "==> [6/6] List valid code signing identities"
security find-identity -v -p codesigning "$KEYCHAIN" | head -20
if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q 'valid identities found'; then
  : # always prints a summary line
fi
# Fail early if nothing is valid (trust step failed silently).
if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q '0 valid identities found'; then
  echo "ERROR: no valid code signing identities after import/trust" >&2
  security find-identity -p codesigning "$KEYCHAIN" 2>&1 | head -30 >&2 || true
  exit 1
fi
echo "==> Code signing identity import complete"
