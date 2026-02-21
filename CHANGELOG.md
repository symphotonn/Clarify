# Changelog

## [Unreleased]
### Added
- Themed semantic colors (`error`, `success`, `info`) to `ClarifyTheme`, replacing hardcoded `.orange`/`.blue`/`.green` across all views
- Entrance scale animation (0.97→1.0) on panel appear, matching the existing exit scale
- Shadow (ambient + contact) for non-vibrancy themes (Dark Violet, Warm Cream)
- Hover states on action bar buttons (Chat, Copy)
- Phase transition animation (crossfade) when switching between loading/result/error states
- Chat message appear animation (slide-up + fade)
- `accessibilityReduceMotion` support: shimmer shows static bars, streaming snaps text, cursor animation disabled
- Accessibility label on ShimmerView ("Loading explanation")
- Accessibility labels on Chat/Copy action buttons
- Themed divider color visible on all themes (replaces system `Divider`)
- Subtle border on `KeyboardGlyph` for better definition
- Selected-row background highlight on theme picker in Settings
- Warning icon alongside hotkey modifier warning in Settings

### Changed
- Tertiary text contrast bumped from 0.45 to 0.55 opacity on Dark Violet and Warm Cream for better readability
- Exit animation duration increased from 0.06s to 0.12s for a noticeable-but-quick dismiss
- Action bar spacing normalized to 4pt grid (14→12)
- All view spacing normalized to 4pt grid multiples (6→8 in answer body, summary card, incomplete hint)
- Chat bubble padding normalized (10h→12h) and font unified to 13pt with 4pt line spacing
- Streaming cursor character changed from `|` to `▎` for a more native feel
- Shimmer animation uses ease-in-out curve per cycle instead of linear
- Error auto-dismiss timeout increased from 2s to 4s for better readability
- No-selection error message improved: "Highlight some text, then press your hotkey again."
- Empty state copy improved: "Nothing to explain yet" with actionable subtitle
- Error view text uses `theme.body` with `.medium` weight instead of `theme.tertiary`
- Permission view text uses `theme.body` instead of `theme.tertiary` for better readability
- Short selections (<5 characters) no longer show the quoted text above the explanation

### Fixed
- Divider visibility on Dark Violet theme (was invisible with system `Divider`)
- Copy button had no visual disabled state beyond `.disabled()` modifier
