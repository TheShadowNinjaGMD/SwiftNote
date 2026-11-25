//
//  Onboarding.swift
//  SwiftNote — first-run tour.
//

import SwiftUI
import AppKit
import EventKit

struct OnboardingView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var backup = BackupManager.shared
    @ObservedObject private var ek = EventKitManager.shared
    @State private var step = 0
    @State private var micOK = Permissions.microphoneGranted
    @State private var speechOK = Permissions.speechGranted
    @State private var desktopOK = false

    private let titles = ["Welcome", "Permissions", "Dictation", "Shortcuts", "Look & feel", "Backups"]
    private let accents: [String] = ["#4A90E2", "#7C5CFF", "#FF5C8A", "#FF9F1C", "#2EC4B6", "#34C759"]

    var body: some View {
        VStack(spacing: 0) {
            progress
            ScrollView {
                VStack(spacing: 16) { page }
                    .padding(28)
                    .frame(maxWidth: .infinity)
            }
            Divider().opacity(0.4)
            HStack {
                if step > 0 { Button("Back") { animated { step -= 1 } } }
                Spacer()
                if step < titles.count - 1 {
                    Button("Next") { animated { step += 1 } }
                        .buttonStyle(SoftButtonStyle(tint: settings.accentColor, prominent: true))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start using SwiftNote") { finish() }
                        .buttonStyle(SoftButtonStyle(tint: settings.accentColor, prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .background(OnboardingBackdrop().ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { finish() } label: {
                Label("Skip onboarding", systemImage: "forward.end")
            }
            .buttonStyle(SoftButtonStyle(tint: .secondary))
            .padding(.top, 10).padding(.trailing, 14)
            .help("Skip the tour. You can reopen it from Help.")
        }
        .toastOverlay()
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<titles.count, id: \.self) { i in
                Capsule().fill(i <= step ? settings.accentColor : Color.primary.opacity(0.15)).frame(height: 4)
            }
        }
        .padding(.horizontal, 28).padding(.top, 46)
    }

    @ViewBuilder private var page: some View {
        switch step {
        case 0: welcome
        case 1: permissions
        case 2: dictation
        case 3: shortcuts
        case 4: look
        default: backups
        }
    }

    private func header(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(settings.accentColor)
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    // MARK: Pages
    private var welcome: some View {
        VStack(spacing: 18) {
            header("bolt.fill", "Welcome to SwiftNote", "A quick note-taking app that lives in your menu bar. Write, dictate, pin sticky notes and never lose a thought.")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    bullet("menubar.rectangle", "Click the menu bar icon to open your notes instantly")
                    bullet("mic.fill", "Dictate with Apple speech or whisper.cpp")
                    bullet("keyboard", "Global shortcuts work from any app")
                    bullet("icloud", "Automatic backups, mirrored to a Desktop folder")
                    bullet("macwindow", "Optional Dock mode with a full Manager window")
                }
            }
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(settings.accentColor)
            Text(text)
        }
    }

    private var permissions: some View {
        VStack(spacing: 16) {
            header("hand.raised.fill", "Permissions", "Everything is optional. Grant only what you want to use.")
            permRow("mic.fill", "Microphone", "For dictation", micOK) {
                Task { micOK = await Permissions.requestMicrophone() }
            }
            permRow("waveform", "Speech recognition", "For Apple dictation", speechOK) {
                Task { speechOK = await Permissions.requestSpeech() }
            }
            permRow("calendar", "Calendar", "Add notes as events", ek.calendarAuthStatus == .fullAccess) {
                Task { await EventKitManager.shared.requestCalendarAccess() }
            }
            permRow("checklist", "Reminders", "Turn notes into reminders", ek.reminderAuthStatus == .fullAccess) {
                Task { await EventKitManager.shared.requestReminderAccess() }
            }
            permRow("folder", "Desktop folder", "Creates ~/Desktop/\(settings.desktopFolderName)", desktopOK) {
                desktopOK = backup.createDesktopFolder()
            }
        }
    }

    private func permRow(_ symbol: String, _ title: String, _ detail: String, _ granted: Bool, action: @escaping () -> Void) -> some View {
        Card {
            HStack {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(settings.accentColor)
                VStack(alignment: .leading) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if granted { Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Button("Allow", action: action).buttonStyle(SoftButtonStyle(tint: settings.accentColor)) }
            }
        }
    }

    private var dictation: some View {
        VStack(spacing: 16) {
            header("mic.fill", "Dictation", "Pick how SwiftNote turns your voice into text.")
            ForEach(DictationEngine.allCases) { engine in
                Button { settings.dictationEngine = engine } label: {
                    Card {
                        HStack {
                            Image(systemName: engine.symbol).frame(width: 24)
                            VStack(alignment: .leading) { Text(engine.title).font(.headline); Text(engine.summary).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if settings.dictationEngine == engine { Image(systemName: "checkmark.circle.fill").foregroundStyle(settings.accentColor) }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if settings.dictationEngine != .apple {
                Button("Set up Whisper models…") { AdvancedNav.shared.open(.whisper) }
                    .buttonStyle(SoftButtonStyle(tint: settings.accentColor))
            }
        }
    }

    private var shortcuts: some View {
        VStack(spacing: 16) {
            header("keyboard", "Global shortcuts", "These work from any app. Click one to change it.")
            Card { VStack(spacing: 10) { ForEach(HotkeyAction.allCases) { ShortcutRecorderRow(action: $0) } } }
        }
    }

    private var look: some View {
        VStack(spacing: 16) {
            header("paintbrush.fill", "Look & feel", "Liquid Glass on macOS 26, frosted glass everywhere else.")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Sync with system (light / dark)", isOn: settings.binding(\.appearanceSync))
                    if !settings.appearanceSync {
                        Picker("Mode", selection: settings.binding(\.isDarkMode)) { Text("Light").tag(false); Text("Dark").tag(true) }
                            .pickerStyle(.segmented)
                    }
                    Picker("Background", selection: settings.binding(\.backgroundStyle)) {
                        ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("Accent")
                        ForEach(accents, id: \.self) { hex in
                            Button { settings.accentHex = hex } label: {
                                Circle().fill((Color(hex: hex) ?? .blue)).frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(.white.opacity(settings.accentHex == hex ? 0.9 : 0), lineWidth: 2))
                            }.buttonStyle(.plain)
                        }
                        CustomAccentButton(size: 22)
                    }
                    Text("Menu bar icon").font(.headline)
                    MenuIconPicker()
                }
            }
        }
    }

    private var backups: some View {
        VStack(spacing: 16) {
            header("externaldrive.fill", "Backups & Dock", "Your notes are saved automatically.")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Auto-backup to Application Support/SwiftNote", isOn: settings.binding(\.autoBackupEnabled))
                    Toggle("Mirror to ~/Desktop/\(settings.desktopFolderName) (iCloud Desktop)", isOn: settings.binding(\.desktopMirrorEnabled))
                    Toggle("Show in Dock (opens the Manager window)", isOn: settings.binding(\.showInDock))
                    Toggle("Launch at login", isOn: Binding(get: { LaunchAtLogin.isEnabled }, set: { try? LaunchAtLogin.set($0) }))
                }
            }
            Text("You can change all of this later in Advanced Settings.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func finish() {
        settings.onboardingCompleted = true
        BackupManager.shared.configure()
        _ = BackupManager.shared.runBackup(manual: false)
        Windows.onboarding.close()
        if settings.showInDock { Windows.manager.show() } else { PanelController.shared.show() }
    }
}


// MARK: - Onboarding backdrop: opaque frosted glass with an aurora around the edges
struct OnboardingBackdrop: View {
    @ObservedObject private var settings = AppSettings.shared

    private struct Blob {
        let color: Color
        let anchor: UnitPoint
        let size: CGFloat
        let speed: Double
        let phase: Double
    }

    private var blobs: [Blob] {
        [
            Blob(color: settings.accentColor, anchor: .topLeading, size: 0.80, speed: 0.30, phase: 0.0),
            Blob(color: Color(red: 0.20, green: 0.85, blue: 0.70), anchor: .topTrailing, size: 0.75, speed: 0.22, phase: 1.7),
            Blob(color: Color(red: 0.62, green: 0.35, blue: 1.00), anchor: .bottomTrailing, size: 0.80, speed: 0.27, phase: 3.1),
            Blob(color: Color(red: 1.00, green: 0.40, blue: 0.70), anchor: .bottomLeading, size: 0.70, speed: 0.20, phase: 4.6),
            Blob(color: Color(red: 0.30, green: 0.65, blue: 1.00), anchor: .top, size: 0.55, speed: 0.35, phase: 2.4),
            Blob(color: Color(red: 0.40, green: 1.00, blue: 0.55), anchor: .bottom, size: 0.55, speed: 0.25, phase: 5.2)
        ]
    }

    var body: some View {
        ZStack {
            // Frosted base, deliberately fairly opaque.
            VisualEffectView(material: .underWindowBackground)
            Color(nsColor: .windowBackgroundColor).opacity(0.72)

            if !GlassSupport.reduceTransparency {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !settings.animationsEnabled)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    GeometryReader { geo in
                        ZStack {
                            ForEach(0..<blobs.count, id: \.self) { i in
                                let b = blobs[i]
                                let d = min(geo.size.width, geo.size.height) * b.size
                                let dx = CGFloat(sin(t * b.speed + b.phase)) * geo.size.width * 0.06
                                let dy = CGFloat(cos(t * b.speed * 0.8 + b.phase)) * geo.size.height * 0.06
                                Ellipse()
                                    .fill(b.color.opacity(0.55))
                                    .frame(width: d * 1.25, height: d)
                                    .blur(radius: 70)
                                    .position(point(for: b.anchor, in: geo.size, dx: dx, dy: dy))
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .opacity(0.55)
                // Keep the middle calm so text stays readable; the glow lives around the edges.
                .mask(
                    RadialGradient(colors: [.black.opacity(0.15), .black], center: .center,
                                   startRadius: 120, endRadius: 520)
                )
            }
        }
        .clipped()
    }

    private func point(for anchor: UnitPoint, in size: CGSize, dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: size.width * anchor.x + dx, y: size.height * anchor.y + dy)
    }
}
