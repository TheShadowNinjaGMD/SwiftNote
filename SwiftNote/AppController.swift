//
//  AppController.swift
//  SwiftNote — app delegate, menu bar item + floating glass panel, window controllers,
//  global hotkey wiring and dock mode.
//

import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

// MARK: - Themed root (colour scheme + accent for every window)
struct ThemedRoot<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    private let content: Content

    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .preferredColorScheme(settings.preferredScheme)
            .tint(settings.accentColor)
            .toggleStyle(.switch)
    }
}

// MARK: - Floating panel (the menu bar window)
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        Task { @MainActor in
            if DictationManager.shared.isRecording {
                DictationManager.shared.stop()
            } else {
                PanelController.shared.hide()
            }
        }
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    private(set) var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private let settings = AppSettings.shared

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: Status item
    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshIcon()
    }

    func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let result = MenuIcon.make(settings: settings)
        button.image = result.image
        if settings.menuIconShowCount {
            button.imagePosition = .imageLeading
            button.title = " \(NoteManager.shared.notes.count)"
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
        }
        button.toolTip = "SwiftNote"
    }

    @objc private func statusClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isContext = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false)
        if isContext { showContextMenu() } else { toggle() }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add("Show SwiftNote", #selector(menuShow))
        add("Open Manager", #selector(menuManager))
        add("Advanced Settings…", #selector(menuSettings))
        menu.addItem(.separator())
        add("Check for Updates…", #selector(menuUpdates))
        add("View on GitHub", #selector(menuGitHub))
        if let github = menu.items.last, let img = NSImage(named: "GitHubMark") {
            img.size = NSSize(width: 14, height: 14); img.isTemplate = true; github.image = img
        }
        menu.addItem(.separator())
        add("Quit SwiftNote", #selector(menuQuit))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuShow() { show() }
    @objc private func menuManager() { Windows.manager.show() }
    @objc private func menuSettings() { Windows.advanced.show() }
    @objc private func menuUpdates() { UpdateManager.shared.checkForUpdates() }
    @objc private func menuGitHub() { AppLinks.openRepo() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Panel
    private func makePanel() -> FloatingPanel {
        let p = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: settings.panelWidth, height: settings.panelHeight),
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self
        p.contentView = NSHostingView(rootView: ThemedRoot { MainNoteView() })
        return p
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if panel == nil { panel = makePanel() }
        guard let p = panel else { return }

        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(CGFloat(settings.panelWidth), visible.width - 16),
                          height: min(CGFloat(settings.panelHeight), visible.height - 16))
        p.setContentSize(size)
        p.sharingType = settings.hideFromScreenShare ? .none : .readOnly
        p.setFrameOrigin(origin(for: size, visible: visible))

        NSApp.activate(ignoringOtherApps: true)
        if settings.animationsEnabled {
            p.alphaValue = 0
            p.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                p.animator().alphaValue = 1
            }
        } else {
            p.alphaValue = 1
            p.makeKeyAndOrderFront(nil)
        }
        if settings.focusEditorOnOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                NotificationCenter.default.post(name: .focusEditor, object: nil)
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Settings that can change while the panel exists.
    func applyLiveSettings() {
        panel?.sharingType = settings.hideFromScreenShare ? .none : .readOnly
    }

    private func origin(for size: NSSize, visible: NSRect) -> NSPoint {
        let gap = CGFloat(settings.panelGap)
        if let button = statusItem?.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let onScreen = NSScreen.screens.contains { $0.frame.intersects(rect) }
            if onScreen {
                var x = rect.midX - size.width / 2
                x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
                let y = max(visible.minY + 8, rect.minY - gap - size.height)
                return NSPoint(x: x, y: y)
            }
        }
        return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24)
    }

    // MARK: NSWindowDelegate
    func windowDidResignKey(_ notification: Notification) {
        guard !settings.panelPinned, settings.closePanelOnClickOutside else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let p = self.panel, p.isVisible else { return }
            if PanelHold.count > 0 || NSApp.modalWindow != nil || NSColorPanel.shared.isVisible { return }
            if p.attachedSheet != nil || NSApp.keyWindow === p { return }
            if let key = NSApp.keyWindow, key.sheetParent === p { return }
            self.hide()
        }
    }
}

// MARK: - Window helpers
@MainActor
func makeGlassWindow<Content: View>(title: String, size: NSSize, minSize: NSSize,
                                    @ViewBuilder content: () -> Content) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                     styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                     backing: .buffered, defer: false)
    w.title = title
    w.titlebarAppearsTransparent = true
    w.titleVisibility = .hidden
    w.isOpaque = false
    w.backgroundColor = .clear
    w.isReleasedWhenClosed = false
    w.minSize = minSize
    w.contentView = NSHostingView(rootView: ThemedRoot { content() })
    w.center()
    return w
}

