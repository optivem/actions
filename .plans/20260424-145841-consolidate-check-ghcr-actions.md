# Consolidate `check-ghcr-*-exist` actions — 2026-04-24 14:58 UTC

## Context

Two near-duplicate actions exist today:

- `check-ghcr-packages-exist` — 18 callers (acceptance-stage preflight gates, shared tag, any-of boolean, soft-fail on auth)
- `check-ghcr-image-tag-exists` — 1 caller (`_meta-prerelease-pipeline.yml`, per-image tags, keyed per-line results, hard-fail on auth)

Both share ~60 lines of identical OCI token-exchange + manifest-probe bash. The only real differences are **input shape** (newline list vs JSON array), **output shape** (`exist` scalar vs `results` array + `any-exist`), and **auth-error policy** (warn-and-continue vs fail-loud).

**Decision** (confirmed in conversation):
- Keep the name **`check-ghcr-packages-exist`** — matches GitHub's own UI/API terminology, zero rename for the 18 dominant callers, and semantically correct (the action probes whether *anything* exists at a tag, which is package-level, not image-level).
- Extend that one action to cover the second use case via additive inputs/outputs.
- Delete `check-ghcr-image-tag-exists` after migrating its single caller.

All changes to `check-ghcr-packages-exist` are **additive and backward-compatible** — the 18 existing callers keep working unchanged at `@v1`.

## Plan

- [ ] **1. Extend `check-ghcr-packages-exist/action.yml` with per-line tag support, keyed results output, and configurable auth-error policy.** Matches the union of both actions' capabilities behind one surface.
  - `inputs.image-urls` — keep the name and input format (newline-separated). Update the description to document that each line may be either `ghcr.io/{path}` (uses the `tag` default) OR `ghcr.io/{path}:{tag}` (per-line tag override). Safe: OCI image paths do not contain `:`, so splitting on `:` is unambiguous.
  - `inputs.tag` — keep the default `'latest'`. Becomes the fallback when a line omits its own `:tag`.
  - `inputs.fail-on-error` — **new**, default `'false'` (preserves current soft-fail behavior for the 18 existing callers). When `'true'`, auth failures and unexpected HTTP codes cause `exit 1` instead of warning-and-continue.
  - `outputs.exist` — unchanged (any-of boolean).
  - `outputs.results` — **new**, JSON array of `{"image": string, "tag": string, "exists": boolean}` objects, one entry per input line. Enables keyed consumers without needing per-line caller-supplied `key` strings (the prerelease caller will reconstruct its descriptive strings from `{image, tag}`).
  - Bash changes:
    - Parse optional trailing `:tag` from each line; fall back to `$TAG` input.
    - Build `results` array alongside the existing `any_exist` accumulator.
    - Branch auth/unexpected-HTTP handling on `$FAIL_ON_ERROR`.
  - Affects: `check-ghcr-packages-exist/action.yml`
  - Consumers to update: none (change is additive; all 18 existing callers continue to pass URL-only lines and read only `exist`)
  - Category: refactoring (capability expansion)

- [ ] **2. Migrate `_meta-prerelease-pipeline.yml` from `check-ghcr-image-tag-exists` to the extended `check-ghcr-packages-exist`.**
  - In `shop/.github/workflows/_meta-prerelease-pipeline.yml` step `Probe Component + Monolith Image Tags`:
    - Change `uses: optivem/actions/check-ghcr-image-tag-exists@v1` → `uses: optivem/actions/check-ghcr-packages-exist@v1`
    - Replace the JSON `images:` block with a newline-separated `image-urls:` list where each line is `ghcr.io/{path}:v{version}`.
    - Add `fail-on-error: 'true'` to preserve current hard-fail semantics.
  - In the downstream `Verify System Release + Component Images Not Yet Published` step:
    - Read `steps.probe-images.outputs.results` (now `[{image, tag, exists}]` instead of `[{key, exists}]`).
    - Rebuild the human-readable "(from VERSION)" / "(from system/.../VERSION)" provenance strings client-side using `jq` over `{image, tag}` (5-line lookup table keyed on the image suffix → provenance label).
  - Affects: `shop/.github/workflows/_meta-prerelease-pipeline.yml` (two steps: `probe-images` and `Verify System Release + Component Images Not Yet Published`)
  - Consumers to update: none beyond the file itself (only caller of `check-ghcr-image-tag-exists`)
  - Category: migration

- [ ] **3. Delete `check-ghcr-image-tag-exists/` action directory.** Safe once step 2 lands and the shop workflow references the new action.
  - Affects: `actions/check-ghcr-image-tag-exists/` (entire directory)
  - Consumers to update: none (step 2 removes the last caller)
  - Category: cleanup

- [ ] **4. Delete the orphaned smoke test workflow for the removed action.**
  - Affects: `actions/.github/workflows/test-check-ghcr-image-tag-exists.yml`
  - Consumers to update: none
  - Category: cleanup

- [ ] **5. Extend `actions/.github/workflows/test-check-ghcr-packages-exist.yml` (or create it) with assertions for the new behavior.** Cover: default-tag line, per-line `:tag` override, mixed default+override, `fail-on-error: false` soft-miss, `fail-on-error: true` strict-fail, `results` output shape.
  - Affects: `actions/.github/workflows/test-check-ghcr-packages-exist.yml` (verify whether this file exists — if not, create; if yes, extend)
  - Consumers to update: none
  - Category: tests

- [ ] **6. Regenerate `actions/README.md` via `actions-readme-updater` agent.** Required because an action is being removed *and* the surviving action's inputs/outputs table changes materially. Per the token-usage rule this is a valid agent invocation (structural change, not an input-only edit).
  - Affects: `actions/README.md`
  - Consumers to update: none
  - Category: docs

## Non-goals / out of scope

- **No `@v2` bump.** All changes to `check-ghcr-packages-exist` are additive (new optional input, new additional output, relaxed input description). Existing callers at `@v1` continue to work.
- **No rename of `image-urls` → `images`.** The input name stays even though lines may now carry `:tag` — renaming would break 18 workflows for a cosmetic win.
- **No Helm/SBOM/cosign artifact support.** The action continues to use image-manifest Accept headers. If a future caller needs arbitrary OCI artifact probing, revisit then.
- **No rename of the action itself.** `check-ghcr-packages-exist` is kept for the reasons in the Context section.
