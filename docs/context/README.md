# Context Docs

These files are the project memory pack for fast context reload:

1. `01-system-overview.md`
2. `02-file-folder-map.md`
3. `03-data-model.md`
4. `04-decision-log.md` (append-only)
5. `05-current-state.md`
6. `06-smoke-test-checklist.md`

## Update workflow

1. Make code changes.
2. Run `./scripts/update_context_docs.sh` from `Clarify/`.
3. If architecture/behavior changed, append one entry to `docs/context/04-decision-log.md`.
4. Run `docs/context/06-smoke-test-checklist.md` (automated + manual sections).
5. Refresh `docs/context/05-current-state.md` with what works, what is broken, and next steps.

## Automation

- `./scripts/update_context_docs.sh` regenerates `02-file-folder-map.md` and updates `_Last updated:` timestamps.
- A pre-commit hook at `.githooks/pre-commit` runs the updater and stages `docs/context/*.md` automatically.
- Ensure hooks are enabled once per clone:

```bash
git config core.hooksPath .githooks
```