@MainActor
final class WindowHolder {
    private var window: NSWindow?
    private let factory: @MainActor () -> NSWindow

    init(_ factory: @escaping @MainActor () -> NSWindow) { self.factory = factory }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil { window = factory() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

@MainActor
enum Windows {
    static let manager = WindowHolder {
        makeGlassWindow(title: "SwiftNote", size: NSSize(width: 1060, height: 740), minSize: NSSize(width: 840, height: 560)) {
            ManagerView()
        }
    }
    static let advanced = WindowHolder {
        makeGlassWindow(title: "SwiftNote Advanced Settings", size: NSSize(width: 880, height: 680), minSize: NSSize(width: 720, height: 520)) {
            AdvancedSettingsView()
        }
    }
    static let onboarding = WindowHolder {
        makeGlassWindow(title: "Welcome to SwiftNote", size: NSSize(width: 640, height: 620), minSize: NSSize(width: 640, height: 620)) {
            OnboardingView()
        }
    }
    static let help = WindowHolder {
        makeGlassWindow(title: "SwiftNote Help", size: NSSize(width: 520, height: 640), minSize: NSSize(width: 460, height: 420)) {
            HelpView()
        }
    }
}

@MainActor
final class AdvancedNav: ObservableObject {
    static let shared = AdvancedNav()
    @Published var selection: AdvancedCategory = .general

    func open(_ category: AdvancedCategory) {
        selection = category
        Windows.advanced.show()
    }
}

// MARK: - Menu bar icon
@MainActor
enum MenuIcon {
    struct Result {
        let image: NSImage
        let isCustom: Bool
    }

    static let fallbackSymbol = "square.and.pencil"

    static func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: "SwiftNote")?.withSymbolConfiguration(config)
    }

    static func customImage(path: String, size: CGFloat, template: Bool) -> NSImage? {
        guard !path.isEmpty, let source = NSImage(contentsOfFile: path),
              source.size.width > 0, source.size.height > 0 else { return nil }
        guard let image = source.copy() as? NSImage else { return nil }
        let ratio = source.size.width / source.size.height
        image.size = NSSize(width: size * ratio, height: size)
        image.isTemplate = template
        return image
    }

    static func make(settings: AppSettings) -> Result {
        let size = CGFloat(settings.menuIconSize)
        if settings.menuIconKind == MenuIconKind.custom.rawValue,
           let image = customImage(path: settings.menuIconCustomFile, size: size, template: settings.menuIconTemplate) {
            return Result(image: image, isCustom: true)
        }
        if let image = symbolImage(settings.menuIconSymbol, size: size) {
            image.isTemplate = true
            return Result(image: image, isCustom: false)
        }
        let image = symbolImage(fallbackSymbol, size: size) ?? NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true
        return Result(image: image, isCustom: false)
    }

