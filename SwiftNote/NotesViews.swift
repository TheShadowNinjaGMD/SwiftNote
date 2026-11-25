//
//  NotesViews.swift
//  SwiftNote — Calendar / Reminder sheets, the sticky notes list, note cards,
//  filter bar, desktop stickies.
//

import SwiftUI
import AppKit
import EventKit
import UniformTypeIdentifiers

// MARK: - Calendar sheet
struct CalendarEventSheet: View {
    let initialTitle: String
    let notes: String
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ek = EventKitManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var calendarID = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(.blue)
                Text("New Calendar Event").font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            if ek.calendarAuthStatus != .fullAccess {
                accessBanner
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.caption).foregroundStyle(.secondary)
                TextField("Event title", text: $title).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Starts").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $start).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ends").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $end, in: start...).labelsHidden()
                }
            }
            if !ek.calendars.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $calendarID) {
                        Text("Default").tag("")
                        ForEach(ek.calendars, id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(cal.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Adding…" : "Add Event") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmed().isEmpty || saving)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            title = initialTitle
            start = Date().addingTimeInterval(3600)
            end = start.addingTimeInterval(Double(max(5, settings.eventMinutes)) * 60)
            calendarID = settings.defaultCalendarID
            ek.refreshStatus()
        }
    }

    private var accessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("SwiftNote needs Calendar access.").font(.caption)
            Spacer()
            Button("Allow") { Task { await ek.requestCalendarAccess() } }
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private func save() {
        saving = true
        Task {
            let ok = await ek.addCalendarEvent(title: title.trimmed(), notes: notes, startDate: start, endDate: end,
                                               calendarID: calendarID.isEmpty ? nil : calendarID)
            saving = false
            if ok {
                SoundManager.shared.play(.calendar)
                onSaved()
                dismiss()
            }
        }
    }
}

// MARK: - Reminder sheet
struct ReminderSheet: View {
    let initialTitle: String
    let notes: String
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ek = EventKitManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var title = ""
    @State private var hasDate = true
    @State private var due = Date().addingTimeInterval(3600)
    @State private var listID = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.orange)
                Text("New Reminder").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            if ek.reminderAuthStatus != .fullAccess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("SwiftNote needs Reminders access.").font(.caption)
                    Spacer()
                    Button("Allow") { Task { await ek.requestReminderAccess() } }.controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Title").font(.caption).foregroundStyle(.secondary)
                TextField("Reminder title", text: $title).textFieldStyle(.roundedBorder)
            }
            Toggle("Due date", isOn: $hasDate.animation())
            if hasDate {
                DatePicker("", selection: $due).labelsHidden()
            }
            if !ek.reminderLists.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("List").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $listID) {
                        Text("Default").tag("")
                        ForEach(ek.reminderLists, id: \.calendarIdentifier) { list in
                            Text(list.title).tag(list.calendarIdentifier)
                        }
                    }
                    .labelsHidden()
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "Adding…" : "Add Reminder") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmed().isEmpty || saving)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            title = initialTitle
            due = Date().addingTimeInterval(Double(max(1, settings.reminderOffsetMinutes)) * 60)
            listID = settings.defaultReminderListID
            ek.refreshStatus()
        }
    }

    private func save() {
        saving = true
        Task {
            let ok = await ek.addReminder(title: title.trimmed(), notes: notes, dueDate: hasDate ? due : nil,
                                          listID: listID.isEmpty ? nil : listID)
            saving = false
            if ok {
                SoundManager.shared.play(.reminder)
                onSaved()
                dismiss()
            }
        }
    }
}

// MARK: - "Add to Calendar / Reminder" bar for the quick note
struct EditorEventBar: View {
    let noteText: String
    @State private var showCalendar = false
    @State private var showReminder = false

