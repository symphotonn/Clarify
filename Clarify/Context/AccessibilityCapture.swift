import AppKit
import ApplicationServices
import Vision

enum AccessibilityCapture {
    enum CapturePolicy {
        case fastFirst
        case full
    }

    private static var didRequestScreenCapturePermission = false
    private static let supportedBrowserNames: Set<String> = [
        "Google Chrome",
        "Google Chrome Canary",
        "Brave Browser",
        "Microsoft Edge",
        "Arc",
        "Chromium",
        "Safari"
    ]
    private static let conversationAppNames: Set<String> = [
        "ChatGPT",
        "Claude",
        "Slack",
        "Discord",
        "Messages",
        "Telegram",
        "WeChat",
        "Microsoft Teams",
        "WhatsApp",
        "LINE"
    ]
    private static let conversationURLKeywords = [
        "chatgpt.com",
        "claude.ai",
        "slack.com",
        "discord.com",
        "teams.microsoft.com",
        "web.whatsapp.com",
        "messenger.com"
    ]
    private static let conversationTitleKeywords = [
        "chatgpt",
        "claude",
        "slack",
        "discord",
        "messenger",
        "inbox",
        "direct message"
    ]

    static func captureContext(policy: CapturePolicy = .full, budgetMs: Int? = nil) -> ContextInfo {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName
        let systemWideElement = AXUIElementCreateSystemWide()

        // Get focused element
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard focusedResult == .success, let focusedElement = focusedValue else {
            return clipboardFallback(
                appName: appName,
                focusedElement: nil,
                policy: policy,
                budgetMs: budgetMs,
                startedAt: startedAt
            )
        }

        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return clipboardFallback(
                appName: appName,
                focusedElement: nil,
                policy: policy,
                budgetMs: budgetMs,
                startedAt: startedAt
            )
        }
        let focused = unsafeBitCast(focusedElement, to: AXUIElement.self)

