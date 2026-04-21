# Review — `actions-auditor` agent definition

## Header

- `depth`: standard (default; caller did not specify)
- Subject file: `.claude/agents/actions-auditor.md`
- Subject length: 410 lines
- Date: 2026-04-21

## Summary

The auditor is substantively sound: it names the right sources (Farley/Humble, DORA, Twelve-Factor, Marketplace), it draws the right architectural distinctions (primitives vs. composites, separation of concerns, reversibility-ordered composition, idempotence), and it codifies useful exemptions (`:latest`, Docker Compose stepping stone, author-determined environments) so that the review pass does not pick fights the author has already settled. The three highest-impact issues are:

1. A **"Portability" / "Prefer git over gh api"** violation category is referenced in the `When auditing` instructions (line 282) but has no corresponding section in the **Output** schema (lines 307–353) — the auditor is told to produce findings with nowhere to put them.
2. The **Usage findings** output section (line 318) lists consumers only for `shop` and `gh-optivem`, but the Consumer-repos section and the plan-file section both require `optivem-testing` to be grepped and cited. A consumer grep that skips `optivem-testing` will produce false "dead code" / "unused input" findings, which is exactly what the agent warns against in lines 34 and 46.
3. The **portability claim** (a student "could mechanically rename `create-github-release` → `create-gitlab-release` and keep the rest unchanged") does not quite hold on close reading: the rubric's Tier 2 examples include `resolve-tag-from-sha`, `ensure-tag-exists`, and `create-and-push-tag`, but the actual repo implements them against `https://x-access-token:${TOKEN}@github.com/...` hardcoded URLs. The naming tier is correct, but the auditor has no rule telling authors to factor the git host out of Tier 2 actions. Without that, the "only Tier 3 needs renaming when porting" promise leaks.

Counts: internal inconsistencies **4** | CD misalignments **3** | DORA/SRE/12-Factor gaps **4** | portability issues **5** | practicality issues **5** | additional findings **6**

## Internal consistency findings

### 1. "Prefer git over gh api" violations have no Output section

- **Issue:** The auditor is instructed to produce a `"Prefer git over gh api"` finding, but the Output schema has no subsection for it.
- **Quote A (line 282):** `"Report these under **Naming violations** (for pure rename cases), **DevOps alignment findings** → "Tool-agnostic composition" (for mixed-concern cases), **DevOps alignment findings** → "Separation of concerns" (for concern-mixing violations), **DevOps alignment findings** → "Composite opacity" (for opaque composites), or **DevOps alignment findings** → "Prefer git over gh api" (for portability violations)."`
- **Quote B (lines 342–349):** The DevOps alignment findings Output section does not enumerate subsections at all — just tells the auditor to "group by action or by theme". The four sub-themes named in line 282 ("Tool-agnostic composition", "Separation of concerns", "Composite opacity", "Prefer git over gh api") appear only inside the Process section and never in the Output section.
- **Resolution:** In the Output section, replace the free-form "group by action or by theme" wording (line 343) with a concrete subsection list: `"Tool-agnostic composition"`, `"Separation of concerns"`, `"Composite opacity"`, `"Prefer git over gh api"`, `"Composition ordering"`, `"Idempotence"`, plus a catch-all `"Other"`. Every subsection referenced in Process must appear in Output.

### 2. `Usage findings` output omits `optivem-testing`

- **Issue:** The auditor requires greps of three consumer repos but the Output schema for Usage findings only names two.
- **Quote A (lines 28–32):** `"these live as siblings to this repo: - `../shop/` — shop templates and pipelines - `../gh-optivem/` — gh workflow suite - `../optivem-testing/` — one-click release & cross-pipeline orchestration"` plus line 34: `"Critical: grep ALL consumer repos. Missing a repo produces false "dead code" findings."`
- **Quote B (line 318):** `"- Actions with **zero** call sites across `shop` and `gh-optivem` (candidates for removal)."`
- **Resolution:** Amend line 318 to `"Actions with zero call sites across shop, gh-optivem, and optivem-testing"`. Apply the same triple-consumer rule to the Inventory table header (line 315: `"call sites (shop + gh-optivem)"` should be `"call sites (shop + gh-optivem + optivem-testing)"`) and to the plan file template (line 380: `"<N> in shop, <M> in gh-optivem"` needs a third count).

### 3. "Composition ordering" and "Idempotence" categories are defined but not listed in Output

- **Issue:** Two concern categories are introduced in the `Composition order and idempotence` section but never appear in the Output schema.
- **Quote A (line 262):** `"flag it as an **ordering violation** under **DevOps alignment findings** → "Composition ordering"."` And line 263: `"flag it as an **idempotence violation** under **DevOps alignment findings** → "Idempotence"."`
- **Quote B (lines 342–349):** DevOps alignment findings Output section lists no subsections at all; the full enumeration of categories is scattered across Process and must be reconstructed by the reader.
- **Resolution:** Same as finding 1 — codify the subsection list in Output. Both "Composition ordering" and "Idempotence" must be named alongside "Separation of concerns", "Composite opacity", etc.