    private var firstLine: String {
        String((noteText.split(separator: "\n").first.map(String.init) ?? "").prefix(60))
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Add to").font(.caption2).foregroundStyle(.secondary)
            Button { showCalendar = true } label: { Label("Calendar", systemImage: "calendar") }
                .buttonStyle(SoftButtonStyle(tint: .blue))
            Button { showReminder = true } label: { Label("Reminder", systemImage: "bell.fill") }
                .buttonStyle(SoftButtonStyle(tint: .orange))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(isPresented: $showCalendar) { CalendarEventSheet(initialTitle: firstLine, notes: noteText) }
        .sheet(isPresented: $showReminder) { ReminderSheet(initialTitle: firstLine, notes: noteText) }
    }
}

// MARK: - Drag & drop reorder
struct NoteDropDelegate: DropDelegate {
    let target: UUID
    let enabled: Bool
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard enabled, let d = dragging, d != target else { return }
        withAnimation(.easeInOut(duration: 0.2)) { NoteManager.shared.moveNote(d, onto: target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: enabled ? .move : .cancel) }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return enabled
    }
}

// MARK: - Sticky notes list (menu bar panel)
struct StickyNotesList: View {
    @ObservedObject private var notes = NoteManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var newTitle = ""
    @State private var filterText = ""
    @State private var filterColor: Int? = nil
    @State private var filterTag: String? = nil
    @State private var showPinnedOnly = false
    @State private var hoveredID: UUID?
    @State private var draggingID: UUID?

    private var filtersActive: Bool {
        !filterText.isEmpty || filterColor != nil || filterTag != nil || showPinnedOnly
    }
    private var reorderEnabled: Bool {
        settings.noteSort == .manual && !settings.compactNotes && !filtersActive
    }