    /// Copies the chosen artwork into the app's folder and switches the icon to it.
    @discardableResult
    static func importArtwork(from url: URL) -> Bool {
        guard NSImage(contentsOf: url) != nil else {
            ToastCenter.shared.show("❌ macOS couldn't read that image. Try a different SVG or a PNG.", seconds: 4)
            return false
        }
        let dest = AppPaths.appSupport.appendingPathComponent("MenuBarIcon.\(url.pathExtension.lowercased())")
        do {
            for old in FileStore.list(AppPaths.appSupport) where old.url.lastPathComponent.hasPrefix("MenuBarIcon.") {
                try? FileManager.default.removeItem(at: old.url)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            AppSettings.shared.menuIconCustomFile = dest.path
            AppSettings.shared.menuIconKind = MenuIconKind.custom.rawValue
            return true
        } catch {
            ToastCenter.shared.show("❌ Couldn't import the icon: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Floating desktop sticky notes
@MainActor
final class DesktopStickyManager {
    static let shared = DesktopStickyManager()
    private var windows: [UUID: NSWindow] = [:]

    func showSticky(note: StickyNote) {
        if let existing = windows[note.id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let s = AppSettings.shared
        let root = ThemedRoot { DesktopStickyView(noteID: note.id, onClose: { [weak self] in self?.closeSticky(id: note.id) }) }
        let window = NSWindow(contentRect: NSRect(x: 220, y: 260, width: s.stickyWidth, height: s.stickyHeight),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = note.title
        let hosting = NSHostingView(rootView: root)
        // Let the user's window size win over SwiftUI's ideal size, otherwise the window can't be resized.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(NSSize(width: s.stickyWidth, height: s.stickyHeight))
        window.contentMinSize = NSSize(width: 160, height: 120)
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.level = s.stickyAlwaysOnTop ? .floating : .normal
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isReleasedWhenClosed = false
        // Remember where the user put each sticky and how big they made it.
        window.setFrameAutosaveName("SwiftNote.sticky.\(note.id.uuidString)")
        window.makeKeyAndOrderFront(nil)
        windows[note.id] = window
    }

    func closeSticky(id: UUID) {
        windows[id]?.close()
        windows.removeValue(forKey: id)
    }
}

// MARK: - App delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()
    private var lastDock = false
    private var lastAppearance = ""
    private var lastHotkeys = ""
    private var lastIcon = ""

    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let s = AppSettings.shared
        _ = AppPaths.appSupport
        NSApp.appearance = s.nsAppearance

        lastDock = s.showInDock
        lastAppearance = appearanceSignature(s)
        lastHotkeys = hotkeySignature(s)
        lastIcon = iconSignature(s)

        NSApp.setActivationPolicy(s.showInDock ? .regular : .accessory)
        PanelController.shared.install()
        registerHotkeys()
        BackupManager.shared.configure()
        observe()
        ensureEditMenu()
        installLocalKeybinds()
        UpdateManager.shared.start()

        if !s.onboardingCompleted {
            Windows.onboarding.show()
        } else if s.openManagerOnLaunch {
            Windows.manager.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppSettings.shared.showInDock { Windows.manager.show() } else { PanelController.shared.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        NoteManager.shared.writeNow()
        let s = AppSettings.shared
        if s.backupOnQuit, s.autoBackupEnabled, s.onboardingCompleted {
            BackupManager.shared.runBackup(manual: false)
        }
    }

    // MARK: Observing preferences
    private func observe() {
        AppSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &cancellables)

        NoteManager.shared.$notes
            .receive(on: RunLoop.main)
            .sink { _ in PanelController.shared.refreshIcon() }
            .store(in: &cancellables)
    }

    private func appearanceSignature(_ s: AppSettings) -> String { "\(s.appearanceSync)-\(s.isDarkMode)" }
    private func hotkeySignature(_ s: AppSettings) -> String {
        "\(s.hotkeysEnabled)|" + HotkeyAction.allCases.map { s.shortcut(for: $0)?.serialize() ?? "off" }.joined(separator: "|")
    }
    private func iconSignature(_ s: AppSettings) -> String {
        "\(s.menuIconKind)|\(s.menuIconSymbol)|\(s.menuIconCustomFile)|\(s.menuIconSize)|\(s.menuIconTemplate)|\(s.menuIconShowCount)"
    }

    private func settingsChanged() {
        let s = AppSettings.shared

        if s.showInDock != lastDock {
            lastDock = s.showInDock
            NSApp.setActivationPolicy(s.showInDock ? .regular : .accessory)
            if s.showInDock { Windows.manager.show() } else { Windows.manager.close() }
        }
        let appearance = appearanceSignature(s)
        if appearance != lastAppearance {
            lastAppearance = appearance
            NSApp.appearance = s.nsAppearance
        }
        let hotkeys = hotkeySignature(s)
        if hotkeys != lastHotkeys {
            lastHotkeys = hotkeys
            registerHotkeys()
        }
        let icon = iconSignature(s)
        if icon != lastIcon {
            lastIcon = icon
            PanelController.shared.refreshIcon()
        }
        PanelController.shared.applyLiveSettings()
        BackupManager.shared.configure()
    }

    // MARK: Global hotkeys
    func registerHotkeys() {
        let s = AppSettings.shared
        let center = HotkeyCenter.shared
        center.unregisterAll()
        guard s.hotkeysEnabled else { return }

        var errors: [String: String] = [:]
        for action in HotkeyAction.allCases {
            guard let shortcut = s.shortcut(for: action) else { continue }
            let status = center.register(id: action.hotkeyID, keyCode: shortcut.keyCode,
                                         modifiers: shortcut.carbonModifiers) {
                AppDelegate.perform(action)
            }
            if status != noErr {
                errors[action.rawValue] = status == OSStatus(eventHotKeyExistsErr)
                    ? "\(shortcut.readableString) is already used by macOS or another app."
                    : "Couldn't register \(shortcut.readableString) (error \(status))."
            }
        }
        center.errors = errors
    }

    /// When global keybinds are off, the same shortcuts still work while SwiftNote is the active app.
    private func installLocalKeybinds() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let s = AppSettings.shared
            guard !s.hotkeysEnabled, !shortcutRecordingActive else { return event }
            let mods = CustomShortcut.carbonModifiers(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            for action in HotkeyAction.allCases {
                if let sc = s.shortcut(for: action), sc.keyCode == UInt32(event.keyCode), sc.carbonModifiers == mods {
                    AppDelegate.perform(action)
                    return nil
                }
            }
            return event
        }
    }

    static func perform(_ action: HotkeyAction) {
        let s = AppSettings.shared
        switch action {
        case .startDictation:
            if s.startHotkeyToggles { DictationManager.shared.toggle() } else { DictationManager.shared.start() }
        case .stopDictation:
            DictationManager.shared.stop()
        case .togglePanel:
            PanelController.shared.toggle()
        case .saveNote:
            NoteManager.shared.saveQuickNote()
        case .openManager:
            Windows.manager.show()
        }
    }

    // MARK: Edit menu (⌘C / ⌘V / ⌘Z must work inside the floating panel)
    private func ensureEditMenu() {
        DispatchQueue.main.async {
            guard let main = NSApp.mainMenu else { return }
            if main.items.contains(where: { $0.title == "Edit" }) { return }

            let edit = NSMenu(title: "Edit")
            func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = [.command]) {
                let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
                i.keyEquivalentModifierMask = mods
                edit.addItem(i)
            }
            item("Undo", Selector(("undo:")), "z")
            item("Redo", Selector(("redo:")), "z", [.command, .shift])
            edit.addItem(.separator())
            item("Cut", #selector(NSText.cut(_:)), "x")
            item("Copy", #selector(NSText.copy(_:)), "c")
            item("Paste", #selector(NSText.paste(_:)), "v")
            item("Select All", #selector(NSText.selectAll(_:)), "a")

            let holder = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            holder.submenu = edit
            main.insertItem(holder, at: min(1, main.items.count))
        }
    }
}


// MARK: - Custom accent colour (system colour wheel)
@MainActor
final class AccentPanel: NSObject {
    static let shared = AccentPanel()

    func open() {
        let panel = NSColorPanel.shared
        panel.mode = .wheel
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(AppSettings.shared.accentColor)
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        AppSettings.shared.accentHex = Color(nsColor: sender.color).toHex()
    }
}

/// Rainbow swatch that opens the colour wheel.
struct CustomAccentButton: View {
    @ObservedObject private var settings = AppSettings.shared
    var size: CGFloat = 18
    var body: some View {
        Button { AccentPanel.shared.open() } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Custom colour… (opens the colour wheel)")
    }
}
