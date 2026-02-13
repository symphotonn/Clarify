# 06. Smoke-Test Checklist
_Last updated: 2026-02-13 06:20 UTC_

Purpose: quick regression sweep for hotkey, overlay panel behavior, and permissions.

## Run Metadata
- Date: 2026-02-13
- Environment: macOS local xcodebuild test run
- App build path: DerivedData Debug test host
- Tester: Codex (automated checks) + pending human manual checks

## A. Automated Checks (CLI)

Run from `Clarify/`:

1. `xcodebuild -project Clarify.xcodeproj -scheme Clarify -destination 'platform=macOS' -only-testing:ClarifyTests/AppStateTests test`
2. `xcodebuild -project Clarify.xcodeproj -scheme Clarify -destination 'platform=macOS' -only-testing:ClarifyTests/HotkeyManagerTests test`
3. `xcodebuild -project Clarify.xcodeproj -scheme Clarify -destination 'platform=macOS' -only-testing:ClarifyTests/PromptBuilderTests test`

Pass criteria:
- All selected test suites pass.

## B. Manual Checks (Interactive)

### B1. Hotkey Trigger and Overlay Open
1. Select text in another app.
2. Press configured hotkey.
3. Verify overlay opens near selection and enters loading state.

Expected:
- Overlay appears once, correctly positioned, then streams result.

### B2. Esc Dismiss (Active-App Path)
1. Trigger overlay.
2. Ensure Clarify is active/focused.
3. Press `Esc`.

Expected:
- Overlay dismisses immediately.

### B3. Esc Dismiss (Inactive-App Path)
1. Trigger overlay from another foreground app.
2. Keep that app active.
3. Press `Esc`.

Expected:
- Overlay dismisses immediately.

### B4. Deeper and Copy Actions
1. Wait for result state.
2. Trigger deeper using either `More` or hotkey double-press.
3. Verify deeper explanation request starts.
4. Press `Cmd+C` in result state.
5. Paste into a text field.

Expected:
- Deeper action triggers request (up to depth 3).
- `Cmd+C` copies current explanation text.

### B5. Click-Outside Dismiss
1. Trigger overlay and wait for result.
2. Click outside panel bounds.
3. Enter chat mode and click outside panel bounds.
4. Trigger a new request and click outside during loading.
5. Trigger an error state and click outside.

Expected:
- Result view does not dismiss on outside click.
- Chat view does not dismiss on outside click.
- Loading state does not dismiss on outside click.
- Error state dismisses on outside click.

### B6. Permission Flow and Auto-Resume
1. Revoke Accessibility permission for Clarify.
2. Trigger hotkey.
3. Use permission enable flow.
4. Grant permission and return.

Expected:
- Permission screen appears.
- After grant, hotkey flow resumes without app restart.

### B7. Hotkey Conflict Hint
1. Set a likely-conflicting shortcut in Settings.
2. Observe settings hint.
3. Restore valid shortcut.

Expected:
- Conflict hint appears on failure and clears after valid registration.

### B8. Enter-To-Chat + Esc Layering
1. Trigger overlay and wait for result state.
2. Press `Return` while source app remains foreground.
3. Verify chat mode opens and input gains focus.
4. Type a follow-up and press `Return`; verify streaming reply appears.
5. Press `Esc`; verify chat exits to result (panel still visible).
6. Press `Esc` again; verify panel dismisses.

Expected:
- First `Return` enters chat mode and does not pass through to host app.
- Chat submit works via `Return`.
- Esc in chat exits chat; Esc in result dismisses panel.

### B9. Progressive Reveal Consistency
1. Trigger explanation flow on a medium/long selection.
2. Watch explanation text render.
3. Enter chat and ask a follow-up question.
4. Watch assistant reply render.

Expected:
- Explanation appears progressively (not instant full snap).
- Chat reply appears progressively (not instant full snap).

### B10. In-Flight Hotkey Guard
1. Trigger overlay and start a request.
2. While loading/streaming, press the global hotkey repeatedly.
3. Wait for completion.

Expected:
- In-flight request continues to completion without reset.
- No second request starts until the first one finishes.

### B11. Completion Reliability Gate
1. Trigger a case that previously tended to truncate depth-1 output (short phrase/context).
2. Verify normal complete answers still return immediately with no visible repair delay.
3. Trigger a forced/known truncation scenario (for example test fixture with `.length` stop reason).
4. Observe final rendered output after stream completion.

Expected:
- `.stop` completions are accepted without unnecessary repair round-trip.
- `.length`/`.unknown` completions are auto-repaired once, bounded by timeout.
- If repair times out, original text remains visible (no synthetic punctuation patch).
- Final text never remains partially revealed beyond the flush deadline.

## C. Results Log (Append Newest First)

- 2026-02-13
  - Automated checks: pass
  - Manual checks: pending
  - Notes: CLI checks passed for `AppStateTests`, `HotkeyManagerTests`, and `PromptBuilderTests`. Interactive checks B1-B11 still require human run on desktop session.
