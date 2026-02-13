import Foundation
import AppKit

@MainActor
@Observable
final class AppState {
    typealias ContextProvider = @Sendable (_ policy: AccessibilityCapture.CapturePolicy, _ budgetMs: Int?) -> ContextInfo
    typealias ClientFactory = (_ apiKey: String, _ model: String) -> any StreamingClient
    typealias ClipboardWriter = (_ text: String) -> Bool

    enum OverlayPhase: Equatable {
        case permissionRequired
        case loadingPreToken
        case loadingStreaming
        case result
        case chat
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

    struct SessionDiagnostic {
        let sessionID: UUID
        let phase: SessionPhase
        let depth: Int
        let metrics: RequestMetrics?
        let errorMessage: String?
        let stopReason: CompletionStopReason?
        let completionGateEvaluated: Bool?
        let completionGatePassed: Bool?
        let repairAttempted: Bool?
        let repairSucceeded: Bool?
        let repairTimedOut: Bool?
        let metFirstTokenBudget: Bool?
        let metTotalLatencyBudget: Bool?
        let endedAt: Date
    }

    enum SessionPhase: Equatable {
        case permissionRequired
        case loadingPreToken
        case loadingStreaming
        case result
        case chat
        case error
        case empty

        var overlayPhase: OverlayPhase {
            switch self {
            case .permissionRequired:
                return .permissionRequired
            case .loadingPreToken:
                return .loadingPreToken
            case .loadingStreaming:
                return .loadingStreaming
            case .result:
                return .result
            case .chat:
                return .chat
            case .error:
                return .error
            case .empty:
                return .empty
            }
        }

        var isLoading: Bool {
            self == .loadingPreToken || self == .loadingStreaming
        }
    }

    struct OverlaySession {
        let id: UUID
        var phase: SessionPhase
        var depth: Int
        var context: ContextInfo?
        var displayText: String
        var errorMessage: String?
        var mode: ExplanationMode
        var metrics: RequestMetrics?
        let startedAt: Date
    }

    private(set) var session = OverlaySession(
        id: UUID(),
        phase: .empty,
        depth: 0,
        context: nil,
        displayText: "",
        errorMessage: nil,
        mode: .learn,
        metrics: nil,
        startedAt: Date()
    )

    var explanationText: String {
        get { session.displayText }
        set {
            session.displayText = newValue
            if session.phase == .loadingPreToken, hasMeaningfulText(newValue) {
                session.phase = .loadingStreaming
            }
        }
    }

    var isLoading: Bool {
        session.phase.isLoading
    }

    var isOverlayVisible: Bool = false
    var currentMode: ExplanationMode {
        get { session.mode }
        set { session.mode = newValue }
    }
    var currentDepth: Int {
        get { session.depth }
        set { session.depth = newValue }
    }
    var currentContext: ContextInfo? {
        get { session.context }
        set { session.context = newValue }
    }
    var errorMessage: String? {
        get { session.errorMessage }
        set {
            session.errorMessage = newValue
            if newValue != nil {
                session.phase = .error
            }
        }
    }
    var permissionGranted: Bool = false {
        didSet {
            updateSessionPhaseForPermissionChange()
        }
    }
    var generationStage: GenerationStage = .idle
    var lastRequestMetrics: RequestMetrics? {
        get { session.metrics }
        set { session.metrics = newValue }
    }
    private(set) var recentSessionDiagnostics: [SessionDiagnostic] = []
    var chatSession: ChatSession?

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
    private let clipboardWriter: ClipboardWriter
    private let refreshPermissionOnHotkey: Bool
    private var currentStreamTask: Task<Void, Never>?
    private var currentChatStreamTask: Task<Void, Never>?
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
        session.phase.overlayPhase
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
        clipboardWriter: @escaping ClipboardWriter = { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        },
        refreshPermissionOnHotkey: Bool = true
    ) {
        self.contextProvider = contextProvider
        self.clientFactory = clientFactory
        self.clipboardWriter = clipboardWriter
        self.refreshPermissionOnHotkey = refreshPermissionOnHotkey
        permissionGranted = permissionManager.isAccessibilityGranted
        session = Self.initialSession(permissionGranted: permissionGranted)
        permissionManager.onPermissionChanged = { [weak self] granted in
            Task { @MainActor in
                self?.permissionGranted = granted
                if granted {
                    self?.onPermissionGranted?()
                }
            }
        }
    }

