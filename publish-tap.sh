#!/bin/bash
# Creates or updates the Homebrew tap, so anyone can run:  brew install --cask swiftnote
# Usage: ./publish-tap.sh [version] [sha256]
#   version   default: the latest GitHub release of SwiftNote
#   sha256    default: worked out from dist/SwiftNote-<version>.dmg, or from the release download
# release.sh runs this for you after every release.
set -euo pipefail
cd "$(dirname "$0")"
say() { printf "\n▶︎ %s\n" "$*"; }

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login --web --git-protocol https
gh auth setup-git >/dev/null 2>&1 || true

OWNER="$(gh api user --jq .login)"
APP_REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "$OWNER/SwiftNote")"
TAP="$OWNER/homebrew-swiftnote"

VERSION="${1:-}"
[ -n "$VERSION" ] || VERSION="$(gh release view --repo "$APP_REPO" --json tagName --jq .tagName)"
VERSION="${VERSION#v}"
SHA="${2:-}"
DMG="SwiftNote-$VERSION.dmg"

if [ -z "$SHA" ]; then
  if [ -f "dist/$DMG" ]; then
    SHA="$(shasum -a 256 "dist/$DMG" | awk '{print $1}')"
  else
    say "Downloading $DMG from the release to checksum it"
    TMP="$(mktemp -d)"
    gh release download "v$VERSION" --repo "$APP_REPO" --pattern "$DMG" --dir "$TMP" \
      || { echo "Couldn't find $DMG on release v$VERSION. Run ./release.sh $VERSION first."; exit 1; }
    SHA="$(shasum -a 256 "$TMP/$DMG" | awk '{print $1}')"
    rm -rf "$TMP"
  fi
fi
echo "SwiftNote $VERSION  sha256 $SHA"

if ! gh repo view "$TAP" >/dev/null 2>&1; then
  say "Creating $TAP"
  gh repo create "$TAP" --public --description "Homebrew tap for SwiftNote"
fi

say "Updating the cask"
WORK="$(mktemp -d)"
gh repo clone "$TAP" "$WORK/tap" >/dev/null 2>&1 || { mkdir -p "$WORK/tap"; git -C "$WORK/tap" init -q; git -C "$WORK/tap" remote add origin "https://github.com/$TAP.git"; }
cd "$WORK/tap"
git checkout -q -B main
mkdir -p Casks
HERE="$OLDPWD/homebrew"
fill() { sed -e "s|@VERSION@|$VERSION|g" -e "s|@SHA@|$SHA|g" -e "s|@REPO@|$APP_REPO|g" -e "s|@OWNER@|$OWNER|g" "$1"; }
fill "$HERE/swiftnote.rb.template" > Casks/swiftnote.rb
fill "$HERE/README.md.template" > README.md

git add -A
if git diff --cached --quiet; then
  echo "Tap already up to date."
else
  git commit -q -m "swiftnote $VERSION"
  git push -q -u origin main
fi
cd - >/dev/null
rm -rf "$WORK"

echo
echo "✅ Done. Install SwiftNote with Homebrew:"
echo "   brew tap $OWNER/swiftnote"
echo "   brew install --cask swiftnote"
echo "   (or in one line: brew install --cask $OWNER/swiftnote/swiftnote)"