### 4. "Dead-output" category is in the plan-file format but missing from Usage findings report

- **Issue:** The plan file's `Category:` line (line 384) supports `dead-input` but not `dead-output`, while the Output `Usage findings` section (lines 318–321) does enumerate "outputs declared but never read". The two forms are out of sync.
- **Quote A (line 320):** `"- Outputs declared but never read by any consumer."` (Usage findings Output)
- **Quote B (line 384):** `"Category: naming | duplicate | consolidation | dead-code | dead-input"` (plan file)
- **Resolution:** Extend line 384's category enumeration to `"naming | duplicate | consolidation | dead-code | dead-input | dead-output | devops-alignment"`. Also add `devops-alignment` explicitly since the DevOps alignment findings section produces items that belong in the plan but have no category today.

## Continuous Delivery alignment findings

### 1. `build-once-promote-many` is only implicit; not stated as a rule

- **CD practice:** Build once, promote the same binary through environments. Farley & Humble, *Continuous Delivery*, ch. 5 "Anatomy of the Deployment Pipeline" — the commit stage produces the artifact; downstream stages consume the **same** artifact, never rebuild.
- **Source:** Farley & Humble, *Continuous Delivery*.
- **Rule in the agent:** Silent. The rubric discusses reversibility ordering (lines 199–220) and ties together artifact-push → tag → release, but it never explicitly forbids rebuilding. The auditor cannot detect an action named `build-image` that is called in a promote-to-staging job, which is the most common CD violation in the wild.
- **What's off:** Without an explicit rule, the auditor will not flag actions that re-derive an artifact (rebuild image, regenerate tarball) from a SHA downstream of the commit stage. A team could add `build-and-release-staging` with Docker build steps inside a promote workflow, and the rubric as written gives the auditor no hook to object.
- **Proposed change:** Add a new bullet under "DevOps alignment" (after the `"Dead" outputs` block, around line 74): `"**Build-once-promote-many** — flag any action whose name or `runs:` block implies rebuilding an artifact past the commit stage (e.g. `build-image` called from a promote/deploy workflow). Promote actions must consume an existing artifact reference (image digest, tag, URL), not rebuild from source. Cite Farley & Humble ch. 5."`

### 2. `Deployment` definition is enforced only for naming, not for input/output design

- **CD practice:** A deployment puts a build onto an environment with a persistent target reachable by consumers.
- **Source:** Farley, *Modern Software Engineering* ch. 12; Farley & Humble, *Continuous Delivery* ch. 1.
- **Rule in the agent (line 295):** `"do not call something 'deploy' unless it actually deploys to an environment (persistent target, reachable by consumers) per Farley's definition. 'docker compose up' on a CI runner is a test-harness spin-up, not a deployment."` This is good — but it is **only** applied as a naming rule. The rubric has nothing to say about whether an action named `deploy-*` actually carries the inputs a deployment needs (`environment`, `target`, `service-name`, `image-url`, health-check).
- **What's off:** A `deploy-to-cloud-run` action that accepts `image-url` but no `service-name` and no `environment` still fails Farley's definition — it deploys, but the deployment is not *traceable* to a specific service × environment pair. The naming passes because "deploy" is used honestly, but the input contract does not enforce the concept.
- **Proposed change:** Under "Inputs and outputs" (line 61), add: `"For actions named `deploy-*`: their required inputs must include both an environment identifier (`environment` or equivalent) and a service identifier (`service-name`, `app-name`, etc.), plus the artifact reference. A deploy action without both is a naming-vs-contract mismatch (the name promises a deployment; the contract only models an artifact push)."`

### 3. `fast feedback` is cited in spirit but never operationalised

- **CD practice:** Fail fast, on the cheapest stage that can detect the failure.
- **Source:** Farley & Humble, *Continuous Delivery* ch. 4 "Testing Strategy".
- **Rule in the agent:** Silent. The agent's "idempotence" rule (lines 221–230) is adjacent but different — idempotence is about rerun safety, not about failing on cheap checks early.
- **What's off:** The auditor has no rule that would flag an action which defers a cheap precondition check to a later, slower step. Example: `create-github-release` that does `gh release create` (network call, rate-limited) *before* validating the release notes template are non-empty — fixable, but the auditor as written has no reason to notice.
- **Proposed change:** Under "Error handling / idempotence" (line 75), expand to include: `"**Fail-fast on cheap preconditions.** Input validation, format checks, and reachability probes must happen *before* any API call, docker build, or external side effect. Flag actions whose first side-effecting step can fail on a precondition the action could have validated in a prior, side-effect-free step."`

## DORA / SRE / Twelve-Factor / Marketplace alignment findings

### DORA — four key metrics

