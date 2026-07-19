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
#
# Requires bash features (arrays, process substitution). On macOS, `sh script`
# often runs bash *in POSIX mode* where BASH_VERSION is still set but
# process substitution is disabled — detect capability, not just $BASH_VERSION.
if ! eval ': <(:)' 2>/dev/null; then
  exec /usr/bin/env bash "$0" "$@"
fi
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

# Re-sign for the stable output path (keeps Accessibility TCC pinned).
# IMPORTANT: do NOT use `codesign --deep` with the host entitlements file.
# That stamps Sparkle XPC helpers / resource bundles with app entitlements and
# can make Apple System Policy SIGKILL the main binary on launch (exit 137,
# kernel log: "ASP: Security policy would not allow process").
# Sign inside-out: nested code first (no host entitlements), then the app.
sign_nested_code() {
  local app="$1"
  local identity="$2"
  local sign_opts=(--force --timestamp=none)
  if [[ "$identity" != "-" ]]; then
    sign_opts+=(--options runtime)
  fi

  # SPM resource bundles (e.g. PermissionFlow_*.bundle)
  local bundle
  while IFS= read -r bundle; do
    [[ -n "$bundle" ]] || continue
    codesign "${sign_opts[@]}" --sign "$identity" "$bundle"
  done < <(find "$app/Contents" -name '*.bundle' -type d 2>/dev/null)

  # Sparkle nested code (if present)
  local sparkle="$app/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$sparkle" ]]; then
    local xpc
    while IFS= read -r xpc; do
      [[ -n "$xpc" ]] || continue
      codesign "${sign_opts[@]}" --sign "$identity" "$xpc"
    done < <(find "$sparkle" -name '*.xpc' -type d 2>/dev/null)

    if [[ -d "$sparkle/Versions/B/Updater.app" ]]; then
      codesign "${sign_opts[@]}" --sign "$identity" "$sparkle/Versions/B/Updater.app"
    elif [[ -d "$sparkle/Versions/Current/Updater.app" ]]; then
      codesign "${sign_opts[@]}" --sign "$identity" "$sparkle/Versions/Current/Updater.app"
    fi

    if [[ -f "$sparkle/Versions/B/Autoupdate" ]]; then
      codesign "${sign_opts[@]}" --sign "$identity" "$sparkle/Versions/B/Autoupdate"
    elif [[ -f "$sparkle/Versions/Current/Autoupdate" ]]; then
      codesign "${sign_opts[@]}" --sign "$identity" "$sparkle/Versions/Current/Autoupdate"
    fi

    codesign "${sign_opts[@]}" --sign "$identity" "$sparkle"
  fi
}

echo "==> codesign (inside-out, no --deep entitlements)"
if [[ "$IDENTITY" == "-" ]]; then
  sign_nested_code "$OUTPUT_APP" "-"
  codesign --force --timestamp=none --sign - "$OUTPUT_APP"
else
  sign_nested_code "$OUTPUT_APP" "$IDENTITY"
  codesign --force --options runtime --timestamp=none \
    --sign "$IDENTITY" \
    --entitlements "$ROOT/StrokeMouse/Supporting/StrokeMouse.entitlements" \
    "$OUTPUT_APP"
fi

echo "==> codesign verify"
codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP" 2>&1 | tail -5
echo
echo "Built: $OUTPUT_APP"
echo "  open \"$OUTPUT_APP\""
echo "  or: ./scripts/build.sh --open"

if [[ "$OPEN_AFTER" -eq 1 ]]; then
  echo "==> Opening $OUTPUT_APP"
  # Path form (not `open -a`, which expects an app name).
  open "$OUTPUT_APP"
  # Confirm LaunchServices actually kept the process alive (ASP kills show as instant quit).
  sleep 0.8
  if pgrep -x StrokeMouse >/dev/null 2>&1; then
    echo "    StrokeMouse is running."
  else
    echo "WARNING: StrokeMouse did not stay running after open." >&2
    echo "  Check Console for: ASP: Security policy would not allow process" >&2
    echo "  Binary: $OUTPUT_APP/Contents/MacOS/StrokeMouse" >&2
    exit 1
  fi
fi
