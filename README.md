# SwiftNote

A quick-note app that lives in your macOS menu bar.

## Build
1. Open `SwiftNote.xcodeproj` in Xcode 16 or later (Xcode 26 for native Liquid Glass; older SDKs use frosted glass automatically).
2. Target → Signing & Capabilities → pick your Team (or "Sign to Run Locally").
3. Press ⌘R. If you see compile errors, send them over and they'll be fixed.

`./build.sh` builds the app and packages `dist/SwiftNote.dmg` with create-dmg (`brew install create-dmg`), using `dmg/Background.tiff` and `dmg/VolumeIcon.icns`.

## Notes
- Minimum macOS 14. App Sandbox is intentionally off (Desktop backup folder, whisper.cpp CLI).
- Data: `~/Library/Application Support/SwiftNote/` (notes, Saves, Backups, Models). Mirror: `~/Desktop/Swiftnote`.
- Local dictation: `brew install whisper-cpp`, then download a model in Settings → Advanced → Whisper.

## Publish to GitHub
`./publish.sh` creates the repo and pushes. Options: `./publish.sh MyRepo --private --release` (the last one also builds the DMG and attaches it to a release).
