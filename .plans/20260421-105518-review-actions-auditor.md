# Actions-auditor reviewer report — 2026-04-21

## Header

- **depth**: standard (no option supplied by caller; defaulting per spec)
- **Subject files**:
  - `.claude/agents/actions-auditor.md` (217 lines)
  - `.claude/agents/docs/devops-rubric.md` (312 lines)
- **Subject length**: 529 lines total
- **Date**: 2026-04-21

## Summary

The auditor is fundamentally sound. The rubric is well-grounded in Farley/Humble, Twelve-Factor, and GitHub Actions idioms, and its main structural choices — splitting process (auditor file) from standards (rubric file), tiering names by portability, biasing toward *keep* for dead inputs/outputs, and enumerating reversibility/idempotence rules — all hold up against the five review dimensions. The top three issues are: **(1)** the rubric's Tier 2 portability claim is partially undercut by its own implementation sub-rule (it permits git-host hardcoding in some actions while forbidding it in others, with no explicit override), **(2)** the "prefer git over gh api" rule never addresses non-GitHub CI platforms even though the auditor sits inside a repo that explicitly invokes a porting story (Jenkins/GitLab CI/etc. have `glab api`, `bb`, shell curl, etc. — the principle generalizes but the rubric doesn't say so), and **(3)** the auditor's **Process** step 7 ("Recommend the best-practice option, not the lowest-effort one") can collide with the rubric's **teaching-clarity override** (§2) without a stated tie-breaker, leaving the auditor without guidance when pedagogy and rubric-alignment disagree on a recommendation.

**Counts**: internal inconsistencies 3 | CD misalignments 1 | DORA/SRE/12-Factor/Marketplace gaps 2 | portability issues 3 | practicality issues 3 | additional findings 4

## Internal consistency findings

### Finding 1 — "prefer git over `gh api`" vs. "Tier 3 = GitHub-platform-specific" leave timestamp ambiguity undefined

- **Issue**: Rubric §3.2 says "use git" when git works; Rubric §3.3 lists "Push timestamps (distinct from committer timestamps — git only has the latter)" as a Tier 3 signal. But an action that needs a commit *committer* timestamp — which git *does* have — would be Tier 2 by §3.2, yet the repo has no rule for how to name it. Neither passage answers whether `has-update-since-last-github-workflow-run` (`gh run list` — genuinely Tier 3) is in the same naming class as a hypothetical `has-update-since-last-commit-timestamp` (pure git). The auditor would end up inferring.
- **Quote A**: `devops-rubric.md:114` — "If a git command achieves the same outcome as a `gh api` call, use git. Reserve `gh api` for concepts that genuinely do not exist in git."
- **Quote B**: `devops-rubric.md:127` — "Push timestamps (distinct from committer timestamps — git only has the latter)."
- **Resolution**: Add a half-sentence to §3.2 clarifying that an action can be *Tier 2* (name without `github`) even when its tool-of-choice today happens to be `gh api` because of convenience — the tier is determined by **the concept accessed**, not the tool used. The rubric says this at §3.3 note ("Note: consuming `GITHUB_TOKEN` for git auth...does NOT by itself make an action Tier 3"), but not for the `gh api`-as-tool case. Suggest: "Tier is determined by the concept accessed, not the tool used. An action named `has-update-since-last-commit` (Tier 2) may use `gh api` internally for speed — the tier promise is that a port to GitLab replaces only the implementation, not the name."

### Finding 2 — "best-practice option" vs. "teaching-clarity override" collision with no tie-breaker

- **Issue**: Auditor step 7 tells the reviewer to always recommend the rubric-aligned option over the lowest-effort one. Rubric §2's teaching-clarity override tells the reviewer to preserve pedagogical distinctions even when a merge would satisfy the rubric. The two collide when the "best-practice option" *is* a consolidation that flattens a teaching-distinction (e.g. the `check-*` vs. `has-*` split). The auditor's output schema gives no slot for "best-practice-but-pedagogically-risky", so the auditor has to pick one and the reader never sees the trade-off.
- **Quote A**: `actions-auditor.md:74` — "Recommend the best-practice option, not the lowest-effort one...present them all (numbered) but explicitly recommend the one most aligned with long-term rubric compliance — even when it means more consumer churn."
- **Quote B**: `devops-rubric.md:88` — "Teaching-clarity override...prefer to leave the primitives separate and note the pedagogical role in the finding. A finding that is 'correct by the rubric but bad for the course' must say so explicitly — don't silently merge pedagogically-important distinctions for code-line savings."
- **Resolution**: In `actions-auditor.md` step 7, add an explicit ordering: "When step 7 and the teaching-clarity override (§2) both apply, the teaching-clarity override wins — recommend the pedagogy-preserving split as the primary recommendation, list the rubric-alignment-maximising consolidation as **Option 2 — rubric-aligned but pedagogically risky**, and flag the trade-off in the finding body." This makes the collision explicit and gives the reviewer a deterministic output.

