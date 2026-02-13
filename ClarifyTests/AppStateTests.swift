import XCTest
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
    func testOverlayPhaseStateMachine() {
        let state = makeState(events: [.done])

        state.permissionGranted = false
        state.errorMessage = nil
        state.isLoading = false
        state.explanationText = ""
        XCTAssertEqual(state.overlayPhase, .permissionRequired)

        state.permissionGranted = true
        state.isLoading = true
        XCTAssertEqual(state.overlayPhase, .loadingPreToken)

        state.explanationText = "partial"
        XCTAssertEqual(state.overlayPhase, .loadingStreaming)

        state.isLoading = false
        XCTAssertEqual(state.overlayPhase, .result)

        state.errorMessage = "boom"
        XCTAssertEqual(state.overlayPhase, .error)
    }

    @MainActor
    func testDoublePressHiddenOverlayStartsNewExplanation() {
        let state = makeState(events: [.done])
        state.currentDepth = 2
        state.isOverlayVisible = false
        state.explanationBuffer.push(makeExplanation(text: "previous"))

        state.handleHotkey(isDoublePress: true)

        XCTAssertEqual(state.currentDepth, 1)
    }

    @MainActor
    func testDoublePressVisibleOverlayGoesDeeper() {
        let state = makeState(events: [.done])
        state.currentDepth = 1
        state.isOverlayVisible = true
        state.currentContext = Self.makeContext()
        state.explanationBuffer.push(makeExplanation(text: "previous"))

        state.handleHotkey(isDoublePress: true)

        XCTAssertEqual(state.currentDepth, 2)
    }

    @MainActor
    func testHotkeyWithoutPermissionShowsOnboardingState() {
        let state = makeState(events: [.done])
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
                StubStreamingClient(events: [.delta("[MODE: Learn]\nHello"), .done])
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
                StubStreamingClient(events: [.delta("[MODE: Learn]\nHello"), .done])
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
                StubStreamingClient(events: [.delta("[MODE: Learn]\nHello"), .done])
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
        let state = makeState(events: [.delta("Hello world"), .done])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.currentMode, .learn)
        XCTAssertEqual(state.explanationText, "Hello world")
        XCTAssertEqual(state.explanationBuffer.last()?.fullText, "Hello world")
    }

    @MainActor
    func testDuplicateDoneOnlyFinalizesOnce() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .done, .done])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationBuffer.count, 1)
        XCTAssertEqual(state.explanationBuffer.last()?.fullText, "Hello")
    }

    @MainActor
    func testModePrefixWithoutNewlineStillStreamsBodyText() async {
        let state = makeState(events: [.delta("[MODE: Learn]"), .delta("Hello world"), .done])

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
        let state = makeState(events: [.done])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationText, "")
        XCTAssertEqual(state.explanationBuffer.count, 0)
        XCTAssertEqual(state.errorMessage, "No explanation returned. Verify API key, model, and network access.")
    }

    @MainActor
    func testWhitespaceOnlyBodyShowsActionableError() async {
        let state = makeState(events: [.delta("[MODE: Learn]\n\n\n"), .done])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationText, "")
        XCTAssertEqual(state.explanationBuffer.count, 0)
        XCTAssertEqual(state.errorMessage, "No explanation returned. Verify API key, model, and network access.")
    }

    @MainActor
    func testLeadingWhitespaceInBodyIsTrimmed() async {
        let state = makeState(events: [.delta("[MODE: Learn]\n\n  Hello world"), .done])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationText, "Hello world")
        XCTAssertEqual(state.explanationBuffer.last()?.fullText, "Hello world")
        XCTAssertNil(state.errorMessage)
    }

    @MainActor
    func testZeroWidthOnlyBodyShowsActionableError() async {
        let state = makeState(events: [.delta("[MODE: Learn]\n\u{200B}\u{2060}\u{FEFF}"), .done])

        state.handleHotkey(isDoublePress: false)
        await waitUntilLoaded(state)

        XCTAssertEqual(state.explanationText, "")
        XCTAssertEqual(state.explanationBuffer.count, 0)
        XCTAssertEqual(state.errorMessage, "No explanation returned. Verify API key, model, and network access.")
    }

    @MainActor
    func testRequestMetricsCaptureStreamingProgress() async {
        let state = makeState(events: [.delta("[MODE: Learn]\nHello"), .delta(" world"), .done])

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
