# 01. System Overview
_Last updated: 2026-02-13 06:20 UTC_

## What The App Does
Clarify is a macOS menu bar assistant for instant text explanations.

- User selects text in any app and triggers a global hotkey.
- Clarify captures local context (selection, nearby lines, source hints).
- Clarify sends a prompt to OpenAI and streams the answer into a floating overlay panel.
- User can dismiss, copy, request deeper follow-up explanations, or press Enter to open an in-panel chat.

## Tech Stack
- Language/runtime: Swift 5, Swift Concurrency.
- UI: SwiftUI + AppKit (`NSPanel`) for floating overlay behavior.
- macOS integrations: Accessibility APIs, Carbon hotkeys, pasteboard.
- Networking: `URLSession` with SSE parsing for streamed responses.
- Persistence: `UserDefaults` for settings (API key, model, hotkey), in-memory buffers for session/explanations.
- Tests: `XCTest`.

## How Parts Connect
- `ClarifyApp` boots menu bar scenes and settings scene.
- `AppDelegate` wires `AppState`, `SettingsManager`, `HotkeyManager`, and `PanelController`.
- `HotkeyManager` emits hotkey presses to `AppState.handleHotkey(...)`.
- `AppState` orchestrates capture -> prompt build -> API stream -> overlay state transitions.
- `ChatSession` stores ephemeral follow-up conversation state (system + assistant + user turns).
- `AccessibilityCapture` + `CursorPositionProvider` provide selected text and anchor coordinates.
- `PromptBuilder` builds deterministic instructions/input; `OpenAIClient` streams SSE deltas.
- `ExplanationView` renders current `overlayPhase`; `ChatView` renders follow-up chat UI in `.chat` phase.

## Simple Diagram
`User -> Frontend -> API -> DB`

- `User`: keyboard + text selection in foreground app.
- `Frontend`: Clarify menu bar + overlay UI (SwiftUI/AppKit).
- `API`: OpenAI Chat Completions endpoint.
- `DB`: local persistence (`UserDefaults`) plus in-memory runtime buffers.

## Request Lifecycle (Happy Path)
1. Hotkey pressed.
2. Accessibility capture gathers selected text + context.
3. Panel appears near selection.
4. Prompt is built with depth/context/tone rules.
5. SSE stream begins; UI moves from pre-token loading to streaming.
6. Final text is committed; result actions become available (`Enter to chat`, `More`, `Copy`).
7. Optional chat mode: user asks follow-up questions; assistant responses stream in-message.