### Finding 3 — Auditor output section names do not match rubric §8 filing guide

- **Issue**: Rubric §8's "Filing findings" table lists **"Tool-agnostic composition"**, **"Separation of concerns"**, **"Composite opacity"**, **"Prefer git over gh api"**, **"Composition ordering"**, **"Idempotence"**, and **"Other"** — seven subsections. Auditor Output section enumerates the same seven by name at `actions-auditor.md:136–141`. But **"Secrets / auth"** is listed in the filing guide (`devops-rubric.md:310–311`) with TWO distinct cases (implicit-env token, and `${{ inputs.token }}` interpolation into `run:`) yet there is no `Secrets / auth` subsection in the auditor's Output list — only the unhelpfully-broad `Other`. Any finding in this category gets filed under **Other**, which defeats the filing guide's purpose.
- **Quote A**: `actions-auditor.md:135–141` (Output list) — "Tool-agnostic composition / Separation of concerns / Composite opacity / Prefer git over gh api / Composition ordering / Idempotence / Other"
- **Quote B**: `devops-rubric.md:310–311` (Filing guide rows) — "Action expects caller to set an implicit `env:` for a token...→ DevOps alignment → **Secrets / auth**" and "Action interpolates `${{ inputs.token }}` or `${{ env.TOKEN }}` directly into a `run:` shell line...→ DevOps alignment → **Secrets / auth**"
- **Resolution**: Add **Secrets / auth** as an explicit named subsection in the auditor's Output list, between **Idempotence** and **Other**. Both files should agree on the same eight subsections.

## Continuous Delivery alignment findings

### Finding 4 — "Release" verb is defined but "promote" is not

- **CD practice**: Deployment vs. release distinction; **promotion** as the Farley term for moving an RC through stages.
- **Source**: Farley & Humble, *Continuous Delivery*, ch. 5 (deployment pipeline) and ch. 10 (release strategy). Farley, *Modern Software Engineering*, ch. 12.
- **Rule in the agent**: `devops-rubric.md:16` names "promotion" as "Farley's term for moving an RC through stages" — but the **naming rules** in §4 only require honesty for `deploy-*`, `release-*`, `build-*`, `validate-*`, `cleanup-*`, and `wait-for-*`. There is no rule for `promote-*` even though the rubric's own vocabulary depends on it, and no rule that would flag an action named `release-to-qa` that actually performs a *promotion* (pulling an already-built RC image and re-tagging it for QA).
- **What's off**: The rubric uses "promote" as a load-bearing CD term (§1.3: "Build-once-promote-many") but never extends the misleading-verbs list to cover `promote-*`, `publish-*`, or `ship-*`. An action named `release-to-acceptance` that does a re-tag + docker pull (which *is* a promotion) would not be flagged, because `release-*` per §4 only requires "makes features available to users" — and acceptance isn't users.
- **Proposed change**: Extend `devops-rubric.md:156–162` (the misleading-verbs list) with:
  - `promote-*` must move an already-built artifact through a pipeline stage without rebuilding. If the action rebuilds, it's `build-*` or `build-and-*`, not `promote-*`.
  - `publish-*` must make an artifact reachable by external consumers (registry push to a public tag, npm publish to the registry). A local `docker tag` is not a publish.
  - `ship-*` / `release-*` are end-of-pipeline — must make the change visible to end users.

## DORA / SRE / Twelve-Factor / Marketplace alignment findings

### Finding 5 — SRE "error budget" and graceful-degradation guidance is absent from idempotence/fail-fast rules

