import SwiftUI

@main
struct ClarifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.appState)
                .environment(appDelegate.settingsManager)
        } label: {
            Image(systemName: "sparkle.magnifyingglass")
        }

        Settings {
            SettingsView()
                .environment(appDelegate.settingsManager)
        }
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.permissionGranted {
                Text("Clarify is active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Grant Accessibility Access...") {
                    appState.permissionManager.requestPermission()
                }
            }
        }

        Divider()

        Button("Settings...") {
            openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Clarify") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func openSettingsWindow() {
        AppDelegate.requestSettingsWindow()

        if NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }

        _ = NSApplication.shared.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
