import Foundation
import AppKit

@MainActor
@Observable
final class AppState {
    typealias ContextProvider = @Sendable (_ policy: AccessibilityCapture.CapturePolicy, _ budgetMs: Int?) -> ContextInfo
    typealias ClientFactory = (_ apiKey: String, _ model: String) -> any StreamingClient

    enum OverlayPhase: Equatable {
        case permissionRequired
        case loadingPreToken
        case loadingStreaming
        case result
        case error
        case empty
    }

    enum GenerationStage: Equatable {
        case idle
        case capturingSelection
        case buildingPrompt
        case contactingModel
        case generating

        var title: String {
            switch self {
            case .idle:
                return "Thinking..."
            case .capturingSelection:
                return "Reading selection..."
            case .buildingPrompt:
                return "Preparing prompt..."
            case .contactingModel:
                return "Contacting model..."
            case .generating:
                return "Streaming..."
            }
        }
    }

    struct RequestMetrics: Equatable {
        let captureLatencyMs: Int?
        let promptBuildLatencyMs: Int
        let requestStartLatencyMs: Int
        let firstTokenLatencyMs: Int?
        let totalLatencyMs: Int
        let didStreamIncrementally: Bool
    }

    var explanationText: String = ""
    var isLoading: Bool = false
    var isOverlayVisible: Bool = false
    var currentMode: ExplanationMode = .learn
    var currentDepth: Int = 0
    var currentContext: ContextInfo?
    var errorMessage: String?
    var permissionGranted: Bool = false
    var generationStage: GenerationStage = .idle
    var lastRequestMetrics: RequestMetrics?

    let permissionManager = PermissionManager()
    let explanationBuffer = ExplanationBuffer()
    var settingsManager: SettingsManager?
    var panelController: PanelController?
    var onPermissionGranted: (() -> Void)?

    private enum StreamLifecycleState {
        case idle
        case streaming
        case completed
        case failed
    }

