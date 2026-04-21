# Production release policy — 2026-04-20 13:32 UTC

## Items

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