- **Practice:** DORA identifies deployment frequency, lead time, change-failure rate, and MTTR as the load-bearing metrics.
- **Source:** *Accelerate* (Forsgren, Humble, Kim); DORA annual State of DevOps reports.
- **Rule in the agent:** Silent. The auditor does not once mention these four metrics, even though consolidation/naming findings directly influence MTTR (smaller primitives are easier to debug) and change-failure rate (idempotence protects against rerun-induced failures).
- **What's off:** Without an explicit DORA hook, the auditor can't explain *why* a given finding matters beyond "violates best practice". Findings that reduce a team's MTTR (e.g. "this composite hides 6 steps — a failure in step 3 requires opening `action.yml` to understand, lengthening MTTR") go un-quantified.
- **Proposed change:** Add a short DORA paragraph to the "DevOps alignment" preamble (after line 56): `"Where possible, link each finding to the DORA metric it moves: composite opacity → MTTR; missing idempotence → change-failure rate; missing primitive-level reusability → lead time. This is for the author's sensemaking; it is not a required field on every finding."`

### SRE — error budgets and graceful degradation

- **Practice:** Actions that run as part of a pipeline should emit machine-parseable status (`outputs.status`, `outputs.failure-reason`) so downstream steps can make policy decisions (e.g. "fail the deploy but leave the tag in place for investigation").
- **Source:** *Site Reliability Engineering* (Beyer, Jones, Petoff, Murphy), ch. 4 "Service Level Objectives"; ch. 11 "Being On-Call".
- **Rule in the agent (line 77):** `"flag actions that don't produce useful logs or step summaries when they do significant work."` — this is half the story. Logs help humans; structured outputs help pipelines.
- **What's off:** The rule only asks for human-readable output (logs, step summaries). It does not ask for machine-parseable failure surfaces that would let a caller graceful-degrade.
- **Proposed change:** Expand line 77 to: `"**Observability — dual surface.** For human review: useful logs and step summaries when the action does significant work. For downstream pipeline decisions: where an action can fail in a recoverable way, expose a structured failure reason as an output (e.g. `status`, `failure-reason`) rather than only exiting non-zero. Flag actions that use `exit 1` for recoverable conditions a caller might want to branch on."`

### Twelve-Factor — Factor V (build/release/run separation)

