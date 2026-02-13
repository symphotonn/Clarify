# 04. Decision Log (Append-Only)
_Last updated: 2026-02-13 06:20 UTC_

Do not edit or rewrite prior entries. Add new entries at the top using this format:

- `YYYY-MM-DD` - **Decision:** ...
  - **Why:** ...
  - **Rejected:** ...

## Entries

- `2026-02-13` - **Decision:** Trust model-completed `.stop` responses and skip depth-1 completeness gate for that stop reason.
  - **Why:** Reduces false-positive repair calls on intentionally concise/fragment-like but valid completions.
  - **Rejected:** Running completion gate for every stop reason.

- `2026-02-13` - **Decision:** Add a `.stop` exception for obvious incomplete endings (dangling suffix or unmatched delimiters/quotes) and run one repair pass.
  - **Why:** Some model `.stop` completions can still end mid-thought (for example trailing “an”), which hurts first-response reliability.
  - **Rejected:** Blindly trusting all `.stop` outputs with no structural guard.

- `2026-02-13` - **Decision:** Run depth-1 completion gate only for uncertain/truncated stops (`.length` or `.unknown`), with a single repair attempt capped at 3 seconds.
  - **Why:** Improves completeness reliability while bounding latency and avoiding long repair stalls.
  - **Rejected:** Unlimited/uncapped repair retries.

- `2026-02-13` - **Decision:** Keep progressive reveal but force final flush after a 300ms post-stream deadline if text is still partially revealed.
  - **Why:** Preserves typing-like animation while preventing “looks truncated” UI states.
  - **Rejected:** 150ms flush deadline that can race slower main-thread scheduling.

- `2026-02-13` - **Decision:** Ignore new global hotkey triggers while an explanation request is already loading/streaming.
  - **Why:** Prevents accidental restart/cancel behavior from repeated key presses that can truncate first explanations.
  - **Rejected:** Allowing re-trigger during loading and relying on users to avoid duplicate key presses.

- `2026-02-13` - **Decision:** Disable outside-click dismissal during loading phases (`loadingPreToken`, `loadingStreaming`).
  - **Why:** Click focus changes during generation should not cancel in-flight responses or produce incomplete output.
  - **Rejected:** Dismissing panel on outside click in loading state.

- `2026-02-13` - **Decision:** Force depth-1 explanations to beginner-friendly plain language with tighter brevity budgets.
  - **Why:** First response should optimize for immediate comprehension and minimal cognitive load.
  - **Rejected:** Keeping depth-1 style/tone mostly inferred from code-like context.

- `2026-02-13` - **Decision:** Enforce “concise but complete” for depth-1 by prohibiting sentence fragments and raising depth-1 token headroom.
  - **Why:** Overly strict token caps can produce truncated first explanations that feel incomplete.
  - **Rejected:** Keeping very low depth-1 token budgets that risk mid-sentence cutoffs.

- `2026-02-13` - **Decision:** Add depth-1 fragment repair pass for obvious incomplete endings (for example trailing “a/the/to”).
  - **Why:** Prompt constraints alone cannot guarantee completion on every response; repair pass recovers incomplete first explanations.
  - **Rejected:** Accepting fragment outputs and relying only on manual retry.

- `2026-02-13` - **Decision:** Disable outside-click dismissal in `result` and `chat` phases; keep it in non-result phases.
  - **Why:** Prevents accidental loss of context while users are reading or chatting.
  - **Rejected:** Single outside-click dismissal in all phases.

- `2026-02-13` - **Decision:** Keep progressive word-by-word reveal in UI even when model output arrives in one large chunk.
  - **Why:** Maintains perceived streaming behavior and readability for both explanation and follow-up chat responses.
  - **Rejected:** Snap-to-full-text rendering when the provider emits a single delta.

- `2026-02-13` - **Decision:** Pause global hotkey handling while the Settings hotkey recorder is active.
  - **Why:** Prevents accidental Clarify overlay triggers when testing conflicting shortcuts (for example Spotlight combos).
  - **Rejected:** Leaving global hotkey callbacks active during shortcut recording.

- `2026-02-13` - **Decision:** Enter opens follow-up chat mode from result view; deeper remains on `More` and double-hotkey.
  - **Why:** Enter-to-chat is higher-value than Enter-to-deeper, and `More` already covers depth progression explicitly.
  - **Rejected:** Keeping Enter mapped to deeper explanation.

- `2026-02-13` - **Decision:** Use a global key event tap while overlay is visible to intercept Clarify shortcuts (`Esc`, `Return`, `Cmd+C`) before host apps.
  - **Why:** Non-activating overlays do not reliably receive local key events; global interception prevents VSCode/host app propagation bugs.
  - **Rejected:** Local-monitor-only handling for shortcuts.

- `2026-02-13` - **Decision:** Do not globally hijack `Return` for deeper explanation while overlay is visible.
  - **Why:** `Return` is a primary input key in chat/editors; swallowing it harms normal typing flow in source apps.
  - **Rejected:** Global `Return` interception for overlay actions.

- `2026-02-13` - **Decision:** Do not use `makeKeyAndOrderFront` for the overlay panel during capture flow.
  - **Why:** It can steal focus from source apps (for example VSCode), causing AX capture to miss active selection and show false `Select some text first` errors.
  - **Rejected:** Making the overlay key as the primary way to guarantee Esc handling.

- `2026-02-13` - **Decision:** Keep project context docs under `docs/context` and auto-refresh them via script + pre-commit hook.
  - **Why:** Reduces context loss between sessions and keeps file map freshness tied to normal development flow.
  - **Rejected:** Manual-only documentation updates with no automation.

- `2026-02-13` - **Decision:** Use `OverlaySession` + explicit `SessionPhase` as overlay state source of truth.
  - **Why:** Derived state (`isLoading + text + error + permission`) created race-prone transitions and fragile UI logic.
  - **Rejected:** Keep inferred phase logic from scattered booleans.

- `2026-02-13` - **Decision:** Standardize overlay keyboard actions (`Esc` dismiss, `Return` deeper, `Cmd+C` copy).
  - **Why:** High-utility interactions with minimal UI complexity and strong keyboard-first workflow.
  - **Rejected:** Mouse-only action row.

- `2026-02-13` - **Decision:** Tighten prompt constraints (direct first sentence; likely meaning before ambiguity note).
  - **Why:** Improves answer quality consistency without adding new UI controls.
  - **Rejected:** Add user-facing expertise/tone toggles.

- `2026-02-13` - **Decision:** Keep settings intentionally minimal (API key, hotkey, model under advanced).
  - **Why:** Faster onboarding, fewer failure modes, less cognitive load.
  - **Rejected:** Large settings surface with manual explanation style controls.

- `2026-02-13` - **Decision:** Keep app as menu bar utility with floating non-document overlay panel.
  - **Why:** User intent is quick contextual clarification, not long-form editor workflow.
  - **Rejected:** Full window-first architecture.