- **Practice**: Graceful degradation under partial failure; error-budget framing for retries. Google SRE book ch. 22 ("Addressing Cascading Failures") and ch. 3 ("Embracing Risk").
- **Source**: Google SRE book.
- **Rule in the agent**: The rubric has **idempotence** (§7.2) and **fail-fast on cheap preconditions** (§1.3, `devops-rubric.md:45`). It also has **rate-limit awareness** (§1.3, `devops-rubric.md:46`). But there is no rule covering **bounded retry** — an action that retries indefinitely on a transient failure can exhaust the error budget of the calling pipeline and drag MTTR up. `build-docker-image` (sampled) retries 3 times with 15s backoff — good. But the rubric doesn't mandate a retry-bound-with-jitter policy anywhere.
- **What's off**: The auditor will not flag a future action that uses `while true; do ... done` or that retries without exponential backoff. Given the rubric already cites SRE in §1.4 (observability) and §1.5 (DORA linkage), the silence on bounded retry is an inconsistency — a category the rubric *should* cover given its stated source set.
- **Proposed change**: Add to `devops-rubric.md` §1.3 a new bullet:
  - **Bounded retry with backoff.** Any action that retries a transient failure (API call, network fetch, docker pull) must cap retries (typically 3–5), use exponential or jittered backoff, and surface the final failure reason as an output when the caller might want to branch. Unbounded retries delay MTTR and can cascade under rate-limit exhaustion. Source: Google SRE ch. 22.

### Finding 6 — Twelve-Factor Factor III ("Config in environment") is cited but misapplied for `env:`-style tokens

- **Practice**: Factor III — store config in the environment (environment variables).
- **Source**: *The Twelve-Factor App*.
- **Rule in the agent**: `devops-rubric.md:51` — the rubric flags **Token contract — input, not implicit env** as an anti-pattern, citing that `${{ env.X }}` has no interface contract. But Factor III explicitly advocates *environment variables* as the config channel. The rubric is conflating "interface discoverability" (an Actions-specific concern — is the input declared in `action.yml`?) with Factor III (is the value delivered via env at runtime?).
- **What's off**: The rule is correct *for GitHub Actions composites* (where `action.yml` is the interface contract), but it invokes Factor III imprecisely. A reader who applies the rubric to Jenkins shared library code (where parameters and env vars are legitimately interchangeable) will over-flag. The citation to Factor III is subtly wrong — the real source is **Marketplace conventions** and **action-interface discoverability**, not Twelve-Factor.
- **Proposed change**: In `devops-rubric.md:51`, reword the source attribution. Drop the implicit Factor III framing and cite the correct sources instead: "Reference: `actions/checkout`, `actions/setup-node`, `actions/github-script`, `docker/login-action`, `softprops/action-gh-release` — all take the token as a named input. This is a **Marketplace convention** (interface discoverability) and not an instance of Factor III, which is about runtime environment variable delivery and is orthogonal."

## Portability findings

The rubric claims portability as its headline value (§3 opening paragraph: "Students may swap the CI/CD platform..."). The tier system does most of the work here, but several rules leak GitHub Actions assumptions.

### Jenkins

- **Translate cleanly**: Tier 1 / Tier 2 names; idempotence rules; composition-order rules; "build once, promote many"; `branding:` exemption (Jenkins has no Marketplace).
- **Break**:
  - The primitive-vs-composite model maps to Jenkins **shared libraries** (`vars/*.groovy`), which have a flat namespace and no analog to `action.yml`'s explicit `inputs:`/`outputs:` contract. The rubric's repeated language about "declare the token as a named input" (`devops-rubric.md:51`) doesn't translate to a Jenkins shared library step, where the contract is a Groovy function signature. The rubric should acknowledge this — say "equivalent: function parameter signature in a Jenkins shared library step, `parameters:` block in a GitLab CI template, etc."
  - The "composite" terminology is Actions-specific. Jenkins' equivalent ("shared library step") has different opacity semantics — a shared library step can call other steps but pipeline steps can't easily be inlined. Rubric §5 ("every behavior exposed by a composite must also be reachable by calling primitives directly") is a stronger claim on Jenkins than on Actions and would need adaptation.
  - `$GITHUB_ACTION_PATH` is hardcoded in the sampled actions (e.g. `create-github-release/action.yml:50` sources `shared/gh-retry.sh` via it). No rubric rule addresses whether helpers living in a `shared/` dir port to Jenkins' shared-library structure or not.

### GitLab CI

