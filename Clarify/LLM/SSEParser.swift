import Foundation

/// Parses Server-Sent Events from the OpenAI Chat Completions API.
/// Chat Completions streams `data:` lines (no `event:` field).
/// Content arrives in `choices[0].delta.content`.
/// Stream ends with `data: [DONE]`.
final class SSEParser {
    private var buffer = ""

    /// Feed raw text data into the parser. Returns parsed stream events.
    func parse(_ chunk: String) -> [StreamEvent] {
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
        var events: [StreamEvent] = []

        while let blankLineRange = buffer.range(of: "\n\n") {
            let block = String(buffer[buffer.startIndex..<blankLineRange.lowerBound])
            buffer = String(buffer[blankLineRange.upperBound...])

            for event in processBlock(block) {
                events.append(event)
            }
        }

        return events
    }

    /// Flushes any trailing non-terminated frame when the stream closes.
    func finish() -> [StreamEvent] {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !trimmed.isEmpty else { return [] }
        return processBlock(trimmed)
    }

    private func processBlock(_ block: String) -> [StreamEvent] {
        var events: [StreamEvent] = []

        for line in block.components(separatedBy: "\n") {
            guard line.hasPrefix("data:") else { continue }
            let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

            if data == "[DONE]" {
                events.append(.done)
                continue
            }

            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Check for error responses
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String, !message.isEmpty {
                events.append(.error(message))
                continue
            }

            // Extract delta content from choices[0].delta.content
            guard let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first else {
                continue
            }

            // Check finish_reason
            if let finishReason = first["finish_reason"] as? String, !finishReason.isEmpty {
                if finishReason == "stop" || finishReason == "length" {
                    // Will get [DONE] next, but extract any remaining content first
                }
            }

            if let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                events.append(.delta(content))
            }
        }

        return events
    }

    func reset() {
        buffer = ""
    }
}
