//
//  Models.swift
//  SwiftNote — shared data models, enums and small helpers
//

import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Notification names
extension Notification.Name {
    static let updateNoteTitle        = Notification.Name("com.swiftnote.updateNoteTitle")
    static let desktopNoteTextChanged = Notification.Name("com.swiftnote.desktopNoteTextChanged")
    static let markNoteCalendar       = Notification.Name("com.swiftnote.markNoteCalendar")
    static let markNoteReminder       = Notification.Name("com.swiftnote.markNoteReminder")
    static let focusEditor            = Notification.Name("com.swiftnote.focusEditor")
}

// MARK: - Small helpers
extension String {
    var wordCountValue: Int { split(whereSeparator: { $0.isWhitespace }).count }
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard h.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }
        self.init(red: Double((rgb & 0xFF0000) >> 16) / 255,
                  green: Double((rgb & 0x00FF00) >> 8) / 255,
                  blue: Double(rgb & 0x0000FF) / 255)
    }

    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.systemBlue
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

enum JSONCoders {
    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

// MARK: - Enums
enum DictationEngine: String, CaseIterable, Identifiable {
    case apple, whisperLocal, whisperAPI
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple:        return "Apple Speech (built-in)"
        case .whisperLocal: return "Whisper — local (whisper.cpp)"
        case .whisperAPI:   return "Whisper — online API"
        }
    }
    var shortTitle: String {
        switch self {
        case .apple:        return "Apple"
        case .whisperLocal: return "Whisper local"
        case .whisperAPI:   return "Whisper API"
        }
    }
    var symbol: String {
        switch self {
        case .apple:        return "waveform"
        case .whisperLocal: return "cpu"
        case .whisperAPI:   return "cloud"
        }
    }
    var summary: String {
        switch self {
        case .apple:        return "Live words as you speak. Works offline for most languages. Nothing to install."
        case .whisperLocal: return "Runs a Whisper model on your Mac through whisper.cpp. Private and very accurate."
        case .whisperAPI:   return "Sends audio to an OpenAI-compatible or whisper.cpp server you choose."
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case liquid, frosted, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .liquid:  return "Liquid Glass"
        case .frosted: return "Frosted Glass"
        case .solid:   return "Solid"
        }
    }
    var symbol: String {
        switch self {
        case .liquid:  return "drop.fill"
        case .frosted: return "square.on.square.dashed"
        case .solid:   return "square.fill"
        }
    }
}

enum FrostedMaterial: String, CaseIterable, Identifiable {
    case hud, popover, sidebar, menu, underWindow, fullScreen, windowBackground, headerView
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hud:              return "HUD (dark, strong)"
        case .popover:          return "Popover"
        case .sidebar:          return "Sidebar"
        case .menu:             return "Menu"
        case .underWindow:      return "Under window"
        case .fullScreen:       return "Full-screen UI"
        case .windowBackground: return "Window background"
        case .headerView:       return "Header"
        }
    }
    var material: NSVisualEffectView.Material {
        switch self {
        case .hud:              return .hudWindow
        case .popover:          return .popover
        case .sidebar:          return .sidebar
        case .menu:             return .menu
        case .underWindow:      return .underWindowBackground
        case .fullScreen:       return .fullScreenUI
        case .windowBackground: return .windowBackground
        case .headerView:       return .headerView
        }
    }
}

enum NoteSortMode: String, CaseIterable, Identifiable {
    case manual, modified
    var id: String { rawValue }
    var title: String { self == .manual ? "Manual (drag to reorder)" : "Recently edited first" }
}

enum DesktopBackupFormat: String, CaseIterable, Identifiable {
    case json, markdown, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .json:     return "JSON only"
        case .markdown: return "Markdown only"
        case .both:     return "JSON + Markdown"
        }
    }
}

enum CloudTarget: String, CaseIterable, Identifiable {
    case desktop, icloudDrive, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .desktop:     return "Desktop folder (syncs if iCloud Desktop is on)"
        case .icloudDrive: return "iCloud Drive folder"
        case .custom:      return "Custom folder"
        }
    }
}

enum MenuIconKind: String, CaseIterable, Identifiable {
    case symbol, custom
    var id: String { rawValue }
}

enum EditorFontDesign: String, CaseIterable, Identifiable {
    case standard, serif, mono, rounded
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "System"
        case .serif:    return "Serif"
        case .mono:     return "Monospaced"
        case .rounded:  return "Rounded"
        }
    }
}

enum NewNoteColorMode: String, CaseIterable, Identifiable {
    case cycle, random, fixed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cycle:  return "Cycle through colors"
        case .random: return "Random color"
        case .fixed:  return "Always the same color"
        }
    }
}

enum WhisperAPIStyle: String, CaseIterable, Identifiable {
    case openAI, whisperCppServer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAI:           return "OpenAI-compatible (/audio/transcriptions)"
        case .whisperCppServer: return "whisper.cpp server (/inference)"
        }
    }
}

// MARK: - Dictation session
struct DictationSession: Codable, Identifiable {
    let id: UUID
    let date: Date
    let transcript: String
    let wordCount: Int
    let locale: String
    let engine: String?

    init(transcript: String, locale: String, engine: String) {
        self.id = UUID()
        self.date = Date()
        self.transcript = transcript
        self.wordCount = transcript.wordCountValue
        self.locale = locale
        self.engine = engine
    }
}

