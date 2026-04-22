# Consolidate into mainstream Marketplace actions — 2026-04-22 07:36 UTC

Targeted plan (not a full `actions-auditor` run). Scope is the **deletion** of five custom actions whose behavior is covered by well-maintained Marketplace actions, in the same spirit as the docker primitives removal (`.plans/20260422-072347-migrate-docker-primitives.md`). Applying the Mainstream-first principle (see `actions/.claude/agents/docs/devops-rubric.md` top-of-file) and the §1.6 precedent: when an ecosystem-standard action covers the behavior, the custom wrapper is a private dialect that buys nothing.

| Custom action | Replacement | Reason |
|---|---|---|
| `setup-dotnet` | `actions/setup-dotnet@v5` (direct) | 1:1 pass-through; zero added logic |
| `setup-java-gradle` | `actions/setup-java@v5` + `gradle/actions/setup-gradle@v5` (inlined) | Two-step composite with hardcoded `distribution: temurin` and unused `working-directory` input; inlining restores per-caller customisation |
| `setup-node` | `actions/setup-node@v5` + `npm ci` step (inlined) | Conflates "setup" with "build" (`npm ci`); inlining separates the two visible steps |
| `create-github-release` | `softprops/action-gh-release@v2` | Marketplace standard for idempotent create-or-update release records; covers all current inputs |
| `deploy-to-cloud-run` | `google-github-actions/deploy-cloudrun@v2` + existing `wait-for-endpoints@v1` step | Google's official action maps 1:1 to current inputs; step-summary and readiness-poll separable |

**Companions kept** (do not confuse with deletions): `compose-release-notes`, `publish-tag`, `create-component-tags`, `cleanup-github-prereleases`, `compose-release-version`, `compose-prerelease-version`, `compose-prerelease-status`, `wait-for-endpoints` — these encode org-specific conventions (non-SemVer tag scheme, component-tag composition, retention policy, JSON-array URL polling) with no mainstream equivalent. Full rationale in the consolidation audit (2026-04-22).

## Consumer audit — 2026-04-22 07:36 UTC

Greps against **live on-disk** directories only (`shop/`, `actions/`, `optivem-testing/`, `gh-optivem/`). Course content under `courses/` and scaffold outputs under `.tmp/course-tester-*` are out of scope per user direction (2026-04-22) and are not counted.

| Custom action | Live consumers |
|---|---|
| `setup-dotnet` | 8 (all in `shop/.github/workflows/`) |
| `setup-java-gradle` | 8 (all in `shop/.github/workflows/`) |
| `setup-node` | 9 (all in `shop/.github/workflows/`) |
| `create-github-release` | 12 (all in `shop/.github/workflows/`, `*-prod-stage*.yml`) |
| `deploy-to-cloud-run` | 18 (all in `shop/.github/workflows/`, `*-cloud.yml`) |

No live consumers in `actions/` (internal cross-references), `optivem-testing/`, or `gh-optivem/`.

## Coexistence with other plans

- `.plans/20260422-072347-migrate-docker-primitives.md` — also cuts a new `@v1` tag. Coordinate: land both plans before the single tag cut (item 8 below **supersedes** the tag cut in the docker plan — execute whichever comes last).
- `.plans/20260422-055006-audit-actions.md` (10 open items) and `.plans/20260422-045423-audit-actions.md` (2 open items) — unrelated; no overlap.

## Items

- [ ] **Cut a new `optivem/actions@v1` tag** — after items 1-7 land (and after the docker-primitives plan's equivalent tag cut if it has not already fired), force-update the `@v1` tag on `optivem/actions` so the next downstream consumer run pulls a tree that no longer contains the five deleted actions. Per the repo's moving-major-tag convention, this is a `gh release edit v1 --target <new-sha>` style operation (or `git tag -f v1 && git push --force origin v1` if no GitHub Release is attached to the major tag). Verify afterwards with `gh api repos/optivem/actions/git/refs/tags/v1` that the tag points at the post-deletion SHA. If the docker plan's tag cut has already fired and this plan's deletions land after, a second tag move is required — coordinate at execution time to batch into one move.
  - Affects: `optivem/actions` tag `v1`
  - Consumers to update: none (consumers re-resolve `@v1` automatically on their next run)
  - Category: release

Per project convention, items are removed from this file as they are executed, the file is deleted when empty, and the `.plans/` directory is deleted when it contains no files.