- **Practice:** Factor V mandates strict separation of build (code → artifact), release (artifact + config → release), run (execute release). Each stage has its own failure surface; mixing them is an architectural smell.
- **Source:** [The Twelve-Factor App](https://12factor.net/build-release-run), Factor V.
- **Rule in the agent:** Partial. The agent's "separation of concerns" table (lines 164–172) maps closely to Factor V but is never explicitly tied to it, and the rubric lists "artifact type & tagging" as a single concern when Factor V would split "tag with a release version" (release stage) from "build an artifact" (build stage).
- **What's off:** `build-docker-image` currently accepts `component-version` and tags with `v{component-version}-dev.{build-number}` inside the build step (lines 82–89 of that action.yml). That's a Factor V violation: the build step is encoding release-stage information (version tagging). The auditor's concern table doesn't currently make that specific split visible.
- **Proposed change:** Amend the concerns table (lines 164–172) to split `"Artifact type & tagging"` into two rows: `"Artifact construction"` (Factor V build) and `"Artifact release tagging"` (Factor V release). Cite Factor V in the section header. Example primitives column updates accordingly.

### Marketplace — input naming conventions

- **Practice:** GitHub Actions Marketplace's most-starred actions converge on a small vocabulary: `token`, `ref`, `sha`, `repository`, `path`, `working-directory`, `environment`. Custom names (`github-token`, `commit-sha`, `repo`) are tolerated but read as mild ad-hocness.
- **Source:** GitHub Actions Marketplace conventions (actions/checkout, actions/setup-node, actions/upload-artifact input schemas).
- **Rule in the agent (line 61):** `"names should use DevOps-standard terms (`image-url`, `commit-sha`, `tag`, `version`, `environment`, `status`)."` This is good but inconsistent: actions/checkout uses `token`, not `github-token`; uses `repository`, not `repo`; uses `ref`, not `commit-sha`. The agent privileges a slightly different vocabulary.
- **What's off:** The agent will flag `repo:` as non-standard but the reference canon (`actions/checkout@v4`) uses `repository:`. Sampled actions in this repo actually use `repo:` (see `resolve-commit`, `ensure-tag-exists`, `resolve-tag-from-sha`, `resolve-github-prerelease-tag`) — which means the rubric, taken strictly, would flag every one of them. That's a lot of signal for a nit.
- **Proposed change:** At line 61, replace `"names should use DevOps-standard terms"` with an explicit reference list: `"Input names should match `actions/checkout` / `actions/setup-*` conventions where applicable (`token`, `ref`, `repository`, `path`, `working-directory`), and use DevOps-standard terms (`image-url`, `tag`, `version`, `environment`, `status`) elsewhere. `commit-sha` (over `sha`) is acceptable when disambiguation is needed. `repo` (short for `repository`) is permitted as a local convention but should be flagged for consistency — either the whole repo uses `repo` or the whole repo uses `repository`."`

## Portability findings

### Jenkins

- **What translates cleanly:** The primitives-first principle translates directly to Jenkins shared-library `vars/*.groovy` + pipeline scripts. The reversibility-ordered ordering rule is platform-agnostic. The idempotence rule is platform-agnostic.
- **What breaks:**
  - The `composite` vs. primitive distinction is GitHub-Actions-specific terminology. Jenkins has no "composite" — it has shared-library steps that wrap other shared-library steps. The auditor's rule "composites are acceptable only as thin sugar over primitives" (line 134) needs a platform-abstracted phrasing ("a pipeline helper that wraps other helpers must remain optional sugar").
  - `GITHUB_STEP_SUMMARY` (referenced in `resolve-tag-from-sha`, `create-and-push-tag`, and elsewhere) has no Jenkins equivalent. Students porting would silently lose step summaries. The auditor has no rule that flags `GITHUB_STEP_SUMMARY` usage as Tier-3-ish, even though it is.
- **Needed changes:** Add `GITHUB_STEP_SUMMARY` and `GITHUB_OUTPUT` to the list of universal-on-Actions-but-Tier-3-elsewhere env vars (line 128 currently lists `GITHUB_WORKSPACE`, `GITHUB_SHA`, `GITHUB_REF` as universal and only pulls out `GITHUB_RUN_ID`). On Jenkins, the output-passing mechanism between steps is shared-library return values or `env.*`, not `$GITHUB_OUTPUT`. The auditor should say: step summary is Tier-2-compatible (equivalent exists on most platforms — GitLab CI job reports, Jenkins `publishHTML`) but the *invocation* is platform-specific.

### GitLab CI

- **What translates cleanly:** Tier 2 actions that operate on git (`create-and-push-tag`, `ensure-tag-exists`, `bump-patch-versions`, `resolve-tag-from-sha`) translate directly to GitLab CI `before_script`/`script` blocks. `include:` + `extends:` is the equivalent of primitives + thin composite.
- **What breaks:**
  - The `https://x-access-token:${TOKEN}@github.com/...` URL pattern (used in `resolve-commit` line 46, `ensure-tag-exists` line 33, `resolve-tag-from-sha` line 38) **hardcodes the git host**. A student porting to GitLab would have to edit the URL string inside every Tier 2 action. The auditor's rule that Tier 2 is portable (line 101) is not enforced by a sub-rule that says "the git host must be parameterised, not hardcoded".
  - Tier 3 renames: `create-github-release` → `create-gitlab-release` works. But `has-update-since-last-github-workflow-run` → GitLab equivalent is `has-update-since-last-gitlab-pipeline-run`, which is not merely a prefix swap — the underlying concept (workflow run vs. pipeline) has a different shape (GitLab pipelines contain jobs, not runs).
- **Needed changes:**
  - Add a sub-rule under Tier 2: `"Tier 2 actions must parameterise the git host, not hardcode github.com. Accept a `git-host` input (default: `github.com`) or derive it from `repo` when given in URL form."`
  - Weaken the portability claim in lines 180–181 and 93: `"a student could mechanically rename `create-github-release` → `create-gitlab-release` and keep the rest unchanged"` is too strong when the Tier 3 concept itself has shape differences across platforms. Change to `"a student can mechanically rename Tier 3 actions where the target platform has a 1:1 concept. When concepts differ in shape (workflow-run vs. pipeline-job), the rename is the first step; the inputs/outputs may also shift."`

### Azure Pipelines

- **What translates cleanly:** Primitives-first principle (→ Azure Pipelines templates). Reversibility ordering. Idempotence. DevOps-standard input names.
- **What breaks:**
  - Azure Pipelines has no concept equivalent to `$GITHUB_OUTPUT`. Actions communicate via `##vso[task.setvariable]` logging commands, which are shell-printed, not file-written. A rule that says "use `$GITHUB_OUTPUT` to pass outputs" (implicit in the rubric via sampled actions) will not survive the port.
  - Azure DevOps "Releases" are a first-class concept distinct from "Builds" — closer to Farley's deploy/release distinction than GitHub's. A student porting might find the Tier 3 category collapses (GitHub's Release → Azure's Release) but discover that the Azure Release concept implies an environment/stage, which a GitHub Release does not. The auditor's Tier 3 list doesn't warn about this.
- **Needed changes:** Add a short note to the Tier 3 discussion (around line 102): `"Note: the Tier 3 concept may not have identical shape on other platforms. A `create-github-release` ports to Azure DevOps "Release" but Azure Releases model deployment stages, which GitHub Releases do not. Students should treat Tier 3 renames as 'start here', not 'done'."`

### CircleCI

- **What translates cleanly:** Primitives → CircleCI *commands*; composites → CircleCI *orbs*. Reversibility ordering. Idempotence.
- **What breaks:**
  - CircleCI orbs have a stricter namespacing (`namespace/orb-name`) that does not map to GitHub Actions' `owner/repo/action-name@ref`. A rule like "optivem/actions/create-github-release@v1" translates to `optivem/release-orb/create-release@1.0.0` — not a mechanical rename.
  - CircleCI has no native step-summary analogue. Step-summary usage in the rubric should be marked as Tier 2.5.
- **Needed changes:** Already covered above; no CircleCI-specific rule beyond the step-summary note.

### Buildkite

- **What translates cleanly:** Primitives-first principle (→ Buildkite plugins). Reversibility ordering. Idempotence.
- **What breaks:**
  - Buildkite plugins are versioned by git ref, not by release tag — the `@v1` convention in action calls is slightly different in spirit but looks identical on the surface. Minor, worth noting.
  - Buildkite has strong conventions around *agents* (which runner picks up which job). The auditor has nothing to say about agent targeting, which would become a real concern if the rubric evolves to cover deployment actions seriously.
- **Needed changes:** None urgent. Add to the Tier discussion (around line 90) that "the runner-selection axis (which machine executes the action) is a dimension beyond the tier system — handle it at the pipeline level, not the action level."

### Cross-platform summary

Five platform findings, two of them load-bearing (git host parameterisation; softening the "mechanical rename" claim for Tier 3 concept mismatch). The rest are smaller notes. The rubric's overall portability thesis holds — but the naming tiers are not enough on their own; the **implementations must also keep the git host and the output-passing mechanism abstracted**, and the rubric doesn't currently say so.

## Practicality findings

### 1. Verb list in line 290 drifts from repo reality

- **Issue:** The "established set" of verbs listed is both incomplete (missing `get-`, `run-`, `map-`, `ensure-`, `commit-`) and bloated with verbs that do not appear in the repo (`promote-`, `approve-`, `reject-`, `validate-`, `simulate-`).
- **Quote (line 290):** `"Draw from the established set already in use in this repo (currently: `check-`, `resolve-`, `generate-`, `has-`, `summarize-`, `setup-`, `deploy-`, `promote-`, `build-`, `push-`, `tag-`, `cleanup-`, `create-`, `bump-`, `read-`, `find-`, `wait-for-`, `approve-`, `reject-`, `validate-`, `simulate-`, `compose-`, `trigger-`)"`
- **Why it's a problem:** The agent claims this list is "in use in this repo", but `promote-`, `approve-`, `reject-`, `validate-`, and `simulate-` are not in the repo (enumerated `ls -d */ | cut -d- -f1 | sort -u`: build, bump, check, cleanup, commit, compose, create, deploy, ensure, find, generate, get, has, map, push, read, resolve, run, setup, summarize, tag, trigger, wait). The list is actually a mix of "present" and "aspirational" verbs presented as observations. It will go stale as soon as an aspirational verb is implemented (making the agent look wrong) or as the repo adds a genuinely new verb (the agent won't notice and will flag it).
- **Proposed change:** Reframe the rule at line 290 as follows: `"The current repo uses the verbs in USED_VERBS.txt (a companion file updated on each audit). The audited set is not a closed list — if an action would be better named with a verb outside this set, prefer clarity over conformance and document the new verb in the report." — and either (a) drop the inline list (making the rule prose-only) or (b) factor it into a companion file the audit regenerates. Recommended: drop the inline list; keep only the principle.`

