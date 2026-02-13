#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$ROOT_DIR/docs/context"
TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M UTC')"

if [[ ! -d "$DOCS_DIR" ]]; then
  echo "Missing docs directory: $DOCS_DIR" >&2
  exit 1
fi

update_last_updated() {
  local file="$1"
  if [[ -f "$file" ]] && grep -q '^_Last updated:' "$file"; then
    sed -i '' "s#^_Last updated:.*#_Last updated: ${TIMESTAMP}_#" "$file"
  fi
}

describe_file() {
  case "$1" in
    run.sh) echo "Builds Debug app, rsyncs to ~/Applications/Clarify.app, and launches it." ;;

    Clarify/App/ClarifyApp.swift) echo "App entry point; defines menu bar and settings scenes." ;;
    Clarify/App/AppDelegate.swift) echo "Wires runtime dependencies and application lifecycle callbacks." ;;
    Clarify/App/AppState.swift) echo "Main actor state machine for capture, streaming, overlay phases, and shortcuts." ;;
    Clarify/App/ChatSession.swift) echo "Ephemeral follow-up chat model for multi-turn message state and streaming deltas." ;;

    Clarify/Context/AccessibilityCapture.swift) echo "Captures selected text/context via AX, DOM hints, OCR, and clipboard fallback." ;;
    Clarify/Context/CursorPositionProvider.swift) echo "Computes overlay anchor position from selection bounds or mouse location." ;;
    Clarify/Context/ContextInfo.swift) echo "Context payload model for selected text and surrounding source metadata." ;;

    Clarify/Hotkey/HotkeyBinding.swift) echo "Defines supported hotkey keys, modifiers, and matching logic." ;;
    Clarify/Hotkey/HotkeyManager.swift) echo "Registers global Carbon hotkey and emits press/double-press events." ;;
    Clarify/Hotkey/DoublePressDetector.swift) echo "Detects consecutive hotkey presses within a time window." ;;
    Clarify/Hotkey/PermissionManager.swift) echo "Tracks and requests Accessibility/screen-capture permissions." ;;

    Clarify/LLM/Models.swift) echo "Shared API/prompt/stream domain models and protocols." ;;
    Clarify/LLM/PromptBuilder.swift) echo "Builds prompt instructions/input from context, depth, and intent heuristics." ;;
    Clarify/LLM/OpenAIClient.swift) echo "OpenAI streaming client with timeout fallback and response extraction." ;;
    Clarify/LLM/SSEParser.swift) echo "Parses SSE frames into delta/done/error stream events." ;;

    Clarify/Panel/OverlayPanel.swift) echo "Custom floating NSPanel configuration for the explanation overlay." ;;
    Clarify/Panel/PanelController.swift) echo "Shows/hides panel, installs outside-click and key monitors, handles dismissal." ;;
    Clarify/Panel/PanelPositioner.swift) echo "Calculates on-screen clamped panel frame near selection." ;;

    Clarify/Storage/SettingsManager.swift) echo "Persists API/model/hotkey settings and exposes registration issues." ;;
    Clarify/Storage/ExplanationBuffer.swift) echo "In-memory ring buffer of recent explanations for deeper follow-ups." ;;

    Clarify/Utilities/Constants.swift) echo "Central constants for API, UI sizing, timeouts, and budgets." ;;
    Clarify/Utilities/Extensions.swift) echo "Shared helpers for geometry conversion and string truncation/context slicing." ;;

    Clarify/Views/ExplanationView.swift) echo "Main overlay UI: loading, result, error, permission, and actions." ;;
    Clarify/Views/ChatView.swift) echo "Follow-up chat UI with message bubbles, auto-scroll, and input composer." ;;
    Clarify/Views/SettingsView.swift) echo "Settings UI for API key, hotkey capture/reset, and advanced model." ;;
    Clarify/Views/OnboardingView.swift) echo "Permission onboarding UI used when accessibility access is missing." ;;
    Clarify/Views/Components/StreamingTextView.swift) echo "Renders streamed text with progressive reveal and cursor indicator." ;;
    Clarify/Views/Components/ShimmerView.swift) echo "Skeleton shimmer placeholder for pre-token loading state." ;;
    Clarify/Views/Components/VisualEffectBackground.swift) echo "AppKit visual effect wrapper for translucent overlay background." ;;

    Clarify/Info.plist) echo "App metadata and macOS permission usage strings/configuration." ;;
    Clarify/Resources/Clarify.entitlements) echo "App entitlements used for local debug/runtime behavior." ;;
    Clarify/Resources/Assets.xcassets/Contents.json) echo "Asset catalog root manifest." ;;
    Clarify/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json) echo "App icon asset metadata." ;;

    ClarifyTests/AppStateTests.swift) echo "Tests AppState request lifecycle, phases, metrics, and keyboard actions." ;;
    ClarifyTests/PromptBuilderTests.swift) echo "Tests prompt constraints, depth behavior, and inference rules." ;;
    ClarifyTests/SSEParserTests.swift) echo "Tests SSE framing, deltas, done, and error parsing behavior." ;;
    ClarifyTests/HotkeyManagerTests.swift) echo "Tests hotkey matching, modifiers, and detector integration points." ;;
    ClarifyTests/DoublePressDetectorTests.swift) echo "Tests double-press timing detection boundaries." ;;
    ClarifyTests/ExplanationBufferTests.swift) echo "Tests explanation buffer capacity and eviction behavior." ;;
    ClarifyTests/PanelPositionerTests.swift) echo "Tests panel placement and edge clamping logic." ;;
    ClarifyTests/ChatSessionTests.swift) echo "Tests chat session seeding, message append, and API message mapping." ;;

    Clarify.xcodeproj/project.pbxproj) echo "Xcode project configuration, build settings, and file references." ;;
    Clarify.xcodeproj/xcshareddata/xcschemes/Clarify.xcscheme) echo "Shared Xcode scheme for build/test/run actions." ;;
    docs/context/README.md) echo "How to maintain and auto-refresh the context documentation pack." ;;
    docs/context/01-system-overview.md) echo "One-page architecture and request-flow reorientation document." ;;
    docs/context/02-file-folder-map.md) echo "Generated one-line map of folders/files and responsibilities." ;;
    docs/context/03-data-model.md) echo "Persistent/runtime/external data shapes and relationships." ;;
    docs/context/04-decision-log.md) echo "Append-only record of architecture and product decisions." ;;
    docs/context/05-current-state.md) echo "Living snapshot of what works, gaps, and next steps." ;;
    docs/context/06-smoke-test-checklist.md) echo "Automated and manual smoke-test checklist with latest execution log." ;;
    scripts/update_context_docs.sh) echo "Regenerates context docs and updates timestamps." ;;
    .githooks/pre-commit) echo "Pre-commit automation that refreshes and stages context docs." ;;

    *) echo "Purpose not documented yet; add one-line description." ;;
  esac
}

