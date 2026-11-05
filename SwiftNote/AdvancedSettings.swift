//
//  AdvancedSettings.swift
//  SwiftNote — full control over every feature.
//

import SwiftUI
import AppKit
import Speech
import UniformTypeIdentifiers

enum AdvancedCategory: String, CaseIterable, Identifiable {
    case general, appearance, menuBar, editor, notes, dictation, whisper, sound, shortcuts, backup, calendar, data
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .menuBar: return "Menu Bar & Dock"
        case .editor: return "Editor"
        case .notes: return "Sticky Notes"
        case .dictation: return "Dictation"
        case .whisper: return "Whisper"
        case .sound: return "Sound"
        case .shortcuts: return "Shortcuts"
        case .backup: return "Backup & Saves"
        case .calendar: return "Calendar & Reminders"
        case .data: return "Data & Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .menuBar: return "menubar.rectangle"
        case .editor: return "textformat"
        case .notes: return "note.text"
        case .dictation: return "mic"
        case .whisper: return "waveform"
        case .sound: return "speaker.wave.2"
        case .shortcuts: return "keyboard"
        case .backup: return "externaldrive"
        case .calendar: return "calendar"
        case .data: return "lock.shield"
        }
    }
}

// MARK: - Row helpers
struct ToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: $isOn)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct SliderRow: View {
    let title: String
    var detail: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: step < 1 ? "%.2f" : "%.0f", value) + unit)
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct IntStepperRow: View {
    let title: String
    var detail: String? = nil
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Stepper(value: $value, in: range) {
                HStack { Text(title); Spacer(); Text("\(value)\(unit)").monospacedDigit().foregroundStyle(.secondary) }
            }
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct TextRow: View {
    let title: String
    var detail: String? = nil
    var prompt: String = ""
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            TextField(prompt, text: $text).textFieldStyle(.roundedBorder)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title: title, symbol: symbol)
            Card { VStack(alignment: .leading, spacing: 12) { content } }
        }
    }
}

// MARK: - Window
struct AdvancedSettingsView: View {
    @ObservedObject private var nav = AdvancedNav.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 0) {
            List(AdvancedCategory.allCases, selection: Binding(get: { Optional(nav.selection) }, set: { if let v = $0 { nav.selection = v } })) { c in
                Label(c.title, systemImage: c.symbol).tag(c)
            }
            .scrollContentBackground(.hidden)
            .frame(width: 210)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(nav.selection.title).font(.title2.bold())
                    page
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(AppBackground(cornerRadius: 0).ignoresSafeArea())
        .toastOverlay()
    }

    @ViewBuilder private var page: some View {
        switch nav.selection {
        case .general: GeneralPage()
        case .appearance: AppearancePage()
        case .menuBar: MenuBarPage()
        case .editor: EditorPage()
        case .notes: NotesPage()
        case .dictation: DictationPage()
        case .whisper: WhisperPage()
        case .sound: SoundPage()
        case .shortcuts: ShortcutsPage()
        case .backup: BackupPage()
        case .calendar: CalendarPage()
        case .data: DataPage()
        }
    }
}

// MARK: - Pages
private struct GeneralPage: View {
    @ObservedObject var s = AppSettings.shared
    var body: some View {
        SettingsGroup(title: "Startup", symbol: "power") {
            Toggle("Launch at login", isOn: Binding(get: { LaunchAtLogin.isEnabled },
                                                    set: { try? LaunchAtLogin.set($0) }))
            ToggleRow(title: "Open the Manager window on launch", isOn: s.binding(\.openManagerOnLaunch))
        }
        SettingsGroup(title: "Panel", symbol: "rectangle.portrait") {
            SliderRow(title: "Width", value: s.binding(\.panelWidth), range: 380...800, step: 10, unit: " pt")
            SliderRow(title: "Height", value: s.binding(\.panelHeight), range: 400...1000, step: 10, unit: " pt")
            SliderRow(title: "Gap below menu bar", value: s.binding(\.panelGap), range: 0...30, step: 1, unit: " pt")
            ToggleRow(title: "Keep panel pinned open", isOn: s.binding(\.panelPinned))
            ToggleRow(title: "Hide when clicking outside", isOn: s.binding(\.closePanelOnClickOutside))
            ToggleRow(title: "Focus the editor when it opens", isOn: s.binding(\.focusEditorOnOpen))
            ToggleRow(title: "Remember the last tab", isOn: s.binding(\.rememberLastTab))
            ToggleRow(title: "Hide from screen sharing", detail: "Excludes the panel from screenshots and screen recordings.", isOn: s.binding(\.hideFromScreenShare))
        }
        SettingsGroup(title: "Feedback", symbol: "bell") {
            ToggleRow(title: "Show toasts", isOn: s.binding(\.showToasts))
            SliderRow(title: "Toast duration", value: s.binding(\.toastSeconds), range: 1...8, step: 0.5, unit: " s")
            ToggleRow(title: "Animations", isOn: s.binding(\.animationsEnabled))
        }
    }
}

