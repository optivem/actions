# Consolidate into mainstream Marketplace actions — 2026-04-22 07:36 UTC

Targeted plan (not a full `actions-auditor` run). Scope is the **deletion** of five custom actions whose behavior is covered by well-maintained Marketplace actions, in the same spirit as the docker primitives removal (`.plans/20260422-072347-migrate-docker-primitives.md`). Applying the Mainstream-first principle (see `actions/.claude/agents/docs/devops-rubric.md` top-of-file) and the §1.6 precedent: when an ecosystem-standard action covers the behavior, the custom wrapper is a private dialect that buys nothing.

| Custom action | Replacement | Reason |
|---|---|---|
| `setup-dotnet` | `actions/setup-dotnet@v5` (direct) | 1:1 pass-through; zero added logic |
| `setup-java-gradle` | `actions/setup-java@v5` + `gradle/actions/setup-gradle@v5` (inlined) | Two-step composite with hardcoded `distribution: temurin` and unused `working-directory` input; inlining restores per-caller customisation |
| `setup-node` | `actions/setup-node@v5` + `npm ci` step (inlined) | Conflates "setup" with "build" (`npm ci`); inlining separates the two visible steps |
| `create-github-release` | `softprops/action-gh-release@v2` | Marketplace standard for idempotent create-or-update release records; covers all current inputs |
| `deploy-to-cloud-run` | `google-github-actions/deploy-cloudrun@v2` + existing `wait-for-urls@v1` step | Google's official action maps 1:1 to current inputs; step-summary and readiness-poll separable |

**Companions kept** (do not confuse with deletions): `compose-release-notes`, `publish-tag`, `create-component-tags`, `cleanup-github-prereleases`, `compose-release-version`, `compose-prerelease-version`, `compose-prerelease-status`, `wait-for-urls` — these encode org-specific conventions (non-SemVer tag scheme, component-tag composition, retention policy, JSON-array URL polling) with no mainstream equivalent. Full rationale in the consolidation audit (2026-04-22).

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

- [ ] **Migrate `deploy-to-cloud-run` consumers and delete the action** — in each consumer workflow, replace the single `uses: optivem/actions/deploy-to-cloud-run@v1` step with two steps:
  1. `uses: google-github-actions/deploy-cloudrun@v2` with input mapping:
     - `service-name` → `service`
     - `image-url` → `image`
     - `region` → `region`
     - `project-id` → `project_id`
     - `env-vars` → `env_vars` (same newline-delimited `KEY=VALUE` shape)
     - `secrets` → `secrets` (same newline-delimited `KEY=SECRET:VERSION` shape)
     - `memory`, `cpu`, `min-instances` (→ `min_instances`), `max-instances` (→ `max_instances`), `port` → pass via the `flags` input or the action's native params (verify against v2 schema at migration time; prefer native params where available)
     - `allow-unauthenticated` → `flags: --allow-unauthenticated` when `true`
     - Output: `service-url` → consume `steps.<id>.outputs.url`
  2. The existing `uses: optivem/actions/wait-for-urls@v1` step that was previously embedded in `deploy-to-cloud-run` — lift it up into the caller workflow, gated on the former `wait-for-ready` input.
  - Port the step-summary table block (currently inside `deploy-to-cloud-run/action.yml` lines 147-158) into a small inline step in the calling workflow, or drop it if the Marketplace action's default logging is sufficient. Recommend: drop — the Marketplace action already surfaces the deployed URL in its own summary.
  - Then delete `actions/deploy-to-cloud-run/`.
  - Affects: `actions/deploy-to-cloud-run/`
  - Consumers to update (18 in shop, all `*-cloud.yml`):
    - `shop/.github/workflows/monolith-dotnet-acceptance-stage-cloud.yml`
    - `shop/.github/workflows/monolith-dotnet-qa-stage-cloud.yml`
    - `shop/.github/workflows/monolith-dotnet-prod-stage-cloud.yml`
    - `shop/.github/workflows/monolith-java-acceptance-stage-cloud.yml`
    - `shop/.github/workflows/monolith-java-qa-stage-cloud.yml`
    - `shop/.github/workflows/monolith-java-prod-stage-cloud.yml`
    - `shop/.github/workflows/monolith-typescript-acceptance-stage-cloud.yml`
    - `shop/.github/workflows/monolith-typescript-qa-stage-cloud.yml`
    - `shop/.github/workflows/monolith-typescript-prod-stage-cloud.yml`
    - `shop/.github/workflows/multitier-dotnet-acceptance-stage-cloud.yml`
    - `shop/.github/workflows/multitier-dotnet-qa-stage-cloud.yml`
    - `shop/.github/workflows/multitier-dotnet-prod-stage-cloud.yml`
    - `shop/.github/workflows/multitier-java-acceptance-stage-cloud.yml`
    - `shop/.github/workflows/multitier-java-qa-stage-cloud.yml`
    - `shop/.github/workflows/multitier-java-prod-stage-cloud.yml`
    - `shop/.github/workflows/multitier-typescript-acceptance-stage-cloud.yml`
    - `shop/.github/workflows/multitier-typescript-qa-stage-cloud.yml`
    - `shop/.github/workflows/multitier-typescript-prod-stage-cloud.yml`
  - Category: consolidation

- [ ] **Remove README sections for the five deleted actions** — in `actions/README.md`, delete these sections (current line numbers, confirm before editing):
  - `### create-github-release` (line 363)
  - `### deploy-to-cloud-run` (line 398)
  - `### setup-dotnet` (line 647)
  - `### setup-java-gradle` (line 657)
  - `### setup-node` (line 668)
  - Scrub any cross-references in neighbouring action sections' parameter tables and replace with a pointer to the new rubric rule (see item 7) + a one-line mention of the Marketplace replacement for each.
  - Affects: `actions/README.md`
  - Category: docs

- [ ] **Cut a new `optivem/actions@v1` tag** — after items 1-7 land (and after the docker-primitives plan's equivalent tag cut if it has not already fired), force-update the `@v1` tag on `optivem/actions` so the next downstream consumer run pulls a tree that no longer contains the five deleted actions. Per the repo's moving-major-tag convention, this is a `gh release edit v1 --target <new-sha>` style operation (or `git tag -f v1 && git push --force origin v1` if no GitHub Release is attached to the major tag). Verify afterwards with `gh api repos/optivem/actions/git/refs/tags/v1` that the tag points at the post-deletion SHA. If the docker plan's tag cut has already fired and this plan's deletions land after, a second tag move is required — coordinate at execution time to batch into one move.
  - Affects: `optivem/actions` tag `v1`
  - Consumers to update: none (consumers re-resolve `@v1` automatically on their next run)
  - Category: release

Per project convention, items are removed from this file as they are executed, the file is deleted when empty, and the `.plans/` directory is deleted when it contains no files.
