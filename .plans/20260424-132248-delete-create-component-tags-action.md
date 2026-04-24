# Update courses after `create-component-tags` deletion

## Context

The `create-component-tags` action has been deleted from `actions/` and removed from `actions/README.md` (2026-04-24). The `v1` git tag still resolves to the historical commit, so student workflows referencing `optivem/actions/create-component-tags@v1` continue to work — but the course teaching narrative is now out of date.

## Remaining work

1. Rewrite the course lessons that teach `create-component-tags` to match the current signal model: component deliverables are Docker images tagged in GHCR (no separate component git tag); system release events are signalled by git tags. The "component-level git tag" concept disappears from the teaching narrative.
   - `courses/01-pipeline/accelerator/course/05-production-stage/03-release-version-tag.md`
   - `courses/01-pipeline/accelerator/course/05-production-stage/04-multi-component.md`
   - `courses/01-pipeline/accelerator/course/08-architecture-reference/04-component-patterns.md`
2. Update the course summary + architecture reference accordingly (`courses/plans/20260422-113736-01-pipeline-accelerator-summary.md`).
