# Building SwiftNote from source

Developer notes. The user-facing README is README.md.

## Build
1. Open `SwiftNote.xcodeproj` in Xcode 16 or later. Xcode downloads Sparkle (Swift Package) automatically the first time.
2. Target → Signing & Capabilities → pick your Team (or "Sign to Run Locally").
3. Press ⌘R.

Xcode 26 gives native Liquid Glass; older SDKs fall back to frosted glass. Minimum macOS 14. The App Sandbox is off on purpose (Desktop backup folder, whisper.cpp CLI).

## Make the DMG
```bash
brew install create-dmg
./build.sh          # → dist/SwiftNote.dmg (background + volume icon from dmg/)
```

## Auto-updates (Sparkle)
The app has **Check for Updates…** (app menu, menu bar icon, Settings → About & updates). To switch on real updates:
```bash
./setup-sparkle.sh   # once: creates your signing key, writes the public key into Info.plist
./release.sh 1.1.1     # builds, signs, updates docs/appcast.xml, pushes, creates the GitHub release
```
Until `setup-sparkle.sh` has run, Check for Updates simply opens the GitHub releases page. The update feed is `docs/appcast.xml`, served from this repo's `main` branch.

## Publish
`./publish.sh` creates the GitHub repo and pushes (options: `--private`, `--release`).
`docs/` is the product site; to host it on GitHub Pages: Settings → Pages → `main` / `/docs`.

## Data
`~/Library/Application Support/SwiftNote/` (notes, Saves, Backups, Models). Mirror: `~/Desktop/Swiftnote`.
Local dictation: `brew install whisper-cpp`, then download a model in Settings → Advanced → Whisper.
