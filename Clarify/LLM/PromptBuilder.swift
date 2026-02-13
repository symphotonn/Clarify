import Foundation

enum PromptBuilder {
    private enum ExplanationIntent: String {
        case identifierLookup = "Identifier lookup"
        case conceptExplanation = "Concept explanation"
    }

    private static let codeLikeAppNames: Set<String> = [
        "Xcode",
        "Visual Studio Code",
        "Code",
        "IntelliJ IDEA",
        "Android Studio",
        "Nova",
        "Terminal",
        "iTerm2"
    ]
    private static let codeLikeURLKeywords = [
        "github.com",
        "gitlab.com",
        "bitbucket.org"
    ]
    private static let codeLikeTitleKeywords = [
        ".swift",
        ".ts",
        ".tsx",
        ".js",
        ".py",
        ".kt",
        ".go",
        ".java",
        ".rb",
        "pull request",
        "diff",
        "commit"
    ]

    static func build(
        context: ContextInfo,
        depth: Int,
        previousExplanation: String?
    ) -> PromptParts {
        let wordLimit = depth >= 2 ? Constants.depth2WordLimit : Constants.depth1WordLimit
        let intent = inferIntent(from: context)
        let expertise = inferExpertise(from: context)
        let tone = inferTone(from: context)
        let selectedWordCount = context.selectedText?
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count ?? 0

        let instructions = buildInstructions(
            expertise: expertise,
            tone: tone,
            wordLimit: wordLimit,
            depth: depth,
            intent: intent,
            hasConversationContext: context.isConversationContext
        )
        let input = buildInput(
            context: context,
            depth: depth,
            previousExplanation: previousExplanation,
            intent: intent
        )

        return PromptParts(
            instructions: instructions,
            input: input,
            maxOutputTokens: recommendedMaxOutputTokens(depth: depth, selectedWordCount: selectedWordCount)
        )
    }

    static func inferExpertise(from context: ContextInfo) -> ExpertiseLevel {
        if sourceLooksCodeLike(context) {
            return .expert
        }
        let url = (context.sourceURL ?? "").lowercased()
        if docsURLKeywords.contains(where: { url.contains($0) }) {
            return .intermediate
        }
        return .beginner
    }

    static func inferTone(from context: ContextInfo) -> Tone {
        if sourceLooksCodeLike(context) {
            return .technical
        }
        let url = (context.sourceURL ?? "").lowercased()
        if docsURLKeywords.contains(where: { url.contains($0) }) {
            return .neutral
        }
        return .friendly
    }

    private static let docsURLKeywords = [
        "docs.", "documentation", "developer.apple.com",
        "devdocs.io", "mdn", "readthedocs", "wiki"
    ]

    private static func buildInstructions(
        expertise: ExpertiseLevel,
        tone: Tone,
        wordLimit: Int,
        depth: Int,
        intent: ExplanationIntent,
        hasConversationContext: Bool
    ) -> String {
        var parts: [String] = []

        parts.append("You are Clarify, a concise explanation assistant. Audience: \(expertise.description). Tone: \(tone.description).")
        parts.append("First line: [MODE: Learn], [MODE: Simplify], or [MODE: Diagnose]. Short selections (≤4 words): 1-2 sentences. Max \(wordLimit) words. No markdown emphasis.")
        parts.append("Use provided context. Nearest context > dictionary meaning. Always explain, never refuse.")

        if intent == .identifierLookup {
            parts.append("Treat as identifier. Explain in source context. Use nearby context to disambiguate.")
        }

        if hasConversationContext {
            parts.append("Conversation context may be noisy. Don't infer project structure from chat snippets.")
        }

        if depth >= 2 {
            parts.append("Depth \(depth): add one nuance + one example. Don't repeat prior explanation.")
        }

        return parts.joined(separator: "\n\n")
    }

