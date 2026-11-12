//
//  UIParts.swift
//  SwiftNote — small shared UI pieces: toasts, stat badges, shortcut recorder, helpers.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Animation helper (respects the "Animations" setting)
@MainActor
func animated<T>(_ body: () -> T) -> T {
    if AppSettings.shared.animationsEnabled {
        return withAnimation(.easeInOut(duration: 0.2), body)
    }
    return body()
}

// MARK: - Toast overlay
struct ToastOverlay: ViewModifier {
    @ObservedObject private var toast = ToastCenter.shared
    @ObservedObject private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = toast.message, settings.showToasts {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 380)
                        .glassControl(in: Capsule(), interactive: false)
                        .padding(.bottom, 64)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: toast.message)
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}

// MARK: - Stat badge
struct StatBadge: View {
    let value: String
    let label: String
    @ObservedObject private var settings = AppSettings.shared

    init(value: String, label: String) {
        self.value = value
        self.label = label
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(settings.accentColor)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 52)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassControl(in: RoundedRectangle(cornerRadius: 10, style: .continuous), interactive: false)
    }
}

// MARK: - Section title used by the settings screens
struct SectionTitle: View {
    let title: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol = symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
        }
        .padding(.horizontal, 2)
    }
}

@MainActor var shortcutRecordingActive = false

// MARK: - Shortcut recorder
struct ShortcutRecorderRow: View {
    let action: HotkeyAction
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var hotkeys = HotkeyCenter.shared

    @State private var recording = false
    @State private var liveModifiers = ""
    @State private var monitor: Any?
    @State private var warning: String?

    private var label: String {
        if recording { return liveModifiers.isEmpty ? "Press keys…" : liveModifiers }
        return settings.shortcut(for: action)?.readableString ?? "Off"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: action.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(settings.accentColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title).font(.system(size: 12.5, weight: .medium))
                    Text(action.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: toggleRecording) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .frame(minWidth: 88)
                }
                .buttonStyle(SoftButtonStyle(tint: recording ? .red : settings.accentColor, prominent: recording))

                if settings.isShortcutCustom(action) && !recording {
                    Button { settings.resetShortcut(for: action) } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Reset to the default shortcut")
                }
            }
            if let message = warning ?? hotkeys.errors[action.rawValue] {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.leading, 30)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        recording = true
        shortcutRecordingActive = true
        warning = nil
        liveModifiers = ""
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func stopRecording() {
        recording = false
        shortcutRecordingActive = false
        liveModifiers = ""
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.type == .flagsChanged {
            liveModifiers = CustomShortcut.modifierGlyphs(from: mods)
            return nil
        }
        if event.keyCode == 53 {                      // Esc cancels
            stopRecording()
            return nil
        }
        if (event.keyCode == 51 || event.keyCode == 117) && mods.isEmpty {   // Delete switches the shortcut off
            settings.setShortcut(nil, for: action)
            warning = nil
            stopRecording()
            return nil
        }

        let carbon = CustomShortcut.carbonModifiers(from: mods)
        let isFunctionKey = CustomShortcut.functionKeyCodes.contains(event.keyCode)
        if carbon == 0 && !isFunctionKey {
            warning = "Include ⌘, ⌥, ⌃ or ⇧ so the shortcut doesn't fire while you type."
            return nil
        }
        if carbon == UInt32(cmdKey) && !isFunctionKey {
            warning = "⌘-only shortcuts clash with other apps. Add ⌥, ⌃ or ⇧."
            return nil
        }
        let shortcut = CustomShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbon,
                                      display: CustomShortcut.displayName(for: event))
        if let other = HotkeyAction.allCases.first(where: { $0 != action && settings.shortcut(for: $0) == shortcut }) {
            warning = "Already used by “\(other.title)”."
            return nil
        }
        settings.setShortcut(shortcut, for: action)
        warning = nil
        stopRecording()
        return nil
    }
}
