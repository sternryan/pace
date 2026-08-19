#!/bin/bash
set -euo pipefail
APP_NAME="Pace"
BUILD_DIR=".build/release"
APP_BUNDLE=".build/${APP_NAME}.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Sources/Pace/Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Prefer the stable local identity; fall back to ad-hoc (with a warning —
# ad-hoc means a Keychain re-prompt after every rebuild).
IDENTITY="$(./Scripts/ensure-signing-cert.sh || true)"
if [ -n "$IDENTITY" ] && security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --deep --sign "$IDENTITY" "$APP_BUNDLE" \
    || { echo "warning: signing with '$IDENTITY' failed; falling back to ad-hoc" >&2; codesign --force --deep --sign - "$APP_BUNDLE"; }
else
  echo "warning: no stable signing identity; using ad-hoc (Keychain will re-prompt after rebuilds)" >&2
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "Built $APP_BUNDLE"
