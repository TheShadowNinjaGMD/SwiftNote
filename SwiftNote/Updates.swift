//
//  Updates.swift
//  SwiftNote — Sparkle auto-updates, project links and the GitHub mark.
//

import SwiftUI
import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

// MARK: - Links
enum AppLinks {
    static let repoURL = URL(string: "https://github.com/TheShadowNinjaGMD/SwiftNote")!
    static let releasesURL = URL(string: "https://github.com/TheShadowNinjaGMD/SwiftNote/releases/latest")!
    static let issuesURL = URL(string: "https://github.com/TheShadowNinjaGMD/SwiftNote/issues")!
    static let siteURL = URL(string: "https://swiftnote.base44.app")!

    static func openRepo() { NSWorkspace.shared.open(repoURL) }
}

// MARK: - Update manager (Sparkle when available, GitHub releases page otherwise)
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var canCheck = true
    @Published private(set) var isConfigured = false

    var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    #if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        isConfigured = !key.isEmpty && !key.hasPrefix("REPLACE")
        if isConfigured {
            controller.startUpdater()
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        }
    }

    var automaticChecks: Bool {
        get { isConfigured ? controller.updater.automaticallyChecksForUpdates : false }
        set { objectWillChange.send(); if isConfigured { controller.updater.automaticallyChecksForUpdates = newValue } }
    }

    func checkForUpdates() {
        if isConfigured {
            NSApp.activate(ignoringOtherApps: true)
            controller.checkForUpdates(nil)
        } else {
            NSWorkspace.shared.open(AppLinks.releasesURL)
        }
    }
    #else
    private init() {}
    var automaticChecks: Bool { get { false } set { objectWillChange.send() } }
    func checkForUpdates() { NSWorkspace.shared.open(AppLinks.releasesURL) }
    #endif

    /// Called once at launch so Sparkle starts its schedule.
    func start() { _ = canCheck }
}

// MARK: - GitHub mark
struct GitHubMark: View {
    var size: CGFloat = 16
    var body: some View {
        Image("GitHubMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GitHubButton: View {
    var title = "View on GitHub"
    var body: some View {
        Button { AppLinks.openRepo() } label: {
            HStack(spacing: 6) { GitHubMark(size: 14); Text(title) }
        }
        .help("Open the SwiftNote repository on GitHub")
    }
}

// MARK: - About & updates card (used in quick settings and Advanced Settings)
struct AboutUpdatesCard: View {
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SwiftNote").font(.headline)
                    Text(updates.versionString).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if updates.isConfigured {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updates.automaticChecks }, set: { updates.automaticChecks = $0 }))
            } else {
                Text("Automatic updates need a Sparkle key. Run setup-sparkle.sh once (see the README). Until then, the button below opens the releases page.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button { updates.checkForUpdates() } label: { Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(SoftButtonStyle(tint: settings.accentColor, prominent: true))
                    .disabled(!updates.canCheck)
                Button { AppLinks.openRepo() } label: {
                    HStack(spacing: 6) { GitHubMark(size: 13); Text("View on GitHub") }
                }
                .buttonStyle(SoftButtonStyle(tint: .primary))
                Button { NSWorkspace.shared.open(AppLinks.siteURL) } label: { Label("Website", systemImage: "globe") }
                    .buttonStyle(SoftButtonStyle(tint: .primary))
            }
        }
    }
}