- **Translate cleanly**: Tier 1/2 names with tier labels. Idempotence rules. `branding:` exemption.
- **Break**:
  - Tier 3 concepts ("GitHub Release", "commit status", "Deployment") have near-direct analogs on GitLab ("Release", "commit status", "Environment"), but the rubric never names the mapping. A student porting `create-github-release` to `create-gitlab-release` gets no guidance on whether Environments map to Deployments or something else.
  - GitLab's `include:` + `extends:` model doesn't have a "call with outputs" semantic the way Actions' `outputs:` does. Rubric §7.2 "Tag creation: create-if-missing, otherwise verify-or-update" is a `run:`-script contract that ports cleanly, but the "every primitive must be independently callable" rule (`devops-rubric.md:171–172`) maps only loosely.
  - "Prefer git over gh api" generalizes to "prefer git over `glab api`", but the rubric says "gh api" specifically (§3.2 title and body). A porter has to guess whether the rule abstracts.

### Azure Pipelines

- **Translate cleanly**: Tier 1 naming; idempotence; reversibility ordering.
- **Break**:
  - Azure templates are YAML-based like Actions, so the composition model translates. But Azure's **Release** concept includes **deployment stages** (with gates/approvals), which GitHub Releases do not. Rubric §3.1 does call this out for Tier 3 ("Azure Releases model deployment stages, which GitHub Releases do not"), but the porting caveat is a single paragraph at `devops-rubric.md:110` and doesn't extend to inputs/outputs. An Azure port of `create-github-release` would need additional inputs (`stage`, `approval-gate`) — the rubric's forward-looking note ("Treat Tier 3 renames as 'start here', not 'done'") is right, but doesn't spell out the shape changes.
  - Azure Pipelines has first-class `approvals:` / `checks:`. The rubric's `wait-for-approval` is listed as Tier 1 (`devops-rubric.md:100`), which is correct — but actions like `create-github-commit-status` are Tier 3 and have a direct Azure analog (`buildStatus`) that the rubric doesn't mention.

### CircleCI

- **Translate cleanly**: Tier 1/2 names; most of §7 (ordering/idempotence).
- **Break**:
  - CircleCI's **orbs** are the composition analog. An orb can define `commands`, `jobs`, and `executors` — the rubric's flat "primitive vs. composite" distinction doesn't map cleanly. An orb's `command` is equivalent to a composite action's `runs: composite`, but `executors` don't exist in Actions. Rubric §5 is silent on this.
  - CircleCI's config has `parameters:` at the orb / job level, similar to Actions' `inputs:`, but with typed values (string/boolean/integer/enum). The rubric's input-naming rules translate, but the type-system constraint (Actions has no input types; everything is string) is a GitHub-specific limitation that the rubric implicitly assumes (e.g. `is-prerelease: default: 'false'` as a string in `create-github-release/action.yml:21`).

### Buildkite

- **Translate cleanly**: Tier 1 names; reversibility ordering; idempotence (pipelines and plugins are both genuinely reusable).
- **Break**:
  - Buildkite **plugins** are the composition analog. Plugin config is YAML-in-YAML (`plugins: - some-org/plugin#v1.2.3: { input: value }`). The rubric's `uses: optivem/actions/<dir>@<ref>` syntax (§3 examples, `devops-rubric.md:104`) is strictly Actions. The rubric's rule "Pinning to a major tag (`@v4`) is acceptable" (`devops-rubric.md:69`) maps to plugin version pins, but the wording is Actions-specific.
  - Buildkite's retry semantics (`retry:` at step or plugin level) offer graceful-degradation controls the rubric doesn't mention (see Finding 5).

### Portability findings summary — three structural issues

