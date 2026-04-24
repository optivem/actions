# Component Docker Tagging in Production Stage

> **Status (2026-04-24):** Main plan + bump-patch-versions migration follow-up are COMPLETE. Only deferred items remain below.

## Context

Adds component-level Docker tagging to prod-stage workflows in `shop/`. The existing `create-component-tags` step stays in place (it's load-bearing for the patch-version auto-bump mechanism, see Follow-up). Both coexist until the bump mechanism is migrated in a separate project.

## Design decisions (captured for reference)

- **Three-step flow** in prod stage: read VERSION files → compose tags → apply tags to Docker images.
- **Generic, keyed dictionary** passed through all three steps. Keys are opaque until the final action re-interprets them as Docker image URLs.
- **Asymmetric input naming** in `tag-docker-images`: `tag` (broadcast single string) vs `image-tags` (per-image JSON array of `{key, tag}` objects). Mutually exclusive; fail fast if both or neither set.
- **JSON array of objects** for structured inputs (no delimiter-parsing, no positional-array ordering risk).
- **Template default** `v{version}` — matches repo-wide convention for release tags.
- **Scope: production stage only** — acceptance stage keeps uniform system RC tagging as-is.
- **Field name `key`** (not `image` / `source-image-url`) in `tag-docker-images` map mode — chains directly with `compose-tags` output without per-workflow rename boilerplate.

## Verification (user to complete)

- Pilot prod-stage run should produce Docker tags like `multitier-backend-java:v1.5.24` visible in the registry.
- Existing broadcast-mode callers of `tag-docker-images` still work unchanged (sample regression check: `monolith-java-acceptance-stage.yml` at line 266–273).
- No git-tag changes expected from this plan — `create-component-tags` still runs in each prod-stage workflow; historical tags untouched.

## Out of scope (for this plan)

- Deletion of `create-component-tags` action
- Rework of `bump-patch-versions`
- Changes to acceptance-stage tagging
- Changes to commit-stage tagging (already component-level via per-component workflows)
- Changes to course docs about release-version-tag / multi-component / component-patterns

---

# ✅ Completed: bump-patch-versions migration (Option B — GitOps / Docker registry as source of truth)

Decided 2026-04-24. Picked Option B (Docker registry) over C/X/Y for Farley-aligned artifact-is-source-of-truth semantics. One signal per VERSION file: components + monoliths → GHCR image probe, meta → GitHub Release probe.

Delivered:
- New primitive `check-ghcr-image-tag-exists` (OCI manifest probe).
- New primitive `check-github-release-exists` (GitHub Releases API probe).
- Rewrote `bump-patch-versions` to JSON-array input with `signal: github-release | ghcr-image` discriminator.
- Migrated callers: `auto-bump-patch.yml`, `bump-versions.yml`, `gh-auto-bump-patch.yml`.
- Migrated `_meta-prerelease-pipeline.yml` don't-double-release guard.
- Migrated 6 acceptance-stage `check-tag-exists` callers → `check-github-release-exists`.
- Removed `create-component-tags` step from all 12 prod-stage workflows.
- System/Component step name clarity pass across prod + acceptance + meta-prerelease.

Fixed en route: GHCR Accept-header bug — multiple `-H "Accept: ..."` headers were not being combined correctly, causing multi-arch image probes to 404. Switched to single comma-separated Accept header with OCI image index MIME type.

Discovered but out-of-scope: remaining `check-tag-exists@v1` + `validate-tag-exists@v1` callers in prod-stage, qa-stage, qa-signoff, and `_prerelease-pipeline.yml`. Captured in a separate plan: `20260424-105713-system-release-signal-migration.md`.

---

# Deferred: Remove redundant monolith VERSION files

## Decision (2026-04-24)

Monolith systems are single-container (system == component == one Docker image). They never release independently of meta; their version is always the meta version. The per-monolith VERSION files duplicate the top-level `VERSION` and are dead weight.

Files to delete:
- `shop/system/monolith/dotnet/VERSION`
- `shop/system/monolith/java/VERSION`
- `shop/system/monolith/typescript/VERSION`

## What to do

1. Delete the three monolith VERSION files.
2. Update every workflow that reads those files to use top-level `VERSION` instead. Known readers:
   - `shop/.github/workflows/bump-versions.yml` — VERSION-file mapping entry
   - `shop/.github/workflows/auto-bump-patch.yml` — VERSION-file mapping entry
   - `shop/.github/workflows/_meta-prerelease-pipeline.yml` — guard mapping (lines 117-126)
   - `shop/.github/workflows/monolith-{dotnet,java,typescript}-prod-stage.yml` — each reads `system/monolith/{lang}/VERSION` via `read-base-versions` when composing the monolith system release tag
   - Any monolith prerelease / commit-stage workflow that composes a version from the file
3. Update `read-base-versions` calls in monolith prod-stages to read top-level `VERSION`.
4. Regression test: run each monolith prod-stage end-to-end; confirm tag + image versions still come out correct.

## Why deferred

Touches ~6–8 workflow files beyond the bump-patch-versions migration. Tangential to the GHCR-signal swap — keeping it out of scope preserves a focused pilot for the GitOps migration. Should happen after the Option B migration is complete and stable.

## Trigger

After Step 2c of the bump-patch-versions migration is verified in production.

---

# Deferred: Delete `create-component-tags` action

## Why deferred

After Step 5 removes the `create-component-tags` step from all 12 prod-stage workflows, the action becomes unused by live code. BUT three course-accelerator files teach `create-component-tags` as working example code:

- `courses/01-pipeline/accelerator/course/05-production-stage/03-release-version-tag.md`
- `courses/01-pipeline/accelerator/course/05-production-stage/04-multi-component.md`
- `courses/01-pipeline/accelerator/course/08-architecture-reference/04-component-patterns.md`

Plus mentions in `courses/plans/20260422-113736-01-pipeline-accelerator-summary.md`.

Deleting the action would cause students following the course to hit `optivem/actions/create-component-tags@v1 not found`. The original "component Docker tagging" plan explicitly carved course-doc changes as out-of-scope; that exclusion stands here.

## What needs to happen first

1. Rewrite the three course lessons to teach the GitOps-Farley-aligned flow: component artifacts = Docker images in GHCR, system artifacts = GitHub Releases. The "component-level git tag" concept disappears from the teaching narrative.
2. Update the course summary + architecture reference accordingly.
3. Remove `create-component-tags` from `actions/README.md`.
4. Delete the action.

## Trigger

When course content is ready to be updated to match the new signal model.
