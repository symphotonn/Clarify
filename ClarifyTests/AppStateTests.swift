import XCTest
import AppKit
@testable import Clarify

final class AppStateTests: XCTestCase {
    func testSettingsManagerInTestsDoesNotPolluteStandardDefaults() {
        let standard = UserDefaults.standard
        let originalAPIKey = standard.string(forKey: "apiKey")
        let originalModel = standard.string(forKey: "modelName")

        defer {
            restore(originalAPIKey, forKey: "apiKey", defaults: standard)
            restore(originalModel, forKey: "modelName", defaults: standard)
        }

        let manager = SettingsManager()
        manager.apiKey = "unit-test-api-key"
        manager.modelName = "unit-test-model"

        XCTAssertEqual(standard.string(forKey: "apiKey"), originalAPIKey)
        XCTAssertEqual(standard.string(forKey: "modelName"), originalModel)
    }

    func testSettingsManagerPersistsToInjectedDefaults() {
        let suiteName = "Clarify.AppStateTests.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }

        isolatedDefaults.removePersistentDomain(forName: suiteName)
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let manager = SettingsManager(defaults: isolatedDefaults, environment: [:])
        manager.apiKey = "custom-store-key"
        manager.modelName = "gpt-4.1-mini"

        XCTAssertEqual(isolatedDefaults.string(forKey: "apiKey"), "custom-store-key")
        XCTAssertEqual(isolatedDefaults.string(forKey: "modelName"), "gpt-4.1-mini")
    }

    @MainActor
    func testOverlayPhaseStateMachine() async {
        let state = AppState(
            contextProvider: { _, _ in Self.makeContext() },
            clientFactory: { _, _ in
                DelayedStreamingClient(
                    steps: [
                        .init(delayNanos: 40_000_000, event: .delta("[MODE: Learn]\npartial")),
                        .init(delayNanos: 40_000_000, event: .done(.stop))
                    ]
                )
            },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        XCTAssertEqual(state.overlayPhase, .empty)
        state.handleHotkey(isDoublePress: false)
        XCTAssertEqual(state.overlayPhase, .loadingPreToken)

        await waitUntilPhase(state, phase: .loadingStreaming)
        XCTAssertEqual(state.overlayPhase, .loadingStreaming)

        await waitUntilLoaded(state)
        XCTAssertEqual(state.overlayPhase, .result)
    }

    @MainActor
    func testDoublePressHiddenOverlayStartsNewExplanation() {
        let state = makeState(events: [.done(.stop)])
        state.currentDepth = 2
        state.isOverlayVisible = false
        state.explanationBuffer.push(makeExplanation(text: "previous"))

        state.handleHotkey(isDoublePress: true)

        XCTAssertEqual(state.currentDepth, 1)
    }

    @MainActor
    func testDoublePressVisibleOverlayGoesDeeper() {
        let state = makeState(events: [.done(.stop)])
        state.currentDepth = 1
        state.isOverlayVisible = true
        state.currentContext = Self.makeContext()
        state.explanationBuffer.push(makeExplanation(text: "previous"))

        state.handleHotkey(isDoublePress: true)

        XCTAssertEqual(state.currentDepth, 2)
    }

    @MainActor
    func testHotkeyWithoutPermissionShowsOnboardingState() {
        let state = makeState(events: [.done(.stop)])
        state.permissionGranted = false

        state.handleHotkey(isDoublePress: false)

        XCTAssertTrue(state.isOverlayVisible)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.currentContext)
    }

