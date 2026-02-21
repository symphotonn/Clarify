import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.clarifyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool

    var body: some View {
        if let chatSession = appState.chatSession {
            VStack(alignment: .leading, spacing: 8) {
                summaryCard

                theme.divider
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity)

                messagesView(chatSession: chatSession)

                composer(chatSession: chatSession)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isInputFocused = true
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chat unavailable")
                    .font(.headline)
                    .foregroundStyle(theme.headline)
                Text("Press Esc to return.")
                    .font(.caption)
                    .foregroundStyle(theme.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let selectedText = appState.currentContext?.selectedText,
               !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\u{201C}\(selectedText.truncated(to: 90))\u{201D}")
                    .font(.caption)
                    .foregroundStyle(theme.tertiary)
                    .lineLimit(2)
                    .italic()
            }

            Text(appState.explanationText.truncated(to: 180))
                .font(.caption)
                .foregroundStyle(theme.tertiary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messagesView(chatSession: ChatSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(chatSession.visibleMessages.enumerated()), id: \.element.id) { index, message in
                        ChatBubble(
                            message: message,
                            isStreaming: chatSession.isStreaming && chatSession.streamingMessageID == message.id
                        )
                            .id(message.id)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    )
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                scrollToBottom(chatSession: chatSession, proxy: proxy)
            }
            .onChange(of: chatSession.visibleMessages.count) { _, _ in
                scrollToBottom(chatSession: chatSession, proxy: proxy)
            }
            .onChange(of: chatSession.visibleMessages.last?.content ?? "") { _, _ in
                scrollToBottom(chatSession: chatSession, proxy: proxy)
            }
        }
    }

    private func composer(chatSession: ChatSession) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask a follow-up...", text: Binding(
                get: { chatSession.currentInput },
                set: { chatSession.currentInput = $0 }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .focused($isInputFocused)
            .onSubmit {
                appState.sendChatMessage()
            }

            if chatSession.isStreaming {
                Button("Stop") {
                    appState.stopChatStreaming()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Send") {
                    appState.sendChatMessage()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!chatSession.canSend)
            }
        }
    }

    private func scrollToBottom(chatSession: ChatSession, proxy: ScrollViewProxy) {
        guard let lastID = chatSession.visibleMessages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ConversationMessage
    let isStreaming: Bool
    @Environment(\.clarifyTheme) private var theme

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 28)
            }

            WordByWordText(text: message.content, isStreaming: isStreaming)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: 270, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return theme.userBubble
        case .assistant:
            return theme.assistantBubble
        case .system:
            return Color.clear
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user:
            return theme.body
        case .assistant:
            return theme.body
        case .system:
            return theme.tertiary
        }
    }
}

private struct WordByWordText: View {
    let text: String
    let isStreaming: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedText: String = ""
    @State private var pendingText: String = ""
    @State private var revealTask: Task<Void, Never>?
    @State private var revealGeneration: Int = 0
    @State private var cursorOpacity: Double = 1.0

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(displayedText)
                .fixedSize(horizontal: false, vertical: true)

            if isStreaming && !displayedText.isEmpty && !reduceMotion {
                Text("\u{258E}")
                    .opacity(cursorOpacity)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isStreaming)
            }
        }
        .onAppear {
            displayedText = text
            pendingText = text
        }
        .onChange(of: text) { _, newValue in
            handleIncomingText(newValue)
        }
        .onChange(of: isStreaming) { _, newValue in
            handleStreamingStateChange(isStreaming: newValue)
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private func handleIncomingText(_ newValue: String) {
        if newValue.isEmpty {
            revealTask?.cancel()
            revealTask = nil
            displayedText = ""
            pendingText = ""
            return
        }

        if newValue == displayedText && newValue == pendingText {
            return
        }

        // When not streaming and no active reveal animation, snap immediately.
        if !isStreaming && revealTask == nil {
            revealTask?.cancel()
            revealTask = nil
            pendingText = newValue
            displayedText = newValue
            return
        }

        guard newValue.hasPrefix(displayedText) || newValue.hasPrefix(pendingText) else {
            revealTask?.cancel()
            revealTask = nil
            displayedText = newValue
            pendingText = newValue
            return
        }

        pendingText = newValue

        if reduceMotion {
            displayedText = newValue
        } else {
            startWordRevealIfNeeded()
        }
    }

    private func handleStreamingStateChange(isStreaming: Bool) {
        if isStreaming { return }
        // Snap to final text when streaming ends
        revealTask?.cancel()
        revealTask = nil
        displayedText = pendingText
    }

    private func startWordRevealIfNeeded() {
        guard revealTask == nil else { return }
        revealGeneration += 1
        let generation = revealGeneration

        revealTask = Task {
            while !Task.isCancelled {
                let pending = await MainActor.run { pendingText }
                let displayed = await MainActor.run { displayedText }

                guard pending.count > displayed.count else { break }

                let remaining = String(pending.dropFirst(displayed.count))
                let nextWord = extractNextWord(from: remaining)

                await MainActor.run {
                    displayedText.append(contentsOf: nextWord)
                }

                try? await Task.sleep(for: .milliseconds(35))
            }

            await MainActor.run {
                if revealGeneration == generation {
                    revealTask = nil
                    if pendingText.count > displayedText.count {
                        startWordRevealIfNeeded()
                    }
                }
            }
        }
    }

    private func extractNextWord(from text: String) -> String {
        var end = text.startIndex
        while end < text.endIndex, text[end].isWhitespace || text[end].isNewline {
            end = text.index(after: end)
        }
        while end < text.endIndex, !text[end].isWhitespace, !text[end].isNewline {
            end = text.index(after: end)
        }
        return end > text.startIndex ? String(text[text.startIndex..<end]) : String(text.prefix(1))
    }
}