    private static func buildInput(
        context: ContextInfo,
        depth: Int,
        previousExplanation: String?,
        intent: ExplanationIntent
    ) -> String {
        var parts: [String] = []

        parts.append("Intent: \(intent.rawValue)")
        parts.append("Source: \(sourceSummary(from: context))")
        parts.append("Context quality: \(contextQualitySummary(from: context))")
        parts.append("Nearby context available: \(hasNearbyContext(context) ? "yes" : "no")")

        if let selectedOccurrenceContext = trimmed(context.selectedOccurrenceContext) {
            parts.append("Selected occurrence context:\n\(selectedOccurrenceContext)")
        }
        if let nearest = nearestContextSnippet(from: context) {
            parts.append("Nearest context lines:\n\(nearest)")
        }

        if let text = context.selectedText {
            parts.append("Selected text:\n\(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
            if wordCount <= 4 {
                parts.append("Constraint: explain in 1-2 sentences.")
            }
        }

        parts.append("Constraint: if uncertain, explain the most likely meaning and note any ambiguity briefly.")

        if let prev = previousExplanation, depth >= 2 {
            parts.append("Previous explanation (depth \(depth - 1)):\n\(prev)")
        }

        return parts.joined(separator: "\n\n")
    }

    private static func inferIntent(from context: ContextInfo) -> ExplanationIntent {
        let selected = context.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if looksLikeIdentifier(selected) {
            return .identifierLookup
        }

        if sourceLooksCodeLike(context), selected.split(whereSeparator: \.isWhitespace).count <= 6 {
            return .identifierLookup
        }

        return .conceptExplanation
    }

    private static func sourceLooksCodeLike(_ context: ContextInfo) -> Bool {
        if let appName = context.appName, codeLikeAppNames.contains(appName) {
            return true
        }

        let title = (context.windowTitle ?? "").lowercased()
        if codeLikeTitleKeywords.contains(where: { title.contains($0) }) {
            return true
        }

        let sourceURL = (context.sourceURL ?? "").lowercased()
        if codeLikeURLKeywords.contains(where: { sourceURL.contains($0) }) {
            return true
        }

        return false
    }

    private static func looksLikeIdentifier(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return false }
        if text.contains("`") || text.contains("::") || text.contains("()") || text.contains(".") {
            return true
        }
        if text.contains("_") {
            return true
        }
        if text.range(of: #"^[a-z]+(?:[A-Z][a-z0-9]+)+$"#, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: #"^[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func sourceSummary(from context: ContextInfo) -> String {
        var segments: [String] = []
        if let app = trimmed(context.appName) {
            segments.append(app)
        }
        if let title = trimmed(context.sourceHint ?? context.windowTitle) {
            segments.append("title: \(title)")
        }
        if let url = trimmed(context.sourceURL) {
            segments.append("url: \(url)")
        }
        if segments.isEmpty {
            return "unknown"
        }
        return segments.joined(separator: " | ")
    }

    private static func contextQualitySummary(from context: ContextInfo) -> String {
        if context.isConversationContext {
            return "conversation context excluded by default"
        }

        if trimmed(context.selectedOccurrenceContext) != nil {
            return "selected occurrence available"
        }
        if trimmed(context.surroundingLines) != nil {
            return "nearby lines available"
        }
        return "no nearby context"
    }

    private static func hasNearbyContext(_ context: ContextInfo) -> Bool {
        trimmed(context.selectedOccurrenceContext) != nil || trimmed(context.surroundingLines) != nil
    }

    private static func nearestContextSnippet(from context: ContextInfo) -> String? {
        guard let surrounding = trimmed(context.surroundingLines) else { return nil }
        let lines = surrounding
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.prefix(2).joined(separator: "\n")
    }

    private static func recommendedMaxOutputTokens(depth: Int, selectedWordCount: Int) -> Int {
        if depth <= 1 {
            if selectedWordCount <= 4 {
                return 80
            }
            return 120
        }
        return 180
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
