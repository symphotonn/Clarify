import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isInputFocused: Bool

    var body: some View {
        if let chatSession = appState.chatSession {
            VStack(alignment: .leading, spacing: 10) {
                summaryCard

                Divider()

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
                Text("Press Esc to return.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let selectedText = appState.currentContext?.selectedText,
               !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\u{201C}\(selectedText.truncated(to: 90))\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .italic()
            }

            Text(appState.explanationText.truncated(to: 180))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messagesView(chatSession: ChatSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chatSession.visibleMessages) { message in
                        ChatBubble(
                            message: message,
                            isStreaming: chatSession.isStreaming && chatSession.streamingMessageID == message.id
                        )
                            .id(message.id)
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

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 28)
            }

            WordByWordText(text: message.content, isStreaming: isStreaming)
                .font(.callout)
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
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
            return Color.accentColor.opacity(0.22)
        case .assistant:
            return Color.gray.opacity(0.16)
        case .system:
            return Color.clear
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user:
            return .primary
        case .assistant:
            return .primary
        case .system:
            return .secondary
        }
    }
}

private struct WordByWordText: View {
    let text: String
    let isStreaming: Bool

    @State private var displayedText: String = ""
    @State private var pendingText: String = ""
    @State private var revealTask: Task<Void, Never>?
    @State private var finalFlushTask: Task<Void, Never>?
    @State private var revealGeneration: Int = 0
    @State private var cursorOpacity: Double = 1.0

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(displayedText)
                .fixedSize(horizontal: false, vertical: true)

            if isStreaming && !displayedText.isEmpty {
                Text("|")
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
            finalFlushTask?.cancel()
            finalFlushTask = nil
        }
    }

    private func handleIncomingText(_ newValue: String) {
        if newValue.isEmpty {
            revealTask?.cancel()
            revealTask = nil
            finalFlushTask?.cancel()
            finalFlushTask = nil
            displayedText = ""
            pendingText = ""
            return
        }

        if newValue == displayedText {
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
        startWordRevealIfNeeded()
        if !isStreaming {
            scheduleFinalFlushIfNeeded()
        }
    }

    private func handleStreamingStateChange(isStreaming: Bool) {
        if isStreaming {
            finalFlushTask?.cancel()
            finalFlushTask = nil
            return
        }
        scheduleFinalFlushIfNeeded()
    }

    private func scheduleFinalFlushIfNeeded() {
        finalFlushTask?.cancel()
        guard pendingText.count > displayedText.count else {
            finalFlushTask = nil
            return
        }

        finalFlushTask = Task {
            try? await Task.sleep(for: .milliseconds(Constants.completionFinalFlushMs))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                if pendingText.count > displayedText.count {
                    displayedText = pendingText
                }
                finalFlushTask = nil
            }
        }
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