### 2. "Misleading name" criterion relies entirely on Farley's deployment definition

- **Issue:** Line 295 gives one excellent example of a misleading name (calling `docker compose up` "deploy"), but the rubric generalises to "must not be misleading vs. mainstream DevOps/CD terminology" with no other examples.
- **Quote (line 295):** `"The name must not be misleading vs. mainstream DevOps/CD terminology."` — followed by the `deploy` / `release` examples only.
- **Why it's a problem:** The auditor will be sharp-eyed about `deploy-` violations but will not know what to do with, e.g., an action named `build-*` that doesn't build (just downloads a prebuilt binary), or `validate-*` that logs a warning without exiting non-zero, or `cleanup-*` that scans without deleting. Line 295 is a well-defined rule for one case; the surrounding framing overpromises coverage.
- **Proposed change:** Add two more example classes to line 295: `"Similarly: an action named `build-*` must produce an artifact (not merely download one); `validate-*` must fail the step on invalid input (not warn-and-continue); `cleanup-*` must remove things (not merely list candidates — that's `find-*` or `list-*`). When a verb's CD-meaning is load-bearing, the action's `runs:` block must honour it."`

### 3. `setup-*` actions are uncategorised

- **Issue:** The naming tier system (Tier 1/2/3) classifies actions by *portability of the concept*. `setup-dotnet`, `setup-java-gradle`, `setup-node` are all wrappers over Marketplace actions (`actions/setup-java@v5`, `gradle/actions/setup-gradle@v5`). Their portability story is different from either Tier 1 or Tier 3 — they are "portable in principle, but the *implementation* leans on Marketplace".
- **Quote (line 100):** `"Tier 1 — fully generic (any CI, any VCS, any host). No prefix. Examples: `build-image`, `push-image`, `wait-for-approval`, `bump-version`, `run-tests`, `deploy-service`, `validate-config`."`
- **Why it's a problem:** `setup-node` currently uses `actions/setup-node@v5` under the hood, which is GitHub-Actions-only. A student porting to GitLab CI would have to rewrite it entirely (use a Docker image or `asdf`-style installer). The name `setup-node` looks Tier 1 but the implementation is Tier 3-ish — a classic "honest name, deceptive implementation" case the rubric does not yet cover.
- **Proposed change:** Add a note under Tier 1 (line 100): `"Tier 1 includes actions whose *concept* is universal. Some Tier 1 actions (e.g. `setup-node`, `setup-java`) are implemented in this repo via Marketplace setup actions, which are GitHub-Actions-specific under the hood. That is acceptable — the *name* remains Tier 1 because the concept ports — but the rubric should flag when the *implementation* is platform-specific beyond what the name suggests, so a porting student knows which internals to rewrite."`

