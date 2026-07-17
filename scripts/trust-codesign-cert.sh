#!/usr/bin/env bash
# Mark a self-signed Code Signing certificate as trusted so
# `security find-identity -v -p codesigning` lists it as valid and codesign
# does not hang waiting for SecurityAgent UI.
#
# CI (GitHub Actions): prefer admin-domain trust-settings-import via passwordless
# sudo. `add-trusted-cert -r trustAsRoot` fails for CA:FALSE leaf certs with
# SecTrustSettingsSetTrustSettings "parameters not valid".
#
# Usage:
#   ./scripts/trust-codesign-cert.sh path/to/cert.crt
#   ./scripts/trust-codesign-cert.sh --from-p12 path/to.p12 --password PASS
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
  TRUST_TIMEOUT_SEC   Max seconds per trust attempt (default 45)
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
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required" >&2
  exit 1
}

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
  "$@" &
  local pid=$!
  (
    sleep "$seconds"
    if kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: command exceeded ${seconds}s; killing pid $pid (likely SecurityAgent UI)" >&2
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
  [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]
}

can_sudo_nopasswd() {
  command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null
}

# Build a trust-settings plist that marks this cert trusted for Code Signing only.
# Works for CA:FALSE leaf self-signed certs (unlike add-trusted-cert -r trustRoot).
build_trust_plist() {
  local out_plist="$1"
  export STROKEMOUSE_TRUST_CRT="$CRT"
  export STROKEMOUSE_TRUST_PLIST="$out_plist"
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
    # Prefer merging admin export when available (CI after partial trust), else user.
    for args in (
        ["security", "trust-settings-export", "-d", str(export_path)],
        ["security", "trust-settings-export", str(export_path)],
    ):
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode == 0 and export_path.stat().st_size > 0:
            try:
                existing = plistlib.loads(export_path.read_bytes())
            except Exception:
                continue
            if isinstance(existing, dict) and "trustList" in existing:
                data = existing
                for entry in data.get("trustList", {}).values():
                    for setting in entry.get("trustSettings", []):
                        if setting.get("kSecTrustSettingsPolicyName") == "CodeSigning":
                            code_signing_policy = setting["kSecTrustSettingsPolicy"]
                            break
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
            # CSSMERR_TP_CERT_EXPIRED
            "kSecTrustSettingsAllowedError": -2147409654,
            "kSecTrustSettingsPolicy": code_signing_policy,
            "kSecTrustSettingsPolicyName": "CodeSigning",
            # kSecTrustSettingsResultTrustRoot
            "kSecTrustSettingsResult": 1,
        }
    ],
}
out.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
print(f"Prepared trust settings for {fp}")
PY
}

identity_is_valid() {
  # Match SHA-1 fingerprint or common name if present in valid identities list.
  local fp
  fp="$(
    openssl x509 -in "$CRT" -noout -fingerprint -sha1 \
      | awk -F= '{print $2}' | tr -d ':' | tr '[:lower:]' '[:upper:]'
  )"
  local list
  list="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  echo "$list" | grep -Fq "$fp" && return 0
  # Fallback: CN match on a "valid identities" block line.
  local cn
  cn="$(openssl x509 -in "$CRT" -noout -subject | sed -n 's/.*CN=\([^/,]*\).*/\1/p')"
  [[ -n "$cn" ]] && echo "$list" | grep -F "\"$cn\"" | grep -vq CSSMERR && return 0
  return 1
}

try_admin_trust_settings_import() {
  local plist="$1"
  echo "==> [trust] sudo security trust-settings-import -d (admin domain, Code Signing policy)"
  # Capture stderr so CI logs show the real Security framework error.
  local err
  err="$(mktemp -t strokemouse-trust-err.XXXXXX)"
  if run_with_timeout "$TRUST_TIMEOUT_SEC" sudo -n security trust-settings-import -d "$plist" 2>"$err"; then
    rm -f "$err"
    echo "    admin trust-settings-import: OK"
    return 0
  fi
  echo "    admin trust-settings-import failed:" >&2
  sed 's/^/      /' "$err" >&2 || true
  rm -f "$err"
  return 1
}

try_user_trust_settings_import() {
  local plist="$1"
  echo "==> [trust] security trust-settings-import (user domain, timeout ${TRUST_TIMEOUT_SEC}s)"
  run_with_timeout "$TRUST_TIMEOUT_SEC" security trust-settings-import "$plist"
}

try_add_trusted_cert_variants() {
  # Only meaningful for CA:TRUE roots; kept as best-effort fallback.
  local system_kc="/Library/Keychains/System.keychain"
  echo "==> [trust] fallback: sudo add-trusted-cert variants"
  # Import public cert into system keychain (ignore duplicate errors).
  sudo -n security import "$CRT" -k "$system_kc" -T /usr/bin/codesign -T /usr/bin/security 2>/dev/null || true

  local args_list=(
    "-d -r trustRoot -p codeSign -k $system_kc"
    "-d -r trustAsRoot -p codeSign -k $system_kc"
    "-d -r trustRoot -k $system_kc"
    "-d -r unrestricted -k $system_kc"
  )
  local args
  for args in "${args_list[@]}"; do
    echo "    trying: security add-trusted-cert $args"
    # shellcheck disable=SC2086
    if run_with_timeout "$TRUST_TIMEOUT_SEC" sudo -n security add-trusted-cert $args "$CRT" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

TRUST_PLIST="$(mktemp -t strokemouse-trust.XXXXXX.plist)"
cleanup_plist() {
  cleanup
  rm -f "$TRUST_PLIST"
}
trap cleanup_plist EXIT

build_trust_plist "$TRUST_PLIST"

trusted=0

if can_sudo_nopasswd; then
  if try_admin_trust_settings_import "$TRUST_PLIST"; then
    trusted=1
  else
    echo "WARNING: admin trust-settings-import failed" >&2
  fi
  if [[ "$trusted" -eq 0 ]]; then
    if try_add_trusted_cert_variants; then
      trusted=1
    else
      echo "WARNING: add-trusted-cert variants failed (expected for CA:FALSE leaves)" >&2
    fi
  fi
fi

if [[ "$trusted" -eq 0 ]]; then
  if is_ci_like; then
    echo "ERROR: could not establish Code Signing trust non-interactively on CI." >&2
    echo "  Tried: sudo trust-settings-import -d, sudo add-trusted-cert variants." >&2
    openssl x509 -in "$CRT" -noout -subject -ext basicConstraints,extendedKeyUsage 2>&1 | sed 's/^/  /' >&2 || true
    exit 1
  fi
  # Interactive local: user-domain import (may show a keychain dialog once).
  if try_user_trust_settings_import "$TRUST_PLIST"; then
    trusted=1
  else
    echo "ERROR: trust-settings-import failed or timed out." >&2
    echo "  Locally: Keychain Access → certificate → Trust → Code Signing = Always Trust." >&2
    exit 1
  fi
fi

# securityd sometimes needs a moment; re-check validity.
sleep 1
echo "==> Code signing identities after trust:"
security find-identity -v -p codesigning 2>&1 | head -30

if identity_is_valid; then
  echo "==> Trust OK (identity is valid for codesigning)"
  exit 0
fi

# Soft success if we imported settings but find-identity lags — package step will hard-fail.
if is_ci_like; then
  echo "ERROR: trust commands returned success but identity still not valid for codesigning" >&2
  security find-identity -p codesigning 2>&1 | head -40 >&2 || true
  exit 1
fi

echo "WARNING: could not confirm valid identity; continuing (local)" >&2
exit 0
