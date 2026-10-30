#!/usr/bin/env bash
# Requires a logged-in macOS GUI session; briefly opens a temporary full-screen app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/strokemouse-hud-test.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT

xcrun swiftc -parse-as-library \
  "$ROOT/scripts/fixtures/FullscreenHUDProbe.swift" \
  "$ROOT/StrokeMouse/Core/GestureRecognition/GestureHUDController.swift" \
  "$ROOT/StrokeMouse/Core/GestureRecognition/DrawingStyle.swift" \
  "$ROOT/StrokeMouse/Supporting/Constants.swift" \
  -o "$PROBE_DIR/probe"

"$PROBE_DIR/probe" --desktop
"$PROBE_DIR/probe"
"$PROBE_DIR/probe" --accessory