for doc in \
  "$DOCS_DIR/01-system-overview.md" \
  "$DOCS_DIR/03-data-model.md" \
  "$DOCS_DIR/04-decision-log.md" \
  "$DOCS_DIR/05-current-state.md" \
  "$DOCS_DIR/06-smoke-test-checklist.md"; do
  update_last_updated "$doc"
done

MAP_FILE="$DOCS_DIR/02-file-folder-map.md"

{
  echo "# 02. File/Folder Map"
  echo "_Last updated: ${TIMESTAMP}_"
  echo
  echo "One-line purpose per folder/file. Regenerated by scripts/update_context_docs.sh."
  echo
  echo "## Folders"
  echo '- Clarify/App - app lifecycle and orchestration state.'
  echo '- Clarify/Context - text/context capture and cursor anchoring.'
  echo '- Clarify/Hotkey - global hotkey definitions and registration.'
  echo '- Clarify/LLM - prompt construction, streaming client, parser, models.'
  echo '- Clarify/Panel - floating overlay panel and placement logic.'
  echo '- Clarify/Storage - persisted settings and in-memory explanation history.'
  echo '- Clarify/Utilities - constants and cross-cutting helpers.'
  echo '- Clarify/Views - SwiftUI screens for overlay and settings.'
  echo '- Clarify/Views/Components - reusable UI components.'
  echo '- Clarify/Resources - entitlements and asset metadata.'
  echo '- ClarifyTests - XCTest coverage for core behaviors.'
  echo '- docs/context - living architecture, map, data, decisions, and status docs.'
  echo '- scripts - project automation scripts for developer workflows.'
  echo '- .githooks - local git hook scripts used in this repository.'
  echo
  echo "## Files"

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    echo "- $path - $(describe_file "$path")"
  done < <(cd "$ROOT_DIR" && rg --files Clarify ClarifyTests Clarify.xcodeproj docs/context scripts .githooks run.sh | sort)
} > "$MAP_FILE"

echo "Context docs updated: $DOCS_DIR"