    private let contextProvider: ContextProvider
    private let clientFactory: ClientFactory
    private let refreshPermissionOnHotkey: Bool
    private var currentStreamTask: Task<Void, Never>?
    private var currentCaptureTask: Task<ContextInfo, Never>?
    private var contextEnrichmentTask: Task<Void, Never>?
    private var enrichedContextCache: ContextInfo?
    private var activeRequestID = UUID()
    private var streamLifecycleState: StreamLifecycleState = .idle
    private static let nonMeaningfulTextCharacterSet = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{00A0}\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}"))
    private static let modePrefixRegex = try! NSRegularExpression(
        pattern: #"^\s*\[MODE:\s*(Learn|Simplify|Diagnose)\]\s*"#,
        options: [.caseInsensitive]
    )
    private static let modePrefixLeadRegex = try! NSRegularExpression(
        pattern: #"^\s*\[MODE(?::[^\]]*)?$"#,
        options: [.caseInsensitive]
    )

    var overlayPhase: OverlayPhase {
        if errorMessage != nil {
            return .error
        }
        if !permissionGranted && !hasMeaningfulExplanationText {
            return .permissionRequired
        }
        if isLoading && !hasMeaningfulExplanationText {
            return .loadingPreToken
        }
        if isLoading && hasMeaningfulExplanationText {
            return .loadingStreaming
        }
        if hasMeaningfulExplanationText {
            return .result
        }
        return .empty
    }

    var hasMeaningfulExplanationText: Bool {
        hasMeaningfulText(explanationText)
    }

    var shouldShowContextUsedBadge: Bool {
        guard let currentContext, hasMeaningfulExplanationText else { return false }
        return currentContext.hasContextSignal
    }

    init(
        contextProvider: @escaping ContextProvider = { policy, budgetMs in
            AccessibilityCapture.captureContext(policy: policy, budgetMs: budgetMs)
        },
        clientFactory: @escaping ClientFactory = { apiKey, model in
            OpenAIClient(apiKey: apiKey, model: model)
        },
        refreshPermissionOnHotkey: Bool = true
    ) {
        self.contextProvider = contextProvider
        self.clientFactory = clientFactory
        self.refreshPermissionOnHotkey = refreshPermissionOnHotkey
        permissionGranted = permissionManager.isAccessibilityGranted
        permissionManager.onPermissionChanged = { [weak self] granted in
            Task { @MainActor in
                self?.permissionGranted = granted
                if granted {
                    self?.onPermissionGranted?()
                }
            }
        }
    }

    func handleHotkey(isDoublePress: Bool) {
        if isDoublePress, isOverlayVisible, let lastExplanation = explanationBuffer.last() {
            goDeeper(previousExplanation: lastExplanation)
            return
        }

        startNewExplanation()
    }

    private func startNewExplanation() {
        let triggerStartedAt = Date()
        prepareForRequest(depth: 1)
        generationStage = .capturingSelection
        if refreshPermissionOnHotkey {
            permissionManager.refreshPermissionStatus()
            permissionGranted = permissionManager.isAccessibilityGranted
        }

        guard permissionGranted else {
            streamLifecycleState = .idle
            isLoading = false
            generationStage = .idle
            currentContext = nil
            let anchorPoint = CursorPositionProvider.mouseLocation()
            panelController?.show(at: anchorPoint)
            isOverlayVisible = true
            return
        }

        let initialAnchor = CursorPositionProvider.mouseLocation()
        panelController?.show(at: initialAnchor)
        isOverlayVisible = true

        let requestID = activeRequestID
        let captureStartedAt = Date()

        currentCaptureTask = Task.detached(priority: .userInitiated) { [contextProvider] in
            contextProvider(.fastFirst, Constants.fastContextCaptureBudgetMs)
        }

        Task { @MainActor in
            let fastContext = await self.currentCaptureTask?.value
                ?? self.contextProvider(.fastFirst, Constants.fastContextCaptureBudgetMs)
            self.currentCaptureTask = nil

            guard self.activeRequestID == requestID, self.streamLifecycleState == .streaming else { return }

            var context = fastContext
            if !self.hasUsableSelection(context.selectedText) {
                let provider = self.contextProvider
                let fullContext = await Task.detached(priority: .userInitiated) {
                    provider(.full, nil)
                }.value

                guard self.activeRequestID == requestID, self.streamLifecycleState == .streaming else { return }

                if self.hasUsableSelection(fullContext.selectedText) {
                    context = fullContext
                }
            }

            if !self.hasUsableSelection(context.selectedText) {
                try? await Task.sleep(for: .milliseconds(90))
                let provider = self.contextProvider
                let retryContext = await Task.detached(priority: .userInitiated) {
                    provider(.full, nil)
                }.value

                guard self.activeRequestID == requestID, self.streamLifecycleState == .streaming else { return }

                if self.hasUsableSelection(retryContext.selectedText) {
                    context = retryContext
                }
            }

            if self.hasUsableSelection(context.selectedText) && !context.hasContextSignal {
                let provider = self.contextProvider
                let upgradedContext = await Task.detached(priority: .userInitiated) {
                    provider(.full, Constants.preflightContextUpgradeBudgetMs)
                }.value

                guard self.activeRequestID == requestID, self.streamLifecycleState == .streaming else { return }

                if self.hasUsableSelection(upgradedContext.selectedText), upgradedContext.hasContextSignal {
                    context = upgradedContext
                }
            }

            let captureLatencyMs = Int(Date().timeIntervalSince(captureStartedAt) * 1000)
            self.currentContext = context

            guard self.hasUsableSelection(context.selectedText) else {
                self.showNoSelectionError()
                return
            }

            let anchorPoint = CursorPositionProvider.anchorPoint(from: context)
            self.panelController?.show(at: anchorPoint)
            self.isOverlayVisible = true
            self.generationStage = .buildingPrompt

            self.streamExplanation(
                context: context,
                depth: 1,
                previousExplanation: nil,
                requestStartedAt: triggerStartedAt,
                captureLatencyMs: captureLatencyMs
            )
            self.scheduleContextEnrichmentIfNeeded(baseContext: context, requestID: requestID)
        }
    }

    private func goDeeper(previousExplanation: StreamingExplanation) {
        let triggerStartedAt = Date()
        let nextDepth = min(currentDepth + 1, 3)
        prepareForRequest(depth: nextDepth)

        var captureLatencyMs: Int?
        let context: ContextInfo
        if let cached = enrichedContextCache,
           selectionsLikelyMatch(currentContext?.selectedText ?? previousExplanation.context.selectedText, cached.selectedText) {
            context = mergeContext(primary: currentContext ?? previousExplanation.context, enriched: cached)
            currentContext = context
        } else if let existing = currentContext {
            context = existing
        } else {
            let captureStartedAt = Date()
            let captured = contextProvider(.full, nil)
            captureLatencyMs = Int(Date().timeIntervalSince(captureStartedAt) * 1000)
            currentContext = captured
            context = captured
        }

        if !isOverlayVisible {
            let anchorPoint = CursorPositionProvider.anchorPoint(from: context)
            panelController?.show(at: anchorPoint)
            isOverlayVisible = true
        }

        generationStage = .buildingPrompt
        streamExplanation(
            context: context,
            depth: currentDepth,
            previousExplanation: previousExplanation.fullText,
            requestStartedAt: triggerStartedAt,
            captureLatencyMs: captureLatencyMs
        )
    }

    private func prepareForRequest(depth: Int) {
        currentStreamTask?.cancel()
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        contextEnrichmentTask?.cancel()
        contextEnrichmentTask = nil
        activeRequestID = UUID()
        if depth == 1 {
            enrichedContextCache = nil
        }
        currentDepth = depth
        currentMode = .learn
        explanationText = ""
        errorMessage = nil
        lastRequestMetrics = nil
        isLoading = true
        generationStage = .buildingPrompt
        streamLifecycleState = .streaming
    }

    private func streamExplanation(
        context: ContextInfo,
        depth: Int,
        previousExplanation: String?,
        requestStartedAt: Date,
        captureLatencyMs: Int?
    ) {
        guard let settings = settingsManager else {
            failRequest("Settings not available")
            return
        }

        guard !settings.apiKey.isEmpty else {
            failRequest("API key not set. Add it in Settings or set OPENAI_API_KEY in Xcode Scheme > Run > Arguments.")
            return
        }

        let promptBuildStartedAt = Date()
        let prompt = PromptBuilder.build(
            context: context,
            depth: depth,
            previousExplanation: previousExplanation
        )
        let promptBuildLatencyMs = Int(Date().timeIntervalSince(promptBuildStartedAt) * 1000)

        let client = clientFactory(settings.apiKey, settings.modelName)
        generationStage = .contactingModel
        let requestStartLatencyMs = Int(Date().timeIntervalSince(requestStartedAt) * 1000)

        currentStreamTask = Task { @MainActor in
            let networkStartedAt = Date()
            var pendingHeader = ""
            var fullText = ""
            var resolvedMode: ExplanationMode = .learn
            var modeResolved = false
            var didFinalize = false
            var firstDeltaAt: Date?
            var deltaEventCount = 0

            @MainActor
            func resolveModeIfNeeded(force: Bool) {
                guard !modeResolved else { return }

                if let prefixParse = Self.parseModePrefix(from: pendingHeader) {
                    modeResolved = true
                    resolvedMode = prefixParse.mode
                    fullText = prefixParse.remainder
                    self.currentMode = resolvedMode
                    let displayText = self.normalizedDisplayText(from: fullText)
                    self.explanationText = displayText
                    return
                }

                if !force && Self.looksLikeIncompleteModePrefix(pendingHeader) {
                    return
                }

                modeResolved = true
                resolvedMode = .learn
                fullText = pendingHeader
                self.currentMode = resolvedMode
                let displayText = self.normalizedDisplayText(from: fullText)
                self.explanationText = displayText
            }

            @MainActor
            func publishRequestMetrics(text: String) {
                let now = Date()
                let metrics = RequestMetrics(
                    captureLatencyMs: captureLatencyMs,
                    promptBuildLatencyMs: promptBuildLatencyMs,
                    requestStartLatencyMs: requestStartLatencyMs,
                    firstTokenLatencyMs: firstDeltaAt.map { Int($0.timeIntervalSince(networkStartedAt) * 1000) },
                    totalLatencyMs: Int(now.timeIntervalSince(requestStartedAt) * 1000),
                    didStreamIncrementally: deltaEventCount > 1 && self.hasMeaningfulText(text)
                )
                self.lastRequestMetrics = metrics
                self.logLatencyMetricsIfNeeded(metrics)
            }

            @MainActor
            func finalizeSuccess() {
                guard !didFinalize else { return }
                didFinalize = true

                resolveModeIfNeeded(force: true)
                let displayText = self.normalizedDisplayText(from: fullText)
                publishRequestMetrics(text: displayText)

                if !self.hasMeaningfulText(displayText) {
                    self.errorMessage = "No explanation returned. Verify API key, model, and network access."
                    self.isLoading = false
                    self.generationStage = .idle
                    self.streamLifecycleState = .failed
                    return
                }

                self.currentMode = resolvedMode
                self.explanationText = displayText
                self.errorMessage = nil
                self.isLoading = false
                self.generationStage = .idle
                self.streamLifecycleState = .completed

                let explanation = StreamingExplanation(
                    fullText: displayText,
                    mode: resolvedMode,
                    depth: depth,
                    context: context
                )
                self.explanationBuffer.push(explanation)
            }

            @MainActor
            func finalizeFailure(message: String) {
                guard !didFinalize else { return }
                didFinalize = true

                let displayText = self.normalizedDisplayText(from: fullText.isEmpty ? pendingHeader : fullText)
                publishRequestMetrics(text: displayText)
                self.errorMessage = self.decorateErrorMessage(message, settings: settings)
                self.isLoading = false
                self.generationStage = .idle
                self.streamLifecycleState = .failed
            }

            do {
                let stream = try await client.stream(
                    instructions: prompt.instructions,
                    input: prompt.input,
                    maxOutputTokens: prompt.maxOutputTokens
                )

                for try await event in stream {
                    if Task.isCancelled { return }
                    if didFinalize { continue }

                    switch event {
                    case .delta(let text):
                        deltaEventCount += 1
                        if firstDeltaAt == nil {
                            firstDeltaAt = Date()
                        }
                        if self.generationStage != .generating {
                            self.generationStage = .generating
                        }
                        if modeResolved {
                            fullText += text
                            let displayText = self.normalizedDisplayText(from: fullText)
                            self.explanationText = displayText
                        } else {
                            pendingHeader += text
                            resolveModeIfNeeded(force: false)
                        }

                    case .done:
                        // Yield one turn so the latest streamed text paints before finalization
                        // when providers emit delta+done back-to-back.
                        if firstDeltaAt != nil {
                            await Task.yield()
                        }
                        finalizeSuccess()

                    case .error(let message):
                        finalizeFailure(message: message)
                    }
                }

                if !Task.isCancelled && !didFinalize {
                    finalizeSuccess()
                }
            } catch {
                if !Task.isCancelled {
                    finalizeFailure(message: error.localizedDescription)
                }
            }
        }
    }

    private func scheduleContextEnrichmentIfNeeded(baseContext: ContextInfo, requestID: UUID) {
        guard baseContext.isPartialContext else {
            enrichedContextCache = baseContext
            return
        }

        contextEnrichmentTask?.cancel()
        contextEnrichmentTask = Task { [contextProvider] in
            let enriched = await Task.detached(priority: .utility) {
                contextProvider(.full, nil)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.activeRequestID == requestID else { return }
                guard self.selectionsLikelyMatch(baseContext.selectedText, enriched.selectedText) else { return }

                let merged = self.mergeContext(primary: baseContext, enriched: enriched)
                self.enrichedContextCache = merged

                if let current = self.currentContext, current.isPartialContext {
                    self.currentContext = self.mergeContext(primary: current, enriched: enriched)
                }
            }
        }
    }

    private func mergeContext(primary: ContextInfo, enriched: ContextInfo) -> ContextInfo {
        ContextInfo(
            selectedText: enriched.selectedText ?? primary.selectedText,
            appName: enriched.appName ?? primary.appName,
            windowTitle: enriched.windowTitle ?? primary.windowTitle,
            surroundingLines: enriched.surroundingLines ?? primary.surroundingLines,
            selectionBounds: enriched.selectionBounds ?? primary.selectionBounds,
            selectedOccurrenceContext: enriched.selectedOccurrenceContext ?? primary.selectedOccurrenceContext,
            sourceURL: enriched.sourceURL ?? primary.sourceURL,
            sourceHint: enriched.sourceHint ?? primary.sourceHint,
            isConversationContext: primary.isConversationContext || enriched.isConversationContext,
            isPartialContext: primary.isPartialContext && enriched.isPartialContext
        )
    }

    private func selectionsLikelyMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = lhs?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let rhs = rhs?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !lhs.isEmpty, !rhs.isEmpty else {
            return false
        }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    private func failRequest(_ message: String) {
        errorMessage = message
        isLoading = false
        generationStage = .idle
        streamLifecycleState = .failed
    }

    private func logLatencyMetricsIfNeeded(_ metrics: RequestMetrics) {
        #if DEBUG
        print(
            "[ClarifyLatency] capture=\(metrics.captureLatencyMs ?? -1)ms prompt=\(metrics.promptBuildLatencyMs)ms requestStart=\(metrics.requestStartLatencyMs)ms firstToken=\(metrics.firstTokenLatencyMs ?? -1)ms total=\(metrics.totalLatencyMs)ms incremental=\(metrics.didStreamIncrementally)"
        )
        #endif
    }

    private func decorateErrorMessage(_ message: String, settings: SettingsManager) -> String {
        if message.localizedCaseInsensitiveContains("timed out") {
            return "Request timed out. Check network, then retry."
        }
        if message.localizedCaseInsensitiveContains("invalid api key") {
            if settings.isAPIKeyFromEnvironment {
                return "Invalid API key from OPENAI_API_KEY environment variable. Update Xcode Scheme env var or set key in Settings."
            }
            return "Invalid API key. Update it in Settings."
        }
        return message
    }

    private func hasMeaningfulText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: Self.nonMeaningfulTextCharacterSet).isEmpty
    }

    private func hasUsableSelection(_ text: String?) -> Bool {
        guard let text else { return false }
        return hasMeaningfulText(text)
    }

    private static func parseModePrefix(from text: String) -> (mode: ExplanationMode, remainder: String)? {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = modePrefixRegex.firstMatch(in: text, options: [], range: nsRange),
              match.range.location == 0,
              let modeRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range(at: 0), in: text) else {
            return nil
        }

        let modeToken = text[modeRange].lowercased()
        let mode: ExplanationMode
        switch modeToken {
        case "learn":
            mode = .learn
        case "simplify":
            mode = .simplify
        case "diagnose":
            mode = .diagnose
        default:
            return nil
        }

        let remainder = String(text[fullRange.upperBound...])
        return (mode, remainder)
    }

    private static func looksLikeIncompleteModePrefix(_ text: String) -> Bool {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard modePrefixLeadRegex.firstMatch(in: text, options: [], range: nsRange) != nil else {
            return false
        }
        return !text.contains("]")
    }

    private func normalizedDisplayText(from text: String) -> String {
        text.trimmingLeadingCharacters(in: Self.nonMeaningfulTextCharacterSet)
    }

    private func showNoSelectionError() {
        errorMessage = "Select some text first"
        isLoading = false
        generationStage = .idle
        streamLifecycleState = .failed
        let anchorPoint = CursorPositionProvider.mouseLocation()
        panelController?.show(at: anchorPoint)
        isOverlayVisible = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            dismiss()
        }
    }

    func dismiss() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        contextEnrichmentTask?.cancel()
        contextEnrichmentTask = nil
        isLoading = false
        generationStage = .idle
        panelController?.hide()
        isOverlayVisible = false
        streamLifecycleState = .idle
    }

    func cancelGeneration() {
        guard isLoading else { return }
        currentStreamTask?.cancel()
        currentStreamTask = nil
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        contextEnrichmentTask?.cancel()
        contextEnrichmentTask = nil
        isLoading = false
        generationStage = .idle
        streamLifecycleState = .idle
    }

    func retryLastRequest() {
        guard let context = currentContext else {
            startNewExplanation()
            return
        }
        let depth = currentDepth > 0 ? currentDepth : 1
        prepareForRequest(depth: depth)
        currentContext = context
        generationStage = .buildingPrompt
        streamExplanation(
            context: context,
            depth: depth,
            previousExplanation: nil,
            requestStartedAt: Date(),
            captureLatencyMs: nil
        )
    }

    func requestDeeperExplanation() {
        guard let lastExplanation = explanationBuffer.last() else { return }
        goDeeper(previousExplanation: lastExplanation)
    }

    var shouldRecommendStableInstall: Bool {
        Bundle.main.bundlePath.contains("/DerivedData/")
    }

    func installStableBuildAndRelaunch() {
        let fileManager = FileManager.default
        let sourceURL = Bundle.main.bundleURL
        let applicationsURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let targetURL = applicationsURL.appendingPathComponent("Clarify.app", isDirectory: true)
        let stagingURL = applicationsURL.appendingPathComponent("Clarify.app.staging", isDirectory: true)

        do {
            try fileManager.createDirectory(at: applicationsURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: stagingURL.path) {
                try fileManager.removeItem(at: stagingURL)
            }
            try fileManager.copyItem(at: sourceURL, to: stagingURL)

            if fileManager.fileExists(atPath: targetURL.path) {
                _ = try fileManager.replaceItemAt(targetURL, withItemAt: stagingURL, backupItemName: nil, options: [])
            } else {
                try fileManager.moveItem(at: stagingURL, to: targetURL)
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: targetURL, configuration: config) { _, error in
                Task { @MainActor in
                    if let error {
                        self.errorMessage = "Installed to ~/Applications but failed to relaunch: \(error.localizedDescription)"
                        self.streamLifecycleState = .failed
                        return
                    }
                    // Give the relaunched app a brief moment to initialize before closing the debug run.
                    try? await Task.sleep(for: .milliseconds(500))
                    NSApplication.shared.terminate(nil)
                }
            }
        } catch {
            errorMessage = "Failed to install stable app to ~/Applications: \(error.localizedDescription)"
            isLoading = false
            streamLifecycleState = .failed
        }
    }
}

private extension String {
    func trimmingLeadingCharacters(in characterSet: CharacterSet) -> String {
        guard let index = firstIndex(where: { scalar in
            scalar.unicodeScalars.contains { !characterSet.contains($0) }
        }) else {
            return ""
        }
        return String(self[index...])
    }
}

private extension ContextInfo {
    var hasContextSignal: Bool {
        let surrounding = (surroundingLines ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let occurrence = (selectedOccurrenceContext ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !surrounding.isEmpty || !occurrence.isEmpty
    }
}
