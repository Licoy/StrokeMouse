#!/usr/bin/env bash
# Mark a self-signed Code Signing certificate as trusted so
# `security find-identity -v -p codesigning` lists it as valid and codesign
# does not hang waiting for SecurityAgent UI.
#
# Headless CI (GitHub Actions): use passwordless sudo + add-trusted-cert.
# Interactive Mac: prefer the same sudo path when available; else user-domain
# trust-settings-import with a hard timeout (never hang forever).
#
# Usage:
#   ./scripts/trust-codesign-cert.sh path/to/cert.crt
#   ./scripts/trust-codesign-cert.sh --from-p12 path/to.p12 --password PASS
#   ./scripts/trust-codesign-cert.sh --from-p12 path/to.p12 --password-file path
set -euo pipefail

CRT=""
P12=""
PASSWORD=""
PASSWORD_FILE=""
TRUST_TIMEOUT_SEC="${TRUST_TIMEOUT_SEC:-45}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/trust-codesign-cert.sh path/to/cert.crt
  ./scripts/trust-codesign-cert.sh --from-p12 path/to.p12 --password PASS
  ./scripts/trust-codesign-cert.sh --from-p12 path/to.p12 --password-file path

Environment:
  TRUST_TIMEOUT_SEC   Max seconds for interactive trust-settings-import (default 45)
  CI / GITHUB_ACTIONS Prefer sudo add-trusted-cert (non-interactive)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-p12)
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
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      CRT="$1"
      shift
      ;;
  esac
done

TMP_CRT=""
cleanup() {
  [[ -n "$TMP_CRT" && -f "$TMP_CRT" ]] && rm -f "$TMP_CRT"
}
trap cleanup EXIT

if [[ -n "$P12" ]]; then
  [[ -f "$P12" ]] || { echo "p12 not found: $P12" >&2; exit 1; }
  if [[ -z "$PASSWORD" && -n "$PASSWORD_FILE" ]]; then
    PASSWORD="$(head -n 1 "$PASSWORD_FILE" | tr -d '\r')"
  fi
  [[ -n "$PASSWORD" ]] || {
    echo "PKCS#12 password required with --from-p12" >&2
    exit 1
  }
  TMP_CRT="$(mktemp -t strokemouse-trust.XXXXXX.crt)"
  openssl pkcs12 -in "$P12" -clcerts -nokeys -passin "pass:$PASSWORD" -out "$TMP_CRT" 2>/dev/null \
    || openssl pkcs12 -in "$P12" -clcerts -nokeys -passin "pass:$PASSWORD" -out "$TMP_CRT" -legacy
  CRT="$TMP_CRT"
fi

[[ -n "$CRT" && -f "$CRT" ]] || {
  usage >&2
  exit 1
}

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required" >&2
  exit 1
}

# Run a command with a hard timeout (macOS may lack GNU timeout).
run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
    return $?
  fi
  # Portable watchdog: background + kill.
  "$@" &
  local pid=$!
  (
    sleep "$seconds"
    if kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: command exceeded ${seconds}s; killing pid $pid (likely waiting for SecurityAgent UI)" >&2
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
    fi
  ) &
  local watchdog=$!
  local status=0
  wait "$pid" || status=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$status"
}

is_ci_like() {
  # Only real CI env vars — do NOT treat "no TTY" as CI (local scripts often have no TTY).
  [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]
}

can_sudo_nopasswd() {
  command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null
}

trust_via_sudo_add_trusted() {
  echo "==> Trusting cert via sudo security add-trusted-cert (codeSign, non-interactive)"
  # trustAsRoot + codeSign: marks Always Trust for Code Signing without GUI.
  # GHA macOS runners have passwordless sudo.
  run_with_timeout "$TRUST_TIMEOUT_SEC" sudo -n security add-trusted-cert \
    -d \
    -r trustAsRoot \
    -p codeSign \
    "$CRT"
}

trust_via_settings_import() {
  command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required for trust-settings-import fallback" >&2
    exit 1
  }

  export STROKEMOUSE_TRUST_CRT="$CRT"
  local trust_plist
  trust_plist="$(mktemp -t strokemouse-trust.XXXXXX.plist)"
  export STROKEMOUSE_TRUST_PLIST="$trust_plist"

  python3 <<'PY'
import binascii
import os
import plistlib
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

