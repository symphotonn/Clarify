import Foundation

enum Constants {
    // MARK: - Hotkey
    static let doublePressInterval: TimeInterval = 0.4

    // MARK: - API
    static let apiEndpoint = "https://api.openai.com/v1/chat/completions"
    static let defaultModel = "gpt-4o-mini"
    static let requestTimeout: TimeInterval = 20
    static let fallbackRequestTimeout: TimeInterval = 12
    static let devAPIKeyEnvVar = "OPENAI_API_KEY"
    static let devModelEnvVar = "CLARIFY_MODEL"
    static let devAutoInstallStableEnvVar = "CLARIFY_DEV_AUTOINSTALL_STABLE"

    // MARK: - Context Limits
    static let maxSelectionLength = 320
    static let maxSurroundingContextLength = 420
    static let maxSelectedOccurrenceContextLength = 180
    static let surroundingLineCount = 3
    static let clipboardFallbackTimeout: TimeInterval = 0.1
    static let fastClipboardFallbackTimeout: TimeInterval = 0.06
    static let fastContextCaptureBudgetMs = 90
    static let preflightContextUpgradeBudgetMs = 220

    // MARK: - Panel
    static let panelWidth: CGFloat = 360
    static let panelMaxHeight: CGFloat = 480
    static let panelAnchorOffset: CGFloat = 8
    static let panelCornerRadius: CGFloat = 12

    // MARK: - Animation
    static let fadeInDuration: TimeInterval = 0.15
    static let fadeOutDuration: TimeInterval = 0.06
    static let scaleFrom: CGFloat = 0.97
    static let scaleTo: CGFloat = 1.0

    // MARK: - Word Limits
    static let depth1WordLimit = 100
    static let depth2WordLimit = 220
    static let modeHeaderFallbackLength = 120

    // MARK: - Buffer
    static let explanationBufferCapacity = 5

    // MARK: - Permissions
    static let permissionPollInterval: TimeInterval = 1.0
}
