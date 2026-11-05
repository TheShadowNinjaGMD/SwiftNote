//
//  SwiftNoteApp.swift
//  SwiftNote — entry point. All real work happens in AppDelegate (AppController.swift).
//

import SwiftUI

@main
struct SwiftNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { Windows.advanced.show() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(replacing: .newItem) {
                    Button("Show Quick Note") { PanelController.shared.show() }
                    Button("Open Manager") { Windows.manager.show() }
                }
                // Replacing .help gives the standard macOS Help menu, including its search field.
                CommandGroup(replacing: .help) {
                    Button("SwiftNote Help") { Windows.help.show() }
                        .keyboardShortcut("?", modifiers: .command)
                    Button("Welcome Tour") { Windows.onboarding.show() }
                    Button("Advanced Settings…") { Windows.advanced.show() }
                }
            }
    }
}
