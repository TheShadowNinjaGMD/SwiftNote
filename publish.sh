#!/bin/bash
# One-shot: git init, commit, create the GitHub repo, push, and (optionally) publish the DMG as a release.
# Usage:  ./publish.sh [repo-name] [--private] [--release]
#   repo-name   default: SwiftNote
#   --private   create a private repo (default: public)
#   --release   also run ./build.sh and attach dist/SwiftNote.dmg to a GitHub release (v1.0 unless TAG=... is set)
set -euo pipefail
cd "$(dirname "$0")"

NAME="SwiftNote"; VIS="--public"; RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --private) VIS="--private" ;;
    --release) RELEASE=1 ;;
    -*) echo "Unknown option: $arg"; exit 1 ;;
    *) NAME="$arg" ;;
  esac
done
TAG="${TAG:-v1.0}"

say() { printf "\n▶︎ %s\n" "$*"; }

# 1. Tools
command -v git >/dev/null || { echo "git is missing. Run: xcode-select --install"; exit 1; }
if ! command -v gh >/dev/null; then
  command -v brew >/dev/null || { echo "Install Homebrew (https://brew.sh) or the GitHub CLI (https://cli.github.com), then re-run."; exit 1; }
  say "Installing GitHub CLI…"
  brew install gh
fi

# 2. Login
if ! gh auth status >/dev/null 2>&1; then
  say "Logging in to GitHub (a browser window will open)…"
  gh auth login --web --git-protocol https
fi
gh auth setup-git >/dev/null 2>&1 || true

# 3. .gitignore
if [ ! -f .gitignore ]; then
  say "Writing .gitignore"
  cat > .gitignore <<'EOF'
.DS_Store
build/
dist/
DerivedData/
xcuserdata/
*.xcuserstate
EOF
fi

# 4. Git repo + commit
if [ ! -d .git ]; then
  say "Creating git repository"
  git init -q -b main
fi
git add -A
if git diff --cached --quiet; then
  echo "Nothing new to commit."
else
  git commit -q -m "${COMMIT_MSG:-SwiftNote}"
fi

# 5. GitHub repo + push
USER_NAME="$(gh api user --jq .login)"
TARGET="$USER_NAME/$NAME"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# If an old/wrong 'origin' exists (e.g. pointing at a repo that was never created), drop it.
if git remote get-url origin >/dev/null 2>&1; then
  CURRENT="$(git remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git/?$##')"
  if ! gh repo view "$CURRENT" >/dev/null 2>&1; then
    say "Remote '$CURRENT' doesn't exist on GitHub (or isn't yours). Replacing it."
    git remote remove origin
  fi
fi

if git remote get-url origin >/dev/null 2>&1; then
  say "Pushing to $(git remote get-url origin)"
  git push -u origin "$BRANCH"
elif gh repo view "$TARGET" >/dev/null 2>&1; then
  say "Repo $TARGET already exists, connecting to it"
  git remote add origin "https://github.com/$TARGET.git"
  git push -u origin "$BRANCH"
else
  say "Creating $TARGET ($VIS)"
  gh repo create "$TARGET" $VIS --source=. --remote=origin --push \
    --description "A quick note-taking app that lives in your macOS menu bar"
fi
NAME="${TARGET#*/}"

# 6. Optional release with the DMG
if [ "$RELEASE" -eq 1 ]; then
  say "Building the DMG"
  ./build.sh
  say "Publishing release $TAG"
  gh release create "$TAG" "dist/SwiftNote.dmg" --title "SwiftNote $TAG" \
    --notes "Open the DMG and drag SwiftNote to Applications. The app isn't notarised: right-click → Open the first time."
fi

echo
echo "✅ Done: https://github.com/$USER_NAME/$NAME"
