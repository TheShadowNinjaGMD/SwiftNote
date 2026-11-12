#!/bin/bash
# Build, sign and publish a SwiftNote release that Sparkle can update to.
# Usage: ./release.sh 1.1        (the version number; also sets the build number)
# Needs: ./setup-sparkle.sh run once, create-dmg, gh (GitHub CLI, logged in).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh <version>  e.g. ./release.sh 1.1}"
TAG="v$VERSION"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.6.4}"
TOOLS=".sparkle"
# First time? Create the GitHub repo (and git history) with publish.sh.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1 || ! gh repo view >/dev/null 2>&1; then
  echo "▶︎ No GitHub repo yet. Running ./publish.sh first…"
  ./publish.sh
fi
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

[ -x "$TOOLS/bin/generate_appcast" ] || { echo "Run ./setup-sparkle.sh first."; exit 1; }
grep -q "REPLACE_WITH_YOUR_PUBLIC_ED_KEY" SwiftNote/Info.plist && { echo "Run ./setup-sparkle.sh first (no public key set)."; exit 1; }

echo "▶︎ Setting version $VERSION"
BUILD="$(date +%Y%m%d%H%M)"
sed -i '' -E "s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = $VERSION;/g; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD;/g" SwiftNote.xcodeproj/project.pbxproj

echo "▶︎ Building the DMG"
./build.sh

DMG="dist/SwiftNote-$VERSION.dmg"
mv dist/SwiftNote.dmg "$DMG"

echo "▶︎ Generating the appcast"
STAGE="$(mktemp -d)"
cp "$DMG" "$STAGE/"
[ -f docs/appcast.xml ] && cp docs/appcast.xml "$STAGE/appcast.xml"
"$TOOLS/bin/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$STAGE"
cp "$STAGE/appcast.xml" docs/appcast.xml
rm -rf "$STAGE"

echo "▶︎ Publishing the GitHub release $TAG"
git add -A
git commit -q -m "Release $VERSION" || true
git push -q
gh release create "$TAG" "$DMG" --title "SwiftNote $VERSION" --generate-notes

echo "✅ Released $VERSION. Installed copies will see it within a day, or via Check for Updates…"