- **P1**: Rubric §3.2's **"Prefer git over `gh api`"** title is hard-coded to `gh api` (`devops-rubric.md:112`). The principle is *general* (prefer VCS-standard commands over platform API where both work) but the title won't port. **Proposed change**: rename the rule to "Prefer VCS-standard commands over platform API" and keep `gh api` as a concrete example.
- **P2**: Rubric §3.1's Tier 2 **implementation sub-rule** (`devops-rubric.md:106`) requires `git-host` parameterization — but the sampled `create-and-push-tag/action.yml` (Tier 2 by concept) uses `origin` implicitly and `ensure-tag-exists/action.yml` (also Tier 2) correctly takes a `git-host` input. The rubric is inconsistently applied in the repo; the rubric itself is right, but there's no finding-template in the auditor for the sub-rule — it says "flag portability violation under Tool-agnostic composition" which is the right place, but the rubric text doesn't give the auditor a distinguishing signal (e.g. "grep action.yml for `origin` with no corresponding `git-host` input").
- **P3**: The rubric never addresses **AWS CodePipeline / Spinnaker / Argo** even though Farley's pipeline model is pipeline-agnostic and the rubric promises broad portability ("any CI", `devops-rubric.md:94`). These platforms structure the release-record and deployment primitives very differently (Spinnaker pipelines are the unit; Argo Rollouts coalesce "deploy" with health checks). A porting student here would be on their own. **Proposed change**: add a short "Platforms not covered" note at end of §3 saying which platforms the tier system was validated against and which are out of scope.

## Practicality findings

### Finding P1 — `:latest` exemption is repo-specific and phrased too absolutely

- **Issue**: Rubric §2 ("`:latest` is load-bearing in this pipeline — do NOT flag it as an anti-pattern") is correct for this repo but the language is absolute. If a second use of `:latest` appears elsewhere (e.g. in a production-pointing workflow), the rubric would have the auditor silently accept it.
- **Quote**: `devops-rubric.md:87` — "Do not recommend making `:latest` push opt-in, do not recommend removing the `image-latest-url` output, and do not cite SRE/K8s `imagePullPolicy` guidance against it in this repo."
- **Why it's a problem**: The exemption is scoped only to "the acceptance stage intentionally pulls `:latest`". An auditor reading literally will apply the exemption repo-wide.
- **Proposed change**: Tighten `devops-rubric.md:87` to: "**scope the exemption**: only the commit-stage → acceptance-stage handoff may use `:latest`. `:latest` in any other context (deploy-to-production, deploy-to-qa, release-record assets) should be flagged normally."

### Finding P2 — "flag misleading names" has sharp criteria for six verbs, vague for all others

- **Issue**: Rubric §4 (`devops-rubric.md:156–162`) lists six verbs with precise honesty rules: `deploy-*`, `release-*`, `build-*`, `validate-*`, `cleanup-*`, `wait-for-*`. Any other verb (e.g. `resolve-*`, `compose-*`, `generate-*`, `ensure-*`, `has-*`, `check-*`, `read-*`, `bump-*`, `push-*`, `tag-*`, `trigger-*`, `render-*`, `map-*`, `format-*`, `get-*`) has no stated honesty rule — even though the repo uses all of them and some (like `has-*` vs `check-*`) are pedagogically load-bearing.
- **Quote**: `devops-rubric.md:156` — "The name must not be misleading vs. mainstream DevOps/CD terminology. When a verb's CD-meaning is load-bearing, the action's `runs:` block must honour it:" (followed by six verbs).
- **Why it's a problem**: The reader infers that the six-verb list is closed. A `resolve-*` action that actually produces side effects won't be flagged because no rule covers `resolve-*`.
- **Proposed change**: After the six-verb list, add a general clause: "For any verb not listed above, apply the same principle: the action's `runs:` block must match what the verb connotes in mainstream CD/DevOps vocabulary. Spot-check verbs that look read-only (`resolve-*`, `read-*`, `get-*`, `compose-*`, `render-*`, `map-*`, `format-*`, `has-*`, `check-*`, `ensure-*`) for hidden side effects — a `resolve-*` action that mutates state is as misleading as a `deploy-*` that doesn't deploy."

### Finding P3 — Auditor prescribes a plan-file format that sometimes duplicates the report

- **Issue**: Auditor §"Plan file" (`actions-auditor.md:155–202`) specifies a plan with per-item consumer-file listings. For a repo with 49 actions and ~30 potential findings, this plan could balloon; the auditor notes the plan excludes non-actionable items, but the section also says "See report section in workflow output for full context" — implying the plan is routinely orphaned from its report. There's no rule for what to do when the plan file and the report go out of sync (e.g. the user starts executing the plan, then re-runs the auditor — should the new report be a delta against the plan, or a fresh plan?)
- **Quote**: `actions-auditor.md:199` — "Per project convention, items are removed from this file as they are executed, the file is deleted when empty, and the `.plans/` directory is deleted when it contains no files."
- **Why it's a problem**: An auditor re-run mid-execution produces a second plan file alongside a half-consumed earlier one; no rule says which wins or how to reconcile.
- **Proposed change**: Add a sentence to the plan-file section: "If a prior audit plan still exists under `.plans/`, the new plan should not overwrite it. Either append `-partial` to the new filename or the caller should resolve the old plan before re-running the audit. This is the caller's decision, not the auditor's — but the auditor MUST NOT silently clobber an existing plan file."

