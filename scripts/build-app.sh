#!/bin/bash
# Builds "Sticky Things.app" into ./build (release, ad-hoc signed).
#   scripts/build-app.sh            # build for this Mac
#   scripts/build-app.sh --universal  # Apple Silicon + Intel
#   scripts/build-app.sh --install    # also copy to /Applications and launch it
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Sticky Things"
APP="build/${APP_NAME}.app"
UNIVERSAL=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install) INSTALL=1 ;;
  esac
done

if [[ ! -f apps/macos/Resources/AppIcon.icns ]]; then
  echo "› Drawing app icon"
  swift scripts/make-icon.swift apps/macos/Resources/AppIcon.icns
fi

echo "› Compiling (release)"
if [[ $UNIVERSAL == 1 ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/StickyThings"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/StickyThings"
fi

echo "› Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StickyThings"
cp apps/macos/Resources/Info.plist "$APP/Contents/Info.plist"
cp apps/macos/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "› Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"

echo "✓ Built ${APP}"

if [[ $INSTALL == 1 ]]; then
  DEST="/Applications/${APP_NAME}.app"
  echo "› Installing to ${DEST}"
  pkill -x StickyThings 2>/dev/null || true
  sleep 0.5
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "✓ Installed and launched. Look in the bottom-right corner of your screen."
fi
