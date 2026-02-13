import SwiftUI
import AppKit

struct ExplanationView: View {
    @Environment(AppState.self) private var appState
    @State private var permissionPollingTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            VisualEffectBackground()

            VStack(alignment: .leading, spacing: 10) {
                switch appState.overlayPhase {
                case .error:
                    errorView(appState.errorMessage ?? "Something went wrong.")
                case .permissionRequired:
                    permissionRequiredView()
                case .chat:
                    ChatView()
                case .loadingPreToken, .loadingStreaming, .result:
                    contentView
                case .empty:
                    emptyStateView()
                }
            }
            .padding(16)
        }
        .frame(
            width: Constants.panelWidth,
            height: appState.overlayPhase == .chat ? Constants.chatPanelMaxHeight : nil
        )
        .fixedSize(horizontal: false, vertical: appState.overlayPhase != .chat)
    }

    // MARK: - Content (Zero-Chrome)

    @ViewBuilder
    private var contentView: some View {
        answerBody

        if appState.overlayPhase == .result {
            resultActionRow
        }
    }

    private var resultActionRow: some View {
        HStack(spacing: 12) {
            Text("Enter to chat")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if appState.canRequestDeeperExplanation {
                Button("More") {
                    appState.requestDeeperExplanation()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .underline()
            }

            Button("Copy") {
                _ = appState.copyCurrentExplanation()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .underline()
            .disabled(!appState.canCopyCurrentExplanation)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Answer Body

    @ViewBuilder
    private var answerBody: some View {
        let hasText = appState.hasMeaningfulExplanationText

        VStack(alignment: .leading, spacing: 6) {
            if appState.overlayPhase == .loadingPreToken {
                VStack(alignment: .leading, spacing: 8) {
                    if let selected = appState.currentContext?.selectedText {
                        Text("\u{201C}\(selected.truncated(to: 80))\u{201D}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .italic()
                    }

                    ShimmerView()
                }
            }

            StreamingTextView(
                text: appState.explanationText,
                isStreaming: appState.overlayPhase == .loadingStreaming && hasText
            )

            if appState.overlayPhase == .loadingStreaming && hasText {
                HStack(spacing: 6) {
                    Text("Generating...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\u{00B7}")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button("Cancel") {
                        appState.cancelGeneration()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Error

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if message.contains("API key") {
                    Button("Open Settings") {
                        openSettingsWindow()
                        appState.dismiss()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }

                Button("Retry") {
                    appState.retryLastRequest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Permission (Graceful Flow)

    @ViewBuilder
    private func permissionRequiredView() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Clarify needs permission to read selected text.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if appState.permissionGranted {
                Label("You\u{2019}re all set.", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            appState.handleHotkey(isDoublePress: false)
                        }
                    }
            } else {
                Button("Enable") {
                    appState.permissionManager.openAccessibilitySettings()
                    appState.permissionManager.requestPermission()
                    startPermissionPolling()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onDisappear {
            permissionPollingTask?.cancel()
            permissionPollingTask = nil
        }
    }

    // MARK: - Empty

    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No explanation text received")
                .font(.callout.weight(.semibold))

            Text("Select text in another app, then press your hotkey again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        AppDelegate.requestSettingsWindow()

        if NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            return
        }
        _ = NSApplication.shared.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    private func startPermissionPolling() {
        permissionPollingTask?.cancel()
        permissionPollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.permissionPollInterval))
                if Task.isCancelled { break }
                appState.permissionManager.refreshPermissionStatus()
                appState.permissionGranted = appState.permissionManager.isAccessibilityGranted
                if appState.permissionGranted { break }
            }
        }
    }
}
