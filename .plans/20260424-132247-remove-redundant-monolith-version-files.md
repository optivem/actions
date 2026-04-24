# Remove redundant monolith VERSION files

> 🤖 **Picked up by agent** — `ValentinaLaptop` at `2026-04-24T11:27:56Z`

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