## Additional findings

### A1 — Rubric silently assumes all actions are composite (not JavaScript / Docker container actions)

- **Issue**: The rubric's examples are all `runs: composite`. `actions-auditor.md:4` declares the auditor reads `action.yml`. GitHub Actions also supports `runs: node16/node20` (JavaScript actions) and `runs: docker` (container actions). Neither the auditor nor the rubric says anything about these — and some rules (e.g. `devops-rubric.md:52`, token-in-env for `run:` scripts) simply don't apply to a JS action where `inputs` become function parameters and there is no shell.
- **Why it matters**: A future JS or Docker action in this repo (unlikely but not impossible) would be mis-audited. The rubric should declare its scope.
- **Proposed change**: Add one line near the top of `devops-rubric.md`: "This rubric addresses `runs: composite` actions. JavaScript (`runs: node*`) and container (`runs: docker`) actions have different interface and security semantics; findings generated against them should be treated as approximate."

### A2 — "Publication intent: internal-only" exemption is in the auditor file but its consequences leak into the rubric

- **Issue**: `actions-auditor.md:21–27` declares publication intent as internal-only and exempts `branding:`. But `devops-rubric.md:72` also discusses `branding:` ("Optional for internal actions; required by the Marketplace publishing flow. If publication intent is Marketplace, flag..."). Both files own part of the same policy, and the auditor file's "Marketplace input naming conventions beyond what the rubric already mandates" (`actions-auditor.md:24`) implies some Marketplace conventions *do* apply — but the rubric never calls out which ones are "mandated for internal clarity" vs. which are Marketplace-only.
- **Why it matters**: Leaves a grey zone: do `commit-sha` / `image-url` / `tag` / `version` conventions apply because they're internal-clarity or because they're Marketplace? The rubric implies both (§1, `devops-rubric.md:18`).
- **Proposed change**: In `devops-rubric.md` §1, add an explicit sentence: "Input/output naming conventions (`image-url`, `commit-sha`, `tag`, `version`, `environment`) are **internal-clarity** mandates — the Marketplace codified them, but they serve the same purpose in an internal-only repo. The `branding:` field, by contrast, is a Marketplace surface with no internal-clarity payoff; it is the only Marketplace convention that the internal-only exemption in the auditor file actually elides."

### A3 — The rubric has no rule for action *deletion* once the rubric itself changes

- **Issue**: Rubric and auditor both evolve. Every rubric revision potentially reclassifies some existing action's state (e.g. an action that was compliant under the previous rubric now violates a newly-added rule). There is no guidance on how to handle this — do we flag, grandfather, or add a section to the report?
- **Why it matters**: On a second run of the auditor after a rubric update, every existing action could generate findings. The auditor should know whether to treat these as "new issues caused by rubric drift" or as "always-existed issues newly discovered".
- **Proposed change**: Add a clause to `actions-auditor.md` under Rules: "When the auditor re-runs against a rubric that has changed since the last audit, flag findings introduced by rubric changes with `[RUBRIC-CHANGE]` in the finding title. This lets the caller triage 'code drift' vs 'standards drift' separately." This requires the auditor to know the prior rubric version — which might be a too-ambitious ask; if so, at minimum the auditor should note in the header whether the rubric file has changed since some stable landmark (e.g. a `version:` field at the top of `devops-rubric.md`).

### A4 — Review-dimensions doc and auditor-reviewer doc overlap in a way that may drift

