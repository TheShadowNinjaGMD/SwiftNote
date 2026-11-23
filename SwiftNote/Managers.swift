//
//  Managers.swift
//  SwiftNote — toasts, sounds, EventKit, Keychain, login item, global hotkeys (Carbon)
//

import SwiftUI
import AppKit
import AVFoundation
import EventKit
import Security
import ServiceManagement
import Carbon.HIToolbox

// MARK: - Toasts
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var message: String?
    private var task: Task<Void, Never>?

    func show(_ text: String, seconds: Double? = nil) {
        message = text
        task?.cancel()
        let duration = seconds ?? AppSettings.shared.toastSeconds
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, duration) * 1_000_000_000))
            if !Task.isCancelled { self.message = nil }
        }
    }
}

// MARK: - Sounds
@MainActor
final class SoundManager: ObservableObject {
    static let shared = SoundManager()
    private var players: [String: AVAudioPlayer] = [:]

    enum SoundEvent: String, CaseIterable, Identifiable {
        case keyTap, save, noteAdded, noteDeleted, copy, clear, toggle, calendar, reminder, pin, duplicate, dictationStart, dictationStop
        var id: String { rawValue }

        var fileName: String {
            switch self {
            case .keyTap:         return "Tink"
            case .save:           return "Glass"
            case .noteAdded:      return "Pop"
            case .noteDeleted:    return "Basso"
            case .copy:           return "Blow"
            case .clear:          return "Funk"
            case .toggle:         return "Morse"
            case .calendar:       return "Hero"
            case .reminder:       return "Submarine"
            case .pin:            return "Tink"
            case .duplicate:      return "Pop"
            case .dictationStart: return "Ping"
            case .dictationStop:  return "Bottle"
            }
        }

        var title: String {
            switch self {
            case .keyTap:         return "Typing tick"
            case .save:           return "Save"
            case .noteAdded:      return "Note added"
            case .noteDeleted:    return "Note deleted"
            case .copy:           return "Copy"
            case .clear:          return "Clear"
            case .toggle:         return "Toggle switch"
            case .calendar:       return "Added to Calendar"
            case .reminder:       return "Added to Reminders"
            case .pin:            return "Pin / unpin"
            case .duplicate:      return "Duplicate"
            case .dictationStart: return "Dictation start"
            case .dictationStop:  return "Dictation stop"
            }
        }
    }

    func play(_ event: SoundEvent, force: Bool = false) {
        let s = AppSettings.shared
        guard force || (s.soundEnabled && !s.isSoundDisabled(event.rawValue)) else { return }
        let name = event.fileName
        let url = Bundle.main.url(forResource: name, withExtension: "aiff")
            ?? URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = Float(s.soundVolume)
            player.prepareToPlay()
            player.play()
            players[name] = player
        }
    }
}

// MARK: - EventKit (Calendar + Reminders)
@MainActor
final class EventKitManager: ObservableObject {
    static let shared = EventKitManager()
    @Published var calendarAuthStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthStatus: EKAuthorizationStatus = .notDetermined
    @Published var calendars: [EKCalendar] = []
    @Published var reminderLists: [EKCalendar] = []

    private let store = EKEventStore()

    private init() { refreshStatus() }

    func refreshStatus() {
        calendarAuthStatus = EKEventStore.authorizationStatus(for: .event)
        reminderAuthStatus = EKEventStore.authorizationStatus(for: .reminder)
        if calendarAuthStatus == .fullAccess {
            calendars = store.calendars(for: .event).filter { $0.allowsContentModifications }
        }
        if reminderAuthStatus == .fullAccess {
            reminderLists = store.calendars(for: .reminder).filter { $0.allowsContentModifications }
        }
    }

    func requestCalendarAccess() async {
        do { _ = try await store.requestFullAccessToEvents() } catch {}
        refreshStatus()
    }

    func requestReminderAccess() async {
        do { _ = try await store.requestFullAccessToReminders() } catch {}
        refreshStatus()
    }

    func addCalendarEvent(title: String, notes: String, startDate: Date, endDate: Date, calendarID: String?) async -> Bool {
        if calendarAuthStatus != .fullAccess { await requestCalendarAccess() }
        guard calendarAuthStatus == .fullAccess else {
            ToastCenter.shared.show("❌ Calendar access is off — enable it in System Settings → Privacy")
            return false
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendarID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
        let alert = AppSettings.shared.eventAlertMinutes
        if alert > 0 { event.addAlarm(EKAlarm(relativeOffset: -Double(alert) * 60)) }
        do {
            try store.save(event, span: .thisEvent)
            ToastCenter.shared.show("✅ Event added to Calendar")
            return true
        } catch {
            ToastCenter.shared.show("❌ \(error.localizedDescription)")
            return false
        }
    }

    func addReminder(title: String, notes: String, dueDate: Date?, listID: String?) async -> Bool {
        if reminderAuthStatus != .fullAccess { await requestReminderAccess() }
        guard reminderAuthStatus == .fullAccess else {
            ToastCenter.shared.show("❌ Reminders access is off — enable it in System Settings → Privacy")
            return false
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = listID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewReminders()
        if let due = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
            ToastCenter.shared.show("✅ Reminder added")
            return true
        } catch {
            ToastCenter.shared.show("❌ \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Keychain (API key)
enum Keychain {
    private static let service = "com.anaypatro.SwiftNote"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Launch at login
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

// MARK: - Global hotkeys (Carbon). No Accessibility permission needed and works while any app is frontmost.
private func swiftNoteHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hkID = EventHotKeyID()
    let err = GetEventParameter(event,
                                EventParamName(kEventParamDirectObject),
                                EventParamType(typeEventHotKeyID),
                                nil,
                                MemoryLayout<EventHotKeyID>.size,
                                nil,
                                &hkID)
    if err == noErr {
        let id = hkID.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated { HotkeyCenter.shared.fire(id) }
        }
    }
    return noErr
}

@MainActor
final class HotkeyCenter: ObservableObject {
    static let shared = HotkeyCenter()
    @Published var errors: [String: String] = [:]

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var installed = false

    private init() {}

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), swiftNoteHotKeyHandler, 1, &spec, nil, nil)
        installed = true
    }

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> OSStatus {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x534E4F54), id: id)   // 'SNOT'
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            refs[id] = ref
            actions[id] = action
        }
        return status
    }

    func unregisterAll() {
        for (_, r) in refs { UnregisterEventHotKey(r) }
        refs = [:]
        actions = [:]
        errors = [:]
    }

    func fire(_ id: UInt32) { actions[id]?() }
}