    private var filtered: [StickyNote] {
        notes.sortedNotes.filter { n in
            let text = filterText.isEmpty
                || n.title.localizedCaseInsensitiveContains(filterText)
                || n.text.localizedCaseInsensitiveContains(filterText)
            let color = filterColor == nil || n.colorIndex % StickyNote.noteColors.count == filterColor
            let tag = filterTag == nil || (filterTag.map { n.tags.contains($0) } ?? true)
            let pinned = !showPinnedOnly || n.isPinned
            return text && color && tag && pinned
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            addBar
            FilterBar(filterText: $filterText, filterColor: $filterColor, filterTag: $filterTag, allTags: notes.allTags)
            Divider().opacity(0.4)
            ScrollView {
                if filtered.isEmpty {
                    emptyState
                } else if settings.compactNotes {
                    FlowLayout(spacing: 8) {
                        ForEach(filtered) { note in CompactPill(note: note) }
                    }
                    .padding(12)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { note in
                            NoteCard(note: note,
                                     hovered: hoveredID == note.id,
                                     reorderEnabled: reorderEnabled,
                                     onHover: { hoveredID = $0 ? note.id : (hoveredID == note.id ? nil : hoveredID) },
                                     onDragStart: {
                                         draggingID = note.id
                                         return NSItemProvider(object: note.id.uuidString as NSString)
                                     })
                            .onDrop(of: [UTType.text], delegate: NoteDropDelegate(target: note.id, enabled: reorderEnabled, dragging: $draggingID))
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField("New note title…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassControl(in: RoundedRectangle(cornerRadius: 10, style: .continuous), interactive: false)
                .onSubmit(add)

            Button(action: add) {
                Image(systemName: "plus.circle.fill").font(.system(size: 19))
            }
            .buttonStyle(.plain)
            .foregroundStyle(newTitle.trimmed().isEmpty ? Color.secondary : settings.accentColor)
            .disabled(newTitle.trimmed().isEmpty)
            .help("Add note")

            Button { animated { showPinnedOnly.toggle() } } label: {
                Image(systemName: showPinnedOnly ? "pin.fill" : "pin")
            }
            .buttonStyle(IconButtonStyle(tint: showPinnedOnly ? settings.accentColor : .secondary))
            .help(showPinnedOnly ? "Show all notes" : "Show pinned only")

            Button { animated { settings.noteSort = settings.noteSort == .manual ? .modified : .manual } } label: {
                Image(systemName: settings.noteSort == .manual ? "hand.draw" : "clock.arrow.circlepath")
            }
            .buttonStyle(IconButtonStyle(tint: settings.accentColor))
            .help(settings.noteSort == .manual ? "Manual order — drag the grip to reorder" : "Recently edited first")

            Button { animated { settings.compactNotes.toggle() } } label: {
                Image(systemName: settings.compactNotes ? "rectangle.grid.1x2.fill" : "square.grid.2x2")
            }
            .buttonStyle(IconButtonStyle(tint: settings.compactNotes ? settings.accentColor : .secondary))
            .help(settings.compactNotes ? "Card view" : "Compact view")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: filtersActive ? "magnifyingglass" : "note.text")
                .font(.system(size: 34))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(filtersActive ? "No matching notes" : "No notes yet").font(.callout).foregroundStyle(.secondary)
            if !filtersActive {
                Text("Type a title above and press Return to create your first sticky note.")
                    .font(.caption).foregroundStyle(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    private func add() {
        let title = newTitle.trimmed()
        guard !title.isEmpty else { return }
        SoundManager.shared.play(.noteAdded)
        notes.addNote(title: title)
        newTitle = ""
    }
}

// MARK: - Filter bar
struct FilterBar: View {
    @Binding var filterText: String
    @Binding var filterColor: Int?
    @Binding var filterTag: String?
    let allTags: [String]
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField("Filter notes…", text: $filterText).textFieldStyle(.plain).font(.system(size: 12))
                if !filterText.isEmpty {
                    Button { filterText = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Divider().frame(height: 14)
                ForEach(0..<StickyNote.noteColors.count, id: \.self) { idx in
                    let selected = filterColor == idx
                    Circle()
                        .fill(StickyNote.noteColors[idx])
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Color.primary.opacity(selected ? 0.7 : 0.18), lineWidth: selected ? 2 : 1))
                        .scaleEffect(selected ? 1.15 : 1)
                        .onTapGesture { animated { filterColor = selected ? nil : idx } }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if !allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allTags, id: \.self) { tag in
                            let selected = filterTag == tag
                            Button { animated { filterTag = selected ? nil : tag } } label: {
                                Text("#\(tag)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(selected ? Color.white : settings.accentColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(selected ? settings.accentColor : settings.accentColor.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
        }
    }
}

// MARK: - Compact pill
struct CompactPill: View {
    let note: StickyNote
    @ObservedObject private var settings = AppSettings.shared
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            if note.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(settings.accentColor)
            }
            Text(note.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.14))
                .lineLimit(1)
            if hovered {
                Button { NoteManager.shared.togglePin(note.id); SoundManager.shared.play(.pin) } label: {
                    Image(systemName: note.isPinned ? "pin.slash" : "pin").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain).foregroundStyle(settings.accentColor)
                Button { SoundManager.shared.play(.noteDeleted); NoteManager.shared.deleteNote(note.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain).foregroundStyle(Color.black.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(note.color().opacity(0.92)))
        .overlay(Capsule().stroke(note.isPinned ? settings.accentColor.opacity(0.5) : Color.primary.opacity(hovered ? 0.25 : 0.12),
                                  lineWidth: note.isPinned ? 1.5 : 1))
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }
}

// MARK: - Flow layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Note card
struct NoteCard: View {
    let note: StickyNote
    let hovered: Bool
    let reorderEnabled: Bool
    let onHover: (Bool) -> Void
    let onDragStart: () -> NSItemProvider

    @ObservedObject private var settings = AppSettings.shared
    @State private var expanded = false
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var showTagField = false
    @State private var tagDraft = ""
    @State private var showCalendar = false
    @State private var showReminder = false

    private let ink = Color(red: 0.10, green: 0.10, blue: 0.14)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow
            titleRow
            if note.isPinned { pinnedLabel }
            contentArea
            if !note.tags.isEmpty { tagChips }
            if showTagField { tagField }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(note.color().opacity(0.93)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(note.isPinned ? settings.accentColor.opacity(0.55) : Color.primary.opacity(hovered ? 0.28 : 0.14),
                    lineWidth: note.isPinned ? 2 : 1))
        .shadow(color: .black.opacity(note.isPinned ? 0.18 : 0.10), radius: note.isPinned ? 6 : 3, y: 1)
        .onHover { onHover($0) }
        .sheet(isPresented: $showCalendar) {
            CalendarEventSheet(initialTitle: note.title, notes: note.text) {
                NotificationCenter.default.post(name: .markNoteCalendar, object: nil, userInfo: ["id": note.id])
            }
        }
        .sheet(isPresented: $showReminder) {
            ReminderSheet(initialTitle: note.title, notes: note.text) {
                NotificationCenter.default.post(name: .markNoteReminder, object: nil, userInfo: ["id": note.id])
            }
        }
    }

    // MARK: Rows
    private var metaRow: some View {
        HStack(spacing: 6) {
            if reorderEnabled {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.4))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onDrag { onDragStart() }
                    .help("Drag to reorder")
            }
            if settings.showNoteDates {
                Label { Text(note.createdDate, style: .date) } icon: { Image(systemName: "calendar") }
                    .font(.system(size: 10))
                    .foregroundStyle(.black.opacity(0.5))
            }
            if note.addedToCalendar == true {
                Image(systemName: "calendar.badge.checkmark").font(.system(size: 10)).foregroundStyle(.blue)
            }
            if note.addedToReminders == true {
                Image(systemName: "bell.badge.fill").font(.system(size: 10)).foregroundStyle(.orange)
            }
            if settings.showNoteStats, note.wordCount > 0 {
                Text("\(note.wordCount)w")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.07)))
            }
            Spacer(minLength: 4)
            if hovered || expanded { actions }
        }
        .frame(minHeight: 20)
    }

    private var actions: some View {
        HStack(spacing: 5) {
            ForEach(0..<StickyNote.noteColors.count, id: \.self) { idx in
                Circle()
                    .fill(StickyNote.noteColors[idx])
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.black.opacity(note.colorIndex % StickyNote.noteColors.count == idx ? 0.6 : 0.15), lineWidth: 1))
                    .onTapGesture { NoteManager.shared.updateNoteColor(note.id, colorIndex: idx) }
            }
            actionButton(note.isPinned ? "pin.slash.fill" : "pin.fill", tint: settings.accentColor,
                         help: note.isPinned ? "Unpin" : "Pin to top") {
                NoteManager.shared.togglePin(note.id); SoundManager.shared.play(.pin)
            }
            actionButton("tag.fill", tint: .green, help: "Add tag") { animated { showTagField.toggle() } }
            actionButton("doc.on.doc.fill", tint: .blue, help: "Duplicate") {
                SoundManager.shared.play(.duplicate); NoteManager.shared.duplicateNote(note.id)
            }
            actionButton("macwindow.badge.plus", tint: .purple, help: "Stick to desktop") {
                DesktopStickyManager.shared.showSticky(note: note)
            }
            actionButton("calendar.badge.plus", tint: .blue, help: "Add to Calendar") { showCalendar = true }
            actionButton("bell.badge.fill", tint: .orange, help: "Set a reminder") { showReminder = true }
            actionButton("trash.fill", tint: .red, help: "Delete") { delete() }
        }
        .transition(.opacity)
    }

    private func actionButton(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(tint) }
            .buttonStyle(.plain)
            .help(help)
    }

    @ViewBuilder
    private var titleRow: some View {
        if editingTitle {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(ink)
                .onSubmit {
                    NoteManager.shared.updateNoteTitle(note.id, title: titleDraft.trimmed().isEmpty ? note.title : titleDraft.trimmed())
                    editingTitle = false
                }
        } else {
            Text(note.title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(ink)
                .onTapGesture(count: 2) { titleDraft = note.title; editingTitle = true }
        }
    }

    private var pinnedLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill").font(.system(size: 8))
            Text("Pinned").font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(settings.accentColor)
    }

    @ViewBuilder
    private var contentArea: some View {
        if expanded {
            VStack(alignment: .trailing, spacing: 6) {
                NoteTextEditor(text: Binding(get: { note.text }, set: { NoteManager.shared.updateNote(note.id, text: $0) }),
                               forceLight: true)
                    .frame(height: 140)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.55)))
                HStack(spacing: 8) {
                    DictationControls(getText: { note.text }, setText: { NoteManager.shared.updateNote(note.id, text: $0) })
                    Spacer()
                    Button("Done") { animated { expanded = false } }
                        .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
                }
            }
        } else {
            Text(note.text.isEmpty ? AttributedString("Click to write…") : MarkdownInline.attributed(note.text))
                .font(.system(size: 12.5))
                .lineLimit(max(1, settings.noteCardLines))
                .foregroundStyle(note.text.isEmpty ? ink.opacity(0.4) : ink.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { animated { expanded = true } }
        }
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(note.tags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text("#\(tag)").font(.system(size: 9.5, weight: .medium))
                        if hovered || expanded {
                            Button { NoteManager.shared.removeTag(tag, from: note.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color(red: 0.35, green: 0.55, blue: 0.75).opacity(0.85)))
                }
            }
        }
    }

    private var tagField: some View {
        HStack(spacing: 6) {
            TextField("Add tag…", text: $tagDraft).textFieldStyle(.roundedBorder).font(.system(size: 11)).onSubmit(commitTag)
            Button(action: commitTag) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }.buttonStyle(.plain)
            Button { tagDraft = ""; showTagField = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
        }
    }

    private func commitTag() {
        if !tagDraft.trimmed().isEmpty { NoteManager.shared.addTag(tagDraft, to: note.id) }
        tagDraft = ""
        showTagField = false
    }

    private func delete() {
        if settings.confirmDeleteNote {
            let alert = NSAlert()
            alert.messageText = "Delete “\(note.title)”?"
            alert.informativeText = "This can't be undone."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            guard PanelHold.run({ alert.runModal() }) == .alertFirstButtonReturn else { return }
        }
        SoundManager.shared.play(.noteDeleted)
        NoteManager.shared.deleteNote(note.id)
    }
}

