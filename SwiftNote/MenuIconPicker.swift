//
//  MenuIconPicker.swift
//  SwiftNote — menu bar icon picker with SF Symbol search and custom SVG/PNG import.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Binding helper
extension AppSettings {
    func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}

// MARK: - SF Symbol catalogue
enum SymbolCatalog {
    static let presets: [String] = [
        "square.and.pencil", "note.text", "pencil", "pencil.line", "doc.text", "bolt.fill", "bolt.circle",
        "star.fill", "heart.fill", "bookmark.fill", "tray.full", "mic.fill", "waveform", "text.cursor",
        "paperplane.fill", "lightbulb.fill", "flame.fill", "leaf.fill", "sparkles", "pin.fill", "folder.fill"
    ]

    private static let fallback: [String] = [
        "pencil", "pencil.tip", "pencil.circle", "highlighter", "note", "note.text", "note.text.badge.plus",
        "doc", "doc.text", "doc.richtext", "doc.plaintext", "book", "book.closed", "books.vertical",
        "bookmark", "bookmark.fill", "tag", "tag.fill", "folder", "folder.fill", "tray", "tray.full",
        "paperplane", "paperplane.fill", "envelope", "envelope.fill", "bell", "bell.fill", "calendar",
        "clock", "alarm", "timer", "stopwatch", "mic", "mic.fill", "waveform", "waveform.circle",
        "speaker.wave.2", "music.note", "headphones", "star", "star.fill", "heart", "heart.fill",
        "flag", "flag.fill", "bolt", "bolt.fill", "bolt.circle", "flame", "flame.fill", "leaf", "leaf.fill",
        "drop", "drop.fill", "moon", "moon.fill", "sun.max", "sun.max.fill", "cloud", "cloud.fill",
        "sparkles", "wand.and.stars", "lightbulb", "lightbulb.fill", "brain", "brain.head.profile",
        "bubble.left", "bubble.left.fill", "text.bubble", "quote.bubble", "text.alignleft", "textformat",
        "list.bullet", "checklist", "checkmark.circle", "checkmark.square", "square.and.pencil",
        "square.and.arrow.down", "square.grid.2x2", "circle.grid.2x2", "hexagon", "diamond", "triangle",
        "square", "circle", "capsule", "pin", "pin.fill", "paperclip", "link", "globe", "house", "house.fill",
        "magnifyingglass", "gearshape", "slider.horizontal.3", "hammer", "wrench", "scissors",
        "camera", "photo", "film", "gamecontroller", "cube", "shippingbox", "cart", "gift", "crown",
        "key", "lock", "eye", "hand.raised", "hand.thumbsup", "person", "person.2", "figure.walk",
        "airplane", "car", "bicycle", "bus", "tram", "map", "location", "compass.drawing", "mappin"
    ]

    /// Every public symbol name macOS ships (read from the system symbol metadata), with a curated fallback.
    static let all: [String] = {
        let base = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/"
        for file in ["symbol_search.plist", "name_availability.plist"] {
            let url = URL(fileURLWithPath: base + file)
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { continue }
            var names: [String] = []
            if let dict = plist as? [String: Any] {
                if let symbols = dict["symbols"] as? [String: Any] { names = Array(symbols.keys) }
                else { names = Array(dict.keys) }
            }
            names = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            if names.count > 100 { return names.sorted() }
        }
        return fallback
    }()

    /// Keyword hints so "write" finds pencil and so on.
    static let keywords: [String: [String]] = [
        "pencil": ["write", "edit", "draw"], "note": ["memo", "text", "sticky"], "doc": ["file", "page", "paper"],
        "mic": ["voice", "dictate", "audio", "record"], "bolt": ["quick", "fast", "swift", "lightning", "power"],
        "star": ["favorite", "rating"], "bookmark": ["save", "read"], "tray": ["inbox", "archive"],
        "paperplane": ["send", "swift"], "lightbulb": ["idea", "tip"], "flame": ["fire", "hot"],
        "leaf": ["nature", "plant"], "sparkles": ["magic", "ai", "new"], "pin": ["keep", "attach"]
    ]

    static func search(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        let words = q.split(separator: " ").map(String.init)
        return all.filter { name in
            let hay = name.lowercased()
            let extra = keywords.filter { hay.contains($0.key) }.flatMap { $0.value }
            return words.allSatisfy { w in hay.contains(w) || extra.contains { $0.hasPrefix(w) } }
        }
    }
}

