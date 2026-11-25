//
//  Storage.swift
//  SwiftNote — file locations, file helpers, panels
//

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Locations
enum AppPaths {
    private static var fm: FileManager { FileManager.default }

    /// ~/Library/Application Support/SwiftNote
    static var appSupport: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("SwiftNote", isDirectory: true)
        ensure(url)
        return url
    }

    static var saves: URL      { sub("Saves") }
    static var backups: URL    { sub("Backups") }
    static var models: URL     { sub("Models") }
    static var recordings: URL { sub("Recordings") }

    static var stateFile: URL      { appSupport.appendingPathComponent("notes.json") }
    static var dictationsFile: URL { appSupport.appendingPathComponent("dictations.json") }

    static func desktopFolder(named name: String) -> URL {
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let clean = FileStore.sanitize(name.isEmpty ? "Swiftnote" : name, maxLen: 60)
        return desktop.appendingPathComponent(clean, isDirectory: true)
    }

    private static func sub(_ name: String) -> URL {
        let url = appSupport.appendingPathComponent(name, isDirectory: true)
        ensure(url)
        return url
    }

    @discardableResult
    static func ensure(_ url: URL) -> Bool {
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - File helpers
enum FileStore {
    static func timestamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: date)
    }

    static func sanitize(_ raw: String, maxLen: Int = 48) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        var s = raw.components(separatedBy: illegal).joined(separator: " ")
        s = s.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix(".") { s = String(s.drop(while: { $0 == "." })) }
        if s.count > maxLen { s = String(s.prefix(maxLen)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? "Untitled" : s
    }

    static func uniqueURL(in dir: URL, base: String, ext: String) -> URL {
        var url = dir.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func list(_ dir: URL, exts: [String]? = nil) -> [StoredFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return [] }
        var out: [StoredFile] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if let exts = exts, !exts.contains(url.pathExtension.lowercased()) { continue }
            out.append(StoredFile(url: url,
                                  date: values?.contentModificationDate ?? .distantPast,
                                  size: Int64(values?.fileSize ?? 0)))
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Keep only the newest `keep` files with the given extension in a folder.
    static func prune(_ dir: URL, keep: Int, ext: String, prefix: String) {
        guard keep > 0 else { return }
        let files = list(dir, exts: [ext]).filter { $0.name.hasPrefix(prefix) }
        guard files.count > keep else { return }
        for old in files.dropFirst(keep) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    static func folderSize(_ dir: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openFolder(_ url: URL) {
        AppPaths.ensure(url)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Keeps the floating menu-bar panel from auto-closing while a modal dialog is up
@MainActor
enum PanelHold {
    static var count = 0
    static func run<T>(_ body: () -> T) -> T {
        count += 1
        defer { count -= 1 }
        return body()
    }
}

// MARK: - Open / save panels (bring the app forward first so they're never hidden)
@MainActor
enum Panels {
    static func chooseFile(title: String, types: [UTType], message: String? = nil) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        if let message = message { p.message = message }
        p.allowedContentTypes = types
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        return PanelHold.run { p.runModal() } == .OK ? p.url : nil
    }

    static func chooseAnyFile(title: String, message: String? = nil) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        if let message = message { p.message = message }
        p.canChooseDirectories = false
        p.allowsMultipleSelection = false
        p.treatsFilePackagesAsDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return PanelHold.run { p.runModal() } == .OK ? p.url : nil
    }

    static func chooseFolder(title: String) -> URL? {
        let p = NSOpenPanel()
        p.title = title
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return PanelHold.run { p.runModal() } == .OK ? p.url : nil
    }

    static func save(title: String, name: String, types: [UTType]) -> URL? {
        let p = NSSavePanel()
        p.title = title
        p.nameFieldStringValue = name
        p.allowedContentTypes = types
        p.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return PanelHold.run { p.runModal() } == .OK ? p.url : nil
    }
}
