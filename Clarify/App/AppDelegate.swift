import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let settingsManager = SettingsManager()

    private var hotkeyManager: HotkeyManager?
    private var panelController: PanelController?
    private var settingsWindowController: NSWindowController?
    private var settingsRequestObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        OpenAIClient.prewarmConnection()
        appState.settingsManager = settingsManager

        if shouldAutoInstallStableBuildOnLaunch {
            appState.installStableBuildAndRelaunch()
        }

        settingsRequestObserver = NotificationCenter.default.addObserver(
            forName: .clarifyOpenSettingsRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.presentSettingsWindow()
            }
        }

        appState.permissionManager.startPolling()

        hotkeyManager = HotkeyManager(hotkey: settingsManager.hotkeyBinding) { [weak self] isDoublePress in
            Task { @MainActor in
                self?.appState.handleHotkey(isDoublePress: isDoublePress)
            }
        }

        settingsManager.onHotkeyChanged = { [weak self] hotkey in
            self?.hotkeyManager?.updateHotkey(hotkey)
        }

        panelController = PanelController(appState: appState)
        appState.panelController = panelController

        hotkeyManager?.start()

        appState.onPermissionGranted = { [weak self] in
            self?.hotkeyManager?.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        settingsManager.onHotkeyChanged = nil
        appState.explanationBuffer.clear()
        if let settingsRequestObserver {
            NotificationCenter.default.removeObserver(settingsRequestObserver)
            self.settingsRequestObserver = nil
        }
    }

    static func requestSettingsWindow() {
        NotificationCenter.default.post(name: .clarifyOpenSettingsRequested, object: nil)
    }

    @objc
    func showSettingsWindow(_ sender: Any?) {
        presentSettingsWindow()
    }

    @objc
    func showPreferencesWindow(_ sender: Any?) {
        presentSettingsWindow()
    }

    private func presentSettingsWindow() {
        if settingsWindowController == nil {
            let content = AnyView(
                SettingsView()
                    .environment(settingsManager)
            )
            let hostingController = NSHostingController(rootView: content)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 460))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private var shouldAutoInstallStableBuildOnLaunch: Bool {
        guard appState.shouldRecommendStableInstall else { return false }
        let env = ProcessInfo.processInfo.environment
        if let rawValue = env[Constants.devAutoInstallStableEnvVar]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !rawValue.isEmpty {
            switch rawValue {
            case "0", "false", "no":
                return false
            case "1", "true", "yes":
                return true
            default:
                break
            }
        }

        // Default to stable-path runs in Debug to keep Accessibility trust sticky.
        return true
    }
}

private extension Notification.Name {
    static let clarifyOpenSettingsRequested = Notification.Name("clarify.openSettingsRequested")
}
