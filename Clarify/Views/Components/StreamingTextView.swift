import SwiftUI

struct StreamingTextView: View {
    let text: String
    let isStreaming: Bool
    @State private var displayedText: String = ""
    @State private var revealTask: Task<Void, Never>?
    @State private var revealGeneration: Int = 0

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(displayedText)
                .font(.system(.callout, design: .default))
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if isStreaming && !displayedText.isEmpty {
                cursor
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            displayedText = text
            pendingText = text
        }
        .onChange(of: text) { _, newValue in
            handleIncomingText(newValue)
        }
        .onChange(of: isStreaming) { _, newValue in
            if !newValue {
                revealTask?.cancel()
                revealTask = nil
                displayedText = text
                pendingText = text
            }
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private var cursor: some View {
        Text("|")
            .font(.callout)
            .foregroundStyle(.secondary)
            .opacity(cursorOpacity)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isStreaming)
    }

    @State private var cursorOpacity: Double = 1.0

    init(text: String, isStreaming: Bool) {
        self.text = text
        self.isStreaming = isStreaming
    }

    private func handleIncomingText(_ newValue: String) {
        if newValue.isEmpty {
            revealTask?.cancel()
            revealTask = nil
            displayedText = ""
            pendingText = ""
            return
        }

        guard isStreaming else {
            revealTask?.cancel()
            revealTask = nil
            displayedText = newValue
            pendingText = ""
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
    }

    @State private var pendingText: String = ""

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
        // Grab leading whitespace + next word
        var end = text.startIndex
        // Include leading whitespace
        while end < text.endIndex, text[end].isWhitespace || text[end].isNewline {
            end = text.index(after: end)
        }
        // Include word characters
        while end < text.endIndex, !text[end].isWhitespace, !text[end].isNewline {
            end = text.index(after: end)
        }
        return end > text.startIndex ? String(text[text.startIndex..<end]) : String(text.prefix(1))
    }
}
