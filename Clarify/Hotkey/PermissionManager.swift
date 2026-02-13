import AppKit
import ApplicationServices

@Observable
final class PermissionManager {
    var isAccessibilityGranted: Bool = false
    var onPermissionChanged: ((Bool) -> Void)?

    private var pollTimer: Timer?

    init() {
        isAccessibilityGranted = Self.currentTrustStatus(prompt: false)
    }

    func refreshPermissionStatus() {
        let granted = Self.currentTrustStatus(prompt: false)
        if granted != isAccessibilityGranted {
            isAccessibilityGranted = granted
            onPermissionChanged?(granted)
            if granted {
                stopPolling()
            }
        }
    }

    func startPolling() {
        guard !isAccessibilityGranted else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Constants.permissionPollInterval, repeats: true) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func requestPermission() {
        _ = Self.currentTrustStatus(prompt: true)
        refreshPermissionStatus()
        startPolling()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func isScreenRecordingGranted() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    func requestScreenRecordingPermission() {
        if #available(macOS 10.15, *) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            _ = CGRequestScreenCaptureAccess()
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealRunningAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private static func currentTrustStatus(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
