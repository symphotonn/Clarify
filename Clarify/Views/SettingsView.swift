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
                    Text("Choose at least one modifier to avoid intercepting normal typing.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("Model", text: $settings.modelName)
                    .textFieldStyle(.roundedBorder)
                    .help("Default: gpt-4o-mini. Change to use a different OpenAI model.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
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
        if let hotkeyCaptureMonitor {
            NSEvent.removeMonitor(hotkeyCaptureMonitor)
            self.hotkeyCaptureMonitor = nil
        }
        isRecordingHotkey = false
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