### 4. "Conservative" rule is too thin to arbitrate

- **Issue:** Step 5 of Process (line 303) tells the auditor: `"A similar name is not proof of duplication — read the steps. If two actions look like duplicates but the behavior differs in a meaningful way, say so and do not flag them."` No test, no threshold, no tie-breaker.
- **Quote (line 303):** `"Be conservative. A similar name is not proof of duplication — read the steps."`
- **Why it's a problem:** `resolve-docker-images` and `resolve-docker-image-digests` are two actions with similar names. The auditor may or may not flag them as duplicates depending on how carefully it reads the steps. "Be conservative" alone does not tell the auditor whether to default to flag-with-evidence or default to no-flag-unless-proven.
- **Proposed change:** Rewrite line 303 as: `"Default to 'no-flag unless proven'. Flag two actions as duplicates only if: (a) their `runs:` block produces the same side effect on the same target, AND (b) a caller could swap one for the other without changing inputs/outputs. Similar names without both are not duplicates — say so in the report to explain the absence of a finding."`

### 5. Inventory table loses inputs/outputs detail

- **Issue:** The Inventory section (line 315) requires one row per action with `dir | name | inputs | outputs | one-line behavior | call sites`. For an action with 15 inputs (e.g. `deploy-to-cloud-run`), "inputs" in a single table cell becomes unreadable.
- **Quote (line 315):** `"Table: `dir | name | inputs | outputs | one-line behavior | call sites (shop + gh-optivem)`"`
- **Why it's a problem:** The table will either cram input lists into a cell that wraps ugly, or will show only counts, losing the detail the audit needs.
- **Proposed change:** Change the schema to `"dir | name | #inputs | #outputs | one-line behavior | call sites"`, and produce a separate `### Per-action detail` subsection after the Inventory with one sub-block per action (input-names list, output-names list, one-line behavior, call sites).

## Additional findings

### A1. Self-describing mode: `backwards_compatible` option ergonomics

- **Issue:** The only caller-facing option is a boolean `backwards_compatible`, defaulting false. But the rubric's most common use case is probably "audit this repo and tell me what's broken now" (backwards_compatible=false). The default is correct but undocumented at the call site — the user has to read the agent file to know what they're getting.
- **Quote (line 15):** `"**false** (default): renames, removals, input/output removals, and merging two actions into one are all fair game. Consumers will be updated separately."`
- **Why it matters:** A user invoking the auditor casually will get breaking-change recommendations by default. The report header does surface the mode (line 310), but the user has already received the recommendations by then.
- **Proposed change:** In the report Header (lines 309–312), add: `"**Mode:** backwards_compatible=false — breaking changes are in scope. To restrict to non-breaking changes, re-run with `backwards_compatible=true`."` — and do the same in the plan file header (line 372). Minor polish; the verbosity is worth it.

### A2. No rule about the `action.yml` `branding:` field

- **Issue:** Several actions in the repo have `branding:` fields (icon, color) while others do not (e.g. `run-docker-compose`, `setup-java-gradle`). The auditor has no opinion.
- **Quote:** No applicable rule exists.
- **Why it matters:** `branding:` is optional but becomes relevant if the actions are ever published to the Marketplace. Teaching-repo actions in a `.github` org won't need branding; published Marketplace actions must have it. The rubric is silent on which regime this repo is aiming for.
- **Proposed change:** Add a short bullet under "Observability / Marketplace" (around line 78): `"`branding:` is optional for internal actions but required by the Marketplace publishing flow. If the repo's intent is to publish, flag actions missing `branding:`; if the intent is internal-only, the field is a stylistic choice. State the repo's publication intent once in the report header so all `branding:` findings are consistent."`

### A3. Windows/PowerShell vs. bash shell inconsistency

- **Issue:** Some actions use `shell: bash`, others `shell: pwsh` (e.g. `create-github-release`, `tag-docker-images`, `cleanup-prereleases`, `commit-files-via-github-contents-api`). The rubric does not care about this, but a team that sets `runs-on: ubuntu-latest` (no PowerShell by default) will silently find `pwsh`-using actions unusable.
- **Quote:** No applicable rule exists.
- **Why it matters:** PowerShell is available on GitHub-hosted runners but may not be on self-hosted Linux runners. An action that requires `pwsh` carries a runner constraint that is invisible at the call site. Porting to Jenkins/GitLab CI also requires a PowerShell environment. This is a Tier 2 → Tier 2.5 leak that the rubric does not cover.
- **Proposed change:** Under "DevOps alignment" (after line 77), add: `"**Shell portability.** Prefer `shell: bash` for actions that could run on any POSIX-capable runner. Flag `shell: pwsh` actions unless the logic genuinely benefits from PowerShell (e.g. complex object manipulation). If an action uses `pwsh`, its description should state the runner constraint explicitly so callers don't hit runtime failures on PowerShell-less runners."`