        // Get selected text
        var selectedTextValue: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedTextValue)

        let selectedText: String?
        if textResult == .success, let text = selectedTextValue as? String, !text.isEmpty {
            selectedText = text.truncated(to: Constants.maxSelectionLength)
        } else {
            return clipboardFallback(
                appName: appName,
                focusedElement: focused,
                policy: policy,
                budgetMs: budgetMs,
                startedAt: startedAt
            )
        }

        // Get selection bounds
        let selectionBounds = getSelectionBounds(element: focused)

        // Get window title
        var windowTitle = getWindowTitle(from: focused)
        var sourceURL: String?
        var sourceHint: String?
        var isConversationContext = isConversationSource(
            appName: appName,
            windowTitle: windowTitle,
            sourceURL: nil
        )

        // Get surrounding text and selected occurrence with a single AX read pass.
        let axContext = extractAXTextContext(element: focused)
        var surroundingLines = axContext.surroundingLines
        var selectedOccurrenceContext =
            axContext.selectedOccurrenceContext
            ?? inferOccurrenceContext(selectedText: selectedText, surroundingLines: surroundingLines)

        (surroundingLines, selectedOccurrenceContext) = sanitizeContext(
            selectedText: selectedText,
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext
        )

        if policy == .full,
           hasBudgetRemaining(startedAt: startedAt, budgetMs: budgetMs, policy: policy, reserveMs: 25) {
            let browserContext = captureBrowserDOMContext(
                appName: appName,
                selectedText: selectedText
            )
            if surroundingLines == nil {
                surroundingLines = browserContext?.surroundingLines
            }
            if selectedOccurrenceContext == nil {
                selectedOccurrenceContext = browserContext?.selectedOccurrenceContext
            }
            if let browserTitle = browserContext?.pageTitle {
                sourceHint = browserTitle
                if windowTitle == nil {
                    windowTitle = browserTitle
                }
            }
            if let browserURL = browserContext?.pageURL {
                sourceURL = browserURL
            }
            if browserContext?.isLikelyConversation == true {
                isConversationContext = true
            }
        }

        (surroundingLines, selectedOccurrenceContext) = sanitizeContext(
            selectedText: selectedText,
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext
        )

        if policy == .full && (surroundingLines == nil || selectedOccurrenceContext == nil) {
            let ocrContext = captureContextViaOCR(
                selectedText: selectedText,
                selectionBoundsAX: selectionBounds
            )
            if surroundingLines == nil {
                surroundingLines = ocrContext?.surroundingLines
            }
            if selectedOccurrenceContext == nil {
                selectedOccurrenceContext = ocrContext?.selectedOccurrenceContext
            }
        }

        (surroundingLines, selectedOccurrenceContext) = sanitizeContext(
            selectedText: selectedText,
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext
        )
        (surroundingLines, selectedOccurrenceContext) = applyContextTrustPolicy(
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext,
            isConversationContext: isConversationContext
        )
        let isPartialContext = policy == .fastFirst || selectedOccurrenceContext == nil || surroundingLines == nil

        return ContextInfo(
            selectedText: selectedText,
            appName: appName,
            windowTitle: windowTitle,
            surroundingLines: surroundingLines,
            selectionBounds: selectionBounds,
            selectedOccurrenceContext: selectedOccurrenceContext,
            sourceURL: sourceURL,
            sourceHint: sourceHint,
            isConversationContext: isConversationContext,
            isPartialContext: isPartialContext
        )
    }

    // MARK: - Selection Bounds

    private static func getSelectionBounds(element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard rangeResult == .success, let range = rangeValue else { return nil }

        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        )

        guard boundsResult == .success, let bounds = boundsValue else { return nil }
        guard CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        if AXValueGetValue(unsafeBitCast(bounds, to: AXValue.self), .cgRect, &rect) {
            return rect
        }
        return nil
    }

    // MARK: - Window Title

    private static func getWindowTitle(from element: AXUIElement) -> String? {
        var current: AXUIElement = element

        for _ in 0..<10 {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)

            if let role = roleValue as? String, role == kAXWindowRole as String {
                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(current, kAXTitleAttribute as CFString, &titleValue)
                return titleValue as? String
            }

            var parentValue: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard parentResult == .success, let parent = parentValue else { break }
            guard CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }

        return nil
    }

    // MARK: - Surrounding Text

    private static func getSurroundingText(element: AXUIElement) -> String? {
        extractAXTextContext(element: element).surroundingLines
    }

    private static func getSelectedOccurrenceContext(element: AXUIElement) -> String? {
        extractAXTextContext(element: element).selectedOccurrenceContext
    }

    private static func extractAXTextContext(element: AXUIElement) -> (surroundingLines: String?, selectedOccurrenceContext: String?) {
        guard let (fullText, swiftRange) = getTextAndSelectedRange(element: element) else { return (nil, nil) }

        let surroundingLines = fullText.surroundingLines(around: swiftRange, count: Constants.surroundingLineCount)

        let lineStart = fullText[..<swiftRange.lowerBound]
            .lastIndex(of: "\n")
            .map { fullText.index(after: $0) } ?? fullText.startIndex
        let lineEnd = fullText[swiftRange.upperBound...]
            .firstIndex(of: "\n") ?? fullText.endIndex

        let line = String(fullText[lineStart..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedOccurrenceContext = line.isEmpty ? nil : line.truncated(to: Constants.maxSelectedOccurrenceContextLength)
        return (surroundingLines, selectedOccurrenceContext)
    }

    private static func getTextAndSelectedRange(element: AXUIElement) -> (String, Range<String.Index>)? {
        if let direct = getTextAndSelectedRangeFromValueAttribute(element: element) {
            return direct
        }
        return getTextAndSelectedRangeFromParameterizedRange(element: element)
    }

    private static func getTextAndSelectedRangeFromValueAttribute(element: AXUIElement) -> (String, Range<String.Index>)? {
        var fullTextValue: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &fullTextValue)
        guard textResult == .success, let fullText = fullTextValue as? String else { return nil }

        guard let cfRange = getSelectedTextRange(element: element) else { return nil }

        let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
        guard let swiftRange = Range(nsRange, in: fullText) else { return nil }

        return (fullText, swiftRange)
    }

    private static func getTextAndSelectedRangeFromParameterizedRange(element: AXUIElement) -> (String, Range<String.Index>)? {
        guard let selectedRange = getSelectedTextRange(element: element),
              selectedRange.location >= 0 else {
            return nil
        }

        let selectionLength = max(selectedRange.length, 1)
        let contextRadii = [320, 220, 120, 0]

        for radius in contextRadii {
            let lowerBound = max(0, selectedRange.location - radius)
            let upperBound = selectedRange.location + selectionLength + radius
            let expanded = CFRange(location: lowerBound, length: max(1, upperBound - lowerBound))

            guard let textWindow = stringForRange(expanded, element: element) else {
                continue
            }

            let relativeLocation = max(0, selectedRange.location - lowerBound)
            let relativeLength = min(selectionLength, max(0, textWindow.utf16.count - relativeLocation))
            let range = NSRange(location: relativeLocation, length: relativeLength)

            if let swiftRange = Range(range, in: textWindow) {
                return (textWindow, swiftRange)
            }

            if let selectedText = selectedTextFromAX(element: element),
               let matchedRange = textWindow.range(of: selectedText, options: [.caseInsensitive, .diacriticInsensitive]) {
                return (textWindow, matchedRange)
            }
        }

        return nil
    }

    private static func getSelectedTextRange(element: AXUIElement) -> CFRange? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard rangeResult == .success, let range = rangeValue else { return nil }
        guard CFGetTypeID(range) == AXValueGetTypeID() else { return nil }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(unsafeBitCast(range, to: AXValue.self), .cfRange, &cfRange) else { return nil }
        return cfRange
    }

    private static func stringForRange(_ range: CFRange, element: AXUIElement) -> String? {
        var localRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &localRange) else { return nil }

        var textValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &textValue
        )
        guard result == .success else { return nil }

        if let text = textValue as? String, !text.isEmpty {
            return text
        }
        if let attributed = textValue as? NSAttributedString, !attributed.string.isEmpty {
            return attributed.string
        }
        return nil
    }

    private static func selectedTextFromAX(element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard result == .success, let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Clipboard Fallback

    private static func clipboardFallback(
        appName: String?,
        focusedElement: AXUIElement?,
        policy: CapturePolicy,
        budgetMs: Int?,
        startedAt: CFAbsoluteTime
    ) -> ContextInfo {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousItems = capturePasteboardItems(pasteboard)

        // Simulate Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true) // 8 = 'c'
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Poll briefly for pasteboard updates; some apps post copied text asynchronously.
        let fallbackTimeout = policy == .fastFirst
            ? Constants.fastClipboardFallbackTimeout
            : Constants.clipboardFallbackTimeout
        var selectedText = readClipboardSelection(
            pasteboard: pasteboard,
            previousChangeCount: previousChangeCount,
            timeout: fallbackTimeout
        )

        // Restore previous pasteboard content
        restorePasteboardItems(previousItems, to: pasteboard)

        var windowTitle = focusedElement.flatMap { getWindowTitle(from: $0) }
        var sourceURL: String?
        var sourceHint: String?
        var isConversationContext = isConversationSource(
            appName: appName,
            windowTitle: windowTitle,
            sourceURL: nil
        )
        let axContext = focusedElement.map { extractAXTextContext(element: $0) }
        var surroundingLines = axContext?.surroundingLines
        let selectionBounds = focusedElement.flatMap { getSelectionBounds(element: $0) }
        var selectedOccurrenceContext =
            axContext?.selectedOccurrenceContext
            ?? inferOccurrenceContext(selectedText: selectedText, surroundingLines: surroundingLines)

        (surroundingLines, selectedOccurrenceContext) = sanitizeContext(
            selectedText: selectedText,
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext
        )

        if policy == .full,
           hasBudgetRemaining(startedAt: startedAt, budgetMs: budgetMs, policy: policy, reserveMs: 25) {
            let browserContext = captureBrowserDOMContext(
                appName: appName,
                selectedText: selectedText
            )
            if selectedText == nil {
                selectedText = browserContext?.selectedText?.truncated(to: Constants.maxSelectionLength)
            }
            if surroundingLines == nil {
                surroundingLines = browserContext?.surroundingLines
            }
            if selectedOccurrenceContext == nil {
                selectedOccurrenceContext = browserContext?.selectedOccurrenceContext
            }
            if let browserTitle = browserContext?.pageTitle {
                sourceHint = browserTitle
                if windowTitle == nil {
                    windowTitle = browserTitle
                }
            }
            if let browserURL = browserContext?.pageURL {
                sourceURL = browserURL
            }
            if browserContext?.isLikelyConversation == true {
                isConversationContext = true
            }
        }

        (surroundingLines, selectedOccurrenceContext) = sanitizeContext(
            selectedText: selectedText,
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext
        )

        if policy == .full && (surroundingLines == nil || selectedOccurrenceContext == nil) {
            let ocrContext = captureContextViaOCR(
                selectedText: selectedText,
                selectionBoundsAX: selectionBounds
            )
            if surroundingLines == nil {
                surroundingLines = ocrContext?.surroundingLines
            }
            if selectedOccurrenceContext == nil {
                selectedOccurrenceContext = ocrContext?.selectedOccurrenceContext
            }
        }

        (surroundingLines, selectedOccurrenceContext) = sanitizeContext(
            selectedText: selectedText,
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext
        )
        (surroundingLines, selectedOccurrenceContext) = applyContextTrustPolicy(
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext,
            isConversationContext: isConversationContext
        )
        let isPartialContext = policy == .fastFirst || selectedOccurrenceContext == nil || surroundingLines == nil

        return ContextInfo(
            selectedText: selectedText,
            appName: appName,
            windowTitle: windowTitle,
            surroundingLines: surroundingLines,
            selectionBounds: selectionBounds,
            selectedOccurrenceContext: selectedOccurrenceContext,
            sourceURL: sourceURL,
            sourceHint: sourceHint,
            isConversationContext: isConversationContext,
            isPartialContext: isPartialContext
        )
    }

    private static func capturePasteboardItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }

        return items.map { item in
            let snapshot = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot.setData(data, forType: type)
                }
            }
            return snapshot
        }
    }

    private static func restorePasteboardItems(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }

    private static func readClipboardSelection(
        pasteboard: NSPasteboard,
        previousChangeCount: Int,
        timeout: TimeInterval
    ) -> String? {
        let pollInterval: TimeInterval = 0.01
        let deadline = Date().addingTimeInterval(max(0, timeout))

        while true {
            if pasteboard.changeCount != previousChangeCount,
               let copied = pasteboard.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
               !copied.isEmpty {
                return copied.truncated(to: Constants.maxSelectionLength)
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                return nil
            }
            Thread.sleep(forTimeInterval: min(pollInterval, remaining))
        }
    }

    private static func inferOccurrenceContext(selectedText: String?, surroundingLines: String?) -> String? {
        guard let selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty,
              let surroundingLines else {
            return nil
        }

        let candidates = surroundingLines
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let matchedLine = candidates.first(where: {
            $0.range(of: selectedText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }) else {
            return nil
        }

        return matchedLine.truncated(to: Constants.maxSelectedOccurrenceContextLength)
    }

    private struct BrowserDOMContext {
        let selectedText: String?
        let surroundingLines: String?
        let selectedOccurrenceContext: String?
        let pageTitle: String?
        let pageURL: String?
        let isLikelyConversation: Bool
    }

    private static func captureBrowserDOMContext(appName: String?, selectedText: String?) -> BrowserDOMContext? {
        guard let appName,
              supportedBrowserNames.contains(appName),
              let script = NSAppleScript(source: browserAppleScript(appName: appName)) else {
            return nil
        }

        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if error != nil {
            return nil
        }
        guard let raw = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let browserSelected = (json["selectedText"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        if let selectedText, let browserSelected,
           !stringsLikelySameSelection(selectedText, browserSelected) {
            return nil
        }

        let surroundingLines = (json["surroundingLines"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty?
            .truncated(to: Constants.maxSurroundingContextLength)
        let selectedOccurrenceContext = (json["selectedOccurrenceContext"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty?
            .truncated(to: Constants.maxSelectedOccurrenceContextLength)
        let pageTitle = (json["pageTitle"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let pageURL = (json["pageURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let likelyConversation = isConversationSource(
            appName: appName,
            windowTitle: pageTitle,
            sourceURL: pageURL
        )

        return BrowserDOMContext(
            selectedText: browserSelected,
            surroundingLines: surroundingLines,
            selectedOccurrenceContext: selectedOccurrenceContext,
            pageTitle: pageTitle,
            pageURL: pageURL,
            isLikelyConversation: likelyConversation
        )
    }

    private static func browserAppleScript(appName: String) -> String {
        let js = browserContextJavaScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        if appName == "Safari" {
            return """
            tell application "Safari"
                if not (exists front document) then return ""
                set jsCode to "\(js)"
                try
                    return (do JavaScript jsCode in front document) as text
                on error
                    return ""
                end try
            end tell
            """
        }

        return """
        tell application "\(appName)"
            if not (exists front window) then return ""
            set jsCode to "\(js)"
            try
                return (execute active tab of front window javascript jsCode) as text
            on error
                return ""
            end try
        end tell
        """
    }

    private static let browserContextJavaScript = #"""
    (() => {
      const normalize = (s) => (s || "").replace(/\s+/g, " ").trim();
      const pageTitle = normalize(document.title || "");
      const pageURL = normalize((window.location && window.location.href) ? window.location.href : "");
      const selection = window.getSelection();
      if (!selection || selection.rangeCount === 0) return "";
      const selectedText = normalize(selection.toString());
      if (!selectedText) return "";

      const range = selection.getRangeAt(0);
      let node = range.commonAncestorContainer;
      if (node && node.nodeType === Node.TEXT_NODE) node = node.parentElement;
      let element = node && node.nodeType === Node.ELEMENT_NODE ? node : null;

      const stopTags = new Set(["P", "LI", "TD", "TH", "H1", "H2", "H3", "H4", "H5", "H6", "BLOCKQUOTE", "PRE", "CODE"]);
      while (element && element !== document.body) {
        const txt = normalize(element.innerText || element.textContent);
        if (txt && txt.toLowerCase().includes(selectedText.toLowerCase()) && txt.length <= 700) {
          if (stopTags.has(element.tagName) || txt.length <= 260) break;
        }
        element = element.parentElement;
      }

      const anchorText = normalize(range.startContainer?.textContent || "");
      const elementText = normalize((element && (element.innerText || element.textContent)) || "");
      const occurrenceBase = anchorText || elementText;
      let selectedOccurrenceContext = occurrenceBase || null;

      const lines = [];
      if (selectedOccurrenceContext) lines.push(selectedOccurrenceContext);

      if (element && element.parentElement) {
        const siblings = Array.from(element.parentElement.children);
        const idx = siblings.indexOf(element);
        const nearby = siblings.slice(Math.max(0, idx - 1), Math.min(siblings.length, idx + 2));
        for (const sib of nearby) {
          const txt = normalize(sib.innerText || sib.textContent);
          if (txt && !lines.includes(txt)) lines.push(txt);
        }
      }

      const token = selectedText.toLowerCase();
      const nearest = lines.filter((line) => line.toLowerCase().includes(token));
      const chosenLines = (nearest.length > 0 ? nearest : lines).slice(0, 4);
      const surroundingLines = chosenLines.join("\n") || null;
      return JSON.stringify({ selectedText, selectedOccurrenceContext, surroundingLines, pageTitle, pageURL });
    })();
    """#

    private static func stringsLikelySameSelection(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.contains(right) || right.contains(left)
    }

    private static func sanitizeContext(
        selectedText: String?,
        surroundingLines: String?,
        selectedOccurrenceContext: String?
    ) -> (String?, String?) {
        let token = selectedText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        var occurrence = selectedOccurrenceContext?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        var surrounding = surroundingLines?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        if !token.isEmpty {
            if let currentOccurrence = occurrence, !currentOccurrence.lowercased().contains(token) {
                occurrence = nil
            }

            if let currentSurrounding = surrounding {
                let lines = currentSurrounding
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                let linesContainingToken = lines.filter { $0.lowercased().contains(token) }
                if linesContainingToken.isEmpty {
                    surrounding = nil
                } else {
                    surrounding = linesContainingToken
                        .joined(separator: "\n")
                        .truncated(to: Constants.maxSurroundingContextLength)
                    if occurrence == nil {
                        occurrence = linesContainingToken.first?
                            .truncated(to: Constants.maxSelectedOccurrenceContextLength)
                    }
                }
            }
        }

        return (surrounding, occurrence)
    }

    private static func applyContextTrustPolicy(
        surroundingLines: String?,
        selectedOccurrenceContext: String?,
        isConversationContext: Bool
    ) -> (String?, String?) {
        guard isConversationContext else {
            return (surroundingLines, selectedOccurrenceContext)
        }
        return (nil, nil)
    }

    private static func isConversationSource(appName: String?, windowTitle: String?, sourceURL: String?) -> Bool {
        if let appName, conversationAppNames.contains(appName) {
            return true
        }

        let loweredTitle = (windowTitle ?? "").lowercased()
        if conversationTitleKeywords.contains(where: { loweredTitle.contains($0) }) {
            return true
        }

        let loweredURL = (sourceURL ?? "").lowercased()
        if conversationURLKeywords.contains(where: { loweredURL.contains($0) }) {
            return true
        }

        return false
    }

    private static func hasBudgetRemaining(
        startedAt: CFAbsoluteTime,
        budgetMs: Int?,
        policy: CapturePolicy,
        reserveMs: Int = 0
    ) -> Bool {
        guard policy == .fastFirst else { return true }
        guard let budgetMs else { return true }
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        return elapsedMs < max(0, budgetMs - reserveMs)
    }

    // MARK: - OCR Fallback (cross-app)

    private struct OCRLine {
        let text: String
        let normalizedCenter: CGPoint
    }

    private struct OCRContextResult {
        let surroundingLines: String?
        let selectedOccurrenceContext: String?
    }

    private static func captureContextViaOCR(selectedText: String?, selectionBoundsAX: CGRect?) -> OCRContextResult? {
        guard let selectedText = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            return nil
        }

        if #available(macOS 10.15, *) {
            if !CGPreflightScreenCaptureAccess() {
                if !didRequestScreenCapturePermission {
                    didRequestScreenCapturePermission = true
                    _ = CGRequestScreenCaptureAccess()
                }
                return nil
            }
        }

        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        let lines: [OCRLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let box = observation.boundingBox
            return OCRLine(text: text, normalizedCenter: CGPoint(x: box.midX, y: box.midY))
        }

        guard !lines.isEmpty else { return nil }

        let selectedToken = selectedText.lowercased()
        let matchingLines = lines.filter {
            $0.text.range(of: selectedToken, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        guard !matchingLines.isEmpty else { return nil }

        let anchorPoint: CGPoint
        if let selectionBoundsAX {
            let axCenter = CGPoint(x: selectionBoundsAX.midX, y: selectionBoundsAX.midY)
            anchorPoint = NSScreen.convertFromAX(axCenter)
        } else {
            anchorPoint = CursorPositionProvider.mouseLocation()
        }

        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let normalizedAnchor = CGPoint(
            x: min(max((anchorPoint.x - screenFrame.minX) / max(screenFrame.width, 1), 0), 1),
            y: min(max((anchorPoint.y - screenFrame.minY) / max(screenFrame.height, 1), 0), 1)
        )

        let nearbyCandidates = matchingLines.filter {
            $0.normalizedCenter.distanceSquared(to: normalizedAnchor) < 0.03
        }
        let candidatePool = nearbyCandidates.isEmpty ? matchingLines : nearbyCandidates

        guard let chosen = candidatePool.min(by: { lhs, rhs in
            lhs.normalizedCenter.distanceSquared(to: normalizedAnchor) < rhs.normalizedCenter.distanceSquared(to: normalizedAnchor)
        }) else {
            return nil
        }

        let sorted = lines.sorted { left, right in
            if abs(left.normalizedCenter.y - right.normalizedCenter.y) > 0.01 {
                return left.normalizedCenter.y > right.normalizedCenter.y // Top to bottom
            }
            return left.normalizedCenter.x < right.normalizedCenter.x
        }

        guard let selectedIndex = sorted.firstIndex(where: {
            $0.text == chosen.text && $0.normalizedCenter.distanceSquared(to: chosen.normalizedCenter) < 0.0004
        }) else {
            return OCRContextResult(
                surroundingLines: nil,
                selectedOccurrenceContext: chosen.text.truncated(to: Constants.maxSelectedOccurrenceContextLength)
            )
        }

        let start = max(0, selectedIndex - Constants.surroundingLineCount)
        let end = min(sorted.count - 1, selectedIndex + Constants.surroundingLineCount)
        let surrounding = sorted[start...end]
            .map(\.text)
            .joined(separator: "\n")
            .truncated(to: Constants.maxSurroundingContextLength)

        return OCRContextResult(
            surroundingLines: surrounding,
            selectedOccurrenceContext: chosen.text.truncated(to: Constants.maxSelectedOccurrenceContextLength)
        )
    }
}

private extension CGPoint {
    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx) + (dy * dy)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
