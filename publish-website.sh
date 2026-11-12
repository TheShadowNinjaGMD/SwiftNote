#!/bin/bash
# Uploads the SwiftNote website to GitHub Pages: https://<you>.github.io/SwiftNote/
# Usage: ./publish-website.sh [path-to-website-folder]   (run it from inside 2-App)
#   Works from either 1-Website or 2-App; finds index.html + swiftnote-logo.png itself.
# Needs the repo to exist already (run ./publish.sh once first).
# Note: swiftnote.base44.app is hosted by Base44 and is updated inside Base44, not from here.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# Website folder: the argument, else this script's folder if it holds index.html, else ../1-Website
if [ -n "${1:-}" ]; then SITE="$1"
elif [ -f "$HERE/index.html" ]; then SITE="$HERE"
else SITE="$HERE/../1-Website"; fi
SITE="$(cd "$SITE" && pwd)"

# Repo folder: the folder you ran this from if it's a git repo, else the 2-App folder next to the website
if git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1; then cd "$(git -C "$PWD" rev-parse --show-toplevel)"
elif [ -d "$HERE/../2-App/.git" ]; then cd "$HERE/../2-App"
elif [ -d "$HERE/.git" ]; then cd "$HERE"
else echo "Can't find the git repo. cd into 2-App and run ./publish.sh first, then re-run this."; exit 1; fi

say() { printf "\n▶︎ %s\n" "$*"; }

[ -f "$SITE/index.html" ] || { echo "No index.html in $SITE"; exit 1; }
command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || gh auth login --web --git-protocol https

say "Copying the website into docs/"
mkdir -p docs
cp "$SITE/index.html" "$SITE/swiftnote-logo.png" docs/
touch docs/.nojekyll           # serve files as-is (keeps appcast.xml untouched)

say "Committing and pushing"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git add docs
if git diff --cached --quiet; then echo "Website already up to date."
else git commit -q -m "Update website"; fi
git push -u origin "$BRANCH" 2>/dev/null || { git pull --no-rebase -X ours --no-edit origin "$BRANCH"; git push -u origin "$BRANCH"; }

say "Turning on GitHub Pages (main /docs)"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
gh api -X POST "repos/$REPO/pages" -f "source[branch]=$BRANCH" -f "source[path]=/docs" >/dev/null 2>&1 \
  || gh api -X PUT "repos/$REPO/pages" -f "source[branch]=$BRANCH" -f "source[path]=/docs" >/dev/null 2>&1 \
  || echo "(Pages may already be on, or enable it in Settings → Pages → main /docs)"

echo; echo "✅ Live in a minute or two: https://$(gh api user --jq .login).github.io/${REPO#*/}/"