private struct AppearancePage: View {
    @ObservedObject var s = AppSettings.shared
    @State private var hex = ""
    var body: some View {
        SettingsGroup(title: "Theme", symbol: "circle.lefthalf.filled") {
            ToggleRow(title: "Sync with system", detail: "Follow macOS light / dark mode automatically.", isOn: s.binding(\.appearanceSync))
            if !s.appearanceSync {
                Picker("Mode", selection: s.binding(\.isDarkMode)) {
                    Text("Light").tag(false); Text("Dark").tag(true)
                }.pickerStyle(.segmented)
            }
            HStack {
                Text("Accent colour")
                ColorPicker("", selection: Binding(get: { s.accentColor }, set: { s.accentHex = $0.toHex() })).labelsHidden()
                TextField("#RRGGBB", text: $hex).textFieldStyle(.roundedBorder).frame(width: 100)
                    .onSubmit { if hex.count == 7 { s.accentHex = hex.uppercased() } }
            }
        }
        .onAppear { hex = s.accentHex }
        SettingsGroup(title: "Background", symbol: "square.stack.3d.up") {
            Picker("Style", selection: s.binding(\.backgroundStyle)) {
                ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if s.backgroundStyle == .liquid {
                Text("Uses Apple's native Liquid Glass on macOS 26 or later. Older systems fall back to frosted glass.")
                    .font(.caption).foregroundStyle(.secondary)
                ToggleRow(title: "Glass controls", detail: "Buttons and badges use glass too.", isOn: s.binding(\.glassControls))
            }
            if s.backgroundStyle == .frosted {
                Picker("Material", selection: s.binding(\.frostedMaterial)) {
                    ForEach(FrostedMaterial.allCases) { Text($0.title).tag($0) }
                }
            }
            SliderRow(title: "Glass opacity", detail: "Left = see-through, right = fully frosted.", value: s.binding(\.glassOpacity), range: 0.15...1, step: 0.01)
            ToggleRow(title: "Accent tint on glass", detail: "Colours the glass with your accent colour.", isOn: s.binding(\.accentTintGlass))
            if s.accentTintGlass {
                SliderRow(title: "Tint strength", value: s.binding(\.glassTint), range: 0...0.5, step: 0.01)
            }
            SliderRow(title: "Corner radius", value: s.binding(\.glassCornerRadius), range: 0...40, step: 1, unit: " pt")
            SliderRow(title: "Card opacity", value: s.binding(\.cardOpacity), range: 0...0.3, step: 0.01)
        }
    }
}

private struct MenuBarPage: View {
    @ObservedObject var s = AppSettings.shared
    var body: some View {
        SettingsGroup(title: "Menu bar icon", symbol: "menubar.rectangle") {
            MenuIconPicker()
            ToggleRow(title: "Show note count next to icon", isOn: s.binding(\.menuIconShowCount))
        }
        SettingsGroup(title: "Dock", symbol: "dock.rectangle") {
            ToggleRow(title: "Show in Dock", detail: "Adds a Dock icon. Clicking it opens the Manager window with history, a large editor and the save manager.", isOn: s.binding(\.showInDock))
            Button("Open Manager") { Windows.manager.show() }
        }
    }
}

private struct EditorPage: View {
    @ObservedObject var s = AppSettings.shared
    var body: some View {
        SettingsGroup(title: "Text", symbol: "textformat") {
            SliderRow(title: "Font size", value: s.binding(\.fontSize), range: 10...28, step: 1, unit: " pt")
            SliderRow(title: "Line spacing", value: s.binding(\.lineSpacing), range: 0...16, step: 1, unit: " pt")
            Picker("Font style", selection: s.binding(\.editorFontDesign)) {
                ForEach(EditorFontDesign.allCases) { Text($0.title).tag($0.rawValue) }
            }
        }
        SettingsGroup(title: "Writing aids", symbol: "text.badge.checkmark") {
            ToggleRow(title: "Live Markdown rendering", detail: "Shows **bold**, *italic*, <u>underline</u>, ~~strike~~, headings, `code`, quotes and lists as you type. The markers stay visible but dimmed.", isOn: s.binding(\.liveMarkdown))
            ToggleRow(title: "Spell checking", isOn: s.binding(\.spellCheck))
            ToggleRow(title: "Smart quotes & dashes", isOn: s.binding(\.smartQuotes))
            ToggleRow(title: "Auto-correct", isOn: s.binding(\.autoCorrect))
            ToggleRow(title: "Show word / character stats", isOn: s.binding(\.showStats))
            IntStepperRow(title: "Word goal", detail: "0 disables the progress bar.", value: s.binding(\.wordGoal), range: 0...10000)
        }
        SettingsGroup(title: "Clearing", symbol: "trash") {
            ToggleRow(title: "Confirm before clearing", isOn: s.binding(\.confirmClear))
            ToggleRow(title: "Save a .md copy before clearing", isOn: s.binding(\.saveBeforeClear))
        }
    }
}

private struct NotesPage: View {
    @ObservedObject var s = AppSettings.shared
    var body: some View {
        SettingsGroup(title: "List", symbol: "list.bullet") {
            Picker("Sort", selection: s.binding(\.noteSort)) {
                ForEach(NoteSortMode.allCases) { Text($0.title).tag($0) }
            }
            IntStepperRow(title: "Preview lines per card", value: s.binding(\.noteCardLines), range: 1...12)
            ToggleRow(title: "Compact cards", isOn: s.binding(\.compactNotes))
            ToggleRow(title: "Show word counts", isOn: s.binding(\.showNoteStats))
            ToggleRow(title: "Show dates", isOn: s.binding(\.showNoteDates))
            ToggleRow(title: "Lowercase tags", isOn: s.binding(\.tagsLowercase))
            ToggleRow(title: "Confirm before deleting", isOn: s.binding(\.confirmDeleteNote))
        }
        SettingsGroup(title: "New note colour", symbol: "paintpalette") {
            Picker("Mode", selection: s.binding(\.noteColorMode)) {
                ForEach(NewNoteColorMode.allCases) { Text($0.title).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            if s.noteColorMode == "fixed" {
                IntStepperRow(title: "Colour index", value: s.binding(\.noteFixedColor), range: 0...(max(0, StickyNote.noteColors.count - 1)))
            }
        }
        SettingsGroup(title: "Desktop sticky notes", symbol: "square.on.square") {
            ToggleRow(title: "Always on top", isOn: s.binding(\.stickyAlwaysOnTop))
            SliderRow(title: "Width", value: s.binding(\.stickyWidth), range: 180...600, step: 10, unit: " pt")
            SliderRow(title: "Height", value: s.binding(\.stickyHeight), range: 140...600, step: 10, unit: " pt")
            SliderRow(title: "Opacity", value: s.binding(\.stickyOpacity), range: 0.3...1, step: 0.05)
        }
    }
}

private struct DictationPage: View {
    @ObservedObject var s = AppSettings.shared
    var body: some View {
        SettingsGroup(title: "Engine", symbol: "mic") {
            ToggleRow(title: "Enable dictation", isOn: s.binding(\.dictationEnabled))
            Picker("Engine", selection: s.binding(\.dictationEngine)) {
                ForEach(DictationEngine.allCases) { Text($0.title).tag($0) }
            }
            Text(s.dictationEngine.summary).font(.caption).foregroundStyle(.secondary)
            Picker("Language", selection: s.binding(\.dictationLocale)) {
                ForEach(DictationLocales.all, id: \.id) { Text($0.name).tag($0.id) }
            }
            IntStepperRow(title: "Max length", detail: "Dictation stops automatically. 0 = no limit.", value: s.binding(\.dictationMaxSeconds), range: 0...3600, unit: " s")
            ToggleRow(title: "Pressing the start shortcut again stops dictation", isOn: s.binding(\.startHotkeyToggles))
            ToggleRow(title: "Save each dictation to history", isOn: s.binding(\.dictationSaveHistory))
        }
        SettingsGroup(title: "Apple speech", symbol: "apple.logo") {
            ToggleRow(title: "Prefer on-device recognition", isOn: s.binding(\.appleOnDevice))
            ToggleRow(title: "Automatic punctuation", isOn: s.binding(\.appleAutoPunctuation))
            TextRow(title: "Custom words", detail: "Comma-separated names or jargon to bias recognition.", text: s.binding(\.appleHints))
        }
        SettingsGroup(title: "Clean-up", symbol: "wand.and.stars") {
            SliderRow(title: "Noise gate", detail: "Ignore audio quieter than this level.", value: s.binding(\.micGate), range: 0...0.5, step: 0.01)
            ToggleRow(title: "Remove filler words", isOn: s.binding(\.fillerRemoval))
            if s.fillerRemoval { TextRow(title: "Filler words", text: s.binding(\.fillerWords)) }
            ToggleRow(title: "Spoken punctuation (“comma”, “new line”)", isOn: s.binding(\.voicePunctuation))
            ToggleRow(title: "Voice macros (“all caps … end caps”)", isOn: s.binding(\.voiceMacros))
            ToggleRow(title: "Allow “all caps” command", isOn: s.binding(\.voiceAllCaps))
            ToggleRow(title: "Capitalise sentences", isOn: s.binding(\.autoCapitalise))
        }
        SettingsGroup(title: "Permissions", symbol: "hand.raised") {
            HStack {
                Button("Allow Microphone") { Task { _ = await Permissions.requestMicrophone() } }
                Button("Allow Speech Recognition") { Task { _ = await Permissions.requestSpeech() } }
                Button("Privacy settings…") { Permissions.openPrivacyPane("Privacy_Microphone") }
            }
        }
    }
}

enum DictationLocales {
    struct Item { let id: String; let name: String }
    static let all: [Item] = {
        let ids = SFSpeechRecognizer.supportedLocales().map { $0.identifier }.sorted()
        var list: [Item] = []
        for ident in ids {
            let pretty = Locale.current.localizedString(forIdentifier: ident) ?? ident
            list.append(Item(id: ident, name: "\(pretty) (\(ident))"))
        }
        return list.isEmpty ? [Item(id: "en-US", name: "English (US)")] : list
    }()
}

private struct WhisperPage: View {
    @ObservedObject var s = AppSettings.shared
    @ObservedObject var models = WhisperModelManager.shared
    @State private var apiKey = Keychain.get("whisperAPIKey") ?? ""
    @State private var testResult = ""
    @State private var testing = false

    var body: some View {
        SettingsGroup(title: "whisper.cpp (local)", symbol: "cpu") {
            HStack {
                TextField("Path to whisper-cli", text: s.binding(\.whisperBinaryPath)).textFieldStyle(.roundedBorder)
                Button("Detect") {
                    if let p = Whisper.detectBinary() { s.whisperBinaryPath = p } else { ToastCenter.shared.show("whisper-cli not found. Run: brew install whisper-cpp", seconds: 5) }
                }
                Button("Choose…") { if let u = Panels.chooseAnyFile(title: "Choose whisper-cli") { s.whisperBinaryPath = u.path } }
            }
            Text("Install with Homebrew: brew install whisper-cpp").font(.caption).foregroundStyle(.secondary)
            IntStepperRow(title: "Threads", value: s.binding(\.whisperThreads), range: 1...32)
            TextRow(title: "Language", detail: "“auto” detects the language; or use a code like en.", text: s.binding(\.whisperLanguage))
            ToggleRow(title: "Translate to English", isOn: s.binding(\.whisperTranslate))
            TextRow(title: "Initial prompt", detail: "Names and jargon help accuracy.", text: s.binding(\.whisperPrompt))
            TextRow(title: "Extra arguments", detail: "Passed straight to whisper-cli.", text: s.binding(\.whisperExtraArgs))
            IntStepperRow(title: "Chunk length", detail: "Audio is transcribed in segments of this many seconds.", value: s.binding(\.whisperChunkSeconds), range: 5...120, unit: " s")
        }
        SettingsGroup(title: "Models", symbol: "square.and.arrow.down") {
            Text("Active model: " + (s.whisperModelPath.isEmpty ? "none selected" : URL(fileURLWithPath: s.whisperModelPath).lastPathComponent))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(WhisperModelInfo.catalog) { info in modelRow(info) }
            HStack {
                Button("Import model file…") { models.importModel() }
                Button("Open models folder") { FileStore.openFolder(AppPaths.models) }
            }
            if !models.message.isEmpty { Text(models.message).font(.caption).foregroundStyle(.secondary) }
        }
        SettingsGroup(title: "Online API (OpenAI-compatible)", symbol: "network") {
            TextRow(title: "Base URL", prompt: "https://api.openai.com/v1", text: s.binding(\.whisperAPIBaseURL))
            TextRow(title: "Model", prompt: "whisper-1", text: s.binding(\.whisperAPIModel))
            VStack(alignment: .leading, spacing: 2) {
                Text("API key (stored in Keychain)")
                SecureField("sk-…", text: $apiKey).textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, v in Keychain.set(v, account: "whisperAPIKey") }
            }
            TextRow(title: "Language", detail: "Leave blank to auto-detect.", text: s.binding(\.whisperAPILanguage))
            TextRow(title: "Prompt", text: s.binding(\.whisperAPIPrompt))
            SliderRow(title: "Temperature", value: s.binding(\.whisperAPITemperature), range: 0...1, step: 0.1)
            IntStepperRow(title: "Timeout", value: s.binding(\.whisperAPITimeout), range: 5...300, unit: " s")
            HStack {
                Button(testing ? "Testing…" : "Test connection") {
                    testing = true
                    Task {
                        testResult = await Whisper.testAPI(WhisperConfig.current())
                        testing = false
                    }
                }.disabled(testing)
                Text(testResult).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func modelRow(_ info: WhisperModelInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title)
                Text("\(info.note) · \(info.sizeText)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            let path = AppPaths.models.appendingPathComponent(info.fileName).path
            if models.downloadingID == info.id {
                ProgressView(value: models.progress).frame(width: 90)
                Button("Cancel") { models.cancelDownload() }
            } else if models.isInstalled(info) {
                if s.whisperModelPath == path {
                    Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Use") { models.select(URL(fileURLWithPath: path)) }
                }
            } else {
                Button("Download") { models.download(info) }.disabled(models.downloadingID != nil)
            }
        }
    }
}

private struct SoundPage: View {
    @ObservedObject var s = AppSettings.shared
    var body: some View {
        SettingsGroup(title: "Sounds", symbol: "speaker.wave.2") {
            ToggleRow(title: "Sound effects", isOn: s.binding(\.soundEnabled))
            SliderRow(title: "Volume", value: s.binding(\.soundVolume), range: 0...1, step: 0.05)
        }
        SettingsGroup(title: "Per-event", symbol: "list.bullet") {
            ForEach(SoundManager.SoundEvent.allCases) { event in
                HStack {
                    Toggle(event.title, isOn: Binding(get: { !s.isSoundDisabled(event.rawValue) },
                                                      set: { s.setSound(event.rawValue, enabled: $0) }))
                    Button { SoundManager.shared.play(event, force: true) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(IconButtonStyle(size: 24))
                }
            }
        }
    }
}

private struct ShortcutsPage: View {
    @ObservedObject var s = AppSettings.shared
    var body: some View {
        SettingsGroup(title: "Keybinds", symbol: "keyboard") {
            ToggleRow(title: "Global keybinds", detail: "On: shortcuts work from any app (no Accessibility permission needed). Off: they only work while SwiftNote is the active app.", isOn: s.binding(\.hotkeysEnabled))
            Text("Click a shortcut to record a new one. Esc cancels, Delete turns it off.").font(.caption).foregroundStyle(.secondary)
            ForEach(HotkeyAction.allCases) { ShortcutRecorderRow(action: $0) }
        }
    }
}

private struct BackupPage: View {
    @ObservedObject var s = AppSettings.shared
    @ObservedObject var backup = BackupManager.shared
    @State private var backups: [StoredFile] = []
    @State private var saves: [StoredFile] = []

    var body: some View {
        SettingsGroup(title: "Auto-backup", symbol: "clock.arrow.circlepath") {
            ToggleRow(title: "Auto-backup", detail: "Saves to ~/Library/Application Support/SwiftNote/Backups.", isOn: s.binding(\.autoBackupEnabled))
            IntStepperRow(title: "Every", value: s.binding(\.autoBackupMinutes), range: 1...240, unit: " min")
            Picker("Format", selection: s.binding(\.backupFormat)) {
                ForEach(DesktopBackupFormat.allCases) { Text($0.title).tag($0) }
            }
            IntStepperRow(title: "Keep last", value: s.binding(\.backupKeepCount), range: 1...500, unit: " backups")
            ToggleRow(title: "Back up when quitting", isOn: s.binding(\.backupOnQuit))
            HStack {
                Button("Back up now") { _ = backup.runBackup(manual: true); reload() }
                Text(backup.lastStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        SettingsGroup(title: "Desktop folder (iCloud)", symbol: "icloud") {
            ToggleRow(title: "Mirror to the Desktop", detail: "If iCloud Drive “Desktop & Documents” is on, this folder syncs to iCloud automatically.", isOn: s.binding(\.desktopMirrorEnabled))
            TextRow(title: "Folder name", text: s.binding(\.desktopFolderName))
            Text("The Desktop folder holds the same notes as Application Support/SwiftNote: Quick Note.md, a Notes folder with one .md per sticky note, your Saves, and notes.json.").font(.caption).foregroundStyle(.secondary)
            ToggleRow(title: "Keep timestamped history copies", isOn: s.binding(\.desktopKeepHistory))
            HStack {
                Button("Create folder") { _ = backup.createDesktopFolder() }
                Button("Open") { FileStore.openFolder(backup.desktopFolderURL) }
            }
            if !backup.desktopStatus.isEmpty { Text(backup.desktopStatus).font(.caption).foregroundStyle(.secondary) }
        }
        SettingsGroup(title: "Saved notes (.md)", symbol: "doc.text") {
            Picker("File names", selection: s.binding(\.saveFilenameStyle)) {
                Text("First line of the note").tag("firstLine"); Text("Timestamp only").tag("timestamp")
            }
            ToggleRow(title: "Add front-matter (date, word count)", isOn: s.binding(\.saveFrontMatter))
            Button("Open Saves folder") { FileStore.openFolder(AppPaths.saves) }
        }
        SettingsGroup(title: "Restore", symbol: "arrow.uturn.backward") {
            if backups.isEmpty { Text("No backups yet.").font(.caption).foregroundStyle(.secondary) }
            ForEach(backups.prefix(12)) { file in
                HStack {
                    VStack(alignment: .leading) {
                        Text(file.name).font(.system(size: 12))
                        Text("\(file.date.formatted()) · \(file.sizeString)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if file.url.pathExtension == "json" {
                        Button("Merge") { restore(file, replace: false) }
                        Button("Replace") { restore(file, replace: true) }
                    }
                    Button { FileStore.reveal(file.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(IconButtonStyle(size: 24))
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        backups = FileStore.list(AppPaths.backups).sorted { $0.date > $1.date }
    }

    private func restore(_ file: StoredFile, replace: Bool) {
        if let n = backup.restore(from: file.url, replace: replace) { ToastCenter.shared.show("Restored \(n) notes") }
        else { ToastCenter.shared.show("Couldn't read that backup") }
    }
}

private struct CalendarPage: View {
    @ObservedObject var s = AppSettings.shared
    @ObservedObject var ek = EventKitManager.shared
    var body: some View {
        SettingsGroup(title: "Access", symbol: "lock.open") {
            HStack {
                Button("Allow Calendar") { Task { await ek.requestCalendarAccess() } }
                Button("Allow Reminders") { Task { await ek.requestReminderAccess() } }
            }
        }
        SettingsGroup(title: "Calendar events", symbol: "calendar") {
            Picker("Default calendar", selection: s.binding(\.defaultCalendarID)) {
                Text("System default").tag("")
                ForEach(ek.calendars, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
            }
            IntStepperRow(title: "Event length", value: s.binding(\.eventMinutes), range: 5...480, unit: " min")
            IntStepperRow(title: "Alert before", value: s.binding(\.eventAlertMinutes), range: 0...1440, unit: " min")
        }
        SettingsGroup(title: "Reminders", symbol: "checklist") {
            Picker("Default list", selection: s.binding(\.defaultReminderListID)) {
                Text("System default").tag("")
                ForEach(ek.reminderLists, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) }
            }
            IntStepperRow(title: "Default due in", value: s.binding(\.reminderOffsetMinutes), range: 1...10080, unit: " min")
        }
        .onAppear { ek.refreshStatus() }
    }
}

private struct DataPage: View {
    @ObservedObject var s = AppSettings.shared
    @State private var confirmReset = false
    @State private var confirmWipe = false

    var body: some View {
        SettingsGroup(title: "Storage", symbol: "internaldrive") {
            row("App data", AppPaths.appSupport)
            row("Saved notes", AppPaths.saves)
            row("Backups", AppPaths.backups)
            row("Whisper models", AppPaths.models)
            row("Recordings", AppPaths.recordings)
        }
        SettingsGroup(title: "Settings", symbol: "square.and.arrow.up") {
            HStack {
                Button("Export Settings…") { exportSettings() }
                Button("Import Settings…") { importSettings() }
            }
            Button("Reset all settings", role: .destructive) { confirmReset = true }
            Button("Run welcome tour again") { Windows.onboarding.show() }
        }
        SettingsGroup(title: "Danger zone", symbol: "exclamationmark.triangle") {
            Button("Delete all notes and history", role: .destructive) { confirmWipe = true }
        }
        SettingsGroup(title: "Privacy", symbol: "lock.shield") {
            Text("Notes stay on this Mac. Audio is only sent anywhere if you choose the online Whisper API engine; Apple speech may use Apple servers unless on-device recognition is on.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Reset every setting?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { s.resetAll(keepOnboarding: true) }
        }
        .confirmationDialog("Permanently delete all notes and dictation history?", isPresented: $confirmWipe) {
            Button("Delete everything", role: .destructive) { NoteManager.shared.deleteEverything() }
        }
    }

    private func row(_ title: String, _ url: URL) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: FileStore.folderSize(url), countStyle: .file)).foregroundStyle(.secondary)
            Button { FileStore.openFolder(url) } label: { Image(systemName: "folder") }.buttonStyle(IconButtonStyle(size: 24))
        }
    }

    private func exportSettings() {
        guard let url = Panels.save(title: "Export Settings", name: "SwiftNote-Settings-\(FileStore.timestamp()).json", types: [.json]),
              let data = NoteManager.shared.exportJSONData(includeSettings: true) else { return }
        try? data.write(to: url, options: .atomic)
        ToastCenter.shared.show("Exported")
    }

    private func importSettings() {
        guard let url = Panels.chooseFile(title: "Import Settings", types: [.json]),
              let data = try? Data(contentsOf: url),
              let export = try? JSONCoders.makeDecoder().decode(SwiftNoteExport.self, from: data) else {
            ToastCenter.shared.show("That file isn't a SwiftNote export"); return
        }
        _ = NoteManager.shared.apply(export: export, replace: false, includeSettings: true)
        ToastCenter.shared.show("Imported")
    }
}