// MARK: - Symbol browser sheet
struct SymbolPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var results: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 8)]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Choose an SF Symbol").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search symbols (e.g. pencil, bolt, mic, idea)", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))

            Text("\(results.count) symbols").font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(results.prefix(600), id: \.self) { name in
                        Button { selection = name } label: {
                            Image(systemName: name)
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(selection == name ? settings.accentColor.opacity(0.25) : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            Text(selection).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 460, height: 480)
        .onAppear { results = SymbolCatalog.search(query) }
        .onChange(of: query) { _, q in results = SymbolCatalog.search(q) }
    }
}

// MARK: - Menu icon picker
struct MenuIconPicker: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showBrowser = false
    @State private var symbolDraft = ""
    @State private var presetFilter = ""

    private var kind: MenuIconKind { MenuIconKind(rawValue: settings.menuIconKind) ?? .symbol }
    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 40), spacing: 6)]

    private var filteredPresets: [String] {
        presetFilter.isEmpty ? SymbolCatalog.presets : SymbolCatalog.search(presetFilter).prefix(42).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: Binding(
                get: { kind },
                set: { settings.menuIconKind = $0.rawValue })) {
                Text("SF Symbol").tag(MenuIconKind.symbol)
                Text("Custom SVG / Image").tag(MenuIconKind.custom)
            }
            .pickerStyle(.segmented).labelsHidden()

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    previewImage
                        .frame(width: 64, height: 64)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
                    Text("Preview").font(.caption2).foregroundStyle(.secondary)
                }
                if kind == .symbol { symbolControls } else { customControls }
            }

            HStack {
                Text("Size").font(.caption)
                Slider(value: settings.binding(\.menuIconSize), in: 12...24, step: 1)
                Text("\(Int(settings.menuIconSize)) pt").font(.caption.monospacedDigit()).frame(width: 40)
            }
            Toggle("Tint to match the menu bar (template image)", isOn: settings.binding(\.menuIconTemplate))
                .font(.caption)
                .disabled(kind == .symbol)
        }
        .sheet(isPresented: $showBrowser) {
            SymbolPickerSheet(selection: settings.binding(\.menuIconSymbol))
        }
        .onAppear { symbolDraft = settings.menuIconSymbol }
        .onChange(of: settings.menuIconSymbol) { _, v in symbolDraft = v }
    }

    @ViewBuilder private var previewImage: some View {
        if kind == .custom, let img = MenuIcon.customImage(path: settings.menuIconCustomFile, size: 40, template: true) {
            Image(nsImage: img).renderingMode(settings.menuIconTemplate ? .template : .original)
                .foregroundStyle(.primary)
        } else {
            Image(systemName: NSImage(systemSymbolName: settings.menuIconSymbol, accessibilityDescription: nil) != nil
                  ? settings.menuIconSymbol : MenuIcon.fallbackSymbol)
                .font(.system(size: 30))
        }
    }

    private var symbolControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Symbol name", text: $symbolDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { apply() }
                Button("Apply") { apply() }.buttonStyle(SoftButtonStyle(tint: settings.accentColor))
                Button("Browse All…") { showBrowser = true }.buttonStyle(SoftButtonStyle(tint: .purple))
            }
            TextField("Search presets…", text: $presetFilter).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(filteredPresets, id: \.self) { name in
                        Button { settings.menuIconSymbol = name } label: {
                            Image(systemName: name).font(.system(size: 15))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(settings.menuIconSymbol == name ? settings.accentColor.opacity(0.28) : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain).help(name)
                    }
                }
            }
            .frame(height: 112)
        }
    }

    private var customControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if let url = Panels.chooseFile(title: "Choose menu bar artwork",
                                               types: [.svg, .png, .pdf, .jpeg, .tiff],
                                               message: "SVG or a square PNG works best. Simple one-colour shapes suit the menu bar.") {
                    MenuIcon.importArtwork(from: url)
                }
            } label: { Label("Import SVG / Image…", systemImage: "square.and.arrow.down") }
            .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
            Text(settings.menuIconCustomFile.isEmpty ? "No custom icon imported yet."
                 : URL(fileURLWithPath: settings.menuIconCustomFile).lastPathComponent)
                .font(.caption).foregroundStyle(.secondary)
            Text("The file is copied into Application Support/SwiftNote so it keeps working if you move the original.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func apply() {
        let name = symbolDraft.trimmingCharacters(in: .whitespaces)
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            settings.menuIconSymbol = name
        } else {
            ToastCenter.shared.show("“\(name)” isn't an SF Symbol on this Mac")
        }
    }
}