    private static func initialSession(permissionGranted: Bool) -> OverlaySession {
        OverlaySession(
            id: UUID(),
            phase: permissionGranted ? .empty : .permissionRequired,
            depth: 0,
            context: nil,
            displayText: "",
            errorMessage: nil,
            mode: .learn,
            metrics: nil,
            startedAt: Date()
        )
    }

    private func resetSession(
        id: UUID = UUID(),
        phase: SessionPhase,
        depth: Int,
        context: ContextInfo? = nil,
        displayText: String = "",
        errorMessage: String? = nil,
        mode: ExplanationMode = .learn,
        metrics: RequestMetrics? = nil,
        startedAt: Date = Date()
    ) {
        session = OverlaySession(
            id: id,
            phase: phase,
            depth: depth,
            context: context,
            displayText: displayText,
            errorMessage: errorMessage,
            mode: mode,
            metrics: metrics,
            startedAt: startedAt
        )
    }

    private func phaseAfterLoadingStops() -> SessionPhase {
        if errorMessage != nil {
            return .error
        }
        if hasMeaningfulExplanationText {
            return .result
        }
        return permissionGranted ? .empty : .permissionRequired
    }

    private func updateSessionPhaseForPermissionChange() {
        guard !session.phase.isLoading else { return }
        guard !hasMeaningfulExplanationText, errorMessage == nil else { return }
        session.phase = permissionGranted ? .empty : .permissionRequired
    }

