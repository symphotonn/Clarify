# 03. Data Model
_Last updated: 2026-02-21 21:10 UTC_

## Storage Model (No SQL/Cloud DB)
Clarify currently has no relational database. Data is split into:

- Persistent local settings (`UserDefaults`).
- In-memory runtime/session models.
- External API request/stream payloads.

## Persistent Store: `UserDefaults`
Logical collection: `settings` (singleton document)

- `apiKey: String`
- `modelName: String`
- `hotkeyKey: String` (`HotkeyKey` raw value)
- `hotkeyUseOption: Bool`
- `hotkeyUseCommand: Bool`
- `hotkeyUseControl: Bool`
- `hotkeyUseShift: Bool`

Relationships:
- `settings.hotkey*` -> configures `HotkeyBinding` -> consumed by `HotkeyManager`.
- `settings.apiKey/modelName` -> consumed by `OpenAIClient` creation.

## Runtime Models
Logical collection: `overlay_session` (one active session)

- `id: UUID`
- `phase: SessionPhase` (`permissionRequired | loadingPreToken | loadingStreaming | result | chat | error | empty`)
- `depth: Int`
- `context: ContextInfo?`
- `displayText: String`
- `errorMessage: String?`
- `mode: ExplanationMode` (`learn | simplify | diagnose`)
- `metrics: RequestMetrics?`
- `startedAt: Date`

Logical collection: `context_info`

- `selectedText: String?`
- `appName: String?`
- `windowTitle: String?`
- `surroundingLines: String?`
- `selectionBounds: CGRect?`
- `selectedOccurrenceContext: String?`
- `sourceURL: String?`
- `sourceHint: String?`
- `isConversationContext: Bool`
- `isPartialContext: Bool`

Logical collection: `streaming_explanations` (ring buffer, capacity 5)

- `fullText: String`
- `mode: ExplanationMode`
- `depth: Int`
- `context: ContextInfo`

Logical collection: `session_diagnostics` (ring buffer, capacity 20)

- `sessionID: UUID`
- `phase: SessionPhase`
- `depth: Int`
- `metrics: RequestMetrics?`
- `errorMessage: String?`
- `metFirstTokenBudget: Bool?`
- `metTotalLatencyBudget: Bool?`
- `endedAt: Date`

Logical collection: `chat_session` (ephemeral, one active while overlay is in chat mode)

- `messages: [ConversationMessage]` (`system | assistant | user`)
- `currentInput: String`
- `isStreaming: Bool`
- `streamingMessageID: UUID?`
- lifecycle: created when entering chat, discarded on dismiss/new explanation

## External API Model
Request payload (`ChatCompletionRequest`):
- `model: String`
- `messages: [ChatMessage(role, content)]`
- `stream: Bool`
- `max_tokens: Int?`
- `temperature: Double`
- `store: Bool`

Streaming events (`StreamEvent`):
- `.delta(String)`
- `.done`
- `.error(String)`

## Relationship Summary
- `settings` -> configures hotkey + model/API behavior globally.
- `overlay_session` -> owns current `context_info` + live output text.
- `chat_session` -> reuses source context + current explanation and sends multi-turn `messages` arrays.
- Completed stream -> appended to `streaming_explanations` buffer.
- Session completion/failure -> appended to `session_diagnostics`.
