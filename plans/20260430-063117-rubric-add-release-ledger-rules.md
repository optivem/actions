# Rubric — codify release-ledger rules motivated by shop's bump-patch-signal switch

Proposal to extend `.claude/agents/docs/devops-rubric.md` with three rules that emerged from the shop pipeline cycle that switched `bump-patch-version`'s release-decision signal from `ghcr-image` to `git-tag`. Read-only proposal — does not edit the rubric here. Items are numbered for stable reference; resolved items should be deleted (do NOT renumber the remainder).

## Provenance

The shop work that motivated these rules:

- shop commit `786033d0` — switched `bump-patch-version` signal to `git-tag`, reordered every prod-stage so the user-visible GitHub Release runs last, added per-component git tags in multitier prod-stages.
- gh-optivem commit `5bee027` — extended `systemPrefixDropReplacements` to collapse 3-segment per-component tag prefixes (`multitier-backend-{lang}-v` → `v`, `multitier-frontend-react-v` → `v`) so scaffolded multitier monorepo / multirepo root / per-component repos drop the prefix correctly.
- shop plan `plans/20260429-231139-bump-patch-signal-from-ghcr-to-git-tag.md` — full design rationale. Item 5 of that plan is the trigger for this proposal.

Three principles distilled from that cycle deserve to be codified in the rubric so future audits flag the same anti-patterns when they reappear in this repo or any other.

## The rules

### Rule (i) — Release-decision probes prefer `git-tag` over `ghcr-image`

> **For release-decision probes (e.g. `bump-patch-versions` signal, "has this version been released?" queries, "what's the latest released version?" lookups), prefer `signal: git-tag` over `signal: ghcr-image`.** Git tags are the authoritative release ledger — every `*-prod-stage.yml` already calls `optivem/actions/publish-tag@v1` and `softprops/action-gh-release@v3` against a tag, so the tag is the upstream truth for "this version was released". GHCR images are a downstream artifact of that release event, not the source of truth.

**Concrete consequences for findings:**

- Flag `signal: ghcr-image` in `bump-patch-versions` (or any successor probe action) as **devops-alignment → release-decision-source** when the same information is available from a git tag the prod-stage already publishes. Propose switching to `signal: git-tag` with the matching tag prefix as the probe value.
- Flag any release-decision query that uses a registry HTTP HEAD probe against an OCI manifest endpoint when `git ls-remote --tags` would answer the same question against the authoritative ledger. Cite `git ls-remote` runs on `contents: read` (already granted) versus the OCI two-step bearer exchange against `ghcr.io/token` with `packages: read`.

**Rationale:**

- **Git is the authoritative release ledger.** Every release event already writes a git tag; the OCI tag is a coincident artifact of the same event but is one layer downstream. Probing the registry adds a hop and couples bump logic to a registry that may be migrated.
- **Smaller auth surface.** `git ls-remote` runs on `contents: read`; the OCI tag-existence probe needs `packages: read` plus the OCI bearer-token dance (`GET ghcr.io/token?service=ghcr.io&scope=repository:...:pull` → `Authorization: Bearer ...`).
- **Registry-independent.** A git-tag signal survives a registry move (GHCR → ECR / GAR / Quay); a registry-image signal hard-codes the registry into bump logic.
- **Removes asymmetry.** Meta-level bumps (`bump-patch-version-meta.yml` in shop) already use `git-tag`. Per-flavor and per-component bumps using `ghcr-image` is inconsistency without justification.

**Source:** Humble & Farley, *Continuous Delivery* ch. 5 (build-once-promote-many — git records the release event, registry holds artifacts that the release event references); §1.3 build-once-promote-many rule already in this rubric.

### Rule (ii) — Per-component artifact tagging applies to git tags as well as docker tags

> **In a multi-component release (one prod-stage producing multiple independently-versioned artifacts — e.g. backend + frontend in a multitier flavor), apply the `<flavor>-<role>-<lang>-v<version>` construction principle to git tags as well as docker tags.** Each independently-versioned component must have a first-class git ref so consumers (bump-patch probes, changelog generators, downstream consumers) can resolve it by name. Flavor-level tags are kept; per-component tags are added alongside them. For a single-component flavor (`flavor == component`) the flavor tag already covers both roles and no additional tag is needed.

**Concrete consequences for findings:**

- Flag any prod-stage that publishes per-component **docker** tags but only a flavor-level **git** tag — the asymmetry leaves bump-patch probes (and any downstream consumer asking "was backend v1.2.3 released?") with no name-addressable answer. Propose adding a per-component `optivem/actions/publish-tag` step that mirrors the per-component docker tagging step, using the same component-version sources (`read-base-versions`).
- The multitier-monorepo case: backend and frontend ship distinct versions that bump on different cadences. The flavor tag (`multitier-{lang}-v<flavor>`) cannot encode both — it is the flavor-level RC marker, not a per-component release marker. Per-component tags (`multitier-backend-{lang}-v<backend>`, `multitier-frontend-react-v<frontend>`) are the only honest answer.
- Per-component tag idempotency: a component git tag is owned by the component's version, not by any flavor's release event. Flavors that ship the same frontend version converge on the same tag; re-publishing must be a no-op (the first publish wins the SHA pointer). The `publish-tag@v1` action must exit cleanly when the target tag already exists.