### A4. No security/supply-chain dimension

- **Issue:** The rubric is silent on action-pinning (`actions/setup-java@v5` — SHA-pinned vs. tag-pinned), on least-privilege token scoping (`permissions:` at the workflow level), and on checkout-with-token leakage patterns.
- **Quote (line 76):** `"flag actions that hardcode tokens, require unusual environment shapes, or bypass `GITHUB_TOKEN` conventions."` — a start, but narrow.
- **Why it matters:** Supply-chain risks are a first-class DevOps concern (SLSA, in-toto, GitHub's hardening guide). The auditor would not flag an action that depends on `some-community-action@main` (a moving ref — a classic supply-chain smell).
- **Proposed change:** Add a new bullet in "DevOps alignment" (after line 76): `"**Supply chain.** Flag actions whose `uses:` references point at a mutable ref (`@main`, `@master`, `@latest`, or any branch name), or at an action from an untrusted author. Pinning to a major tag (`@v4`) is acceptable for Marketplace-trusted actions; pinning to a SHA is preferred. Cite GitHub's hardening guide for GitHub Actions."`

### A5. No teaching-value dimension

- **Issue:** The agent knows the repo is a teaching vehicle (line 85: `"The repo is a teaching vehicle that evolves over time"`) but does not have a lens for whether a finding would confuse students vs. clarify a concept. Some findings that are technically correct may be pedagogically harmful (e.g. consolidating two clearly-named primitives into one because they are similar — saves lines of code but costs teaching clarity).
- **Quote (line 85):** `"The repo is a teaching vehicle that evolves over time. Some things that look incomplete today are deliberate stepping stones, not gaps."`
- **Why it matters:** The stepping-stone exemptions cover the known cases (Docker Compose, `:latest`, author-determined environments) but the general principle isn't stated. A consolidation finding that merges `check-` and `has-` primitives might be technically right but flatten a pedagogically-important distinction (check = assert-and-fail, has = return-boolean).
- **Proposed change:** Add to the "Forward-looking context" section (around line 85): `"**Teaching-clarity override.** If a proposed consolidation would flatten a distinction that the pedagogy relies on (e.g. `check-*` = assert/fail vs. `has-*` = boolean-return, or `generate-*` = compute vs. `compose-*` = assemble), prefer to leave the primitives separate and note the pedagogical role in the finding. A finding that is 'correct by the rubric but bad for the course' must say so, not merge silently."`

### A6. `gh api` rate-limit handling is a first-class operational concern but only mentioned in passing

- **Issue:** The rubric mentions `gh api` rate limits at line 113 (`"No rate limits: git operations don't count toward it. Matters for cleanup jobs and loops."`) but has no audit rule for checking that `gh api`-using actions handle rate limits gracefully (retry, backoff, `rate_limit_threshold` input).
- **Quote (line 113):** `"No rate limits: GitHub API has 5000 req/hour per authenticated user; git operations don't count toward it. Matters for cleanup jobs and loops."`
- **Why it matters:** Several actions in the repo (`cleanup-prereleases`, `cleanup-github-deployments`, `trigger-and-wait-for-github-workflow`) use `gh api` in loops. Two of them already carry a `rate-limit-threshold` input. One — `resolve-github-prerelease-tag` — does not, even though it calls `gh api "repos/$REPO/releases?per_page=100"` which could be expensive in a paginated caller loop.
- **Proposed change:** Add to "Error handling / idempotence" (around line 75): `"**Rate-limit awareness for `gh api` actions.** Flag any action that uses `gh api` in a loop (iterating over items, following pagination, or repeatedly called from a caller loop) and does not accept a `rate-limit-threshold` / `poll-interval` input and back off when nearing the limit. Point callers at `gh api rate_limit`. Existing actions `cleanup-prereleases` and `trigger-and-wait-for-github-workflow` are the reference pattern."`

## Self-edits

None.

(I considered adding a `security` dimension to the reviewer's rubric since the auditor has no supply-chain coverage — but the reviewer already says in the `Review dimensions` preamble: *"You are not restricted to these five dimensions ... put such findings under the Additional findings section"*. The supply-chain finding belongs in Additional findings, as it has been placed. No amendment to the reviewer's own rubric is warranted — the open-ended-pass clause already covers it.)

## Recommended edits

Ordered by impact. Highest-impact first.

1. **Output section — enumerate the DevOps alignment subsections.** *Location:* lines 342–349 (Output → DevOps alignment findings). *Change:* Replace `"Group by action or by theme"` with an explicit subsection list: `"Subsections (use in this order): Tool-agnostic composition | Separation of concerns | Composite opacity | Prefer git over gh api | Composition ordering | Idempotence | Other"`. *Reason:* Resolves internal-consistency findings 1 and 3.

2. **Usage findings & Inventory — include all three consumer repos.** *Location:* line 315 (Inventory table header) and line 318 (Usage findings). *Change:* Replace every occurrence of "`shop + gh-optivem`" with "`shop + gh-optivem + optivem-testing`"; update the plan-file template at line 380 similarly. *Reason:* Resolves internal-consistency finding 2 and prevents false dead-code findings per line 34.

3. **Add a `build-once-promote-many` rule.** *Location:* under "DevOps alignment" (after line 74). *Change:* Add the bullet given in CD finding 1. *Reason:* Closes the largest CD-alignment gap — the auditor currently cannot flag artifact-rebuild violations.

4. **Parameterise the git host in Tier 2 actions.** *Location:* after line 101 (Tier 2 definition). *Change:* Add: `"Tier 2 actions must parameterise the git host, not hardcode `github.com`. Accept a `git-host` input (default: `github.com`) or derive it from `repo` when given in URL form. Actions that hardcode `https://x-access-token:${TOKEN}@github.com/...` in the URL break Tier 2's portability claim."` *Reason:* Resolves portability finding (GitLab CI; applies to all non-GitHub git hosts).

5. **Soften the "mechanical rename" Tier 3 claim.** *Location:* lines 93 (Portability dimension, reviewer's own copy — not applicable) and 180–181 (Separation of concerns → payoff). *Change:* Replace "touches only the release-record primitive" with "touches primarily the release-record primitive, possibly with input/output shape differences if the target platform models the concept differently (e.g. Azure Releases include deployment stages that GitHub Releases do not)." *Reason:* Resolves portability finding (Azure Pipelines, GitLab CI).

6. **Extend the `plan-file` category enumeration.** *Location:* line 384. *Change:* `"Category: naming | duplicate | consolidation | dead-code | dead-input | dead-output | devops-alignment"`. *Reason:* Resolves internal-consistency finding 4.

7. **Fix the verb enumeration.** *Location:* line 290. *Change:* Drop the inline list entirely. Keep the prose principle (`"verb-first prefix. Use the verb that best describes what the action actually does, per mainstream DevOps/CD vocabulary. If a novel verb is introduced, call it out in the report's Naming section."`). *Reason:* Resolves practicality finding 1; the inline list is stale as soon as the repo changes.

8. **Tier 1 note for `setup-*`-style actions.** *Location:* after line 100. *Change:* Add the note given in practicality finding 3. *Reason:* Resolves practicality finding 3 and clarifies the Tier 1 boundary.

9. **Shell-portability rule.** *Location:* after line 77. *Change:* Add the bullet given in additional finding A3. *Reason:* Resolves A3; improves portability audit coverage.

10. **Supply-chain bullet.** *Location:* after line 76. *Change:* Add the bullet given in additional finding A4. *Reason:* Resolves A4; closes a significant DevOps-audit gap.

11. **Observability — dual surface.** *Location:* line 77. *Change:* Expand per DORA/SRE finding 2. *Reason:* Resolves DORA/SRE alignment finding 2; small but correct.

12. **Marketplace input-name alignment.** *Location:* line 61. *Change:* Reference `actions/checkout`/`actions/setup-*` conventions explicitly, and say how to handle `repo` vs. `repository`. *Reason:* Resolves Marketplace-alignment finding 1.

13. **"Misleading name" — add examples.** *Location:* line 295. *Change:* Add the `build-*` / `validate-*` / `cleanup-*` examples per practicality finding 2. *Reason:* Generalises the existing `deploy-*` rule.

14. **Fail-fast preconditions.** *Location:* line 75. *Change:* Add the bullet per CD finding 3. *Reason:* Resolves CD alignment finding 3.

15. **Concerns table — split artifact construction from release tagging.** *Location:* lines 164–172. *Change:* Add a row separating Factor V build from Factor V release per Twelve-Factor finding. *Reason:* Resolves Factor V alignment finding; makes the auditor's lens match the `build-docker-image` concern mix it should already be catching.

16. **Teaching-clarity override.** *Location:* after line 85 (Forward-looking context). *Change:* Add the paragraph per additional finding A5. *Reason:* Resolves A5; prevents pedagogically-harmful consolidation findings.

17. **Rate-limit awareness for `gh api`.** *Location:* after line 75. *Change:* Add the bullet per additional finding A6. *Reason:* Resolves A6; operationalises what is currently a side-note in line 113.

18. **Inventory table format.** *Location:* line 315. *Change:* Replace single table with count-summary table + per-action detail subsection. *Reason:* Resolves practicality finding 5.

19. **`backwards_compatible` disclosure in header.** *Location:* lines 309–312 and 372. *Change:* Add a one-line mode disclosure to the report header and plan header. *Reason:* Resolves additional finding A1; a minor polish.

20. **`branding:` field policy.** *Location:* around line 78. *Change:* Add the Marketplace-intent disclosure and `branding:` rule per additional finding A2. *Reason:* Resolves A2; minor, but currently undefined.

21. **"Be conservative" — replace with concrete test.** *Location:* line 303. *Change:* Replace with the two-condition test per practicality finding 4. *Reason:* Resolves practicality finding 4; turns a vague instruction into an adjudicable one.
