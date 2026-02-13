import AppKit

extension CGPoint {
    func offsetBy(dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}

extension NSScreen {
    /// Converts a point from AX coordinate system (origin top-left) to AppKit (origin bottom-left).
    static func convertFromAX(_ axPoint: CGPoint, height: CGFloat = 0) -> CGPoint {
        guard let mainScreen = NSScreen.main else { return axPoint }
        let screenHeight = mainScreen.frame.height
        return CGPoint(x: axPoint.x, y: screenHeight - axPoint.y - height)
    }

    /// Returns the screen containing the given point (AppKit coordinates).
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSPointInRect(point, $0.frame) }
    }
}

extension String {
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength)) + "..."
    }

    /// Extracts surrounding lines centered around a range in the full text.
    /// Includes the exact line that contains the selection.
    func surroundingLines(around range: Range<String.Index>, count: Int) -> String {
        let lineStart = self[..<range.lowerBound]
            .lastIndex(of: "\n")
            .map { index(after: $0) } ?? startIndex
        let lineEnd = self[range.upperBound...]
            .firstIndex(of: "\n") ?? endIndex

        let selectedLine = String(self[lineStart..<lineEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let beforeText = self[startIndex..<lineStart]
        let afterStart = lineEnd < endIndex ? index(after: lineEnd) : endIndex
        let afterText = self[afterStart..<endIndex]

        let linesBefore = beforeText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(count)
            .map(String.init)
        let linesAfter = afterText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(count)
            .map(String.init)

        var rows: [String] = []
        rows.append(contentsOf: linesBefore)
        if !selectedLine.isEmpty {
            rows.append(selectedLine)
        }
        rows.append(contentsOf: linesAfter)

        let result = rows
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return result.truncated(to: Constants.maxSurroundingContextLength)
    }
}
