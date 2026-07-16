#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-$(uname -m)}"
EXPECTED_MACOS_SDK_MAJOR="${EXPECTED_MACOS_SDK_MAJOR:-26}"
if [[ "${1:-}" == "--arch" ]]; then
  ARCH="${2:-}"
  [[ $# -eq 2 ]] || {
    echo "Usage: $0 [--arch arm64|x86_64]" >&2
    exit 2
  }
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--arch arm64|x86_64]" >&2
  exit 2
fi

case "$ARCH" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 2
    ;;
esac

PLACEHOLDER_KEY="__REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY__"
PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
DERIVED="$ROOT/build/release-$ARCH"
SOURCE_PACKAGES="$ROOT/build/SourcePackages"
DIST="$ROOT/dist"
APP_DIR="$DIST/$ARCH"
APP="$APP_DIR/StrokeMouse.app"
ZIP="$DIST/StrokeMouse-macos-$ARCH.zip"
TAR_GZ="$DIST/StrokeMouse-macos-$ARCH.app.tar.gz"
DMG="$DIST/StrokeMouse-macos-$ARCH.dmg"
DMG_ROOT="$DIST/dmg-$ARCH"
ENTITLEMENTS="$ROOT/StrokeMouse/Supporting/StrokeMouse.entitlements"
ENTITLEMENTS_DUMP=""
ARCHIVE_LIST=""
DMG_MOUNT=""

cleanup() {
  if [[ -n "$ENTITLEMENTS_DUMP" ]]; then
    rm -f "$ENTITLEMENTS_DUMP"
  fi
  if [[ -n "$ARCHIVE_LIST" ]]; then
    rm -f "$ARCHIVE_LIST"
  fi
  if [[ -n "$DMG_MOUNT" && -d "$DMG_MOUNT" ]]; then
    if ! hdiutil detach "$DMG_MOUNT" >/dev/null; then
      echo "Warning: unable to detach temporary DMG mount: $DMG_MOUNT" >&2
    fi
    if ! rmdir "$DMG_MOUNT"; then
      echo "Warning: unable to remove temporary DMG mount: $DMG_MOUNT" >&2
    fi
  fi
}
trap cleanup EXIT

for command in base64 xcodebuild xcodegen codesign hdiutil lipo otool plutil ditto; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

if [[ -z "$PUBLIC_KEY" || "$PUBLIC_KEY" == "$PLACEHOLDER_KEY" ]]; then
  echo "SPARKLE_PUBLIC_KEY is required for release packaging." >&2
  exit 1
fi
if ! PUBLIC_KEY_BYTES="$(printf '%s' "$PUBLIC_KEY" | base64 -D | wc -c | tr -d ' ')"; then
  echo "SPARKLE_PUBLIC_KEY must be a valid Base64-encoded Ed25519 public key." >&2
  exit 1
fi
[[ "$PUBLIC_KEY_BYTES" == "32" ]] || {
  echo "SPARKLE_PUBLIC_KEY must decode to 32 bytes, got: $PUBLIC_KEY_BYTES" >&2
  exit 1
}

cd "$ROOT"
./scripts/generate_project.sh

rm -rf "$DERIVED" "$APP_DIR" "$DMG_ROOT"
rm -f "$ZIP" "$TAR_GZ" "$DMG"
mkdir -p "$DERIVED" "$SOURCE_PACKAGES" "$APP_DIR" "$DIST"

echo "==> Building StrokeMouse Release ($ARCH)"
xcodebuild \
  -project "$ROOT/StrokeMouse.xcodeproj" \
  -scheme StrokeMouse \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  -destination "generic/platform=macOS" \
  ARCHS="$ARCH" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  SPARKLE_PUBLIC_KEY="$PUBLIC_KEY" \
  build

BUILT_APP="$DERIVED/Build/Products/Release/StrokeMouse.app"
[[ -d "$BUILT_APP" ]] || {
  echo "Release product not found: $BUILT_APP" >&2
  exit 1
}

ditto "$BUILT_APP" "$APP"

# Xcode's local ad-hoc signature injects get-task-allow. Re-sign the final
# bundle from its production entitlement source after every bundle mutation.
codesign \
  --force \
  --deep \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign - \
  "$APP"
