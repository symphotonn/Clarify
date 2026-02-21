import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @State private var isRecordingHotkey = false
    @State private var hotkeyCaptureMonitor: Any?
    @State private var hotkeyCaptureError: String?
    @State private var showSavedBanner = false
    @State private var savedBannerTask: Task<Void, Never>?
    @State private var showAdvanced = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            if showSavedBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(savedBannerText(settings))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("API Key") {
                SecureField("OpenAI API Key", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)

                Text(apiConfigurationStatus(settings))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Theme") {
                ForEach(ClarifyTheme.allThemes, id: \.name) { theme in
                    ThemeRow(theme: theme, isSelected: settings.themeName == theme.name) {
                        settings.themeName = theme.name
                    }
                }
            }

            Section("Hotkey") {
                HStack {
                    Text("Preview")
                    Spacer()
                    Text(settings.hotkeyBinding.displayText)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Spacer()
                    if isRecordingHotkey {
                        Button("Press shortcut...") {
                            toggleHotkeyCapture(settings: settings)
                        }
                        .font(.system(.body, design: .monospaced))
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Set Shortcut") {
                            toggleHotkeyCapture(settings: settings)
                        }
                        .font(.system(.body, design: .monospaced))
                        .buttonStyle(.borderedProminent)
                    }

                    if isRecordingHotkey {
                        Button("Cancel") {
                            stopHotkeyCapture()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Reset") {
                        settings.updateHotkeyBinding(.default)
                    }
                    .buttonStyle(.bordered)
                }

                Text(isRecordingHotkey ? "Press your desired key combination now. Press Esc to cancel." : "Click the shortcut button, then press the key combination you want.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let hotkeyCaptureError {
                    Text(hotkeyCaptureError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !settings.hotkeyBinding.hasAnyModifier {
                    Label {
                        Text("Choose at least one modifier to avoid intercepting normal typing.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(Color(hex: 0xFF9F0A))
                }

                if let hotkeyIssue = settings.hotkeyRegistrationIssue {
                    Text(hotkeyIssue)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("Model", text: $settings.modelName)
                    .textFieldStyle(.roundedBorder)
                    .help("Default: gpt-4o-mini. Change to use a different OpenAI model.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 500)
        .onDisappear {
            stopHotkeyCapture()
            savedBannerTask?.cancel()
        }
        .onChange(of: settings.lastSavedAt) { _, newValue in
            guard newValue != nil, !isRecordingHotkey else { return }
            showSavedConfirmation()
        }
    }

    private func toggleHotkeyCapture(settings: SettingsManager) {
        if isRecordingHotkey {
            stopHotkeyCapture()
        } else {
            startHotkeyCapture(settings: settings)
        }
    }

    private func startHotkeyCapture(settings: SettingsManager) {
        stopHotkeyCapture()
        hotkeyCaptureError = nil
        isRecordingHotkey = true
        setHotkeyCaptureActive(true)

        hotkeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingHotkey else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                stopHotkeyCapture()
                return nil
            }

            guard let candidate = HotkeyBinding.from(event: event) else {
                NSSound.beep()
                hotkeyCaptureError = "Unsupported key. Use letters, numbers, Space, Return, Tab, /, \\, comma, or period."
                return nil
            }

            guard candidate.hasAnyModifier else {
                NSSound.beep()
                hotkeyCaptureError = "Add at least one modifier (\u{2325}, \u{2318}, \u{2303}, or \u{21E7})."
                return nil
            }

            settings.updateHotkeyBinding(candidate)
            hotkeyCaptureError = nil
            stopHotkeyCapture()
            return nil
        }
    }

    private func stopHotkeyCapture() {
        let wasRecording = isRecordingHotkey
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
            self.hotkeyCaptureMonitor = nil
        }
        isRecordingHotkey = false
        if wasRecording {
            setHotkeyCaptureActive(false)
        }
    }

    private func setHotkeyCaptureActive(_ isActive: Bool) {
        NotificationCenter.default.post(
            name: .clarifyHotkeyCaptureStateChanged,
            object: isActive
        )
    }

    private func apiConfigurationStatus(_ settings: SettingsManager) -> String {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "API key is missing. Add one to enable explanations."
        }

        let keySource: String
        if settings.isAPIKeyFromEnvironment {
            keySource = "environment variable (\(Constants.devAPIKeyEnvVar))"
        } else {
            keySource = "saved settings"
        }

        return "Ready. API key from \(keySource)."
    }

    private func savedBannerText(_ settings: SettingsManager) -> String {
        guard let lastSavedAt = settings.lastSavedAt else {
            return "Auto-save enabled"
        }
        return "\(settings.lastSavedMessage) at \(timeFormatter.string(from: lastSavedAt))"
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    private func showSavedConfirmation() {
        savedBannerTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            showSavedBanner = true
        }
        savedBannerTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    showSavedBanner = false
                }
            }
        }
    }
}

private struct ThemeRow: View {
    let theme: ClarifyTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(theme.name)
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 4) {
                    colorDot(theme.background.opacity(theme.useVibrancy ? 0 : 1), border: theme.useVibrancy)
                    colorDot(theme.button)
                    colorDot(theme.headline)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func colorDot(_ color: Color, border: Bool = false) -> some View {
        Circle()
            .fill(color)
            .overlay(
                Circle().strokeBorder(.secondary.opacity(border ? 0.4 : 0), lineWidth: 1)
            )
            .frame(width: 14, height: 14)
    }
}

private extension Notification.Name {
    static let clarifyHotkeyCaptureStateChanged = Notification.Name("clarify.hotkeyCaptureStateChanged")
}