// MARK: - Desktop sticky note (floating window)
struct DesktopStickyView: View {
    let noteID: UUID
    let onClose: () -> Void
    @ObservedObject private var notes = NoteManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var editor = EditorController()

    var body: some View {
        if let note = notes.note(noteID) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(note.color().opacity(settings.stickyOpacity))
                VStack(alignment: .leading, spacing: 6) {
                    // Header doubles as the drag handle.
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11)).foregroundStyle(.black.opacity(0.35))
                        Text(note.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.12))
                            .lineLimit(1)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.black.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .help("Close this sticky (the note is kept)")
                    }
                    .padding(.vertical, 2)
                    .background(WindowDragHandle())
                    Divider().opacity(0.4)
                    NoteTextEditor(text: Binding(get: { notes.note(noteID)?.text ?? "" },
                                                 set: { notes.updateNote(noteID, text: $0) }),
                                   controller: editor, forceLight: true)
                }
                .padding(12)

                // Resize grip (the whole window edge also resizes).
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.3))
                    .rotationEffect(.degrees(90))
                    .padding(6)
                    .allowsHitTesting(false)
            }
            .environment(\.colorScheme, .light)
            .frame(minWidth: 160, minHeight: 120)
        } else {
            Color.clear.onAppear(perform: onClose)
        }
    }
}

/// An invisible strip that lets the user drag the window from any non-interactive part of a SwiftUI header.
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Inline Markdown for read-only previews
enum MarkdownInline {
    /// Renders **bold**, *italic*, `code`, ~~strike~~ and links; falls back to plain text if parsing fails.
    static func attributed(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        let prepared = text.replacingOccurrences(of: "<u>", with: "").replacingOccurrences(of: "</u>", with: "")
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(text)
    }
}
