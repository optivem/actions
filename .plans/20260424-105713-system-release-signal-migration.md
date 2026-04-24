# System Release Signal Migration

## Context

Follow-up to `20260424-101715-component-docker-tagging.md` (bump-patch-versions → Option B completed). That project migrated the VERSION-file bump and release-guard paths to artifact-aligned probes. A sweep during Step 5 revealed additional git-tag probe callers that were out of scope at the time but should move to the same model for coherence.

Three groups remain on git-tag probing. This plan handles them.

## Scope A — `check-tag-exists@v1` callers probing system RELEASE tags

Straightforward migration, same pattern as the acceptance-stage work already done in the previous plan. Swap to `check-github-release-exists@v1` + update output reference `.exists` → `.any-exist`.

**Callers (13 files):**

- `shop/.github/workflows/_prerelease-pipeline.yml:76` — probes `{prefix}-v{version}` release tag; fails fast if release exists.
- 12× prod-stage `line 64` — the `Check System Release Already Published` step in each of:
  - `shop/.github/workflows/monolith-{dotnet,java,typescript}-prod-stage.yml` + `-cloud.yml`
  - `shop/.github/workflows/multitier-{dotnet,java,typescript}-prod-stage.yml` + `-cloud.yml`

Each file also uses `steps.check-release-tag.outputs.exists` downstream (in the prod-stage case at `Verify System Release Not Yet Published`). Update to `.any-exist`.

## Scope B — `validate-tag-exists@v1` callers

Split into two subscopes.

### B1 — RC tag validations (probably migratable)

Pattern: `validate-tag-exists` probes `{prefix}-v{version}-rc.{N}` to guard against missing RC input.

**Callers (21+ sites):**

- 6× `*-qa-stage.yml` at `line 45`
- 6× `*-qa-stage-cloud.yml` at `line 53`
- 6× `*-qa-signoff.yml` at `line 36`
- 3× prod-stage non-cloud at `line 46` (Check RC Exists)
- 3× prod-stage cloud at `line 54` (Check RC Exists)

**Open question:** are RC tags published as GitHub Prereleases (`prerelease: true` on `softprops/action-gh-release`)? If yes — direct migration using `check-github-release-exists` / need a strict `validate-github-release-exists` sibling (fail-fast variant). If RCs are plain git tags without Release metadata, the probe has to stay as `git ls-remote` OR the prerelease publishing must first be upgraded to create Releases.

**Action item:** inspect `_prerelease-pipeline.yml` + any RC-tagging step to confirm whether `softprops/action-gh-release` runs with `prerelease: true`.

### B2 — QA-approved marker tag validations (architectural question)

Pattern: `validate-tag-exists` probes `{RC}-qa-approved` marker tag — purely a signoff signal, no artifact.

**Callers (12 sites):**

- 3× prod-stage non-cloud at `line 52` (Check QA Approved)
- 3× prod-stage cloud at `line 60` (Check QA Approved)
- 6× `*-qa-stage.yml` / `*-qa-signoff.yml` (each side of the QA flow)

**Design question:** qa-approved markers have no corresponding artifact. Three directions:

1. **Keep `validate-tag-exists` + git tag markers** — concede the GitOps purity for this specific signal, since it's a signoff not a release. Smallest change, explicit carve-out.
2. **Replace with GitHub Deployment environments** — approve a deployment to a `qa-approved` environment; the check becomes "does a deployment exist for this sha?". Platform-native signal.
3. **Replace with commit status / check-run** — set a custom status `qa/approved` on the RC commit. Probe via Commit Statuses API.

Needs an explicit call. **Recommend Option 1** unless Farley-purity trumps minimal change.

## Scope C — Course alignment

After A + B complete, 3 course files teach now-unused actions:

- `courses/01-pipeline/accelerator/course/05-production-stage/01-validate-qa-signoff.md` (teaches both `validate-tag-exists` and `check-tag-exists`)
- `courses/01-pipeline/accelerator/course/04-qa-stage/04-qa-signoff.md` (teaches `validate-tag-exists`)
- `courses/01-pipeline/accelerator/course/04-qa-stage/01-deploy-to-qa.md` (teaches `validate-tag-exists`)

Plus references in `courses/.claude/agents/reviewers/source-verifier.md`.

Course updates are out of scope for the action migration itself, but must happen before `check-tag-exists` / `validate-tag-exists` can be deleted (parallel to the existing `create-component-tags` course-rewrite blocker).

## Execution sequence

1. **Scope A first.** Mechanical, lowest risk. 13 files, one pattern. Validates the system-release-probe signal once again in CI.
2. **Answer B1's open question.** Inspect RC tagging; decide whether to build `validate-github-release-exists` primitive (fail-fast sibling of `check-github-release-exists`) or keep git-tag probing for RCs.
3. **Decide B2's direction.** Author call — default to Option 1 (keep marker tags) unless GitOps purity matters more than simplicity.
4. **Execute B1 + B2** according to decisions.
5. **Course alignment (Scope C)** — separate focused pass when the course-content refresh happens (same trigger as "Delete `create-component-tags` action").
6. **Delete `check-tag-exists` and `validate-tag-exists` actions** (or keep them if B2 chose Option 1) after all live callers + course content are migrated.

## Blast radius

- Scope A: ~13 files, all in `shop/`. Each ~5-line diff.
- Scope B1: ~21 files, all in `shop/`. Each ~5-line diff.
- Scope B2: ~12 files — blast radius depends on chosen direction.
- Scope C: 3-4 course files + 1 agent-docs file. Larger per-file edits.

## Out of scope

- Removing redundant monolith VERSION files — tracked in the other plan.
- Deleting `create-component-tags` action — tracked in the other plan.
- Any non-tag signal migrations (e.g. docker-tag outputs on deploy-docker-compose, cleanup actions).
