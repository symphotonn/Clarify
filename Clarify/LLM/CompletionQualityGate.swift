import Foundation

enum CompletionFailureReason: Equatable, Sendable {
    case empty
    case missingTerminalPunctuation
    case danglingSuffix
    case unmatchedDelimiter
    case unmatchedQuote
}

enum CompletionQualityGate {
    private static let terminalPunctuation = CharacterSet(charactersIn: ".!?")
    private static let trailingClosers = CharacterSet(charactersIn: "\"'”’)]}")
    private static let danglingSuffixes = [
        " a", " an", " the", " to", " of", " for", " with", " in", " on", " by", " at", " from", " as",
        " and", " or", " but", " if", " when", " that", " this", " these", " those",
        " refers to", " means", " is", " are", " was", " were", " because", " since", " unless"
    ]

    static func isComplete(_ text: String) -> Bool {
        reasons(for: text).isEmpty
    }

    static func reasons(for text: String) -> [CompletionFailureReason] {
        let sanitized = sanitizeForStructureChecks(text)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [.empty] }

        var failures: [CompletionFailureReason] = []

        if !hasTerminalSentencePunctuation(trimmed) {
            failures.append(.missingTerminalPunctuation)
        }
        if hasDanglingSuffix(trimmed) {
            failures.append(.danglingSuffix)
        }
        if hasUnmatchedDelimiters(trimmed) {
            failures.append(.unmatchedDelimiter)
        }
        if hasUnmatchedQuotes(trimmed) {
            failures.append(.unmatchedQuote)
        }

        return failures
    }

    static func sanitizeForStructureChecks(_ text: String) -> String {
        stripFencedCodeBlocks(from: text)
    }

    private static func hasTerminalSentencePunctuation(_ text: String) -> Bool {
        var end = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let scalar = end.unicodeScalars.last, trailingClosers.contains(scalar) {
            end.removeLast()
            end = end.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let last = end.unicodeScalars.last else { return false }
        return terminalPunctuation.contains(last)
    }

    private static func hasDanglingSuffix(_ text: String) -> Bool {
        let lower = text.lowercased()
        return danglingSuffixes.contains(where: { lower.hasSuffix($0) })
    }

    private static func hasUnmatchedDelimiters(_ text: String) -> Bool {
        var stack: [Character] = []
        let openerForCloser: [Character: Character] = [")": "(", "]": "[", "}": "{"]

        for char in text {
            switch char {
            case "(", "[", "{":
                stack.append(char)
            case ")", "]", "}":
                guard let expected = openerForCloser[char], stack.last == expected else {
                    return true
                }
                _ = stack.popLast()
            default:
                continue
            }
        }

        return !stack.isEmpty
    }

    private static func hasUnmatchedQuotes(_ text: String) -> Bool {
        var straightDoubleCount = 0
        var escaped = false
        var leftCurlyCount = 0
        var rightCurlyCount = 0

        for char in text {
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" {
                escaped = true
                continue
            }
            switch char {
            case "\"":
                straightDoubleCount += 1
            case "“":
                leftCurlyCount += 1
            case "”":
                rightCurlyCount += 1
            default:
                continue
            }
        }

        let straightUnmatched = straightDoubleCount % 2 != 0
        let curlyUnmatched = leftCurlyCount != rightCurlyCount
        return straightUnmatched || curlyUnmatched
    }

    private static func stripFencedCodeBlocks(from text: String) -> String {
        let fence = "```"
        var remaining = text[...]
        var output = ""

        while let start = remaining.range(of: fence) {
            output += remaining[..<start.lowerBound]
            let afterStart = remaining[start.upperBound...]
            guard let end = afterStart.range(of: fence) else {
                return output
            }
            remaining = afterStart[end.upperBound...]
        }

        output += remaining
        return output
    }
}
