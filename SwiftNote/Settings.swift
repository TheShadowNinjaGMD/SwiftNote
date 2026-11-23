//
//  Settings.swift
//  SwiftNote — single source of truth for every user preference.
//
//  Every preference lives in UserDefaults under the same name as the property, so
//  Export/Import Settings, Reset and the Advanced Settings window all work on one store.
//

import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard
    private init() {}

    // MARK: Storage helpers
    private func get<T>(_ key: String, _ fallback: T) -> T { (d.object(forKey: key) as? T) ?? fallback }
    private func put<T>(_ key: String, _ value: T) {
        objectWillChange.send()
        d.set(value, forKey: key)
    }

    // MARK: General
    var onboardingCompleted: Bool { get { get("onboardingCompleted", false) } set { put("onboardingCompleted", newValue) } }
    var showInDock: Bool { get { get("showInDock", false) } set { put("showInDock", newValue) } }
    var openManagerOnLaunch: Bool { get { get("openManagerOnLaunch", false) } set { put("openManagerOnLaunch", newValue) } }
    var panelWidth: Double { get { get("panelWidth", 520.0) } set { put("panelWidth", newValue) } }
    var panelHeight: Double { get { get("panelHeight", 720.0) } set { put("panelHeight", newValue) } }
    var panelPinned: Bool { get { get("panelPinned", false) } set { put("panelPinned", newValue) } }
    var focusEditorOnOpen: Bool { get { get("focusEditorOnOpen", true) } set { put("focusEditorOnOpen", newValue) } }
    var showToasts: Bool { get { get("showToasts", true) } set { put("showToasts", newValue) } }
    var animationsEnabled: Bool { get { get("animationsEnabled", true) } set { put("animationsEnabled", newValue) } }
    var closePanelOnClickOutside: Bool { get { get("closePanelOnClickOutside", true) } set { put("closePanelOnClickOutside", newValue) } }
    var panelGap: Double { get { get("panelGap", 6.0) } set { put("panelGap", newValue) } }
    var rememberLastTab: Bool { get { get("rememberLastTab", true) } set { put("rememberLastTab", newValue) } }
    var lastTab: String { get { get("lastTab", "editor") } set { put("lastTab", newValue) } }
    var hideFromScreenShare: Bool { get { get("hideFromScreenShare", false) } set { put("hideFromScreenShare", newValue) } }
    var toastSeconds: Double { get { get("toastSeconds", 2.5) } set { put("toastSeconds", newValue) } }

    // MARK: Appearance
    var appearanceSync: Bool { get { get("appearanceSync", true) } set { put("appearanceSync", newValue) } }
    var isDarkMode: Bool { get { get("isDarkMode", false) } set { put("isDarkMode", newValue) } }
    var accentHex: String { get { get("accentHex", "#4A90E2") } set { put("accentHex", newValue) } }
    var backgroundStyleRaw: String { get { get("backgroundStyleRaw", BackgroundStyle.liquid.rawValue) } set { put("backgroundStyleRaw", newValue) } }
    var frostedMaterialRaw: String { get { get("frostedMaterialRaw", FrostedMaterial.popover.rawValue) } set { put("frostedMaterialRaw", newValue) } }
    var glassTint: Double { get { get("glassTint", 0.08) } set { put("glassTint", newValue) } }
    var glassCornerRadius: Double { get { get("glassCornerRadius", 24.0) } set { put("glassCornerRadius", newValue) } }
    var editorFontDesign: String { get { get("editorFontDesign", EditorFontDesign.standard.rawValue) } set { put("editorFontDesign", newValue) } }
    /// 0.15 = very see-through, 1 = fully frosted.
    var glassOpacity: Double { get { get("glassOpacity", 0.85) } set { put("glassOpacity", newValue) } }
    var accentTintGlass: Bool { get { get("accentTintGlass", false) } set { put("accentTintGlass", newValue) } }
    var liquidClear: Bool { get { get("liquidClear", false) } set { put("liquidClear", newValue) } }
    var cardOpacity: Double { get { get("cardOpacity", 0.06) } set { put("cardOpacity", newValue) } }
    var glassControls: Bool { get { get("glassControls", true) } set { put("glassControls", newValue) } }

    var backgroundStyle: BackgroundStyle {
        get { BackgroundStyle(rawValue: backgroundStyleRaw) ?? .liquid }
        set { backgroundStyleRaw = newValue.rawValue }
    }
    var frostedMaterial: FrostedMaterial {
        get { FrostedMaterial(rawValue: frostedMaterialRaw) ?? .popover }
        set { frostedMaterialRaw = newValue.rawValue }
    }
    var accentColor: Color { Color(hex: accentHex) ?? .blue }

    /// nil = follow the system appearance.
    var preferredScheme: ColorScheme? {
        appearanceSync ? nil : (isDarkMode ? .dark : .light)
    }
    var nsAppearance: NSAppearance? {
        appearanceSync ? nil : NSAppearance(named: isDarkMode ? .darkAqua : .aqua)
    }

    // MARK: Menu bar icon
    var menuIconKind: String { get { get("menuIconKind", "symbol") } set { put("menuIconKind", newValue) } }
    var menuIconSymbol: String { get { get("menuIconSymbol", "square.and.pencil") } set { put("menuIconSymbol", newValue) } }
    var menuIconCustomFile: String { get { get("menuIconCustomFile", "") } set { put("menuIconCustomFile", newValue) } }
    var menuIconSize: Double { get { get("menuIconSize", 16.0) } set { put("menuIconSize", newValue) } }
    var menuIconTemplate: Bool { get { get("menuIconTemplate", true) } set { put("menuIconTemplate", newValue) } }
    var menuIconShowCount: Bool { get { get("menuIconShowCount", false) } set { put("menuIconShowCount", newValue) } }

    // MARK: Editor
    var fontSize: Double { get { get("fontSize", 14.0) } set { put("fontSize", newValue) } }
    var lineSpacing: Double { get { get("lineSpacing", 3.0) } set { put("lineSpacing", newValue) } }
    var editorBold: Bool { get { get("editorBold", false) } set { put("editorBold", newValue) } }
    var editorItalic: Bool { get { get("editorItalic", false) } set { put("editorItalic", newValue) } }
    var editorUnderline: Bool { get { get("editorUnderline", false) } set { put("editorUnderline", newValue) } }
    var editorStrike: Bool { get { get("editorStrike", false) } set { put("editorStrike", newValue) } }
    var wordGoal: Int { get { get("wordGoal", 0) } set { put("wordGoal", newValue) } }
    var showStats: Bool { get { get("showStats", true) } set { put("showStats", newValue) } }
    var liveMarkdown: Bool { get { get("liveMarkdown", true) } set { put("liveMarkdown", newValue) } }
    var spellCheck: Bool { get { get("spellCheck", true) } set { put("spellCheck", newValue) } }
    var smartQuotes: Bool { get { get("smartQuotes", false) } set { put("smartQuotes", newValue) } }
    var autoCorrect: Bool { get { get("autoCorrect", false) } set { put("autoCorrect", newValue) } }
    var confirmClear: Bool { get { get("confirmClear", true) } set { put("confirmClear", newValue) } }
    var saveBeforeClear: Bool { get { get("saveBeforeClear", true) } set { put("saveBeforeClear", newValue) } }

    // MARK: Notes
    var noteColorMode: String { get { get("noteColorMode", "cycle") } set { put("noteColorMode", newValue) } }
    var noteFixedColor: Int { get { get("noteFixedColor", 0) } set { put("noteFixedColor", newValue) } }
    var noteCardLines: Int { get { get("noteCardLines", 2) } set { put("noteCardLines", newValue) } }
    var compactNotes: Bool { get { get("compactNotes", false) } set { put("compactNotes", newValue) } }
    var noteSortRaw: String { get { get("noteSortRaw", NoteSortMode.manual.rawValue) } set { put("noteSortRaw", newValue) } }
    var confirmDeleteNote: Bool { get { get("confirmDeleteNote", false) } set { put("confirmDeleteNote", newValue) } }
    var showNoteStats: Bool { get { get("showNoteStats", true) } set { put("showNoteStats", newValue) } }
    var showNoteDates: Bool { get { get("showNoteDates", true) } set { put("showNoteDates", newValue) } }
    var tagsLowercase: Bool { get { get("tagsLowercase", true) } set { put("tagsLowercase", newValue) } }
    var stickyAlwaysOnTop: Bool { get { get("stickyAlwaysOnTop", true) } set { put("stickyAlwaysOnTop", newValue) } }
    var stickyWidth: Double { get { get("stickyWidth", 240.0) } set { put("stickyWidth", newValue) } }
    var stickyHeight: Double { get { get("stickyHeight", 180.0) } set { put("stickyHeight", newValue) } }
    var stickyOpacity: Double { get { get("stickyOpacity", 0.97) } set { put("stickyOpacity", newValue) } }

    var noteSort: NoteSortMode {
        get { NoteSortMode(rawValue: noteSortRaw) ?? .manual }
        set { noteSortRaw = newValue.rawValue }
    }

    // MARK: Dictation
    var dictationEnabled: Bool { get { get("dictationEnabled", true) } set { put("dictationEnabled", newValue) } }
    var dictationEngineRaw: String { get { get("dictationEngineRaw", DictationEngine.apple.rawValue) } set { put("dictationEngineRaw", newValue) } }
    var dictationLocale: String { get { get("dictationLocale", "en-US") } set { put("dictationLocale", newValue) } }
    var appleOnDevice: Bool { get { get("appleOnDevice", true) } set { put("appleOnDevice", newValue) } }
    var appleAutoPunctuation: Bool { get { get("appleAutoPunctuation", true) } set { put("appleAutoPunctuation", newValue) } }
    var appleHints: String { get { get("appleHints", "") } set { put("appleHints", newValue) } }
    var micGate: Double { get { get("micGate", 0.015) } set { put("micGate", newValue) } }
    var fillerRemoval: Bool { get { get("fillerRemoval", true) } set { put("fillerRemoval", newValue) } }
    var fillerWords: String { get { get("fillerWords", "umm, um, err, er, uh, ah") } set { put("fillerWords", newValue) } }
    var voicePunctuation: Bool { get { get("voicePunctuation", true) } set { put("voicePunctuation", newValue) } }
    var voiceMacros: Bool { get { get("voiceMacros", true) } set { put("voiceMacros", newValue) } }
    var voiceAllCaps: Bool { get { get("voiceAllCaps", true) } set { put("voiceAllCaps", newValue) } }
    var autoCapitalise: Bool { get { get("autoCapitalise", true) } set { put("autoCapitalise", newValue) } }
    var dictationMaxSeconds: Int { get { get("dictationMaxSeconds", 0) } set { put("dictationMaxSeconds", newValue) } }
    var dictationSaveHistory: Bool { get { get("dictationSaveHistory", true) } set { put("dictationSaveHistory", newValue) } }
    var startHotkeyToggles: Bool { get { get("startHotkeyToggles", true) } set { put("startHotkeyToggles", newValue) } }

    var dictationEngine: DictationEngine {
        get { DictationEngine(rawValue: dictationEngineRaw) ?? .apple }
        set { dictationEngineRaw = newValue.rawValue }
    }

    // MARK: Whisper (local + API)
    var whisperBinaryPath: String { get { get("whisperBinaryPath", "") } set { put("whisperBinaryPath", newValue) } }
    var whisperModelPath: String { get { get("whisperModelPath", "") } set { put("whisperModelPath", newValue) } }
    var whisperThreads: Int { get { get("whisperThreads", 4) } set { put("whisperThreads", newValue) } }
    var whisperLanguage: String { get { get("whisperLanguage", "auto") } set { put("whisperLanguage", newValue) } }
    var whisperTranslate: Bool { get { get("whisperTranslate", false) } set { put("whisperTranslate", newValue) } }
    var whisperPrompt: String { get { get("whisperPrompt", "") } set { put("whisperPrompt", newValue) } }
    var whisperExtraArgs: String { get { get("whisperExtraArgs", "") } set { put("whisperExtraArgs", newValue) } }
    var whisperChunkSeconds: Int { get { get("whisperChunkSeconds", 0) } set { put("whisperChunkSeconds", newValue) } }
    var whisperAPIBaseURL: String { get { get("whisperAPIBaseURL", "https://api.openai.com/v1") } set { put("whisperAPIBaseURL", newValue) } }
    var whisperAPIModel: String { get { get("whisperAPIModel", "whisper-1") } set { put("whisperAPIModel", newValue) } }
    var whisperAPILanguage: String { get { get("whisperAPILanguage", "") } set { put("whisperAPILanguage", newValue) } }
    var whisperAPIPrompt: String { get { get("whisperAPIPrompt", "") } set { put("whisperAPIPrompt", newValue) } }
    var whisperAPITemperature: Double { get { get("whisperAPITemperature", 0.0) } set { put("whisperAPITemperature", newValue) } }
    var whisperAPITimeout: Int { get { get("whisperAPITimeout", 60) } set { put("whisperAPITimeout", newValue) } }

    // MARK: Hotkeys
    var hotkeysEnabled: Bool { get { get("hotkeysEnabled", true) } set { put("hotkeysEnabled", newValue) } }

    /// nil = this action is switched off. Empty stored string = use the default.
    func shortcut(for action: HotkeyAction) -> CustomShortcut? {
        let raw: String = get("hotkey.\(action.rawValue)", "")
        if raw == "off" { return nil }
        if raw.isEmpty { return action.defaultShortcut }
        return CustomShortcut.deserialize(raw) ?? action.defaultShortcut
    }
    func setShortcut(_ shortcut: CustomShortcut?, for action: HotkeyAction) {
        put("hotkey.\(action.rawValue)", shortcut?.serialize() ?? "off")
    }
    func resetShortcut(for action: HotkeyAction) {
        put("hotkey.\(action.rawValue)", "")
    }
    func isShortcutCustom(_ action: HotkeyAction) -> Bool {
        let raw: String = get("hotkey.\(action.rawValue)", "")
        return !raw.isEmpty
    }

    // MARK: Backup
    var autoBackupEnabled: Bool { get { get("autoBackupEnabled", true) } set { put("autoBackupEnabled", newValue) } }
    var autoBackupMinutes: Int { get { get("autoBackupMinutes", 5) } set { put("autoBackupMinutes", newValue) } }
    var backupFormatRaw: String { get { get("backupFormatRaw", DesktopBackupFormat.both.rawValue) } set { put("backupFormatRaw", newValue) } }
    var backupKeepCount: Int { get { get("backupKeepCount", 50) } set { put("backupKeepCount", newValue) } }
    var backupOnQuit: Bool { get { get("backupOnQuit", true) } set { put("backupOnQuit", newValue) } }
    var desktopMirrorEnabled: Bool { get { get("desktopMirrorEnabled", true) } set { put("desktopMirrorEnabled", newValue) } }
    var desktopFolderName: String { get { get("desktopFolderName", "Swiftnote") } set { put("desktopFolderName", newValue) } }
    var desktopMirrorIndividualNotes: Bool { get { get("desktopMirrorIndividualNotes", true) } set { put("desktopMirrorIndividualNotes", newValue) } }
    var desktopKeepHistory: Bool { get { get("desktopKeepHistory", false) } set { put("desktopKeepHistory", newValue) } }

    var backupFormat: DesktopBackupFormat {
        get { DesktopBackupFormat(rawValue: backupFormatRaw) ?? .both }
        set { backupFormatRaw = newValue.rawValue }
    }

    // MARK: Saves
    var saveFilenameStyle: String { get { get("saveFilenameStyle", "firstLine") } set { put("saveFilenameStyle", newValue) } }
    var saveFrontMatter: Bool { get { get("saveFrontMatter", false) } set { put("saveFrontMatter", newValue) } }

    // MARK: Sound
    var soundEnabled: Bool { get { get("soundEnabled", true) } set { put("soundEnabled", newValue) } }
    var soundVolume: Double { get { get("soundVolume", 0.6) } set { put("soundVolume", newValue) } }
    var disabledSounds: String { get { get("disabledSounds", "keyTap") } set { put("disabledSounds", newValue) } }

    func isSoundDisabled(_ raw: String) -> Bool {
        disabledSounds.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.contains(raw)
    }
    func setSound(_ raw: String, enabled: Bool) {
        var set = Set(disabledSounds.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        if enabled { set.remove(raw) } else { set.insert(raw) }
        disabledSounds = set.sorted().joined(separator: ",")
    }

    // MARK: Calendar & Reminders
    var eventMinutes: Int { get { get("eventMinutes", 60) } set { put("eventMinutes", newValue) } }
    var eventAlertMinutes: Int { get { get("eventAlertMinutes", 10) } set { put("eventAlertMinutes", newValue) } }
    var reminderOffsetMinutes: Int { get { get("reminderOffsetMinutes", 60) } set { put("reminderOffsetMinutes", newValue) } }
    var defaultCalendarID: String { get { get("defaultCalendarID", "") } set { put("defaultCalendarID", newValue) } }
    var defaultReminderListID: String { get { get("defaultReminderListID", "") } set { put("defaultReminderListID", newValue) } }

    // MARK: Export / import / reset
    private static let ignoredPrefixes = ["NS", "Apple", "AK", "com.", "PK", "SU", "INNext", "MSV", "TSM", "WebKit", "AddingEmoji", "Settings"]
    private static let transientKeys: Set<String> = ["onboardingCompleted", "lastBackupTime"]

    private func ownKeys() -> [String] {
        d.dictionaryRepresentation().keys.filter { key in
            !Self.ignoredPrefixes.contains(where: { key.hasPrefix($0) })
        }
    }

    func exportDictionary() -> [String: SettingValue] {
        var out: [String: SettingValue] = [:]
        let all = d.dictionaryRepresentation()
        for key in ownKeys() where !Self.transientKeys.contains(key) {
            if let value = all[key], let sv = SettingValue(any: value) { out[key] = sv }
        }
        return out
    }

    func importDictionary(_ dict: [String: SettingValue]) {
        for (key, value) in dict where !Self.transientKeys.contains(key) {
            d.set(value.anyValue, forKey: key)
        }
        objectWillChange.send()
    }

    func resetAll(keepOnboarding: Bool = true) {
        let done = onboardingCompleted
        for key in ownKeys() { d.removeObject(forKey: key) }
        if keepOnboarding { d.set(done, forKey: "onboardingCompleted") }
        objectWillChange.send()
    }
}
