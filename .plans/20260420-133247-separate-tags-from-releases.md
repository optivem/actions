# Separate git tags from GitHub Releases — 2026-04-20 13:32 UTC

## Principle

**Git tag = source of truth. GitHub Release = UX on top.** Every pipeline step that needs to mark a commit creates a tag. Only commits that need a user-facing landing page (release notes, assets, "latest" UI) get a GitHub Release object layered on top.

Current state conflates the two: `create-release` creates *both* the tag and the release object. `promote-to-rc`, `promote-rc-to-qa`, `promote-rc-to-prod`, `approve-rc-in-qa`, `reject-rc-in-qa` all go through it, producing a GitHub Release for every intermediate state. This is what drives 42+ `check-release-exists` call sites, ongoing cleanup debt, and rate-limit pressure.

## Target state

- **Tag-only** (no GitHub Release object): all RC versions, all status markers (`*-qa-deployed`, `*-qa-approved`, `*-qa-rejected`, `*-prod-deployed`), and by default all final releases too.
- **Tag + GitHub Release**: only where a user-facing landing page is wanted — e.g. a named stable release we want to publish notes/assets for. Opt-in, not default.
- **`create-and-push-tag`**: the tag primitive (already correct).
- **`create-release`**: the release-object primitive, refactored to wrap an *existing* tag (no longer creates tags implicitly).

## Items

### Phase 1 — primitives

- [ ] **Refactor `create-release` to wrap an existing tag only** — Drop implicit tag creation; require the tag already exists. Fail with a clear error if `gh release create` is called against a missing tag. Update `action.yml` description and inputs accordingly (the `base-version` / `release-version` inputs become `tag` + optional `name` + optional `body` + `is-prerelease`).
  - Affects: `create-release`
  - Consumers to update: downstream in phase 2 (all current callers go via `promote-*` / `approve-*` / `reject-*` actions)
  - Category: refactor

- [ ] **Add `check-tag-exists` action** — New primitive: takes `tag` (and optional `repo`), returns success if the tag exists in git, error with a clear message otherwise. Uses `git ls-remote --tags` or `gh api repos/.../git/refs/tags/{tag}`. Replaces the role `check-release-exists` plays in gating QA/prod steps.
  - Affects: new `check-tag-exists` directory
  - Consumers to update: phase 3 updates 42 call sites
  - Category: new

### Phase 2 — RC + status-marker actions go tag-only

- [ ] **Refactor `promote-to-rc` to tag-only** — Drop the `create-release` step; keep `generate-prerelease-version` and `tag-docker-images`; add `create-and-push-tag` at the end to publish the RC tag. Remove `is-prerelease: true` release creation entirely. Outputs (`version`, `image-urls`) stay the same.
  - Affects: `promote-to-rc`
  - Consumers to update: 0 (acceptance-stage workflows already read `version` output from `promote-to-rc`, not from the release object)
  - Category: refactor

- [ ] **Refactor `promote-rc-to-qa` to tag-only** — Replace its `create-release` call with `create-and-push-tag` to produce `{prefix}-v{version}-rc.N-qa-deployed` as a plain tag.
  - Affects: `promote-rc-to-qa`
  - Consumers to update: 12 shop QA-stage call sites (no input changes — action surface stable)
  - Category: refactor

- [ ] **Refactor `approve-rc-in-qa` to tag-only** — Replace `create-release` with `create-and-push-tag` for `{prefix}-v{version}-rc.N-qa-approved`.
  - Affects: `approve-rc-in-qa`
  - Consumers to update: 6 shop signoff call sites (no input changes)
  - Category: refactor

- [ ] **Refactor `reject-rc-in-qa` to tag-only** — Replace `create-release` with `create-and-push-tag` for `{prefix}-v{version}-rc.N-qa-rejected`.
  - Affects: `reject-rc-in-qa`
  - Consumers to update: 6 shop signoff call sites (no input changes)
  - Category: refactor

- [ ] **Refactor `promote-rc-to-prod` to tag-only for the deployed marker** — `{prefix}-v{version}-rc.N-prod-deployed` becomes a plain tag. Final-version release (see phase 4) is a separate concern.
  - Affects: `promote-rc-to-prod`
  - Consumers to update: 12 shop prod-stage call sites (no input changes)
  - Category: refactor