**Rationale:**

- **Tags are name-addressable; their reason for existing is to be looked up.** Per §3.6 of this rubric, the decision criterion for tag-vs-commit-status is "do downstream workflows need to *find* the thing by name?" — and bump-patch probes do. A per-component release without a per-component tag is a name-addressable concept missing its name.
- **Symmetric to docker tagging.** The multitier prod-stage already emits per-component docker tags; treating git tags as a different, less-granular layer is an inconsistency, not a design.
- **Naming construction is parallel.** The principle "`<flavor>-<role>-<lang>-v<version>`" already governs docker image names in this repo (e.g. `multitier-backend-typescript:v1.0.60`, `multitier-frontend-react:v1.3.47`). Extending it to git tags costs nothing and removes the asymmetry.

**Interaction with §1.5 (Version-handling actions — follow SemVer).** §1.5 already says "Prefixed component-tag variants are explicitly permitted" — names like `monolith-java-v1.0.0-rc.7` are an out-of-band extension for monorepo component-tag namespacing. This rule extends that paragraph to **require** per-component prefixed tags whenever the flavor has multiple independently-versioned components. The SemVer suffix grammar still applies — the segment after the prefix must conform to SemVer §9.

### Rule (iii) — Git tags mirror docker *release* tags, not docker *build* labels

> **Git tags and docker tags are symmetric only at the *release* layers (RC and prod). Commit-stage `-dev` build labels stay docker-only — never accompanied by a git tag.** RC and release stages get parallel docker+git treatment because both layers produce content that downstream stages and external consumers must resolve by name. Commit-stage produces a transient build label whose only consumer is the next pipeline stage; that label is a build artifact, not a release-decision marker, so it does not earn a git ref.

**Concrete consequences for findings:**

- Flag any commit-stage that publishes a git tag alongside its docker `-dev` tag as polluting the tag namespace — git tags are reserved for release decisions, not build trace. The docker `-dev` tag is sufficient: its single consumer is the next stage, which can pin by digest.
- Flag any acceptance-stage / RC-stage that publishes a docker RC tag without a matching git RC tag (or vice versa) as asymmetric — RC is a flavor-level QA gate, and downstream "deploy the latest RC" lookups must be name-addressable in both registries.
- Flag any prod-stage that publishes a docker release tag without the matching per-component git tag (per Rule (ii)) as a release-layer asymmetry.

**The general rule:** for each pipeline layer, decide whether the artifact is a build label (docker only) or a release marker (docker + git). The decision criterion: **does any consumer ever need to ask "was this released?" by name?** If yes, both layers; if no, docker only.

**Rationale:**

- **`-dev` tags are pre-release in the colloquial sense, not the SemVer sense.** They identify a build for the very next stage, not a candidate for promotion. Adding a git ref for every commit-stage build would explode the tag namespace (multiple `-dev` tags per commit, garbage-collected by `cleanup.yml`) without giving anyone a meaningful name to look up.
- **Consistency with §3.6 (tags-vs-commit-statuses).** §3.6 already establishes that tags are for name-addressable concepts and statuses are for boolean bookkeeping. A `-dev` build label is closer to a status ("this commit produced a build") than to a release marker. Today it's encoded as a docker tag because the next stage needs to pull the image — but it's not a release-decision artifact.
- **Cleanup follows the same shape.** `cleanup.yml` already sweeps `-dev` docker tags and stale RC tags; adding `-dev` git tags would extend cleanup into the tag namespace for no consumer benefit.

## Suggested home in the rubric

Two organisations are reasonable; the actions/ maintainer should pick.

### Option A — distribute the rules across existing sections (smaller blast radius)

| Rule | Home | Insertion point |
|---|---|---|
| (i) Release-decision source = git tag | §1.3 Process and pipeline rules | New bullet after the existing **"Build-once-promote-many"** bullet at line ~58 — the rule sits in the same family (release-vs-artifact distinction) and reuses §1.3's existing build-once-promote-many citation. |
| (ii) Per-component artifact tagging | §1.5 Version-handling actions — follow SemVer | New paragraph after the existing **"Prefixed component-tag variants are explicitly permitted"** paragraph at line ~147. The current paragraph permits prefixed tags; this proposal *requires* them whenever the flavor has multiple independently-versioned components. |
| (iii) Git tags mirror docker *release* tags | §3.6 Tags vs commit-statuses | New subsection **"Layer-symmetric tagging — release layers get docker+git, build layers stay docker-only"** between **"Naming convention consequences"** (line ~424) and **"When a finding applies"** (line ~431). Sits naturally where tag-mechanism decisions are already discussed. |

