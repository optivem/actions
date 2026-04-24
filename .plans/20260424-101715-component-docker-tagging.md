# Component Docker Tagging in Production Stage

🤖 **Picked up by agent** — `ValentinaLaptop` at `2026-04-24T09:09:31Z`

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

# Follow-up: bump-patch-versions migration (deferred project)

## Why this is deferred

Per-component git tag patterns are load-bearing in three places:

1. **`bump-patch-versions` action** — reads per-component git tags to decide if a VERSION file needs auto-bumping. See [actions/bump-patch-versions/action.yml:6](../bump-patch-versions/action.yml#L6) and its usage in [shop/.github/workflows/bump-versions.yml:26-29](../../shop/.github/workflows/bump-versions.yml#L26-L29) and [auto-bump-patch.yml:36-39](../../shop/.github/workflows/auto-bump-patch.yml#L36-L39).
2. **`_meta-prerelease-pipeline.yml` version-check** ([lines 109-143](../../shop/.github/workflows/_meta-prerelease-pipeline.yml#L109-L143)) — uses the same tag-probing logic as a "don't double-release" guard.
3. **`check-tag-exists` in acceptance stages** — e.g., [monolith-java-acceptance-stage.yml:71](../../shop/.github/workflows/monolith-java-acceptance-stage.yml#L71) uses `monolith-java-v{version}` (system-level tag, not component-level — but same mechanism).

The component-level tags (`multitier-backend-java-v*`, `multitier-frontend-react-v*`, `monolith-system-java-v*`) are the ones created by `create-component-tags`. Removing the action would silently break the bump mechanism because the system-level tags (`multitier-java-v*`, `meta-v*`) use a *different* version number than the component VERSION files, so they can't substitute.

## What needs discussion

Before `create-component-tags` can be safely removed, the bump mechanism needs to read component release information from somewhere other than git tags. Open questions:

1. **Where should the "this component version has been released" signal live?**
   - Option B: Docker registry — query GHCR / Docker Hub for tags like `multitier-backend-java:v1.5.24`. Requires cross-registry API logic in `bump-patch-versions`; auth per registry; pagination; rate limits.
   - Option C: Release-ledger file — commit a `.releases.json` (or similar) at release time listing each released component version. `bump-patch-versions` reads the ledger. Simpler but introduces a new file-format and race conditions around concurrent releases.
   - Option X: Use GitHub Releases API with component-scoped release names (not supported today — GitHub Releases are system-level).
   - Option Y: Keep a small, purpose-scoped git tag (e.g. `released/{component}/{version}`) as a lightweight marker, distinct from the user-facing `{component}-v{version}` tag. Weakens the "never source-code tags" rule but with narrower scope.

2. **How to migrate existing component git tags?**
   - Leave them in place (historical) and populate the new signal going forward? Or backfill?
   - If leave-in-place: need a cutover date — before that date, bump reads old git tags; after, new signal.

3. **Impact on `_meta-prerelease-pipeline.yml` and the acceptance-stage `check-tag-exists` callers** — same mechanism, needs coherent migration.

4. **Cost / effort estimate** — Option B is probably ~2–3 days of action work + registry-API testing. Option C is smaller (~1 day) but introduces a new artifact type. Worth evaluating side-by-side before committing.

## Trigger for the follow-up project

When ready to resume:
1. Open a new plan file: `20260XXX-XXXXXX-bump-patch-versions-migration.md`.
2. Pick an approach (B / C / X / Y).
3. Sequence: build the new signal mechanism → migrate `bump-patch-versions` → migrate `_meta-prerelease-pipeline.yml` guard → migrate acceptance-stage `check-tag-exists` callers → remove `create-component-tags` from all prod-stage workflows → delete the action.

Until then: `create-component-tags` continues to be called in every prod-stage workflow, creating per-component git tags in parallel with the new Docker tagging. No regression.
