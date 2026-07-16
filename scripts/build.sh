#!/usr/bin/env bash
# Build StrokeMouse and install a stable .app under ./output
# so Accessibility / code-sign TCC entries do not need re-grant every build.
#
# Usage:
#   ./scripts/build.sh              # Debug → output/StrokeMouse.app
#   ./scripts/build.sh --open       # build then open
#   ./scripts/build.sh --release    # Release configuration
#   ./scripts/build.sh --release --open
#   ./scripts/build.sh --no-generate
#   CONFIGURATION=Release ./scripts/build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-Debug}"
IDENTITY="${CODE_SIGN_IDENTITY:-StrokeMouse Dev}"
DERIVED="${DERIVED_DATA_PATH:-$ROOT/build}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/output}"
APP_NAME="StrokeMouse.app"
OPEN_AFTER=0
RUN_GENERATE=1

usage() {
  cat <<'EOF'
Usage: ./scripts/build.sh [options]

Options:
  --open           Open output/StrokeMouse.app after a successful build
  --release        Build Release (default: Debug)
  --debug          Build Debug
  --no-generate    Skip xcodegen (use existing .xcodeproj)
  -h, --help       Show this help

Environment:
  CONFIGURATION          Debug | Release (default: Debug)
  CODE_SIGN_IDENTITY     default: "StrokeMouse Dev"
  DERIVED_DATA_PATH      default: <repo>/build
  OUTPUT_DIR             default: <repo>/output
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open)
      OPEN_AFTER=1
      shift
      ;;
    --release)
      CONFIGURATION="Release"
      shift
      ;;
    --debug)
      CONFIGURATION="Debug"
      shift
      ;;
    --no-generate)
      RUN_GENERATE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$RUN_GENERATE" -eq 1 ]]; then
  if [[ ! -f "$ROOT/project.yml" ]]; then
    echo "project.yml not found at $ROOT" >&2
    exit 1
  fi
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
  fi
  echo "==> Generating Xcode project"
  xcodegen generate
fi

if [[ ! -d "$ROOT/StrokeMouse.xcodeproj" ]]; then
  echo "StrokeMouse.xcodeproj missing. Run without --no-generate first." >&2
  exit 1
fi

mkdir -p "$DERIVED" "$OUTPUT_DIR"
OUTPUT_APP="$OUTPUT_DIR/$APP_NAME"

# Quit a running instance that was launched from the stable output path,
# so we can replace the bundle without "app is in use" errors.
if [[ -d "$OUTPUT_APP" ]]; then
  pkill -f "$OUTPUT_APP/Contents/MacOS/StrokeMouse" 2>/dev/null || true
  # Brief wait for process exit / file locks
  sleep 0.3
fi

echo "==> Building StrokeMouse ($CONFIGURATION)"
echo "    identity: $IDENTITY"
echo "    derived:  $DERIVED"
echo "    output:   $OUTPUT_APP"

xcodebuild \
  -project "$ROOT/StrokeMouse.xcodeproj" \
  -scheme StrokeMouse \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS,arch=$(uname -m)" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  build

BUILT_APP="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
  # Fallback search (scheme layout variants)
  BUILT_APP="$(find "$DERIVED/Build/Products/$CONFIGURATION" -name "$APP_NAME" -type d -maxdepth 3 | head -n 1 || true)"
fi

if [[ -z "${BUILT_APP:-}" || ! -d "$BUILT_APP" ]]; then
  echo "Build product not found under $DERIVED/Build/Products/$CONFIGURATION" >&2
  exit 1
fi

echo "==> Installing to $OUTPUT_APP"
rm -rf "$OUTPUT_APP"
# ditto preserves resource forks / code signature better than cp -R
ditto "$BUILT_APP" "$OUTPUT_APP"

# Re-sign the installed bundle so the stable path has a consistent signature
# (helps keep Accessibility grants tied to this fixed location).
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$OUTPUT_APP"
else
  codesign --force --deep --options runtime --sign "$IDENTITY" \
    --entitlements "$ROOT/StrokeMouse/Supporting/StrokeMouse.entitlements" \
    "$OUTPUT_APP"
fi

echo "==> codesign verify"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP" 2>&1 | tail -5
echo
echo "Built: $OUTPUT_APP"
echo "  open -a \"$OUTPUT_APP\""
echo "  or: ./scripts/build.sh --open"

if [[ "$OPEN_AFTER" -eq 1 ]]; then
  echo "==> Opening $OUTPUT_APP"
  open "$OUTPUT_APP"
fi