    func handleHotkey(isDoublePress: Bool) {
        // Protect in-flight generation from accidental re-trigger.
        if isLoading {
            return
        }

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
            generationStage = .idle
            currentContext = nil
            session.phase = .permissionRequired
            session.displayText = ""
            session.errorMessage = nil
            session.metrics = nil
            session.mode = .learn
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
        let existingContext = currentContext
        prepareForRequest(depth: nextDepth)

        var captureLatencyMs: Int?
        let context: ContextInfo
        if let cached = enrichedContextCache,
           selectionsLikelyMatch(existingContext?.selectedText ?? previousExplanation.context.selectedText, cached.selectedText) {
            context = mergeContext(primary: existingContext ?? previousExplanation.context, enriched: cached)
            currentContext = context
        } else if let existing = existingContext {
            context = existing
            currentContext = existing
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
        currentChatStreamTask?.cancel()
        currentChatStreamTask = nil
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        contextEnrichmentTask?.cancel()
        contextEnrichmentTask = nil
        if chatSession != nil {
            chatSession = nil
            panelController?.deactivateFromChat()
        }
        activeRequestID = UUID()
        if depth == 1 {
            enrichedContextCache = nil
        }
        resetSession(
            id: activeRequestID,
            phase: .loadingPreToken,
            depth: depth,
            context: nil,
            displayText: "",
            errorMessage: nil,
            mode: .learn,
            metrics: nil,
            startedAt: Date()
        )
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
            var streamStopReason: CompletionStopReason = .unknown

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
            func finalizeSuccess() async {
                guard !didFinalize else { return }
                didFinalize = true

                resolveModeIfNeeded(force: true)
                var displayText = self.normalizedDisplayText(from: fullText)
                var completionGateEvaluated = false
                var completionGatePassed = true
                var repairAttempted = false
                var repairSucceeded = false
                var repairTimedOut = false
                let forceRepairOnStop = streamStopReason == .stop
                    && self.shouldForceRepairForStopCompletion(displayText)

                if depth <= 1,
                   (streamStopReason.shouldEvaluateCompletionGate || forceRepairOnStop) {
                    completionGateEvaluated = true
                    completionGatePassed = CompletionQualityGate.isComplete(displayText)

                    if !completionGatePassed, !Task.isCancelled {
                        repairAttempted = true
                        let repairResult = await self.repairDepth1ExplanationIfNeeded(
                            partialExplanation: displayText,
                            context: context,
                            client: client
                        )
                        repairTimedOut = repairResult?.timedOut == true
                        if let repaired = repairResult?.text {
                            repairSucceeded = true
                            fullText = repaired
                            displayText = repaired
                            self.explanationText = displayText
                            completionGatePassed = CompletionQualityGate.isComplete(displayText)
                        }
                    }
                }
                publishRequestMetrics(text: displayText)

                if !self.hasMeaningfulText(displayText) {
                    self.errorMessage = "No explanation returned. Verify API key, model, and network access."
                    self.session.phase = .error
                    self.generationStage = .idle
                    self.streamLifecycleState = .failed
                    self.recordSessionDiagnostic(
                        phase: .error,
                        errorMessage: self.errorMessage,
                        stopReason: streamStopReason,
                        completionGateEvaluated: completionGateEvaluated,
                        completionGatePassed: completionGatePassed,
                        repairAttempted: repairAttempted,
                        repairSucceeded: repairSucceeded,
                        repairTimedOut: repairTimedOut
                    )
                    return
                }

                self.currentMode = resolvedMode
                self.explanationText = displayText
                self.errorMessage = nil
                self.session.phase = .result
                self.generationStage = .idle
                self.streamLifecycleState = .completed
                self.recordSessionDiagnostic(
                    phase: .result,
                    errorMessage: nil,
                    stopReason: streamStopReason,
                    completionGateEvaluated: completionGateEvaluated,
                    completionGatePassed: completionGatePassed,
                    repairAttempted: repairAttempted,
                    repairSucceeded: repairSucceeded,
                    repairTimedOut: repairTimedOut
                )

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
                self.session.phase = .error
                self.generationStage = .idle
                self.streamLifecycleState = .failed
                self.recordSessionDiagnostic(
                    phase: .error,
                    errorMessage: self.errorMessage
                )
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

                    case .done(let reason):
                        streamStopReason = reason
                        // Yield one turn so the latest streamed text paints before finalization
                        // when providers emit delta+done back-to-back.
                        if firstDeltaAt != nil {
                            await Task.yield()
                        }
                        await finalizeSuccess()

                    case .error(let message):
                        finalizeFailure(message: message)
                    }
                }

                if !Task.isCancelled && !didFinalize {
                    await finalizeSuccess()
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
        session.phase = .error
        generationStage = .idle
        streamLifecycleState = .failed
        recordSessionDiagnostic(phase: .error, errorMessage: message)
    }

    private func recordSessionDiagnostic(
        phase: SessionPhase,
        errorMessage: String?,
        stopReason: CompletionStopReason? = nil,
        completionGateEvaluated: Bool? = nil,
        completionGatePassed: Bool? = nil,
        repairAttempted: Bool? = nil,
        repairSucceeded: Bool? = nil,
        repairTimedOut: Bool? = nil
    ) {
        let metrics = lastRequestMetrics
        let diagnostic = SessionDiagnostic(
            sessionID: session.id,
            phase: phase,
            depth: currentDepth,
            metrics: metrics,
            errorMessage: errorMessage,
            stopReason: stopReason,
            completionGateEvaluated: completionGateEvaluated,
            completionGatePassed: completionGatePassed,
            repairAttempted: repairAttempted,
            repairSucceeded: repairSucceeded,
            repairTimedOut: repairTimedOut,
            metFirstTokenBudget: metrics?.firstTokenLatencyMs.map { $0 <= Constants.firstTokenTargetMs },
            metTotalLatencyBudget: metrics.map { $0.totalLatencyMs <= Constants.totalLatencySoftBudgetMs },
            endedAt: Date()
        )
        recentSessionDiagnostics.append(diagnostic)
        if recentSessionDiagnostics.count > Constants.sessionDiagnosticsCapacity {
            recentSessionDiagnostics.removeFirst(recentSessionDiagnostics.count - Constants.sessionDiagnosticsCapacity)
        }
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

    private struct RepairAttemptResult {
        let text: String?
        let timedOut: Bool
    }

    private func repairDepth1ExplanationIfNeeded(
        partialExplanation: String,
        context: ContextInfo,
        client: any StreamingClient
    ) async -> RepairAttemptResult? {
        let partial = partialExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasMeaningfulText(partial) else { return nil }
        let continuationTail = repairContextTail(
            from: partial,
            maxCharacters: Constants.repairContextTailCharacters
        )

        let instructions = """
        You are Clarify.
        Continue and finish the explanation from where it stops.
        Keep meaning and tone consistent with the existing text.
        Keep it simple, concise, and beginner-friendly.
        Return one or two short complete sentences total for the continuation.
        Do not include a [MODE:] header.
        """

        var inputParts: [String] = []
        if let selectedText = context.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedText.isEmpty {
            inputParts.append("Selected text:\n\(selectedText)")
        }
        if let nearby = context.selectedOccurrenceContext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !nearby.isEmpty {
            inputParts.append("Nearby context:\n\(nearby)")
        } else if let surrounding = context.surroundingLines?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !surrounding.isEmpty {
            inputParts.append("Nearby context:\n\(surrounding)")
        }
        inputParts.append("Explanation so far (continue from this tail):\n\(continuationTail)")
        inputParts.append("Task: continue and finish the explanation.")

        let input = inputParts.joined(separator: "\n\n")
        return await runRepairWithTimeout(
            instructions: instructions,
            input: input,
            client: client
        )
    }

    private func runRepairWithTimeout(
        instructions: String,
        input: String,
        client: any StreamingClient
    ) async -> RepairAttemptResult {
        actor ResumeGate {
            private var didResume = false

            func markIfNeeded() -> Bool {
                if didResume {
                    return false
                }
                didResume = true
                return true
            }
        }

        let gate = ResumeGate()

        return await withCheckedContinuation { continuation in
            let repairTask = Task {
                let text = await self.collectRepairText(
                    instructions: instructions,
                    input: input,
                    client: client
                )
                guard await gate.markIfNeeded() else { return }
                continuation.resume(returning: RepairAttemptResult(text: text, timedOut: false))
            }

            Task {
                try? await Task.sleep(for: .milliseconds(Constants.depth1RepairTimeoutMs))
                guard await gate.markIfNeeded() else { return }
                repairTask.cancel()
                continuation.resume(returning: RepairAttemptResult(text: nil, timedOut: true))
            }
        }
    }

    private func collectRepairText(
        instructions: String,
        input: String,
        client: any StreamingClient
    ) async -> String? {
        do {
            let stream = try await client.stream(
                instructions: instructions,
                input: input,
                maxOutputTokens: Constants.depth1RepairMaxTokens
            )
            var repaired = ""
            for try await event in stream {
                switch event {
                case .delta(let text):
                    repaired += text
                case .done:
                    break
                case .error:
                    return nil
                }
            }

            repaired = normalizedDisplayText(from: repaired)
            if let parsed = Self.parseModePrefix(from: repaired) {
                repaired = normalizedDisplayText(from: parsed.remainder)
            }
            guard hasMeaningfulText(repaired) else { return nil }
            return repaired
        } catch {
            return nil
        }
    }

    private func shouldForceRepairForStopCompletion(_ text: String) -> Bool {
        let reasons = CompletionQualityGate.reasons(for: text)
        return reasons.contains(.danglingSuffix)
            || reasons.contains(.unmatchedDelimiter)
            || reasons.contains(.unmatchedQuote)
    }

    func repairContextTail(from text: String, maxCharacters: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }

        let hardStart = trimmed.index(trimmed.endIndex, offsetBy: -maxCharacters)
        var boundaryStart = hardStart
        while boundaryStart > trimmed.startIndex {
            let previous = trimmed.index(before: boundaryStart)
            if trimmed[previous].isWhitespace {
                break
            }
            boundaryStart = previous
        }

        var tail = String(trimmed[boundaryStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.isEmpty {
            tail = String(trimmed[hardStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tail
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
        session.phase = .error
        generationStage = .idle
        streamLifecycleState = .failed
        recordSessionDiagnostic(phase: .error, errorMessage: errorMessage)
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
        currentChatStreamTask?.cancel()
        currentChatStreamTask = nil
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        contextEnrichmentTask?.cancel()
        contextEnrichmentTask = nil
        if chatSession != nil {
            chatSession?.cancelStreaming()
            chatSession = nil
            panelController?.deactivateFromChat()
        }
        session.phase = phaseAfterLoadingStops()
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
        session.phase = phaseAfterLoadingStops()
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

    func enterChatMode() {
        guard overlayPhase == .result, hasMeaningfulExplanationText else { return }

        if chatSession == nil {
            let fallbackContext = ContextInfo(
                selectedText: currentContext?.selectedText,
                appName: currentContext?.appName,
                windowTitle: currentContext?.windowTitle,
                surroundingLines: currentContext?.surroundingLines,
                selectionBounds: currentContext?.selectionBounds,
                selectedOccurrenceContext: currentContext?.selectedOccurrenceContext,
                sourceURL: currentContext?.sourceURL,
                sourceHint: currentContext?.sourceHint,
                isConversationContext: currentContext?.isConversationContext ?? false,
                isPartialContext: currentContext?.isPartialContext ?? false
            )
            chatSession = ChatSession(context: fallbackContext, explanation: explanationText)
        }

        session.phase = .chat
        panelController?.activateForChat()
    }

    func exitChatMode() {
        guard overlayPhase == .chat else { return }
        stopChatStreaming(removeEmptyTrailingAssistant: true)
        session.phase = .result
        panelController?.deactivateFromChat()
    }

    func sendChatMessage() {
        guard overlayPhase == .chat, let chatSession else { return }
        guard !chatSession.isStreaming else { return }

        guard let settings = settingsManager else {
            chatSession.appendAssistantMessage("Settings not available.")
            return
        }

        guard !settings.apiKey.isEmpty else {
            chatSession.appendAssistantMessage("API key not set. Add it in Settings first.")
            return
        }

        guard chatSession.appendUserMessageFromInput() != nil else { return }
        _ = chatSession.appendAssistantPlaceholder()

        let messages = chatSession.buildAPIMessages()
        let client = clientFactory(settings.apiKey, settings.modelName)

        currentChatStreamTask?.cancel()
        currentChatStreamTask = Task { @MainActor in
            var didFinalize = false

            @MainActor
            func finalize(removeEmptyTrailingAssistant: Bool) {
                guard !didFinalize else { return }
                didFinalize = true
                self.currentChatStreamTask = nil
                self.chatSession?.finishStreaming()
                if removeEmptyTrailingAssistant {
                    self.chatSession?.removeEmptyTrailingAssistantMessage()
                }
            }

            do {
                let stream = try await client.streamChat(
                    messages: messages,
                    maxOutputTokens: Constants.chatMaxOutputTokens
                )

                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .delta(let text):
                        self.chatSession?.appendDelta(text)
                    case .done:
                        finalize(removeEmptyTrailingAssistant: true)
                    case .error(let message):
                        self.chatSession?.appendDelta("\n\nError: \(message)")
                        finalize(removeEmptyTrailingAssistant: true)
                    }
                }

                if !Task.isCancelled {
                    finalize(removeEmptyTrailingAssistant: true)
                }
            } catch {
                if Task.isCancelled { return }
                self.chatSession?.appendDelta("\n\nError: \(error.localizedDescription)")
                finalize(removeEmptyTrailingAssistant: true)
            }
        }
    }

    func stopChatStreaming() {
        stopChatStreaming(removeEmptyTrailingAssistant: true)
    }

    private func stopChatStreaming(removeEmptyTrailingAssistant: Bool) {
        currentChatStreamTask?.cancel()
        currentChatStreamTask = nil
        chatSession?.cancelStreaming()
        if removeEmptyTrailingAssistant {
            chatSession?.removeEmptyTrailingAssistantMessage()
        }
    }

    var canRequestDeeperExplanation: Bool {
        overlayPhase == .result && currentDepth < 3 && explanationBuffer.last() != nil
    }

    var canCopyCurrentExplanation: Bool {
        overlayPhase == .result && hasMeaningfulExplanationText
    }

    var shouldDismissOnOutsideClick: Bool {
        switch overlayPhase {
        case .loadingPreToken, .loadingStreaming, .result, .chat:
            return false
        case .permissionRequired, .error, .empty:
            return true
        }
    }

    @discardableResult
    func copyCurrentExplanation() -> Bool {
        guard canCopyCurrentExplanation else { return false }
        let value = explanationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        return clipboardWriter(value)
    }

    @discardableResult
    func handlePanelKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return handlePanelKeyDown(
            keyCode: event.keyCode,
            flags: flags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        )
    }

    @discardableResult
    func handleGlobalPanelKeyDown(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        let eventFlags = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
            .intersection(.deviceIndependentFlagsMask)
        return handlePanelKeyDown(
            keyCode: keyCode,
            flags: eventFlags,
            charactersIgnoringModifiers: nil
        )
    }

    private func handlePanelKeyDown(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> Bool {
        if keyCode == 53 {
            if overlayPhase == .chat {
                exitChatMode()
            } else {
                dismiss()
            }
            return true
        }

        if flags.isEmpty, keyCode == 36 {
            if overlayPhase == .result {
                enterChatMode()
                return true
            }
            return false
        }

        let normalizedChars = charactersIgnoringModifiers?.lowercased()
        if flags == [.command],
           (keyCode == 8 || normalizedChars == "c"),
           canCopyCurrentExplanation {
            return copyCurrentExplanation()
        }

        return false
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
                        self.session.phase = .error
                        self.streamLifecycleState = .failed
                        self.recordSessionDiagnostic(phase: .error, errorMessage: self.errorMessage)
                        return
                    }
                    // Give the relaunched app a brief moment to initialize before closing the debug run.
                    try? await Task.sleep(for: .milliseconds(500))
                    NSApplication.shared.terminate(nil)
                }
            }
        } catch {
            errorMessage = "Failed to install stable app to ~/Applications: \(error.localizedDescription)"
            session.phase = .error
            streamLifecycleState = .failed
            recordSessionDiagnostic(phase: .error, errorMessage: errorMessage)
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

private extension CompletionStopReason {
    var shouldEvaluateCompletionGate: Bool {
        self == .length || self == .unknown
    }
}
