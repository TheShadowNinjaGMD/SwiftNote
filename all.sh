#!/bin/bash
# Everything in one go: push code → Sparkle key (if needed) → build DMG + GitHub release → website.
# Usage: ./all.sh <version>        e.g.  ./all.sh 1.2
#        ./all.sh <version> --skip-release    (code + website only, no build)
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:-}"; [ -n "$VERSION" ] || { echo "Usage: ./all.sh <version>   e.g. ./all.sh 1.2"; exit 1; }
SKIP_RELEASE=0; [ "${2:-}" = "--skip-release" ] && SKIP_RELEASE=1
chmod +x *.sh
say() { printf "\n━━━ %s ━━━\n" "$*"; }

say "1/4 Push code to GitHub"
COMMIT_MSG="SwiftNote $VERSION" ./publish.sh
git pull --no-rebase --no-edit || true

say "2/4 Sparkle signing key"
if grep -A1 SUPublicEDKey SwiftNote/Info.plist | grep -q "REPLACE"; then ./setup-sparkle.sh
else echo "Already set up."; fi

if [ "$SKIP_RELEASE" -eq 0 ]; then
  say "3/4 Build DMG + GitHub release $VERSION"
  ./release.sh "$VERSION"
else
  say "3/4 Skipped (--skip-release)"
fi

say "4/4 Publish website"
./publish-website.sh

echo; echo "✅ All done: SwiftNote $VERSION"
