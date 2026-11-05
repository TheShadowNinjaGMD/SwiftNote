//
//  ManagerView.swift
//  SwiftNote — the Dock-mode management window.
//

import SwiftUI
import AppKit

enum ManagerSection: String, CaseIterable, Identifiable {
    case write, notes, history, saves
    var id: String { rawValue }
    var title: String {
        switch self {
        case .write: return "Write"
        case .notes: return "Notes"
        case .history: return "History"
        case .saves: return "Save Manager"
        }
    }
    var symbol: String {
        switch self {
        case .write: return "square.and.pencil"
        case .notes: return "note.text"
        case .history: return "clock.arrow.circlepath"
        case .saves: return "externaldrive"
        }
    }
}

struct ManagerView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var section: ManagerSection = .write

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.4)
            Group {
                switch section {
                case .write: ManagerWriteView()
                case .notes: ManagerNotesView()
                case .history: ManagerHistoryView()
                case .saves: SaveManagerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground(cornerRadius: 0).ignoresSafeArea())
        .toastOverlay()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SwiftNote").font(.title3.bold()).padding(.horizontal, 12).padding(.top, 36).padding(.bottom, 8)
            ForEach(ManagerSection.allCases) { s in
                Button { animated { section = s } } label: {
                    Label(s.title, systemImage: s.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(section == s ? settings.accentColor.opacity(0.22) : .clear))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { Windows.advanced.show() } label: { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).padding(10)
            Button { Windows.help.show() } label: { Label("Help", systemImage: "questionmark.circle").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 6)
            Button { NSApp.terminate(nil) } label: { Label("Quit app", systemImage: "power").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).foregroundStyle(.red).padding(.horizontal, 10).padding(.bottom, 12)
        }
        .padding(.horizontal, 8)
        .frame(width: 190)
    }
}

// MARK: - Write
struct ManagerWriteView: View {
    @ObservedObject private var notes = NoteManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var editor = EditorController()

    private var words: Int { notes.noteText.split { $0.isWhitespace || $0.isNewline }.count }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Quick note").font(.title2.bold())
                Spacer()
                Text("\(words) words · \(notes.noteText.count) characters").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                fmt("bold") { editor.wrap("**") }
                fmt("italic") { editor.wrap("*") }
                fmt("underline") { editor.wrap("<u>", "</u>") }
                fmt("strikethrough") { editor.wrap("~~") }
                fmt("list.bullet") { editor.prefixLines("- ") }
                fmt("text.quote") { editor.prefixLines("> ") }
                Spacer()
                DictationControls(getText: { NoteManager.shared.noteText }, setText: { NoteManager.shared.noteText = $0 })
            }
            NoteTextEditor(text: $notes.noteText, controller: editor, listensForFocus: false)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(settings.cardOpacity)))
            EditorEventBar(noteText: notes.noteText)
            HStack {
                Button { _ = notes.saveQuickNote() } label: { Label("Save as .md", systemImage: "square.and.arrow.down") }
                    .buttonStyle(SoftButtonStyle(tint: .green))
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(notes.noteText, forType: .string)
                    ToastCenter.shared.show("Copied")
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
                Button {
                    let t = notes.noteText.trimmed()
                    guard !t.isEmpty else { return }
                    notes.addNote(title: String(t.split(separator: "\n").first?.prefix(40) ?? "Note"), text: t)
                    ToastCenter.shared.show("Added as a sticky note")
                } label: { Label("Make sticky note", systemImage: "note.text.badge.plus") }
                    .buttonStyle(SoftButtonStyle(tint: .orange))
                Spacer()
                Button { notes.noteText = "" } label: { Label("Clear", systemImage: "trash") }
                    .buttonStyle(SoftButtonStyle(tint: .red))
            }
        }
        .padding(20)
    }

    private func fmt(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }.buttonStyle(IconButtonStyle(size: 26))
    }
}

// MARK: - Notes (list + detail)
struct ManagerNotesView: View {
    @ObservedObject private var notes = NoteManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var selected: UUID?
    @State private var search = ""

