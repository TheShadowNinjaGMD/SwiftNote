#!/bin/bash
# One-time setup for SwiftNote auto-updates (Sparkle).
# Creates your EdDSA signing key in the macOS Keychain and writes the PUBLIC key into Info.plist.
# Keep the private key safe: it lives in your login Keychain (export a backup with: .sparkle/bin/generate_keys -x key.txt).
set -euo pipefail
cd "$(dirname "$0")"

SPARKLE_VERSION="${SPARKLE_VERSION:-2.6.4}"
TOOLS=".sparkle"

if [ ! -x "$TOOLS/bin/generate_keys" ]; then
  echo "▶︎ Downloading Sparkle $SPARKLE_VERSION tools…"
  mkdir -p "$TOOLS"
  curl -fL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" | tar -xJ -C "$TOOLS"
fi

echo "▶︎ Creating (or reading) your signing key…"
OUTPUT="$("$TOOLS/bin/generate_keys" 2>&1 || true)"
PUBKEY="$(echo "$OUTPUT" | grep -Eo '[A-Za-z0-9+/]{42,}={0,2}' | head -n1 || true)"
if [ -z "$PUBKEY" ]; then
  PUBKEY="$("$TOOLS/bin/generate_keys" -p)"
fi
[ -n "$PUBKEY" ] || { echo "Couldn't read the public key. Output was:"; echo "$OUTPUT"; exit 1; }

/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBKEY" SwiftNote/Info.plist
echo "✅ SUPublicEDKey set to: $PUBKEY"
echo "Next: bump the version in Xcode, then run ./release.sh"