    @MainActor
    func testStartNewExplanationRetriesWithFullCaptureWhenFastMissesSelection() async {
        let state = AppState(
            contextProvider: { policy, _ in
                switch policy {
                case .fastFirst:
                    return Self.makeContext(selectedText: nil, surroundingLines: nil, isPartialContext: true)
                case .full:
                    return Self.makeContext(selectedText: "watch")
                }
            },
            clientFactory: { _, _ in
                StubStreamingClient(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])
            },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.currentContext?.selectedText, "watch")
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(state.explanationText, "Hello")
        XCTAssertEqual(state.explanationBuffer.count, 1)
    }

    @MainActor
    func testStartNewExplanationUpgradesWeakContextBeforeStreaming() async {
        let state = AppState(
            contextProvider: { policy, _ in
                switch policy {
                case .fastFirst:
                    return ContextInfo(
                        selectedText: "liquidations",
                        appName: "Google Chrome",
                        windowTitle: "Doc",
                        surroundingLines: nil,
                        selectionBounds: nil,
                        isPartialContext: true
                    )
                case .full:
                    return ContextInfo(
                        selectedText: "liquidations",
                        appName: "Google Chrome",
                        windowTitle: "Doc",
                        surroundingLines: "Mark price is used to calculate profit/loss and liquidations.",
                        selectionBounds: nil,
                        selectedOccurrenceContext: "Mark price is used to calculate profit/loss and liquidations."
                    )
                }
            },
            clientFactory: { _, _ in
                StubStreamingClient(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])
            },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.currentContext?.selectedText, "liquidations")
        XCTAssertNotNil(state.currentContext?.surroundingLines)
        XCTAssertNotNil(state.currentContext?.selectedOccurrenceContext)
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(state.explanationText, "Hello")
    }

    @MainActor
    func testStartNewExplanationShowsSelectionErrorWhenFastAndFullCaptureMiss() async {
        let state = AppState(
            contextProvider: { _, _ in
                Self.makeContext(selectedText: nil, surroundingLines: nil, isPartialContext: true)
            },
            clientFactory: { _, _ in
                StubStreamingClient(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])
            },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.errorMessage, "Select some text first")
        XCTAssertEqual(state.explanationBuffer.count, 0)
    }

    @MainActor
    func testStreamWithoutModeHeaderFallsBackToLearnAndKeepsText() async {
        let state = makeState(events: [.delta("Hello world"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.currentMode, .learn)
        XCTAssertEqual(state.explanationText, "Hello world")
        XCTAssertEqual(state.explanationBuffer.last()?.fullText, "Hello world")
    }

    @MainActor
    func testDuplicateDoneOnlyFinalizesOnce() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done(.stop), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationBuffer.count, 1)
        XCTAssertEqual(state.explanationBuffer.last()?.fullText, "Hello")
    }

    @MainActor
    func testModePrefixWithoutNewlineStillStreamsBodyText() async {
        let state = makeState(events: [.delta("[MODE: Learn]"), .delta("Hello world"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.currentMode, .learn)
        XCTAssertEqual(state.explanationText, "Hello world")
        XCTAssertEqual(state.explanationBuffer.last()?.fullText, "Hello world")
    }

    @MainActor
    func testStreamEndingWithoutDoneStillFinalizes() async {
        let state = makeState(events: [.delta("[MODE: Diagnose]\nTraceback")])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.currentMode, .diagnose)
        XCTAssertEqual(state.explanationText, "Traceback")
        XCTAssertEqual(state.explanationBuffer.count, 1)
    }

    @MainActor
    func testEmptyStreamShowsActionableError() async {
        let state = makeState(events: [.done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationText, "")
        XCTAssertEqual(state.explanationBuffer.count, 0)
        XCTAssertEqual(state.errorMessage, "No explanation returned. Verify API key, model, and network access.")
    }

    @MainActor
    func testWhitespaceOnlyBodyShowsActionableError() async {
        let state = makeState(events: [.delta("[MODE: Learn]\n\n\n"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationText, "")
        XCTAssertEqual(state.explanationBuffer.count, 0)
        XCTAssertEqual(state.errorMessage, "No explanation returned. Verify API key, model, and network access.")
    }

    @MainActor
    func testLeadingWhitespaceInBodyIsTrimmed() async {
        let state = makeState(events: [.delta("[MODE: Learn]\n\n  Hello world"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationText, "Hello world")
        XCTAssertEqual(state.explanationBuffer.last()?.fullText, "Hello world")
        XCTAssertNil(state.errorMessage)
    }

    @MainActor
    func testZeroWidthOnlyBodyShowsActionableError() async {
        let state = makeState(events: [.delta("[MODE: Learn]\n\u{200B}\u{2060}\u{FEFF}"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationText, "")
        XCTAssertEqual(state.explanationBuffer.count, 0)
        XCTAssertEqual(state.errorMessage, "No explanation returned. Verify API key, model, and network access.")
    }

    @MainActor
    func testRequestMetricsCaptureStreamingProgress() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .delta(" world"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertNotNil(state.lastRequestMetrics)
        XCTAssertEqual(state.lastRequestMetrics?.didStreamIncrementally, true)
        XCTAssertNotNil(state.lastRequestMetrics?.captureLatencyMs)
        XCTAssertNotNil(state.lastRequestMetrics?.firstTokenLatencyMs)
        XCTAssertGreaterThanOrEqual(state.lastRequestMetrics?.promptBuildLatencyMs ?? -1, 0)
        XCTAssertGreaterThanOrEqual(state.lastRequestMetrics?.requestStartLatencyMs ?? -1, 0)
        XCTAssertGreaterThanOrEqual(state.lastRequestMetrics?.totalLatencyMs ?? -1, 0)
    }

    @MainActor
    func testReturnKeyEntersChatMode() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)
        XCTAssertEqual(state.overlayPhase, .result)

        guard let returnKey = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) else {
            XCTFail("Failed to create return key event")
            return
        }

        XCTAssertTrue(state.handlePanelKeyDown(returnKey))
        XCTAssertEqual(state.overlayPhase, .chat)
        XCTAssertNotNil(state.chatSession)
    }

    @MainActor
    func testGlobalReturnKeyEntersChatMode() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertTrue(state.handleGlobalPanelKeyDown(keyCode: 36, flags: []))
        XCTAssertEqual(state.overlayPhase, .chat)
    }

    @MainActor
    func testEscInChatReturnsToResult() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)
        state.enterChatMode()
        XCTAssertEqual(state.overlayPhase, .chat)

        guard let esc = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ) else {
            XCTFail("Failed to create escape key event")
            return
        }

        XCTAssertTrue(state.handlePanelKeyDown(esc))
        XCTAssertEqual(state.overlayPhase, .result)
    }

    @MainActor
    func testGlobalEscInChatReturnsToResult() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)
        state.enterChatMode()

        XCTAssertTrue(state.handleGlobalPanelKeyDown(keyCode: 53, flags: []))
        XCTAssertEqual(state.overlayPhase, .result)
    }

    @MainActor
    func testReturnInChatIsNotIntercepted() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)
        state.enterChatMode()

        guard let returnKey = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) else {
            XCTFail("Failed to create return key event")
            return
        }

        XCTAssertFalse(state.handlePanelKeyDown(returnKey))
        XCTAssertEqual(state.overlayPhase, .chat)
    }

    @MainActor
    func testSendChatMessageStreamsAssistantReply() async {
        let state = makeState(events: [.delta("Assistant reply"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)
        state.enterChatMode()

        state.chatSession?.currentInput = "Can you clarify this?"
        state.sendChatMessage()
        await waitUntilChatStreamStops(state)

        XCTAssertEqual(state.overlayPhase, .chat)
        let visibleMessages = state.chatSession?.visibleMessages ?? []
        XCTAssertTrue(visibleMessages.contains(where: { $0.role == .user && $0.content == "Can you clarify this?" }))
        XCTAssertEqual(visibleMessages.last?.role, .assistant)
        XCTAssertEqual(visibleMessages.last?.content, "Assistant reply")
    }

    @MainActor
    func testShouldDismissOnOutsideClickFalseInResult() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.overlayPhase, .result)
        XCTAssertFalse(state.shouldDismissOnOutsideClick)
    }

    @MainActor
    func testShouldDismissOnOutsideClickFalseInChat() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)
        state.enterChatMode()

        XCTAssertEqual(state.overlayPhase, .chat)
        XCTAssertFalse(state.shouldDismissOnOutsideClick)
    }

    @MainActor
    func testShouldDismissOnOutsideClickPolicyByPhase() async {
        let emptyState = makeState(events: [.done(.stop)])
        XCTAssertEqual(emptyState.overlayPhase, .empty)
        XCTAssertTrue(emptyState.shouldDismissOnOutsideClick)

        let permissionState = makeState(events: [.done(.stop)])
        permissionState.permissionGranted = false
        XCTAssertEqual(permissionState.overlayPhase, .permissionRequired)
        XCTAssertTrue(permissionState.shouldDismissOnOutsideClick)

        let loadingState = AppState(
            contextProvider: { _, _ in Self.makeContext() },
            clientFactory: { _, _ in
                DelayedStreamingClient(
                    steps: [
                        .init(delayNanos: 120_000_000, event: .delta("[MODE: Learn]\nHello")),
                        .init(delayNanos: 40_000_000, event: .done(.stop))
                    ]
                )
            },
            refreshPermissionOnHotkey: false
        )
        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        loadingState.settingsManager = settings
        loadingState.permissionGranted = true

        loadingState.handleHotkey(isDoublePress: false)
        XCTAssertEqual(loadingState.overlayPhase, .loadingPreToken)
        XCTAssertFalse(loadingState.shouldDismissOnOutsideClick)

        await waitUntilPhase(loadingState, phase: .loadingStreaming)
        XCTAssertFalse(loadingState.shouldDismissOnOutsideClick)

        let errorState = makeState(events: [.done(.stop)])
        errorState.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(errorState)
        XCTAssertEqual(errorState.overlayPhase, .error)
        XCTAssertTrue(errorState.shouldDismissOnOutsideClick)
    }

    @MainActor
    func testHotkeyPressIgnoredWhileLoading() async {
        let client = SequencedStreamingClient(responses: [
            [.delta("[MODE: Learn]\nhello"), .done(.stop)],
            [.delta("[MODE: Learn]\nsecond"), .done(.stop)]
        ])

        let state = AppState(
            contextProvider: { _, _ in Self.makeContext() },
            clientFactory: { _, _ in client },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        XCTAssertEqual(state.overlayPhase, .loadingPreToken)

        // Should be ignored while loading, preventing request restart/cancel.
        state.handleHotkey(isDoublePress: false)

        await waitUntilLoaded(state)
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 1)
    }

    @MainActor
    func testCommandCCopiesCurrentExplanation() async {
        var copiedText: String?
        let state = AppState(
            contextProvider: { _, _ in Self.makeContext() },
            clientFactory: { _, _ in
                StubStreamingClient(events: [.delta("[MODE: Learn]\nHello"), .done(.stop)])
            },
            clipboardWriter: { text in
                copiedText = text
                return true
            },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        guard let commandC = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ) else {
            XCTFail("Failed to create command-C event")
            return
        }

        XCTAssertTrue(state.handlePanelKeyDown(commandC))
        XCTAssertEqual(copiedText, "Hello")
    }

    @MainActor
    func testDepth1RepairCompletesFragmentExplanation() async {
        let client = SequencedStreamingClient(responses: [
            [.delta("[MODE: Learn]\nIn this context, \"fragment\" refers to a"), .done(.length)],
            [.delta("In this context, \"fragment\" refers to an incomplete piece of text."), .done(.stop)]
        ])

        let state = AppState(
            contextProvider: { _, _ in
                ContextInfo(
                    selectedText: "fragment",
                    appName: "Safari",
                    windowTitle: "Docs",
                    surroundingLines: "A fragment is an incomplete piece.",
                    selectionBounds: nil,
                    selectedOccurrenceContext: "A fragment is an incomplete piece."
                )
            },
            clientFactory: { _, _ in client },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.overlayPhase, .result)
        XCTAssertEqual(
            state.explanationText,
            "In this context, \"fragment\" refers to an incomplete piece of text."
        )
        XCTAssertFalse(state.shouldShowIncompleteRetryHint)
        let repairCallCount = await client.callCount()
        XCTAssertEqual(repairCallCount, 2)
    }

    @MainActor
    func testDepth1StopReasonSkipsRepairForCompleteSentence() async {
        let client = SequencedStreamingClient(responses: [
            [.delta("[MODE: Learn]\nA fragment is an incomplete piece of text."), .done(.stop)],
            [.delta("unused"), .done(.stop)]
        ])

        let state = AppState(
            contextProvider: { _, _ in Self.makeContext(selectedText: "fragment") },
            clientFactory: { _, _ in client },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.overlayPhase, .result)
        XCTAssertEqual(state.explanationText, "A fragment is an incomplete piece of text.")
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 1)
    }

    @MainActor
    func testDepth1StopReasonRepairsDanglingSuffix() async {
        let client = SequencedStreamingClient(responses: [
            [.delta("[MODE: Learn]\nIn this context, \"project\" refers to a collection of files and settings in Xcode that are used to develop an"), .done(.stop)],
            [.delta("In this context, \"project\" means the files and settings Xcode uses to build an app."), .done(.stop)]
        ])

        let state = AppState(
            contextProvider: { _, _ in Self.makeContext(selectedText: "project") },
            clientFactory: { _, _ in client },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.overlayPhase, .result)
        XCTAssertEqual(
            state.explanationText,
            "In this context, \"project\" means the files and settings Xcode uses to build an app."
        )
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 2)
    }

    @MainActor
    func testDepth1UnknownStopReasonTriggersRepair() async {
        let client = SequencedStreamingClient(responses: [
            [.delta("[MODE: Learn]\nIn this context, \"fragment\" refers to a"), .done(.unknown)],
            [.delta("In this context, \"fragment\" refers to an incomplete piece of text."), .done(.stop)]
        ])

        let state = AppState(
            contextProvider: { _, _ in Self.makeContext(selectedText: "fragment") },
            clientFactory: { _, _ in client },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.overlayPhase, .result)
        XCTAssertEqual(state.explanationText, "In this context, \"fragment\" refers to an incomplete piece of text.")
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 2)
    }

    @MainActor
    func testDepth1RepairTimeoutKeepsOriginalText() async {
        let client = SlowSecondCallStreamingClient(
            firstResponse: [.delta("[MODE: Learn]\nIn this context, \"fragment\" refers to a"), .done(.length)],
            secondResponseDelayNanos: 5_000_000_000,
            secondResponse: [.delta("In this context, \"fragment\" refers to an incomplete piece of text."), .done(.stop)]
        )

        let state = AppState(
            contextProvider: { _, _ in Self.makeContext(selectedText: "fragment") },
            clientFactory: { _, _ in client },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state, timeout: 4.5)

        XCTAssertEqual(state.overlayPhase, .result)
        XCTAssertEqual(state.explanationText, "In this context, \"fragment\" refers to a")
        XCTAssertTrue(state.shouldShowIncompleteRetryHint)
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 2)
    }

    @MainActor
    func testIncompleteRetryHintClearsAfterRetrySucceeds() async {
        let client = SequencedStreamingClient(responses: [
            [.delta("[MODE: Learn]\nIn this context, \"fragment\" refers to a"), .done(.length)],
            [.error("repair failed")],
            [.delta("[MODE: Learn]\nIn this context, \"fragment\" means an incomplete piece of text."), .done(.stop)]
        ])

        let state = AppState(
            contextProvider: { _, _ in Self.makeContext(selectedText: "fragment") },
            clientFactory: { _, _ in client },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)
        XCTAssertTrue(state.shouldShowIncompleteRetryHint)

        state.retryLastRequest()
        await waitUntilLoaded(state)

        XCTAssertEqual(state.overlayPhase, .result)
        XCTAssertEqual(state.explanationText, "In this context, \"fragment\" means an incomplete piece of text.")
        XCTAssertFalse(state.shouldShowIncompleteRetryHint)
    }

    @MainActor
    func testRepairContextTailStartsAtWordBoundary() {
        let state = makeState(events: [.done(.stop)])
        let text = """
        alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega
        """

        let tail = state.repairContextTail(from: text, maxCharacters: 40)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: tail, options: .backwards) else {
            XCTFail("Tail should exist inside original text")
            return
        }

        if range.lowerBound > trimmed.startIndex {
            let previous = trimmed.index(before: range.lowerBound)
            XCTAssertTrue(trimmed[previous].isWhitespace, "Tail should start at a word boundary")
        }
    }

    @MainActor
    func testDepth1RepairSkipsWhenExplanationAlreadyComplete() async {
        let client = SequencedStreamingClient(responses: [
            [.delta("[MODE: Learn]\nA fragment is an incomplete piece of text."), .done(.stop)]
        ])

        let state = AppState(
            contextProvider: { _, _ in Self.makeContext(selectedText: "fragment") },
            clientFactory: { _, _ in client },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.overlayPhase, .result)
        XCTAssertEqual(state.explanationText, "A fragment is an incomplete piece of text.")
        let completionCallCount = await client.callCount()
        XCTAssertEqual(completionCallCount, 1)
    }

    @MainActor
    private func makeState(events: [StreamEvent]) -> AppState {
        let state = AppState(
            contextProvider: { _, _ in Self.makeContext() },
            clientFactory: { _, _ in StubStreamingClient(events: events) },
            refreshPermissionOnHotkey: false
        )

        let settings = SettingsManager()
        settings.apiKey = "test-key"
        settings.modelName = "test-model"
        state.settingsManager = settings
        state.permissionGranted = true
        return state
    }

    private func makeExplanation(text: String) -> StreamingExplanation {
        StreamingExplanation(
            fullText: text,
            mode: .learn,
            depth: 1,
            context: Self.makeContext()
        )
    }

    @MainActor
    private func waitUntilLoaded(_ state: AppState, timeout: TimeInterval = 1.0, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !state.isLoading {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for stream completion", file: file, line: line)
    }

    @MainActor
    private func waitUntilPhase(
        _ state: AppState,
        phase: AppState.OverlayPhase,
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state.overlayPhase == phase {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for phase \(phase)", file: file, line: line)
    }

    @MainActor
    private func waitUntilChatStreamStops(
        _ state: AppState,
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if state.chatSession?.isStreaming != true {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for chat stream completion", file: file, line: line)
    }

    private static func makeContext(
        selectedText: String? = "selected text",
        surroundingLines: String? = "let x = 1",
        isPartialContext: Bool = false
    ) -> ContextInfo {
        ContextInfo(
            selectedText: selectedText,
            appName: "Xcode",
            windowTitle: "Editor",
            surroundingLines: surroundingLines,
            selectionBounds: nil,
            isPartialContext: isPartialContext
        )
    }

    private func restore(_ value: String?, forKey key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

private struct StubStreamingClient: StreamingClient {
    let events: [StreamEvent]

    func stream(
        instructions: String,
        input: String,
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

private struct DelayedStreamingClient: StreamingClient {
    struct Step {
        let delayNanos: UInt64
        let event: StreamEvent
    }

    let steps: [Step]

    func stream(
        instructions: String,
        input: String,
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for step in steps {
                    if step.delayNanos > 0 {
                        try? await Task.sleep(nanoseconds: step.delayNanos)
                    }
                    continuation.yield(step.event)
                }
                continuation.finish()
            }
        }
    }
}

private actor SequencedStreamingState {
    private let responses: [[StreamEvent]]
    private var nextIndex = 0
    private var streamInvocations = 0

    init(responses: [[StreamEvent]]) {
        self.responses = responses
    }

    func callCount() -> Int {
        return streamInvocations
    }

    func nextEvents() -> [StreamEvent] {
        streamInvocations += 1
        guard nextIndex < responses.count else {
            return [.done(.stop)]
        }
        defer { nextIndex += 1 }
        return responses[nextIndex]
    }
}

private final class SequencedStreamingClient: StreamingClient, @unchecked Sendable {
    private let state: SequencedStreamingState

    init(responses: [[StreamEvent]]) {
        self.state = SequencedStreamingState(responses: responses)
    }

    func callCount() async -> Int {
        await state.callCount()
    }

    func stream(
        instructions: String,
        input: String,
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let events = await state.nextEvents()

        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}

private actor SlowSecondCallState {
    private var invocationCount = 0

    func nextInvocation() -> Int {
        invocationCount += 1
        return invocationCount
    }

    func callCount() -> Int {
        invocationCount
    }
}

private final class SlowSecondCallStreamingClient: StreamingClient, @unchecked Sendable {
    private let firstResponse: [StreamEvent]
    private let secondResponseDelayNanos: UInt64
    private let secondResponse: [StreamEvent]
    private let state = SlowSecondCallState()

    init(
        firstResponse: [StreamEvent],
        secondResponseDelayNanos: UInt64,
        secondResponse: [StreamEvent]
    ) {
        self.firstResponse = firstResponse
        self.secondResponseDelayNanos = secondResponseDelayNanos
        self.secondResponse = secondResponse
    }

    func callCount() async -> Int {
        await state.callCount()
    }

    func stream(
        instructions: String,
        input: String,
        maxOutputTokens: Int?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let invocation = await state.nextInvocation()
        let response = invocation == 1 ? firstResponse : secondResponse
        let delay = invocation == 1 ? UInt64(0) : secondResponseDelayNanos

        return AsyncThrowingStream { continuation in
            Task {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                for event in response {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