    private var filtered: [StickyNote] {
        let q = search.lowercased()
        return notes.sortedNotes.filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.text.lowercased().contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search notes", text: $search).textFieldStyle(.plain)
                    Button { selected = notes.addNote(title: "New note") } label: { Image(systemName: "plus") }
                        .buttonStyle(IconButtonStyle(size: 24))
                }
                .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filtered) { n in
                            Button { selected = n.id } label: {
                                HStack(alignment: .top) {
                                    Circle().fill(n.color()).frame(width: 10, height: 10).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(n.title.isEmpty ? "Untitled" : n.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                            if n.isPinned { Image(systemName: "pin.fill").font(.caption2) }
                                        }
                                        Text(n.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(selected == n.id ? settings.accentColor.opacity(0.2) : Color.primary.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14).frame(width: 290)
            Divider().opacity(0.4)
            if let id = selected, let note = notes.note(id) {
                NoteDetail(note: note, onDelete: { selected = nil })
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "note.text").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Select or create a note").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct NoteDetail: View {
    let note: StickyNote
    let onDelete: () -> Void
    @ObservedObject private var notes = NoteManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var editor = EditorController()
    @State private var tagDraft = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Title", text: Binding(get: { notes.note(note.id)?.title ?? "" },
                                                 set: { notes.updateNoteTitle(note.id, title: $0) }))
                    .textFieldStyle(.plain).font(.title2.bold())
                Button { notes.togglePin(note.id) } label: { Image(systemName: note.isPinned ? "pin.fill" : "pin") }
                    .buttonStyle(IconButtonStyle())
                Button { notes.duplicateNote(note.id) } label: { Image(systemName: "plus.square.on.square") }
                    .buttonStyle(IconButtonStyle())
                Button { DesktopStickyManager.shared.showSticky(note: note) } label: { Image(systemName: "rectangle.on.rectangle") }
                    .buttonStyle(IconButtonStyle()).help("Show as a desktop sticky")
                Button { notes.deleteNote(note.id); onDelete() } label: { Image(systemName: "trash") }
                    .buttonStyle(IconButtonStyle(tint: .red))
            }
            HStack(spacing: 6) {
                ForEach(0..<StickyNote.noteColors.count, id: \.self) { i in
                    Button { notes.updateNoteColor(note.id, colorIndex: i) } label: {
                        Circle().fill(StickyNote.noteColors[i]).frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(note.colorIndex == i ? 0.8 : 0.15), lineWidth: 1.5))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            NoteTextEditor(text: Binding(get: { notes.note(note.id)?.text ?? "" },
                                         set: { notes.updateNote(note.id, text: $0) }), controller: editor)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(settings.cardOpacity)))
            HStack {
                ForEach(note.tags, id: \.self) { tag in
                    Button { notes.removeTag(tag, from: note.id) } label: { Text("#\(tag) ✕").font(.caption) }
                        .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
                }
                TextField("add tag", text: $tagDraft).textFieldStyle(.roundedBorder).frame(width: 110)
                    .onSubmit { notes.addTag(tagDraft, to: note.id); tagDraft = "" }
                Spacer()
                DictationControls(getText: { notes.note(note.id)?.text ?? "" }, setText: { notes.updateNote(note.id, text: $0) })
                Text("\(note.wordCount) words").font(.caption).foregroundStyle(.secondary)
            }
            EditorEventBar(noteText: note.text)
        }
        .padding(20)
        .id(note.id)
    }
}

// MARK: - History
struct ManagerHistoryView: View {
    @ObservedObject private var notes = NoteManager.shared
    @State private var items: [HistoryItem] = []
    @State private var filter: HistoryKind? = nil
    @State private var query = ""

    private var shown: [HistoryItem] {
        items.filter { (filter == nil || $0.kind == filter) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("History").font(.title2.bold())
                Spacer()
                Button("Refresh") { reload() }
            }
            HStack {
                Picker("", selection: $filter) {
                    Text("All").tag(HistoryKind?.none)
                    Text("Dictations").tag(HistoryKind?.some(.dictation))
                    Text("Saved").tag(HistoryKind?.some(.saved))
                    Text("Backups").tag(HistoryKind?.some(.backup))
                }.pickerStyle(.segmented).labelsHidden()
                TextField("Search", text: $query).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            List(shown) { item in row(item) }.scrollContentBackground(.hidden)
        }
        .padding(20)
        .onAppear { reload() }
        .onReceive(notes.objectWillChange) { _ in DispatchQueue.main.async { reload() } }
    }

