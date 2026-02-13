import Foundation

struct ContextInfo {
    let selectedText: String?
    let appName: String?
    let windowTitle: String?
    let surroundingLines: String?
    let selectionBounds: CGRect?
    let selectedOccurrenceContext: String?
    let sourceURL: String?
    let sourceHint: String?
    let isConversationContext: Bool
    let isPartialContext: Bool

    init(
        selectedText: String?,
        appName: String?,
        windowTitle: String?,
        surroundingLines: String?,
        selectionBounds: CGRect?,
        selectedOccurrenceContext: String? = nil,
        sourceURL: String? = nil,
        sourceHint: String? = nil,
        isConversationContext: Bool = false,
        isPartialContext: Bool = false
    ) {
        self.selectedText = selectedText
        self.appName = appName
        self.windowTitle = windowTitle
        self.surroundingLines = surroundingLines
        self.selectionBounds = selectionBounds
        self.selectedOccurrenceContext = selectedOccurrenceContext
        self.sourceURL = sourceURL
        self.sourceHint = sourceHint
        self.isConversationContext = isConversationContext
        self.isPartialContext = isPartialContext
    }
}