Rationale: each rule already has a natural neighbour, and dropping them in-place avoids creating a new section that may not justify its own subsection number. The cross-references are explicit (rule (ii) calls out §1.5; rule (iii) extends §3.6) so a reader following any of the three to its current home will find the rest one hop away.

### Option B — consolidate as new §1.10 "Release ledger — git tags as the release-decision signal"

A new top-level subsection inside §1, between §1.9 (Marketplace-action version currency) and §2 (Forward-looking context). Holds all three rules as one coherent narrative — the release ledger as a first-class architectural concept, with the three rules as its concrete consequences (source-of-truth, granularity, layer-symmetry).

Rationale: rule (i) and rule (iii) share a thesis (tags are release-decision markers, not artifact bookkeeping); rule (ii) is the granularity sub-rule. Consolidating reads better as a single concept and gives the actions-auditor a single citation handle (`§1.10 release-ledger`) rather than three.

**Recommendation:** Option B if the maintainer is comfortable with adding a §1.10; otherwise Option A. Either way, all three rules end up in the rubric.

## Plan items

- [ ] **1. Pick organisation (Option A vs B).** No code change. Decision item — the rest of the plan branches on this.

- [ ] **2. Draft the three rule paragraphs in the chosen location.** Use the wording proposed under "The rules" above as a starting point; tighten as the maintainer sees fit. If Option A, three separate edits to §1.3, §1.5, and §3.6. If Option B, one new §1.10 plus a one-line cross-reference from §1.5's prefixed-component-tag paragraph (so a reader landing in §1.5 still discovers Rule (ii)).
  - Affects: `.claude/agents/docs/devops-rubric.md`
  - Category: rubric-extension

- [ ] **3. Bump rubric version to v12 and add a Version-history entry.** Following the convention at the top of the file: increment `Rubric version: 11` → `12`, prepend a new entry under `# Version history` summarising the three rules and citing the shop / gh-optivem commits that motivated them (`shop@786033d0`, `gh-optivem@5bee027`, `shop/plans/20260429-231139-…`).
  - Affects: `.claude/agents/docs/devops-rubric.md`
  - Category: rubric-version

- [ ] **4. Update the actions-auditor agent's Output schema to host the new findings, if needed.**
  - For Option A: the new bullets land in §1.3, §1.5, §3.6 — all already covered by existing auditor output subsections (DevOps alignment → "Other" / "Composition ordering" / "Tag vs commit-status mechanism"). No auditor change strictly required, but consider adding a named subsection **"Release-decision source"** under DevOps alignment so rule-(i) findings are filed deterministically rather than swept into "Other".
  - For Option B: §1.10 deserves its own auditor output subsection — add **"Release ledger"** under DevOps alignment with three sub-buckets (release-decision source / per-component granularity / layer-symmetric tagging).
  - Affects: `.claude/agents/actions-auditor.md`
  - Category: auditor-output-schema

- [ ] **5. Re-run actions-auditor on the actions repo to surface any pre-existing violations now visible under the new rules.** None expected — this repo's prod-stage actions already publish git tags as the release ledger and don't probe GHCR for release decisions. But the re-audit is the canonical way to verify the rule lands without false positives, and any genuine drift caught here is bonus signal. Tag findings as `[RUBRIC-CHANGE v12]` per the rubric-version convention.
  - Affects: produces a new `.reports/<ts>-audit-actions-*.md` + `plans/<ts>-audit-actions-*.md` pair under the actions repo's standard auditor output.
  - Category: re-audit-after-rubric-change

## Verification

- `Rubric version:` at top of the file reads `12` and the v12 entry in `# Version history` summarises the three new rules with citations.
- The three rules are reachable by section header (§1.3, §1.5, §3.6 for Option A; §1.10 for Option B) and the cross-references resolve cleanly (§1.5 → §1.10 if Option B; §3.6 internal link from §1.10's layer-symmetry rule).
- A re-audit of the actions repo against rubric v12 produces no `[RUBRIC-CHANGE v12]` findings (this repo's actions already conform), or whatever findings it does produce are filed under the correct new auditor output subsection.

## Out of scope

- The shop changes themselves are already landed (`shop@786033d0`, `gh-optivem@5bee027`). No further code change in shop or gh-optivem is needed for this rubric work.
- The shop plan `plans/20260429-231139-bump-patch-signal-from-ghcr-to-git-tag.md` will be deleted once items 2/3/4 of that plan are complete (they're all triggers — re-publish gh-optivem CLI tag, cut a fresh shop tag, re-run gh-acceptance-stage). This rubric proposal is independent of those triggers.
- Auditing other repos' workflows against rubric v12 — out of scope here. The actions-auditor's existing scope rules apply.