    private func reload() { items = HistoryBuilder.items() }

    private func icon(_ k: HistoryKind) -> String {
        switch k { case .dictation: return "mic.fill"; case .saved: return "doc.text"; case .backup: return "externaldrive" }
    }

    private func row(_ item: HistoryItem) -> some View {
        HStack {
            Image(systemName: icon(item.kind)).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(2)
                Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(item.detail)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch item.kind {
            case .dictation:
                if let id = item.sessionID, let s = notes.dictationSessions.first(where: { $0.id == id }) {
                    Button("Insert") { notes.noteText += (notes.noteText.isEmpty ? "" : "\n") + s.transcript; ToastCenter.shared.show("Inserted into the quick note") }
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s.transcript, forType: .string) }
                    Button { notes.deleteDictationSession(id); reload() } label: { Image(systemName: "trash") }.buttonStyle(IconButtonStyle(tint: .red, size: 24))
                }
            case .saved:
                if let url = item.url {
                    Button("Load") {
                        if let t = try? String(contentsOf: url, encoding: .utf8) { notes.noteText = t; ToastCenter.shared.show("Loaded into the quick note") }
                    }
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.app") }.buttonStyle(IconButtonStyle(size: 24))
                    Button { FileStore.reveal(url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(IconButtonStyle(size: 24))
                }
            case .backup:
                if let url = item.url {
                    Button("Merge") { _ = BackupManager.shared.restore(from: url, replace: false); reload() }
                    Button("Replace") { _ = BackupManager.shared.restore(from: url, replace: true); reload() }
                    Button { FileStore.reveal(url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(IconButtonStyle(size: 24))
                }
            }
        }
    }
}

// MARK: - Save manager
struct SaveManagerView: View {
    @ObservedObject private var backup = BackupManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var saves: [StoredFile] = []
    @State private var backups: [StoredFile] = []
    @State private var desktop: [StoredFile] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Save Manager").font(.title2.bold())
                    Spacer()
                    Button { _ = backup.runBackup(manual: true); reload() } label: { Label("Back up now", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(SoftButtonStyle(tint: .green))
                }
                Text(backup.lastStatus).font(.caption).foregroundStyle(.secondary)
                group("Saved notes (.md)", saves, AppPaths.saves)
                group("Backups", backups, AppPaths.backups)
                group("Desktop mirror — ~/Desktop/\(settings.desktopFolderName)", desktop, backup.desktopFolderURL)
            }
            .padding(20)
        }
        .onAppear { reload() }
    }

    private func reload() {
        saves = FileStore.list(AppPaths.saves).sorted { $0.date > $1.date }
        backups = FileStore.list(AppPaths.backups).sorted { $0.date > $1.date }
        desktop = FileStore.list(backup.desktopFolderURL).sorted { $0.date > $1.date }
    }

    private func group(_ title: String, _ files: [StoredFile], _ folder: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(title: "\(title) · \(files.count)")
                Spacer()
                Button("Open folder") { FileStore.openFolder(folder) }.buttonStyle(.plain).foregroundStyle(settings.accentColor)
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    if files.isEmpty { Text("Nothing here yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(files.prefix(25)) { f in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(f.name).font(.system(size: 12)).lineLimit(1)
                                Text("\(f.date.formatted()) · \(f.sizeString)").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { NSWorkspace.shared.open(f.url) } label: { Image(systemName: "arrow.up.forward.app") }.buttonStyle(IconButtonStyle(size: 24))
                            Button { FileStore.reveal(f.url) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(IconButtonStyle(size: 24))
                            Button { try? FileManager.default.trashItem(at: f.url, resultingItemURL: nil); reload() } label: { Image(systemName: "trash") }
                                .buttonStyle(IconButtonStyle(tint: .red, size: 24))
                        }
                    }
                }
            }
        }
    }
}