// MARK: - Export models
enum SettingValue: Codable, Equatable {
    case bool(Bool), int(Int), double(Double), string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v):   try c.encode(v)
        case .int(let v):    try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        }
    }

    var anyValue: Any {
        switch self {
        case .bool(let v):   return v
        case .int(let v):    return v
        case .double(let v): return v
        case .string(let v): return v
        }
    }

    init?(any: Any) {
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else if CFNumberIsFloatType(n) { self = .double(n.doubleValue) }
            else { self = .int(n.intValue) }
        } else if let s = any as? String {
            self = .string(s)
        } else {
            return nil
        }
    }
}

struct StickyNoteExport: Codable {
    let id: UUID
    let title: String
    let text: String
    let createdDate: Date
    let modifiedDate: Date?
    let colorIndex: Int
    let tags: [String]
    let isPinned: Bool
    let addedToCalendar: Bool
    let addedToReminders: Bool

    init(note n: StickyNote) {
        id = n.id; title = n.title; text = n.text
        createdDate = n.createdDate; modifiedDate = n.modifiedDate
        colorIndex = n.colorIndex; tags = n.tags; isPinned = n.isPinned
        addedToCalendar = n.addedToCalendar ?? false
        addedToReminders = n.addedToReminders ?? false
    }
}

struct SwiftNoteExport: Codable {
    let exportDate: Date
    let editorText: String
    let stickyNotes: [StickyNoteExport]
    let dictationSessions: [DictationSession]
    let settings: [String: SettingValue]?
}

// MARK: - Sticky note model
struct StickyNote: Identifiable, Codable {
    let id: UUID
    var title: String
    var text: String
    var colorIndex: Int
    let createdDate: Date
    var modifiedDate: Date
    var isPinned: Bool
    var tags: [String]
    var addedToCalendar: Bool? = nil
    var addedToReminders: Bool? = nil

    var wordCount: Int { text.wordCountValue }

    static let noteColors: [Color] = [
        Color(red: 1.0,  green: 0.98, blue: 0.85),
        Color(red: 1.0,  green: 0.9,  blue: 0.95),
        Color(red: 0.9,  green: 1.0,  blue: 0.95),
        Color(red: 0.95, green: 0.97, blue: 1.0),
        Color(red: 1.0,  green: 0.95, blue: 0.9),
        Color(red: 0.92, green: 1.0,  blue: 0.92),
        Color(red: 1.0,  green: 0.93, blue: 0.93),
    ]

    func color() -> Color { StickyNote.noteColors[abs(colorIndex) % StickyNote.noteColors.count] }
}

// MARK: - History
enum HistoryKind: String {
    case dictation, saved, backup
}

struct HistoryItem: Identifiable {
    let id: String
    let kind: HistoryKind
    let date: Date
    let title: String
    let detail: String
    let url: URL?
    let sessionID: UUID?
}

// MARK: - Files
struct StoredFile: Identifiable, Hashable {
    let url: URL
    let date: Date
    let size: Int64
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var sizeString: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

// MARK: - Shortcuts
struct CustomShortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    var readableString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + display
    }

    func serialize() -> String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func deserialize(_ string: String) -> CustomShortcut? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CustomShortcut.self, from: data)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }

    static func modifierGlyphs(from flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }

    static let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    static func displayName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 51:  return "⌫"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:  return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

enum HotkeyAction: String, CaseIterable, Identifiable {
    case startDictation, stopDictation, togglePanel, saveNote, openManager
    var id: String { rawValue }

    var hotkeyID: UInt32 {
        switch self {
        case .startDictation: return 1
        case .stopDictation:  return 2
        case .togglePanel:    return 3
        case .saveNote:       return 4
        case .openManager:    return 5
        }
    }

    var title: String {
        switch self {
        case .startDictation: return "Start / toggle dictation"
        case .stopDictation:  return "Stop dictation"
        case .togglePanel:    return "Show / hide SwiftNote"
        case .saveNote:       return "Save note as .md"
        case .openManager:    return "Open Manager"
        }
    }

    var subtitle: String {
        switch self {
        case .startDictation: return "Starts listening from any app. Press again to stop (if toggle mode is on)."
        case .stopDictation:  return "Stops and commits the current dictation."
        case .togglePanel:    return "Opens or closes the menu bar window."
        case .saveNote:       return "Writes the quick note to Application Support/SwiftNote/Saves."
        case .openManager:    return "Opens the Manager window (history, big editor, save manager)."
        }
    }

    var symbol: String {
        switch self {
        case .startDictation: return "mic.fill"
        case .stopDictation:  return "stop.fill"
        case .togglePanel:    return "rectangle.and.pencil.and.ellipsis"
        case .saveNote:       return "square.and.arrow.down"
        case .openManager:    return "macwindow"
        }
    }

    var defaultShortcut: CustomShortcut {
        let ca = UInt32(controlKey | optionKey)
        switch self {
        case .startDictation: return CustomShortcut(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: ca, display: "D")
        case .stopDictation:  return CustomShortcut(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: ca, display: "S")
        case .togglePanel:    return CustomShortcut(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: ca, display: "N")
        case .saveNote:       return CustomShortcut(keyCode: UInt32(kVK_ANSI_W), carbonModifiers: ca, display: "W")
        case .openManager:    return CustomShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: ca, display: "M")
        }
    }
}
