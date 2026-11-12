//
//  MainView.swift
//  SwiftNote — the menu bar panel: editor, notes tab, quick settings.
//

import SwiftUI
import AppKit

enum PanelTab: String, CaseIterable, Identifiable {
    case editor, notes, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .editor: return "Editor"
        case .notes: return "Notes"
        case .settings: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .editor: return "square.and.pencil"
        case .notes: return "note.text"
        case .settings: return "gearshape"
        }
    }
}

struct MainNoteView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var notes = NoteManager.shared
    @StateObject private var editor = EditorController()

    @State private var tab: PanelTab = .editor
    @State private var preview = false
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            Group {
                switch tab {
                case .editor: editorTab
                case .notes: StickyNotesList().padding(12)
                case .settings: QuickSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppBackground())
        .toastOverlay()
        .onAppear {
            if settings.rememberLastTab, let saved = PanelTab(rawValue: settings.lastTab) { tab = saved }
        }
        .onChange(of: tab) { _, newValue in
            if settings.rememberLastTab { settings.lastTab = newValue.rawValue }
        }
        .onExitCommand { PanelController.shared.hide() }
        .confirmationDialog("Clear the quick note?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { clearNote() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 6) {
            ForEach(PanelTab.allCases) { t in
                Button {
                    animated { tab = t }
                } label: {
                    Label(t.title, systemImage: t.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(SoftButtonStyle(tint: settings.accentColor, prominent: tab == t))
            }
            Spacer()
            Button { Windows.help.show() } label: { Image(systemName: "questionmark.circle") }
                .buttonStyle(IconButtonStyle()).help("Help")
            Button { Windows.manager.show() } label: { Image(systemName: "macwindow") }
                .buttonStyle(IconButtonStyle()).help("Open Manager")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(IconButtonStyle(tint: .red)).help("Quit SwiftNote")
            Button { settings.panelPinned.toggle() } label: {
                Image(systemName: settings.panelPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(IconButtonStyle(tint: settings.panelPinned ? settings.accentColor : .secondary))
            .help(settings.panelPinned ? "Unpin (hides when you click away)" : "Pin (stay open)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Editor tab
    private var words: Int { notes.noteText.split { $0.isWhitespace || $0.isNewline }.count }

    private var editorTab: some View {
        VStack(spacing: 8) {
            if settings.showStats { statsRow }
            formatBar
            ZStack(alignment: .topLeading) {
                if preview {
                    ScrollView { MarkdownPreviewView(text: notes.noteText).padding(10) }
                } else {
                    NoteTextEditor(text: $notes.noteText, controller: editor, listensForFocus: true)
                    if notes.noteText.isEmpty {
                        Text("Start typing, or press the mic to dictate…")
                            .font(.system(size: CGFloat(settings.fontSize)))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.horizontal, 14).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(settings.cardOpacity)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

            EditorEventBar(noteText: notes.noteText)
            footer
        }
        .padding(12)
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            StatBadge(value: "\(words)", label: "words")
            StatBadge(value: "\(notes.noteText.count)", label: "chars")
            StatBadge(value: "\(max(1, Int((Double(words) / 200).rounded(.up))))", label: "min read")
            if settings.wordGoal > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: min(1, Double(words) / Double(settings.wordGoal)))
                    Text("Goal \(words)/\(settings.wordGoal)").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Spacer()
            }
        }
    }

    private var formatBar: some View {
        HStack(spacing: 4) {
            Group {
                fmt("bold", "Bold") { editor.wrap("**") }
                fmt("italic", "Italic") { editor.wrap("*") }
                fmt("underline", "Underline") { editor.wrap("<u>", "</u>") }
                fmt("strikethrough", "Strikethrough") { editor.wrap("~~") }
                fmt("list.bullet", "Bullets") { editor.prefixLines("- ") }
                fmt("number", "Heading") { editor.prefixLines("# ") }
                fmt("text.quote", "Quote") { editor.prefixLines("> ") }
            }
            Spacer()
            Button { animated { preview.toggle() } } label: {
                Image(systemName: preview ? "pencil" : "eye")
            }
            .buttonStyle(IconButtonStyle(tint: preview ? settings.accentColor : .secondary))
            .help(preview ? "Back to editing" : "Preview Markdown")
            DictationControls(getText: { NoteManager.shared.noteText },
                              setText: { NoteManager.shared.noteText = $0 })
        }
    }

    private func fmt(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(IconButtonStyle(size: 26))
            .help(help)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
            Button { save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .buttonStyle(SoftButtonStyle(tint: .green))
                .help("Save as a .md file in Application Support/SwiftNote/Saves")
            ShareLink(item: notes.noteText) { Label("Share", systemImage: "square.and.arrow.up") }
                .buttonStyle(SoftButtonStyle(tint: .blue))
                .disabled(notes.noteText.trimmed().isEmpty)
            Spacer()
            Button { requestClear() } label: { Label("Clear", systemImage: "trash") }
                .buttonStyle(SoftButtonStyle(tint: .red))
            Button { PanelController.shared.hide() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(IconButtonStyle()).help("Hide")
        }
        .labelStyle(.titleAndIcon)
    }

    // MARK: Actions
    private func copy() {
        guard !notes.noteText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notes.noteText, forType: .string)
        SoundManager.shared.play(.copy)
        ToastCenter.shared.show("Copied")
    }

    private func save() {
        if notes.saveQuickNote() != nil { SoundManager.shared.play(.save) }
    }

    private func requestClear() {
        guard !notes.noteText.isEmpty else { return }
        if settings.confirmClear { confirmingClear = true } else { clearNote() }
    }

    private func clearNote() {
        if settings.saveBeforeClear { _ = notes.saveQuickNote() }
        notes.noteText = ""
        SoundManager.shared.play(.clear)
    }
}