### Phase 3 — replace release-based lookups with tag-based lookups

- [ ] **Replace `find-release-by-run` with tag-based lookup** — Currently scans GitHub Release bodies for the run ID (via GraphQL). In tag-only world there are no release bodies to scan. Replacement: the acceptance-stage job already outputs `version` from `promote-to-rc`; expose that as a workflow output so `_prerelease-pipeline.yml` can read it via `trigger-and-wait`'s run-id. If `trigger-and-wait` cannot surface triggered-workflow outputs, fall back to a new `find-tag-by-run` action that queries tags whose tagger-date / tagger-message references the run ID (or that point to a SHA reachable from the run's commit).
  - Affects: `find-release-by-run` (delete or rename), possibly new `find-tag-by-run`, possibly `trigger-and-wait`
  - Consumers to update: 1 call site in `_prerelease-pipeline.yml:178-180`
  - Category: refactor

- [ ] **Replace all `check-release-exists` call sites with `check-tag-exists`** — 42 occurrences across shop workflows (12 QA-stage + 24 prod-stage + 6 QA-signoff). Each call currently validates a GitHub Release object; should instead validate a git tag.
  - Affects: 12 workflows in `shop/.github/workflows/`
  - Consumers to update: 42 workflow steps
  - Category: callsite-update

- [ ] **Delete `check-release-exists` action** — Once all 42 call sites are migrated to `check-tag-exists`, remove the directory.
  - Affects: `check-release-exists`
  - Consumers to update: 0 (after previous item)
  - Category: delete

### Phase 4 — production release policy

- [ ] **Decide production-release policy** — For final production releases (e.g. `meta-v1.0.0`, `monolith-java-v1.0.0`), should we:
  - (a) tag-only by default, add GitHub Release opt-in via a separate manual step when release notes matter, OR
  - (b) always tag + release (keep current production behaviour, separation applies to RCs/status only)?
  - **Recommended: (a)** — matches the principle; production releases are rare, and a separate "publish release notes" step is low-overhead and keeps the pipeline uniform. Release-object creation becomes a deliberate editorial act, not an automatic byproduct.
  - Affects: `meta-release-stage.yml`, `*-prod-stage.yml`, `*-prod-stage-cloud.yml`
  - Consumers to update: TBD based on decision
  - Category: decision

- [ ] **Apply production-release policy** — Execute whichever decision the previous item yields. If (a): strip `create-release` from the prod-stage flow; add an optional `publish-release` workflow that takes an existing tag and creates the GitHub Release object on demand. If (b): leave prod flow alone.
  - Affects: `meta-release-stage.yml`, `*-prod-stage*.yml`, possibly new `publish-release.yml`
  - Consumers to update: depends on decision
  - Category: callsite-update

### Phase 5 — retire cleanup paths that no longer apply

- [ ] **Retool or retire `cleanup-prereleases`** — Currently deletes GitHub Release objects (+ their tags) older than N days. Once RCs are tag-only, there are no prerelease GitHub Releases to clean. Options:
  - (a) Delete the action entirely — orphan tag cleanup is not needed if tags are cheap and version queries filter by prefix+SHA reachability.
  - (b) Retool as `cleanup-rc-tags` — deletes RC/status-marker tags (`*-rc.*`, `*-qa-deployed`, `*-qa-approved`, `*-qa-rejected`, `*-prod-deployed`) older than N days.
  - **Recommended: (b)** — tags do accumulate visibly in `git tag -l` output and in the GitHub UI tags view; bounded cleanup keeps noise down without touching release objects.
  - Affects: `cleanup-prereleases` (rename to `cleanup-rc-tags`), `shop/.github/workflows/cleanup.yml`
  - Consumers to update: 1 call site in `cleanup.yml`
  - Category: refactor

### Phase 6 — verification

- [ ] **Run a full meta-prerelease-stage end-to-end after phase 3 merges** — Confirm the pipeline produces RC tags only (no prerelease GitHub Releases), QA/prod gates pass on tags, status markers are tags, and downstream meta-release still resolves RCs correctly from tags.
  - Affects: runtime verification only
  - Consumers to update: 0
  - Category: verification
