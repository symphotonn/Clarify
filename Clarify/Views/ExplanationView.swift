import SwiftUI
import AppKit

struct ExplanationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.clarifyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var permissionPollingTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            VisualEffectBackground()

            VStack(alignment: .leading, spacing: 8) {
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
            .animation(
                reduceMotion ? nil : .easeInOut(duration: Constants.phaseTransitionDuration),
                value: appState.overlayPhase
            )
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
        VStack(spacing: 0) {
            if appState.shouldShowIncompleteRetryHint {
                HStack {
                    Text("Incomplete response")
                        .font(.caption2)
                        .foregroundStyle(theme.tertiary)
                    Button("Retry") {
                        appState.retryLastRequest()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(theme.tertiary)
                    .underline()
                    Spacer()
                }
                .padding(.bottom, 8)
            }

            theme.divider
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, -16)

            HStack {
                ActionButton(label: "Chat", glyph: "\u{21B5}", theme: theme) {
                    appState.enterChatMode()
                }
                .accessibilityLabel("Enter chat mode, press Return")

                Spacer()

                ActionButton(label: "Copy", glyph: "\u{2318}C", theme: theme) {
                    _ = appState.copyCurrentExplanation()
                }
                .disabled(!appState.canCopyCurrentExplanation)
                .accessibilityLabel("Copy explanation, press Command C")
            }
            .padding(.top, Constants.actionBarSpacing)
        }
    }

    // MARK: - Answer Body

    @ViewBuilder
    private var answerBody: some View {
        let hasText = appState.hasMeaningfulExplanationText

        VStack(alignment: .leading, spacing: 8) {
            if let selected = appState.currentContext?.selectedText,
               selected.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 {
                Text("\u{201C}\(selected.truncated(to: 80))\u{201D}")
                    .font(.caption)
                    .foregroundStyle(theme.tertiary)
                    .lineLimit(2)
                    .italic()
            }

            if appState.overlayPhase == .loadingPreToken {
                ShimmerView(stageText: appState.generationStage.loadingLabel)
            }

            if appState.overlayPhase == .loadingStreaming && hasText {
                StreamingTextView(
                    text: appState.explanationText,
                    isStreaming: true
                )
            } else if appState.overlayPhase == .result {
                MarkdownText(markdown: appState.explanationText)
            }

            if appState.overlayPhase == .loadingStreaming && hasText {
                HStack(spacing: 4) {
                    Text("Generating...")
                        .font(.caption2)
                        .foregroundStyle(theme.tertiary)
                    Text("\u{00B7}")
                        .font(.caption2)
                        .foregroundStyle(theme.tertiary)
                    Button("Cancel") {
                        appState.cancelGeneration()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(theme.tertiary)
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
                .foregroundStyle(theme.error)

            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.body)
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
                .foregroundStyle(theme.info)

            Text("Clarify needs permission to read selected text.")
                .font(.callout)
                .foregroundStyle(theme.body)
                .multilineTextAlignment(.center)

            if appState.permissionGranted {
                Label("You\u{2019}re all set.", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.success)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            appState.handleHotkey()
                        }
                    }
            } else {
                Button("Enable") {
                    appState.permissionManager.openAccessibilitySettings()
                    startPermissionPolling()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Text("Toggle Clarify \u{2192} ON, then come back.")
                    .font(.caption)
                    .foregroundStyle(theme.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear {
            startPermissionPolling()
        }
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
                .foregroundStyle(theme.tertiary)

            Text("Nothing to explain yet")
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.headline)

            Text("Highlight some text, then press your hotkey again.")
                .font(.callout)
                .foregroundStyle(theme.tertiary)
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

// MARK: - Action Button with Hover State

private struct ActionButton: View {
    let label: String
    let glyph: String
    let theme: ClarifyTheme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                KeyboardGlyph(glyph: glyph)
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(theme.tertiary)
            .opacity(isHovered ? 1.0 : 0.8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
