# Idea: Symmetric rename for validate-tag-exists / validate-version-unreleased

**Status:** parked as a possible future idea. Not scheduled. No execution until explicitly greenlit.

**Captured:** 2026-04-23.

## Context

During a review of this repo, the pair `validate-tag-exists` and `validate-version-unreleased` came up as semantically inverse but inconsistently designed. The README already labels them inverses ("Inverse of `validate-version-unreleased`" at [README.md:721](../README.md#L721)), but the naming and mechanics diverge in ways that hurt discoverability and reuse. This note captures the asymmetry, the refactor options, and the reasoning for parking it — so whoever picks it up next has the tradeoffs already worked out.

## Current state

| Dimension | [validate-tag-exists](../validate-tag-exists/action.yml) | [validate-version-unreleased](../validate-version-unreleased/action.yml) |
|---|---|---|
| Asserts | tag **DOES** exist | tag does **NOT** exist |
| Tag input name | `tag` | `version` |
| Implementation | remote (`git ls-remote --tags`) | local (`git tag -l` after `git fetch --tags`) |
| Cross-repo capable | yes (`repository`, `token`, `git-host`) | no |
| Skip option | none | `on-already-released: fail\|skip` |
| Output | none | `already-released` (only when `on-...=skip`) |
| Error message tone | generic | release-domain ("Bump the VERSION file…") |

**Caller footprint** (enumerated from workspace scan on 2026-04-23):
- `validate-tag-exists`: ~27 call sites across `shop` (multitier/monolith × ts/java/dotnet × qa/prod/signoff), `gh-optivem` (1 cross-repo use in `gh-acceptance-stage.yml:171` against `optivem/shop`), and 3 lesson files under `courses/01-pipeline/accelerator/course/`.
- `validate-version-unreleased`: ~10 call sites in `shop` (6 acceptance-stage + prod-stage variants), `shop/_prerelease-pipeline.yml:75`, `gh-optivem/.github/workflows/gh-release-stage.yml:76`. Of those, 6 acceptance-stage workflows read `steps.ensure-unreleased.outputs.already-released` and forward it to a downstream skip gate.

## Why it matters (a little)
- A developer searching for "how do I assert a tag is absent?" won't find `validate-version-unreleased` by name.
- Only 3 `validate-*` actions exist today — this pair will anchor the convention for the next ones. Fixing the inconsistency later is more expensive.
- `validate-version-unreleased` already does a network round trip (`git fetch --tags`), so switching to `git ls-remote` would be free in cost and gain cross-repo capability.

## Why it doesn't matter (a lot)
- Everything works. No bug, no page.
- Domain-flavored call sites (`on-already-released: skip`) read more naturally than generic (`on-found: skip`) in release workflows.
- Even after "symmetry," outputs stay inverse (`missing` vs `found`), because the assertions are inverse. Full symmetry is aesthetic, not structural.
- The churn (up to ~37 caller updates across multiple repos, plus lesson examples) is non-trivial for a cosmetic cleanup.

## Options, in increasing scope

### Option A — Defer (status quo)
Leave as-is. Revisit only when the release pipeline is already being refactored, when a 4th+ `validate-*` action is added, or when someone hits the missing feature (cross-repo "not exists" check).

### Option B — Document-only
Zero code churn. Add a README note explaining the pair is intentionally asymmetric: one is a generic remote tag assertion (used at many gates, including cross-repo), the other is a release-pipeline-specific gate with skip semantics for the acceptance-stage race window. Tighten `validate-tag-exists` grep match for robustness (minor fix unrelated to the rename).

### Option C — Name-only rename (middle ground)
- Rename directory: `validate-version-unreleased` → `validate-tag-not-exists`.
- Rename input: `version` → `tag`.
- Keep everything else: local implementation, `on-already-released`, `already-released` output, domain-flavored error message.
- Caller churn: ~10 call sites (action path + input name). Output references unchanged.

### Option D — Full symmetry refactor
- Everything from C, plus:
  - Make `validate-tag-not-exists` remote-capable: add `repository`, `token`, `git-host` inputs.
  - Switch implementation from `git tag -l` (local) to `git ls-remote --tags` (remote). Same cost as today's `git fetch` + local check.
  - Generalize option names: `validate-tag-exists` gains `on-missing: fail|skip`; `validate-tag-not-exists` uses `on-found: fail|skip` (replacing `on-already-released`).
  - Rename outputs: `validate-tag-exists` outputs `missing`; `validate-tag-not-exists` outputs `found` (replacing `already-released`).
  - Tighten match strictness on both (`git ls-remote` with explicit refspec is already exact; just confirm grep pattern doesn't substring-match).
- Caller churn: ~37 call sites (action path + input rename on 10; output ref rename on 6 acceptance-stage; no changes needed on the 27 `validate-tag-exists` callers unless they want `on-missing`).
- Plus: [README.md](../README.md) regeneration via the `actions-readme-updater` subagent; 3 lesson files under `courses/01-pipeline/accelerator/course/` need updating (`04-qa-stage/01`, `04-qa-stage/04`, `05-production-stage/01`).

## Recommendation

**Option A (defer) for now, Option C (name-only) if/when triggered.**

- The asymmetry is real but low-cost in practice. Deferring is the honest call.
- If a trigger fires — a 4th `validate-*` action is proposed, or the release pipeline is being touched for another reason — upgrade to Option C. It fixes the worst inconsistency (discoverability: the "not-exists" action is findable by name) without forcing 6 acceptance-stage workflows to re-learn an output they already use correctly.
- Option D is "correct" design but the return on the churn is low. Reserve it for if/when cross-repo "not-exists" checks are genuinely needed (e.g., some gh-optivem-style workflow wants to assert a tag is absent on a sibling repo).

## Triggers to revisit

Revisit this note if any of these become true:
- A 4th `validate-*` action is proposed — time to lock in the naming/input conventions before they proliferate.
- A caller needs cross-repo "tag does not exist" (currently not a use case, but would push toward Option D).
- The release pipeline (prerelease → acceptance → qa → prod) is being restructured for some other reason — bundle this in.
- The `actions` repo publishes a v2 with a migration guide anyway — piggyback.

## If Option C or D is chosen later, execution outline

1. Refactor [validate-version-unreleased/action.yml](../validate-version-unreleased/action.yml) → new path `validate-tag-not-exists/action.yml`. Update `name:`, `description:`, inputs per the option picked.
2. (D only) Extend [validate-tag-exists/action.yml](../validate-tag-exists/action.yml) with `on-missing` input + `missing` output; tighten grep match.
3. Regenerate [README.md](../README.md) via the `actions-readme-updater` subagent.
4. Update callers in this order (push actions repo first, then callers within same session to minimize the window where `@v1` is out-of-sync):
   - `shop/.github/workflows/_prerelease-pipeline.yml`
   - `shop/.github/workflows/multitier-{typescript,java,dotnet}-{acceptance,prod,prod-cloud}-stage.yml`
   - `shop/.github/workflows/monolith-{typescript,java,dotnet}-acceptance-stage.yml`
   - `gh-optivem/.github/workflows/gh-release-stage.yml`
5. Update 3 lesson files under `courses/01-pipeline/accelerator/course/`: `04-qa-stage/01-deploy-to-qa.md`, `04-qa-stage/04-qa-signoff.md`, `05-production-stage/01-validate-qa-signoff.md`.
6. Verification: trigger one full release pipeline end-to-end against a non-prod target (sandbox/test repo) and one acceptance-stage run that exercises the skip path (where the RC tag already exists). Watch for: (a) actions resolve, (b) skip-path output still feeds the run-gate correctly, (c) course lesson examples match reality.
7. Coordination: if `@main` vs `@v1` pinning matters, confirm which ref the callers pin before the cutover; if `@v1`, a v2 tag on the actions repo decouples the rollout.

## Critical files (if executing)
- [validate-tag-exists/action.yml](../validate-tag-exists/action.yml)
- [validate-version-unreleased/action.yml](../validate-version-unreleased/action.yml)
- [README.md](../README.md) (index table at lines 65–67, detailed sections at 719–748)
- `shop/.github/workflows/*.yml` (~9 callers)
- `gh-optivem/.github/workflows/gh-release-stage.yml`
- `courses/01-pipeline/accelerator/course/{04-qa-stage,05-production-stage}/*.md`
