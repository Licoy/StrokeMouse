#!/usr/bin/env bash
# Mark a self-signed Code Signing certificate as trusted for the Code Signing
# policy (user trust domain). Required so `security find-identity -v -p codesigning`
# lists the identity as valid and `codesign -s "..."` works without GUI prompts.
#
# Usage:
#   ./scripts/trust-codesign-cert.sh path/to/cert.crt
#   ./scripts/trust-codesign-cert.sh --from-p12 path/to/cert.p12 --password-file path
set -euo pipefail

CRT=""
P12=""
PASSWORD=""
PASSWORD_FILE=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/trust-codesign-cert.sh path/to/cert.crt
  ./scripts/trust-codesign-cert.sh --from-p12 path/to.p12 --password PASS
  ./scripts/trust-codesign-cert.sh --from-p12 path/to.p12 --password-file path
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

export STROKEMOUSE_TRUST_CRT="$CRT"
TRUST_PLIST="$(mktemp -t strokemouse-trust.XXXXXX.plist)"
export STROKEMOUSE_TRUST_PLIST="$TRUST_PLIST"
cleanup_plist() {
  cleanup
  rm -f "$TRUST_PLIST"
}
trap cleanup_plist EXIT

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
_, _, pos = take_tlv(tbs, pos)  # signature algorithm
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

# Code Signing policy OID as exported by macOS trust-settings-export:
# 1.2.840.113635.100.1.16  →  2a 86 48 86 f7 63 64 01 10
code_signing_policy = binascii.unhexlify("2a864886f763640110")

# Merge with existing user trust settings when present.
data = {"trustVersion": 1, "trustList": {}}
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
            # Prefer the policy blob from an existing Code Signing entry when available.
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
            # CSSMERR_TP_CERT_EXPIRED — allow continued use after notAfter (optional).
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

echo "==> Importing user Code Signing trust for $(basename "$CRT")"
security trust-settings-import "$TRUST_PLIST"
security find-identity -v -p codesigning 2>&1 | head -20
