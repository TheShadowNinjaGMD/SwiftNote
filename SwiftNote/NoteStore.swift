//
//  NoteStore.swift
//  SwiftNote — notes, saves, backups (Application Support + Desktop mirror), history
//

import Foundation
import SwiftUI
import AppKit

private struct PersistedState: Codable {
    var noteText: String
    var notes: [StickyNote]
}

// MARK: - Notes
@MainActor
final class NoteManager: ObservableObject {
    static let shared = NoteManager()

    @Published var noteText: String = "" { didSet { if !loading { scheduleSave() } } }
    @Published var notes: [StickyNote] = [] { didSet { if !loading { scheduleSave() } } }
    @Published private(set) var lastSavedTime: Date?
    @Published private(set) var dictationSessions: [DictationSession] = []

    private var loading = true
    private var saveTask: Task<Void, Never>?
    private let settings = AppSettings.shared

    private init() {
        load()
        loading = false
        installObservers()
    }

    // MARK: Derived
    var wordCount: Int { noteText.wordCountValue }
    var charCount: Int { noteText.count }
    var allTags: [String] { Array(Set(notes.flatMap { $0.tags })).sorted() }

    var sortedNotes: [StickyNote] {
        switch settings.noteSort {
        case .manual:
            return notes.filter { $0.isPinned } + notes.filter { !$0.isPinned }
        case .modified:
            return notes.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.modifiedDate > $1.modifiedDate
            }
        }
    }

    var quickNoteTitle: String {
        let line = noteText.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let t = line.trimmed()
        return t.isEmpty ? "Quick Note" : String(t.prefix(60))
    }

    // MARK: Persistence
    private func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: AppPaths.stateFile),
           let state = try? decoder.decode(PersistedState.self, from: data) {
            noteText = state.noteText
            notes = state.notes
        } else {
            // One-time migration from the old UserDefaults storage.
            let d = UserDefaults.standard
            if let s = d.string(forKey: "com.swiftnote.mainNote") { noteText = s }
            if let data = d.data(forKey: "com.swiftnote.savedNotes"),
               let old = try? decoder.decode([StickyNote].self, from: data) { notes = old }
        }
        if let data = try? Data(contentsOf: AppPaths.dictationsFile),
           let sessions = try? decoder.decode([DictationSession].self, from: data) {
            dictationSessions = sessions
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    /// Flush the current state to disk immediately.
    func writeNow() {
        saveTask?.cancel()
        let state = PersistedState(noteText: noteText, notes: notes)
        guard let data = try? JSONEncoder().encode(state) else { return }
        do {
            try data.write(to: AppPaths.stateFile, options: .atomic)
            lastSavedTime = Date()
        } catch {
            ToastCenter.shared.show("❌ Couldn't write notes: \(error.localizedDescription)")
        }
    }

    private func writeDictations() {
        if let data = try? JSONEncoder().encode(dictationSessions) {
            try? data.write(to: AppPaths.dictationsFile, options: .atomic)
        }
    }

    private func installObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .desktopNoteTextChanged, object: nil, queue: .main) { [weak self] n in
            guard let id = n.userInfo?["id"] as? UUID, let text = n.userInfo?["text"] as? String else { return }
            Task { @MainActor in self?.updateNote(id, text: text) }
        }
        nc.addObserver(forName: .markNoteCalendar, object: nil, queue: .main) { [weak self] n in
            guard let id = n.userInfo?["id"] as? UUID else { return }
            Task { @MainActor in self?.markNoteCalendar(id) }
        }
        nc.addObserver(forName: .markNoteReminder, object: nil, queue: .main) { [weak self] n in
            guard let id = n.userInfo?["id"] as? UUID else { return }
            Task { @MainActor in self?.markNoteReminder(id) }
        }
    }

    // MARK: Sticky note operations
    private func nextColorIndex() -> Int {
        let count = StickyNote.noteColors.count
        switch settings.noteColorMode {
        case "fixed":  return min(max(settings.noteFixedColor, 0), count - 1)
        case "random": return Int.random(in: 0..<count)
        default:       return notes.count % count
        }
    }

    @discardableResult
    func addNote(title: String, text: String = "") -> UUID {
        let now = Date()
        let note = StickyNote(id: UUID(), title: title, text: text, colorIndex: nextColorIndex(),
                              createdDate: now, modifiedDate: now, isPinned: false, tags: [],
                              addedToCalendar: nil, addedToReminders: nil)
        notes.insert(note, at: 0)
        return note.id
    }

    func deleteNote(_ id: UUID) { notes.removeAll { $0.id == id } }

    func duplicateNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let o = notes[idx]
        let now = Date()
        let copy = StickyNote(id: UUID(), title: "\(o.title) (copy)", text: o.text, colorIndex: o.colorIndex,
                              createdDate: now, modifiedDate: now, isPinned: false, tags: o.tags,
                              addedToCalendar: nil, addedToReminders: nil)
        notes.insert(copy, at: idx + 1)
    }

    func note(_ id: UUID) -> StickyNote? { notes.first(where: { $0.id == id }) }

    func updateNote(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].modifiedDate = Date()
    }

    func updateNoteTitle(_ id: UUID, title: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].title != title else { return }
        notes[i].title = title
        notes[i].modifiedDate = Date()
    }

    func updateNoteColor(_ id: UUID, colorIndex: Int) {
        if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].colorIndex = colorIndex }
    }

    func togglePin(_ id: UUID) {
        if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].isPinned.toggle() }
    }

    func addTag(_ tag: String, to id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        var t = tag.trimmed()
        if settings.tagsLowercase { t = t.lowercased() }
        t = t.replacingOccurrences(of: "#", with: "")
        guard !t.isEmpty, !notes[i].tags.contains(t) else { return }
        notes[i].tags.append(t)
    }

    func removeTag(_ tag: String, from id: UUID) {
        if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].tags.removeAll { $0 == tag } }
    }

    /// Drag-to-reorder: put `id` into the slot currently occupied by `target`.
    func moveNote(_ id: UUID, onto target: UUID) {
        guard id != target,
              let from = notes.firstIndex(where: { $0.id == id }),
              let to = notes.firstIndex(where: { $0.id == target }) else { return }
        let item = notes.remove(at: from)
        notes.insert(item, at: to)
    }

    func markNoteCalendar(_ id: UUID) {
        if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].addedToCalendar = true }
    }

    func markNoteReminder(_ id: UUID) {
        if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].addedToReminders = true }
    }

    // MARK: Dictation history
    func addDictationSession(_ session: DictationSession) {
        dictationSessions.append(session)
        if dictationSessions.count > 500 { dictationSessions.removeFirst(dictationSessions.count - 500) }
        writeDictations()
    }

    func deleteDictationSession(_ id: UUID) {
        dictationSessions.removeAll { $0.id == id }
        writeDictations()
    }

    func clearDictationHistory() {
        dictationSessions = []
        writeDictations()
    }

    // MARK: Saving (.md in Application Support/SwiftNote/Saves)
    @discardableResult
    func saveMarkdown(text: String, titleHint: String) -> URL? {
        let body = text.trimmed()
        guard !body.isEmpty else {
            ToastCenter.shared.show("Nothing to save yet")
            return nil
        }
        let base: String
        if settings.saveFilenameStyle == "timestamp" {
            base = "Note"
        } else {
            base = FileStore.sanitize(titleHint.isEmpty ? (body.split(separator: "\n").first.map(String.init) ?? "Note") : titleHint, maxLen: 40)
        }
        let url = FileStore.uniqueURL(in: AppPaths.saves, base: "\(base) \(FileStore.timestamp())", ext: "md")
        var out = body + "\n"
        if settings.saveFrontMatter {
            let iso = ISO8601DateFormatter().string(from: Date())
            out = "---\ntitle: \(base)\ndate: \(iso)\nwords: \(body.wordCountValue)\n---\n\n" + out
        }
        do {
            try FileStore.write(out, to: url)
            SoundManager.shared.play(.save)
            ToastCenter.shared.show("✅ Saved \(url.lastPathComponent)")
            return url
        } catch {
            ToastCenter.shared.show("❌ Couldn't save: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func saveQuickNote() -> URL? {
        saveMarkdown(text: noteText, titleHint: "")
    }

    // MARK: Export / import
    func makeExport(includeSettings: Bool) -> SwiftNoteExport {
        SwiftNoteExport(exportDate: Date(),
                        editorText: noteText,
                        stickyNotes: notes.map(StickyNoteExport.init(note:)),
                        dictationSessions: dictationSessions,
                        settings: includeSettings ? settings.exportDictionary() : nil)
    }

    func exportJSONData(includeSettings: Bool) -> Data? {
        try? JSONCoders.makeEncoder().encode(makeExport(includeSettings: includeSettings))
    }

    func markdownExport() -> String {
        var out = "# SwiftNote Export\n\n"
        if !noteText.trimmed().isEmpty { out += "## Quick Note\n\n\(noteText)\n\n---\n\n" }
        for n in sortedNotes {
            out += "## \(n.isPinned ? "📌 " : "")\(n.title)\n\n"
            if !n.tags.isEmpty { out += n.tags.map { "#\($0)" }.joined(separator: " ") + "\n\n" }
            out += n.text.isEmpty ? "_No content_\n\n" : "\(n.text)\n\n"
        }
        return out
    }

    /// Merges an export into the current data. Returns how many notes were added.
    @discardableResult
    func apply(export: SwiftNoteExport, replace: Bool, includeSettings: Bool) -> Int {
        loadingGuard {
            if replace {
                notes = []
                noteText = export.editorText
                dictationSessions = []
            }
        }
        let existing = Set(notes.map { $0.id })
        var added = 0
        for n in export.stickyNotes where !existing.contains(n.id) {
            notes.append(StickyNote(id: n.id, title: n.title, text: n.text, colorIndex: n.colorIndex,
                                    createdDate: n.createdDate, modifiedDate: n.modifiedDate ?? n.createdDate,
                                    isPinned: n.isPinned, tags: n.tags,
                                    addedToCalendar: n.addedToCalendar ? true : nil,
                                    addedToReminders: n.addedToReminders ? true : nil))
            added += 1
        }
        let known = Set(dictationSessions.map { $0.id })
        dictationSessions.append(contentsOf: export.dictationSessions.filter { !known.contains($0.id) })
        writeDictations()
        if !replace, noteText.trimmed().isEmpty, !export.editorText.isEmpty { noteText = export.editorText }
        if includeSettings, let dict = export.settings { settings.importDictionary(dict) }
        writeNow()
        return added
    }

    private func loadingGuard(_ body: () -> Void) {
        body()
    }

    func deleteEverything() {
        notes = []
        noteText = ""
        dictationSessions = []
        writeDictations()
        writeNow()
    }
}

// MARK: - Backups
@MainActor
final class BackupManager: ObservableObject {
    static let shared = BackupManager()

    @Published private(set) var lastBackup: Date?
    @Published private(set) var lastStatus: String = "No backup yet this session"
    @Published private(set) var desktopStatus: String = ""

    private var timer: Timer?
    private var signature = ""

    private init() {}

    var iCloudSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    var desktopFolderURL: URL { AppPaths.desktopFolder(named: AppSettings.shared.desktopFolderName) }

    /// (Re)starts the timer from the current settings. Safe to call as often as you like.
    func configure() {
        let s = AppSettings.shared
        let sig = "\(s.autoBackupEnabled)-\(s.autoBackupMinutes)-\(s.onboardingCompleted)"
        guard sig != signature else { return }
        signature = sig
        timer?.invalidate()
        timer = nil
        guard s.autoBackupEnabled, s.onboardingCompleted else { return }
        let interval = TimeInterval(max(1, s.autoBackupMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.runBackup(manual: false) }
        }
    }

    @discardableResult
    func runBackup(manual: Bool) -> Bool {
        let s = AppSettings.shared
        let notes = NoteManager.shared
        notes.writeNow()

        guard let json = notes.exportJSONData(includeSettings: true) else {
            lastStatus = "❌ Couldn't encode backup"
            if manual { ToastCenter.shared.show(lastStatus) }
            return false
        }
        let md = notes.markdownExport()
        let stamp = FileStore.timestamp()
        let dir = AppPaths.backups

        do {
            if s.backupFormat != .markdown {
                try json.write(to: dir.appendingPathComponent("SwiftNote-backup-\(stamp).json"), options: .atomic)
            }
            if s.backupFormat != .json {
                try FileStore.write(md, to: dir.appendingPathComponent("SwiftNote-backup-\(stamp).md"))
            }
            FileStore.prune(dir, keep: s.backupKeepCount, ext: "json", prefix: "SwiftNote-backup-")
            FileStore.prune(dir, keep: s.backupKeepCount, ext: "md", prefix: "SwiftNote-backup-")
            try writeNotesTree(into: AppPaths.appSupport)
        } catch {
            lastStatus = "❌ Backup failed: \(error.localizedDescription)"
            if manual { ToastCenter.shared.show(lastStatus) }
            return false
        }

        if s.desktopMirrorEnabled { mirrorToDesktop(json: json, markdown: md, stamp: stamp) }

        lastBackup = Date()
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        lastStatus = "✅ Backed up at \(time)"
        if manual { ToastCenter.shared.show("✅ Backup saved") }
        return true
    }


    /// Writes Quick Note.md and one .md per sticky note into `root` (used for Application Support and the Desktop mirror).
    private func writeNotesTree(into root: URL) throws {
        let quick = NoteManager.shared.noteText
        if !quick.trimmed().isEmpty {
            try FileStore.write(quick + "\n", to: root.appendingPathComponent("Quick Note.md"))
        }
        let notesDir = root.appendingPathComponent("Notes", isDirectory: true)
        AppPaths.ensure(notesDir)
        var written = Set<String>()
        for n in NoteManager.shared.notes {
            let fileName = "\(FileStore.sanitize(n.title, maxLen: 40)) (\(n.id.uuidString.prefix(4))).md"
            var body = "# \(n.title)\n\n"
            if !n.tags.isEmpty { body += n.tags.map { "#\($0)" }.joined(separator: " ") + "\n\n" }
            body += n.text + "\n"
            try FileStore.write(body, to: notesDir.appendingPathComponent(fileName))
            written.insert(fileName)
        }
        // Remove files for notes that no longer exist (only files that match our naming pattern).
        if let existing = try? FileManager.default.contentsOfDirectory(atPath: notesDir.path) {
            let pattern = try? NSRegularExpression(pattern: "\\([0-9A-Fa-f]{4}\\)\\.md$")
            for name in existing where !written.contains(name) {
                let range = NSRange(name.startIndex..., in: name)
                if pattern?.firstMatch(in: name, range: range) != nil {
                    try? FileManager.default.removeItem(at: notesDir.appendingPathComponent(name))
                }
            }
        }
    }

    /// Copies the saved .md files and notes.json so the Desktop folder holds the same notes as Application Support.
    private func copyAppSupportContents(to folder: URL) throws {
        let fm = FileManager.default
        let saves = folder.appendingPathComponent("Saves", isDirectory: true)
        AppPaths.ensure(saves)
        for f in FileStore.list(AppPaths.saves, exts: ["md"]) {
            let dest = saves.appendingPathComponent(f.name)
            if let a = try? fm.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date, a >= f.date { continue }
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: f.url, to: dest)
        }
        let state = AppPaths.stateFile
        if fm.fileExists(atPath: state.path) {
            let dest = folder.appendingPathComponent("notes.json")
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: state, to: dest)
        }
    }

    private func mirrorToDesktop(json: Data, markdown: String, stamp: String) {
        let s = AppSettings.shared
        let folder = desktopFolderURL
        guard AppPaths.ensure(folder) else {
            desktopStatus = "⚠️ Couldn't create ~/Desktop/\(folder.lastPathComponent). Allow Desktop access in System Settings → Privacy & Security → Files & Folders → SwiftNote."
            return
        }
        do {
            try json.write(to: folder.appendingPathComponent("SwiftNote-latest.json"), options: .atomic)
            try FileStore.write(markdown, to: folder.appendingPathComponent("SwiftNote-latest.md"))

            try writeNotesTree(into: folder)
            try copyAppSupportContents(to: folder)

            if s.desktopKeepHistory {
                let hist = folder.appendingPathComponent("Backups", isDirectory: true)
                AppPaths.ensure(hist)
                try json.write(to: hist.appendingPathComponent("SwiftNote-backup-\(stamp).json"), options: .atomic)
                FileStore.prune(hist, keep: s.backupKeepCount, ext: "json", prefix: "SwiftNote-backup-")
            }

            let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            desktopStatus = "✅ Mirrored to ~/Desktop/\(folder.lastPathComponent) at \(time)"
        } catch {
            desktopStatus = "⚠️ Desktop write failed: \(error.localizedDescription)"
        }
    }

    /// Creates the Desktop folder right away (used by onboarding so the permission prompt appears at a sensible moment).
    @discardableResult
    func createDesktopFolder() -> Bool {
        let ok = AppPaths.ensure(desktopFolderURL)
        desktopStatus = ok ? "✅ ~/Desktop/\(desktopFolderURL.lastPathComponent) is ready"
                           : "⚠️ Couldn't create the Desktop folder — allow Desktop access in System Settings."
        return ok
    }

    func restore(from url: URL, replace: Bool) -> Int? {
        guard let data = try? Data(contentsOf: url),
              let export = try? JSONCoders.makeDecoder().decode(SwiftNoteExport.self, from: data) else { return nil }
        return NoteManager.shared.apply(export: export, replace: replace, includeSettings: false)
    }
}

// MARK: - History
@MainActor
enum HistoryBuilder {
    static func items() -> [HistoryItem] {
        var out: [HistoryItem] = []

        for s in NoteManager.shared.dictationSessions {
            let preview = s.transcript.replacingOccurrences(of: "\n", with: " ")
            out.append(HistoryItem(id: "d-\(s.id.uuidString)", kind: .dictation, date: s.date,
                                   title: String(preview.prefix(90)),
                                   detail: "\(s.wordCount) words · \(s.engine ?? "apple") · \(s.locale)",
                                   url: nil, sessionID: s.id))
        }
        for f in FileStore.list(AppPaths.saves, exts: ["md"]) {
            out.append(HistoryItem(id: "s-\(f.url.path)", kind: .saved, date: f.date,
                                   title: f.url.deletingPathExtension().lastPathComponent,
                                   detail: f.sizeString, url: f.url, sessionID: nil))
        }
        for f in FileStore.list(AppPaths.backups, exts: ["json"]) {
            out.append(HistoryItem(id: "b-\(f.url.path)", kind: .backup, date: f.date,
                                   title: f.name, detail: f.sizeString, url: f.url, sessionID: nil))
        }
        return out.sorted { $0.date > $1.date }
    }
}