codesign --verify --deep --strict --verbose=4 "$APP"
codesign -dvv "$APP" 2>&1 | grep -Eq 'flags=.*\(.*runtime.*\)'

EXECUTABLE="$APP/Contents/MacOS/StrokeMouse"
ACTUAL_ARCHS="$(lipo -archs "$EXECUTABLE")"
[[ "$ACTUAL_ARCHS" == "$ARCH" ]] || {
  echo "Expected executable architecture $ARCH, got: $ACTUAL_ARCHS" >&2
  exit 1
}

SDK_VERSION="$(otool -l "$EXECUTABLE" | awk '$1 == "sdk" { print $2; exit }')"
case "$SDK_VERSION" in
  "${EXPECTED_MACOS_SDK_MAJOR}".*) ;;
  *)
    echo "Expected macOS SDK ${EXPECTED_MACOS_SDK_MAJOR}.x, got ${SDK_VERSION:-unknown}" >&2
    exit 1
    ;;
esac

INFO_PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
MINIMUM_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"
EMBEDDED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")"
SOURCE_VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$ROOT/project.yml")"
SOURCE_BUILD="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$ROOT/project.yml")"

[[ "$MINIMUM_SYSTEM" == "14.0" ]] || {
  echo "Expected minimum system version 14.0, got: $MINIMUM_SYSTEM" >&2
  exit 1
}
[[ "$EMBEDDED_KEY" == "$PUBLIC_KEY" ]] || {
  echo "Sparkle public key was not embedded into the application." >&2
  exit 1
}
[[ "$VERSION" == "$SOURCE_VERSION" && "$BUILD" == "$SOURCE_BUILD" ]] || {
  echo "Built version $VERSION ($BUILD) does not match project.yml $SOURCE_VERSION ($SOURCE_BUILD)." >&2
  exit 1
}
if [[ -n "${EXPECTED_VERSION:-}" && "$VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "Expected app version $EXPECTED_VERSION, got: $VERSION" >&2
  exit 1
fi

ENTITLEMENTS_DUMP="$(mktemp)"
codesign -d --entitlements :- "$APP" >"$ENTITLEMENTS_DUMP" 2>/dev/null
plutil -lint "$ENTITLEMENTS_DUMP" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$ENTITLEMENTS_DUMP" | grep -qx true
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' "$ENTITLEMENTS_DUMP" | grep -qx true
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS_DUMP" >/dev/null 2>&1; then
  echo "Release entitlement unexpectedly contains get-task-allow." >&2
  exit 1
fi

echo "==> Packaging StrokeMouse $VERSION ($BUILD)"
(
  cd "$APP_DIR"
  ditto -c -k --keepParent "StrokeMouse.app" "$ZIP"
  COPYFILE_DISABLE=1 tar -czf "$TAR_GZ" "StrokeMouse.app"
)

mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/StrokeMouse.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "StrokeMouse" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

unzip -tq "$ZIP"
tar -tzf "$TAR_GZ" >/dev/null
hdiutil verify "$DMG" >/dev/null
ARCHIVE_LIST="$(mktemp)"
unzip -Z1 "$ZIP" >"$ARCHIVE_LIST"
grep -Fqx 'StrokeMouse.app/Contents/MacOS/StrokeMouse' "$ARCHIVE_LIST"
tar -tzf "$TAR_GZ" >"$ARCHIVE_LIST"
grep -Fqx 'StrokeMouse.app/Contents/MacOS/StrokeMouse' "$ARCHIVE_LIST"

DMG_MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$DMG_MOUNT" >/dev/null
[[ -x "$DMG_MOUNT/StrokeMouse.app/Contents/MacOS/StrokeMouse" ]]
codesign --verify --deep --strict "$DMG_MOUNT/StrokeMouse.app"
hdiutil detach "$DMG_MOUNT" >/dev/null
rmdir "$DMG_MOUNT"
DMG_MOUNT=""

printf 'Built and verified:\n%s\n%s\n%s\n' "$ZIP" "$TAR_GZ" "$DMG"
