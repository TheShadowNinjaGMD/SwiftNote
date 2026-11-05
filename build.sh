#!/bin/bash
# Builds SwiftNote.app and packages it as a styled DMG with create-dmg.
# Needs: Xcode, and create-dmg  ->  brew install create-dmg
set -euo pipefail
cd "$(dirname "$0")"

command -v create-dmg >/dev/null || { echo "create-dmg not found. Install it with: brew install create-dmg"; exit 1; }

OUT="$PWD/dist"; rm -rf "$OUT" build; mkdir -p "$OUT"

echo "▶︎ Building Release app…"
xcodebuild -project SwiftNote.xcodeproj -scheme SwiftNote -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES build | tail -n 5

APP="build/Build/Products/Release/SwiftNote.app"
[ -d "$APP" ] || { echo "Build failed: $APP missing"; exit 1; }

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"

echo "▶︎ Creating DMG…"
set +e
create-dmg \
  --volname "SwiftNote" \
  --volicon "dmg/VolumeIcon.icns" \
  --background "dmg/Background.tiff" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 110 \
  --icon "SwiftNote.app" 165 200 \
  --hide-extension "SwiftNote.app" \
  --app-drop-link 495 200 \
  --no-internet-enable \
  "$OUT/SwiftNote.dmg" \
  "$STAGE"
STATUS=$?
set -e
rm -rf "$STAGE"
# create-dmg exits 2 when it only skipped code-signing; the DMG is still fine.
if [ $STATUS -ne 0 ] && [ $STATUS -ne 2 ]; then echo "create-dmg failed ($STATUS)"; exit $STATUS; fi

echo "✅ Done: $OUT/SwiftNote.dmg"
