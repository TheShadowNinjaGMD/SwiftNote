//
//  QuickSettings.swift
//  SwiftNote — the compact Settings tab inside the menu bar panel.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct QuickSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var backup = BackupManager.shared
    @State private var hexDraft = ""
    @State private var confirmReset = false

    private let accents: [String] = ["#4A90E2", "#7C5CFF", "#FF5C8A", "#FF9F1C", "#2EC4B6", "#34C759", "#8E8E93"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                appearance
                menuBarIcon
                general
                dictation
                backupSection
                shortcuts
                data
                aboutSection
            }
            .padding(12)
        }
    }

    // MARK: Appearance
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Appearance", symbol: "paintbrush")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Sync with system (light / dark)", isOn: settings.binding(\.appearanceSync))
                    if !settings.appearanceSync {
                        Picker("Mode", selection: settings.binding(\.isDarkMode)) {
                            Label("Light", systemImage: "sun.max").tag(false)
                            Label("Dark", systemImage: "moon").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Background", selection: settings.binding(\.backgroundStyle)) {
                        ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text("Glass opacity").font(.caption); Spacer()
                            Text("\(Int(settings.glassOpacity * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        Slider(value: settings.binding(\.glassOpacity), in: 0.15...1)
                    }
                    Toggle("Accent tint on glass", isOn: settings.binding(\.accentTintGlass))
                    if settings.backgroundStyle == .frosted {
                        Picker("Material", selection: settings.binding(\.frostedMaterial)) {
                            ForEach(FrostedMaterial.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Accent").font(.caption)
                        ForEach(accents, id: \.self) { hex in
                            Button { settings.accentHex = hex; hexDraft = hex } label: {
                                Circle().fill((Color(hex: hex) ?? .blue)).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.white.opacity(settings.accentHex == hex ? 0.9 : 0), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                        CustomAccentButton(size: 18)
                        TextField("#RRGGBB", text: $hexDraft)
                            .textFieldStyle(.roundedBorder).frame(width: 84)
                            .onSubmit { applyHex() }
                    }
                }
            }
        }
        .onAppear { hexDraft = settings.accentHex }
        .onChange(of: settings.accentHex) { _, v in hexDraft = v }
    }

    private func applyHex() {
        var s = hexDraft.trimmingCharacters(in: .whitespaces)
        if !s.hasPrefix("#") { s = "#" + s }
        if s.count == 7, s.dropFirst().allSatisfy({ $0.isHexDigit }) { settings.accentHex = s.uppercased() }
        else { ToastCenter.shared.show("Use a 6-digit hex like #4A90E2") }
    }

    private var menuBarIcon: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Menu bar icon", symbol: "menubar.rectangle")
            Card { MenuIconPicker() }
        }
    }

    // MARK: General
    private var general: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "General", symbol: "gearshape")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show in Dock (opens the Manager window)", isOn: settings.binding(\.showInDock))
                    Toggle("Launch at login", isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { on in
                            do { try LaunchAtLogin.set(on) }
                            catch { ToastCenter.shared.show("Couldn't change login item: \(error.localizedDescription)") }
                        }))
                    Toggle("Sound effects", isOn: settings.binding(\.soundEnabled))
                    Toggle("Global keybinds (work from any app)", isOn: settings.binding(\.hotkeysEnabled))
                    HStack {
                        Button { Windows.advanced.show() } label: { Label("Advanced Settings…", systemImage: "slider.horizontal.3") }
                            .buttonStyle(SoftButtonStyle(tint: settings.accentColor, prominent: true))
                        Button { Windows.onboarding.show() } label: { Label("Welcome tour", systemImage: "sparkles") }
                            .buttonStyle(SoftButtonStyle(tint: .purple))
                    }
                }
            }
        }
    }

    // MARK: Dictation
    private var dictation: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Dictation", symbol: "mic")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable dictation", isOn: settings.binding(\.dictationEnabled))
                    Picker("Engine", selection: settings.binding(\.dictationEngine)) {
                        ForEach(DictationEngine.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Text(settings.dictationEngine.summary).font(.caption2).foregroundStyle(.secondary)
                    Button { AdvancedNav.shared.open(.whisper) } label: { Label("Whisper models & API…", systemImage: "arrow.down.circle") }
                        .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
                }
            }
        }
    }

    // MARK: Backup
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Backup & saves", symbol: "externaldrive")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-backup to Application Support/SwiftNote", isOn: settings.binding(\.autoBackupEnabled))
                    Toggle("Mirror to ~/Desktop/\(settings.desktopFolderName) (syncs via iCloud Desktop)", isOn: settings.binding(\.desktopMirrorEnabled))
                    HStack {
                        Button { _ = backup.runBackup(manual: true) } label: { Label("Back up now", systemImage: "arrow.triangle.2.circlepath") }
                            .buttonStyle(SoftButtonStyle(tint: .green))
                        Button { FileStore.openFolder(AppPaths.appSupport) } label: { Label("Open folder", systemImage: "folder") }
                            .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
                    }
                    Text(backup.lastStatus).font(.caption2).foregroundStyle(.secondary)
                    if !backup.desktopStatus.isEmpty { Text(backup.desktopStatus).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }

    // MARK: Shortcuts
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Keybinds", symbol: "keyboard")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(HotkeyAction.allCases) { ShortcutRecorderRow(action: $0) }
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "About & updates", symbol: "info.circle")
            Card { AboutUpdatesCard() }
        }
    }

    // MARK: Data
    private var data: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: "Data", symbol: "tray.and.arrow.down")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button { exportSettings() } label: { Label("Export Settings", systemImage: "square.and.arrow.up") }
                            .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
                        Button { importSettings() } label: { Label("Import Settings", systemImage: "square.and.arrow.down") }
                            .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
                    }
                    HStack {
                        Button { exportMarkdown() } label: { Label("Export Markdown", systemImage: "doc.text") }
                            .buttonStyle(SoftButtonStyle(tint: .blue))
                        Button { confirmReset = true } label: { Label("Reset settings", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(SoftButtonStyle(tint: .red))
                    }
                    Text("Save (in the editor) writes a .md file to Application Support/SwiftNote/Saves.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Reset every setting to its default?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { settings.resetAll(keepOnboarding: true) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func exportSettings() {
        guard let url = Panels.save(title: "Export Settings", name: "SwiftNote-\(FileStore.timestamp()).json", types: [.json]),
              let data = NoteManager.shared.exportJSONData(includeSettings: true) else { return }
        do { try data.write(to: url, options: .atomic); ToastCenter.shared.show("Exported to \(url.lastPathComponent)") }
        catch { ToastCenter.shared.show("Export failed: \(error.localizedDescription)") }
    }

    private func importSettings() {
        guard let url = Panels.chooseFile(title: "Import Settings", types: [.json]),
              let data = try? Data(contentsOf: url),
              let export = try? JSONCoders.makeDecoder().decode(SwiftNoteExport.self, from: data) else {
            ToastCenter.shared.show("That file isn't a SwiftNote export")
            return
        }
        let count = NoteManager.shared.apply(export: export, replace: false, includeSettings: true)
        ToastCenter.shared.show("Imported \(count) notes and settings")
    }

    private func exportMarkdown() {
        guard let url = Panels.save(title: "Export Markdown", name: "SwiftNote-\(FileStore.timestamp()).md",
                                    types: [UTType(filenameExtension: "md") ?? .plainText]) else { return }
        do { try NoteManager.shared.markdownExport().write(to: url, atomically: true, encoding: .utf8)
            ToastCenter.shared.show("Exported Markdown") }
        catch { ToastCenter.shared.show("Export failed: \(error.localizedDescription)") }
    }
}
