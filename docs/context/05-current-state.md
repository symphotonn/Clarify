# 05. Current State / Next Steps
_Last updated: 2026-02-13 06:28 UTC_

## What Works
- Global hotkey triggers capture and explanation flow.
- Overlay state machine is explicit via `OverlaySession` / `SessionPhase`.
- Loading UX includes shimmer, streaming text reveal, cancel, retry, and instant dismissal animation.
- Depth flow works (`More` button and double-hotkey for deeper explanation up to depth 3).
- Copy works via button and `Cmd+C`.
- Enter from result opens follow-up chat mode with an input field and streaming multi-turn replies.
- Esc behavior is layered: Esc in chat returns to result; Esc in result dismisses overlay.
- Explanation and chat rendering both reveal text progressively word-by-word (including single-chunk model outputs).
- Progressive reveal now has a 300ms final-flush deadline after streaming stops, preventing stale partial text.
- Outside-click dismissal is disabled in loading/result/chat and enabled only in permission/error/empty states.
- First explanation (depth 1) now enforces plain-language beginner style with concise-but-complete constraints (no sentence fragments).
- Depth-1 completion gate runs only for `.length`/`.unknown` stop reasons; `.stop` is trusted and skips repair.
- Depth-1 repair uses continuation-tail context, one attempt max, and a 3s hard timeout.
- `.stop` now has a safety exception: obvious incomplete endings still trigger one repair pass.
- If completion still degrades (for example repair timeout/failure), result view shows a subtle inline `Incomplete response` hint with a `Retry` action.
- Permission onboarding supports polling and auto-resume after grant.
- Settings persist API key/hotkey/model, with registration conflict hint for unavailable shortcuts.
- Global hotkey callbacks are paused during Settings shortcut recording to avoid accidental overlay triggers.
- Global hotkey retriggers are ignored while generation is in-flight to protect stream completion.
- Streaming path includes SSE parser hardening plus non-stream fallback on timeout/empty stream paths.
- Project memory docs are in `docs/context/`, with auto-refresh on commit via `.githooks/pre-commit`.
- Global key event tap intercepts overlay shortcuts while visible, without forcing source-app focus loss in result mode.

## Latest Smoke Test
- Date: 2026-02-13
- Automated: pass (`xcodebuild -scheme Clarify test`, including `AppStateTests`, `ChatSessionTests`, `PromptBuilderTests`)
- Manual interactive: pending (`docs/context/06-smoke-test-checklist.md`, sections B1-B10)

## Known Risks / Gaps
- Keep smoke-testing Esc/Return/Cmd+C and outside-click behavior in VSCode/browser editors to catch propagation regressions early.
- Runtime style-mask toggling (`nonactivatingPanel` <-> activating) can be brittle on some macOS versions; monitor focus edge cases.
- Prompt behavior quality is rule-based; no offline eval harness yet.
- Accessibility/DOM/OCR capture is best-effort and can vary by target app.

## Next Steps
1. Run and record manual interactive smoke checks B1-B10 from `docs/context/06-smoke-test-checklist.md` (especially chat mode + host-app key propagation).
2. Add a deterministic prompt-quality regression test fixture set (expected style/structure checks).
3. Add lightweight diagnostics UI (optional debug section) fed by `recentSessionDiagnostics`.

## Session Reload Prompt
When starting a new AI session, paste:

- `docs/context/01-system-overview.md`
- `docs/context/05-current-state.md`
- Relevant sections of `docs/context/04-decision-log.md`