crt = Path(os.environ["STROKEMOUSE_TRUST_CRT"])
out = Path(os.environ["STROKEMOUSE_TRUST_PLIST"])
der = subprocess.check_output(["openssl", "x509", "-in", str(crt), "-outform", "DER"])


def read_len(data: bytes, i: int):
    first = data[i]
    i += 1
    if first < 0x80:
        return first, i
    n = first & 0x7F
    val = int.from_bytes(data[i : i + n], "big")
    return val, i + n


def take_tlv(data: bytes, i: int):
    tag = data[i]
    length, j = read_len(data, i + 1)
    value = data[j : j + length]
    return tag, value, j + length


def encode_len(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    b = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(b)]) + b


tag, cert_seq, _ = take_tlv(der, 0)
assert tag == 0x30
tag, tbs, _ = take_tlv(cert_seq, 0)
assert tag == 0x30
pos = 0
if tbs[pos] == 0xA0:
    _, _, pos = take_tlv(tbs, pos)
tag, serial, pos = take_tlv(tbs, pos)
assert tag == 0x02
_, _, pos = take_tlv(tbs, pos)
tag, issuer, pos = take_tlv(tbs, pos)
assert tag == 0x30
issuer_name = bytes([0x30]) + encode_len(len(issuer)) + issuer

fp = (
    subprocess.check_output(
        ["openssl", "x509", "-in", str(crt), "-noout", "-fingerprint", "-sha1"],
        text=True,
    )
    .strip()
    .split("=")[1]
    .replace(":", "")
    .upper()
)

# Code Signing policy OID: 1.2.840.113635.100.1.16
code_signing_policy = binascii.unhexlify("2a864886f763640110")

data: dict = {"trustVersion": 1, "trustList": {}}
export_path = Path(tempfile.mkstemp(suffix=".plist")[1])
try:
    result = subprocess.run(
        ["security", "trust-settings-export", str(export_path)],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0 and export_path.stat().st_size > 0:
        existing = plistlib.loads(export_path.read_bytes())
        if isinstance(existing, dict) and "trustList" in existing:
            data = existing
            for entry in data.get("trustList", {}).values():
                for setting in entry.get("trustSettings", []):
                    if setting.get("kSecTrustSettingsPolicyName") == "CodeSigning":
                        code_signing_policy = setting["kSecTrustSettingsPolicy"]
                        break
finally:
    export_path.unlink(missing_ok=True)

data.setdefault("trustList", {})
data["trustList"][fp] = {
    "issuerName": issuer_name,
    "modDate": datetime.now(timezone.utc),
    "serialNumber": serial,
    "trustSettings": [
        {
            "kSecTrustSettingsAllowedError": -2147409654,
            "kSecTrustSettingsPolicy": code_signing_policy,
            "kSecTrustSettingsPolicyName": "CodeSigning",
            "kSecTrustSettingsResult": 1,
        }
    ],
}
out.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
print(f"Prepared trust settings for {fp}")
PY

  echo "==> Importing user Code Signing trust (timeout ${TRUST_TIMEOUT_SEC}s)"
  # WARNING: without sudo this can wait forever for SecurityAgent on headless hosts.
  if ! run_with_timeout "$TRUST_TIMEOUT_SEC" security trust-settings-import "$trust_plist"; then
    rm -f "$trust_plist"
    echo "ERROR: trust-settings-import failed or timed out." >&2
    echo "  On CI use passwordless sudo (add-trusted-cert path)." >&2
    echo "  Locally: open Keychain Access → certificate → Trust → Code Signing = Always Trust." >&2
    exit 1
  fi
  rm -f "$trust_plist"
}

# Prefer non-interactive sudo path on CI / when available.
if can_sudo_nopasswd; then
  if ! trust_via_sudo_add_trusted; then
    echo "WARNING: sudo add-trusted-cert failed; trying trust-settings-import fallback" >&2
    if is_ci_like; then
      echo "ERROR: cannot set Code Signing trust non-interactively on CI" >&2
      exit 1
    fi
    trust_via_settings_import
  fi
elif is_ci_like; then
  echo "ERROR: headless/CI environment but passwordless sudo is unavailable." >&2
  echo "  Cannot call security trust-settings-import without hanging on SecurityAgent." >&2
  exit 1
else
  # Interactive local Mac without passwordless sudo.
  trust_via_settings_import
fi

echo "==> Code signing identities after trust:"
security find-identity -v -p codesigning 2>&1 | head -20
