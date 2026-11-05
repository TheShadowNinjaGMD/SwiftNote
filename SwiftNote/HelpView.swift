//
//  HelpView.swift
//  SwiftNote — in-app help.
//

import SwiftUI

struct HelpView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("SwiftNote Help").font(.title.bold())

                topic("Getting around", "menubar.rectangle", [
                    "Click the menu bar icon to open or close the panel. Right-click it for the menu.",
                    "Pin the panel (pin button) to keep it open while you work in other apps.",
                    "Turn on Show in Dock in Settings to get a Dock icon and the Manager window: a large editor, all notes, history and the save manager."
                ])

                topic("Global shortcuts", "keyboard", [
                    "Shortcuts work in every app and need no Accessibility permission.",
                    "Defaults: ⌃⌥D dictation, ⌃⌥S save, ⌃⌥N show/hide, ⌃⌥W stop dictation, ⌃⌥M Manager.",
                    "Change or turn off any shortcut in Settings → Global shortcuts. Click it, press the new keys. Esc cancels; Delete turns it off."
                ])

                topic("Dictation", "mic", [
                    "Apple speech works out of the box once you allow the microphone and speech recognition.",
                    "whisper.cpp runs locally: install it with “brew install whisper-cpp”, then download or import a ggml model in Advanced Settings → Whisper.",
                    "The online API option works with any OpenAI-compatible transcription endpoint. Your API key is stored in the Keychain.",
                    "Spoken punctuation, filler-word removal and macros are under Advanced Settings → Dictation."
                ])

                topic("Saving & backups", "externaldrive", [
                    "Save writes a .md file to ~/Library/Application Support/SwiftNote/Saves.",
                    "Auto-backups go to ~/Library/Application Support/SwiftNote/Backups.",
                    "A mirror is kept in ~/Desktop/\(settings.desktopFolderName). With iCloud “Desktop & Documents” on, that folder syncs to iCloud.",
                    "Export Settings / Import Settings in Settings move your notes and preferences between Macs."
                ])

                topic("Appearance", "paintbrush", [
                    "Liquid Glass uses Apple's native API on macOS 26 and later; other systems get frosted glass.",
                    "Sync with system follows light / dark mode automatically.",
                    "Pick any SF Symbol or import your own SVG for the menu bar icon."
                ])

                HStack {
                    Button("Advanced Settings") { Windows.advanced.show() }
                    Button("Welcome tour") { Windows.onboarding.show() }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppBackground(cornerRadius: 0).ignoresSafeArea())
    }

    private func topic(_ title: String, _ symbol: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: title, symbol: symbol)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundStyle(settings.accentColor)
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 12.5))
                    }
                }
            }
        }
    }
}
