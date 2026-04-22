# Actions repo — Claude Code conventions

## Agent plan files

Agents in `.claude/agents/` write plan/report files to `.plans/<YYYYMMDD-HHMMSS>-<suffix>.md`.

- **Filename suffix is agent-specific**, to prevent collisions between parallel runs:
  - `actions-auditor` → `*-audit-actions.md`
  - `actions-auditor-reviewer` → `*-review-actions-auditor.md`
  - `actions-auditor-consistency` → `*-audit-auditor-reviewer-consistency.md`
- **Timestamp source.** All agents use `date -u +%Y%m%d-%H%M%S` for the UTC prefix.
- **Lifecycle.** Items are removed from the plan file as they are executed, the file is deleted when empty, and the `.plans/` directory is deleted when it contains no files.
- **Do not silently clobber.** Before writing, check `.plans/` for an existing file with the same suffix. If one exists with open unchecked items, do NOT overwrite — write to a new distinct timestamp and surface the coexistence to the author.