- **Issue**: `.claude/agents/docs/review-dimensions.md` and `.claude/agents/actions-auditor-reviewer.md` both describe the review process at different levels of detail. The auditor-reviewer file says "Read the review dimensions first" (`actions-auditor-reviewer.md:11`) and names all five dimensions inline (`actions-auditor-reviewer.md:3`), which means the two files have a single source of truth divided across them. If a future edit to one doesn't propagate to the other, the reviewer will run against an inconsistent spec.
- **Why it matters**: Precisely the sort of thing the reviewer flags in the *subject* files (Finding 3 above) — yet the reviewer's own docs have the same pattern.
- **Proposed change**: Either (a) consolidate — move the dimensions doc's content into `actions-auditor-reviewer.md` and delete the separate file, or (b) make the split explicit and enforceable — have `actions-auditor-reviewer.md:3` cite only the dimension *numbers* (1–5) and the names, with all substantive content (signals, sources, etc.) living in `review-dimensions.md`. I'd recommend (b) — it preserves the same process/standards split the auditor uses.

## Self-edits

None.

The run surfaced several findings but no flaw in the reviewer's own spec severe enough to justify modifying `actions-auditor-reviewer.md` or `review-dimensions.md` this run. Finding A4 identifies a structural drift risk in the reviewer docs themselves, but it's a **recommendation to the author**, not a self-edit — the reviewer is explicitly told (spec line 175) not to "structurally reverse" author choices unilaterally, and consolidating the two docs (option A) or restructuring one to depend on the other (option B) both feel like structural calls for the author to make. Proposing the change via this report is the correct path.

## Recommended edits

Ordered by impact, highest first. File references are relative to `c:\Users\valen\Documents\GitHub\optivem\academy\actions`.

1. **`devops-rubric.md` §3.2, title and intro (lines ~112–114).** Rename the rule from **"Prefer git over `gh api`"** to **"Prefer VCS-standard commands over platform API"** and keep `gh api` as the concrete example. Resolves: Portability P1, Finding 1.

2. **`actions-auditor.md` Output section (lines 135–141)** and **`devops-rubric.md` §8 filing guide (lines 310–311).** Add **Secrets / auth** as an explicit subsection in the auditor's DevOps alignment output. Both files should list the same eight subsections. Resolves: Finding 3.

3. **`devops-rubric.md` §4 (lines 156–162).** After the six-verb honesty list, add a general clause telling the auditor to apply the same principle to any other verb (including `resolve-*`, `compose-*`, `has-*`, `check-*`, `ensure-*`). Resolves: Practicality P2.

4. **`actions-auditor.md` step 7 (line 74).** Add an explicit tie-breaker: when step 7 collides with the teaching-clarity override (rubric §2), the teaching-clarity override wins; list the rubric-aligned consolidation as an explicit Option 2 and flag the trade-off in the finding body. Resolves: Finding 2.

5. **`devops-rubric.md` §1.3 (after line 46).** Add a **Bounded retry with backoff** bullet citing SRE ch. 22. Resolves: Finding 5.

6. **`devops-rubric.md` §4, misleading-verbs list (lines 156–162).** Add entries for `promote-*`, `publish-*`, `ship-*`. Resolves: Finding 4.

7. **`devops-rubric.md` §3 opening paragraph (around line 94).** Add a "Platforms validated" / "Platforms not covered" note. Resolves: Portability P3.

8. **`devops-rubric.md` §2, `:latest` exemption (line 87).** Tighten scope: exempt only the commit-stage → acceptance-stage handoff. Resolves: Practicality P1.

9. **`devops-rubric.md` top-of-file scoping note.** Add a line declaring the rubric addresses `runs: composite` actions; JS/Docker actions are approximate. Resolves: A1.

10. **`devops-rubric.md` §1 (around line 18).** Clarify that input/output naming conventions are internal-clarity mandates (even though Marketplace codified them); the internal-only exemption in the auditor only elides `branding:`. Resolves: A2.

11. **`devops-rubric.md` §1.4 (line 51).** Remove the implicit Factor III framing from **Token contract — input, not implicit env** and re-attribute to Marketplace convention / interface discoverability. Resolves: Finding 6.

12. **`actions-auditor.md` Plan file section (around line 199).** Add a rule against silently clobbering an existing `.plans/` file from a prior audit run. Resolves: Practicality P3.

13. **`actions-auditor.md` Rules section (end).** Add a `[RUBRIC-CHANGE]` tag mechanism — or at minimum a `version:` field at the top of `devops-rubric.md` so auditor re-runs can note whether the rubric has drifted. Resolves: A3.

14. **`.claude/agents/actions-auditor-reviewer.md` and `review-dimensions.md`.** Consider (author decision) restructuring so the dimensions doc is the sole source of dimension names+signals, with the reviewer file citing only the dimension numbers. Resolves: A4.
