# actions-auditor-reviewer report

## Header

- `depth`: standard
- Subject files:
  - `.claude/agents/actions-auditor.md` (276 lines)
  - `.claude/agents/docs/devops-rubric.md` (502 lines)
- Subject length: 778 lines across the two primary subjects (plus 190 lines of reviewer self-definition and 98 lines of review-dimensions read for context)
- Date: 2026-04-22

## Summary

The auditor/rubric pair is largely sound. The mainstream-first principle is carried consistently from the rubric's top-of-file into the auditor's preamble, the Parameter findings vocabulary is rigorous, and the process gating (`scope=naming`, `backwards_compatible=true`) is fully spelled out. The rubric has also absorbed substantial recent work (v6–v8 of §1.5 SemVer, §1.6 Docker, §1.7 DORA, §1.8 thin-wrapper deletion) without losing structure. The three highest-impact issues I found:

1. **Stale action names embedded as rubric examples.** The rubric still cites `create-github-release`, `setup-dotnet`, `setup-java-gradle`, `setup-node` as if they were current repo actions (across §3, §5, §6, §7), but the repo no longer contains them — §1.8 explicitly documents their deletion in favour of `softprops/action-gh-release` and `actions/setup-*`. Downstream examples in §7 and §6 now reference actions that don't exist, which will confuse future auditors trying to ground the rubric against the repo.
2. **Orphan rule code in Parameter findings.** `actions-auditor.md:156` lists `name-mainstream-convention` as a rule keyword, but Process step 3 at `actions-auditor.md:77` introduces it inline only as part of a paragraph — not as a clearly numbered rule. Several sibling rules (`output-name-verb-led`, `type-shape-ambiguous`) have the same soft-introduction problem. Acceptable but easy to fix.
3. **`name-mainstream-convention` and `name-misleading` overlap without a tie-breaker.** The same parameter issue (e.g. `sha` vs. `commit-sha`) arguably qualifies under either — the rubric calls out bare `sha:` as `name-mainstream-convention` (devops-rubric.md:33) but the rule definition at `actions-auditor.md:156` is phrased as "name conflicts with mainstream precedent", which also fits `name-misleading`. No tie-breaker is specified.

Counts: internal inconsistencies = 4 | CD misalignments = 2 | DORA/SRE/12-Factor/Marketplace gaps = 3 | portability issues = 3 | practicality issues = 5 | additional findings = 4

## Internal consistency findings

### Finding 1 — Stale action-name examples in rubric examples

**Issue:** The rubric's examples reference actions that no longer exist in the repo after the §1.8 thin-wrapper deletion.

**Quote A** — `devops-rubric.md:349`:
> "If prerelease creation is decomposed into `compose-prerelease-version` → `tag-<artifact-type>` → `create-github-release`, adding a new artifact type means adding one new tagging primitive"

**Quote B** — `devops-rubric.md:200–202` (§1.8):
> "`setup-node` (setup + `npm ci` conflated) | `actions/setup-node` + `npm ci` | … `create-github-release` (thin `gh release create/edit`) | `softprops/action-gh-release` | `@v2`"

**Resolution:** Either (a) the rubric's §3, §5, §6, §7 examples should be updated to reflect that `create-github-release` has been replaced by `softprops/action-gh-release@v2` and `setup-*` by direct `actions/setup-*@v5` calls; or (b) the §3.1 Tier-3 example table at `devops-rubric.md:257` should annotate `create-github-release` as "example only — this repo now delegates to `softprops/action-gh-release@v2`". (a) is cleaner. The §7.3 "Concrete example" at `devops-rubric.md:449–474` correctly uses `docker/build-push-action@v6` but still includes `create-github-release` as a local action — revise to either the mainstream replacement or the `optivem/actions/publish-tag@v1` sibling that still exists.

### Finding 2 — Orphan rule codes in Parameter findings

**Issue:** The auditor's Parameter-findings enumeration lists rule codes that are only soft-introduced in Process step 3, and one (`output-name-verb-led`) is introduced but never used as a category marker in Process.

**Quote A** — `actions-auditor.md:156` (the list):
> "- `name-mainstream-convention` — parameter name conflicts with mainstream `actions/*` precedent …
> - `output-name-verb-led` — output names should be noun-based, not verb-led."

**Quote B** — `actions-auditor.md:77` (the introduction):
> "… (`name-kebab-case` / `name-mainstream-convention` / `name-misleading` / `output-name-verb-led`)**.** kebab-case; matches mainstream `actions/checkout` / `actions/setup-*` conventions …"

**Resolution:** This is cosmetic — all the codes *are* introduced, but inside parenthesised bullet headers. If the auditor is ever run by a model that parses the Process section mechanically to extract the rule vocabulary, it may miss them. Reformat Process step 3 so each rule code is on its own line with a one-line definition, matching the output list at `actions-auditor.md:153–164`. Keeps the introduction and the list in lockstep.

### Finding 3 — `name-mainstream-convention` vs. `name-misleading` overlap

**Issue:** Bare `sha:` is simultaneously (a) non-mainstream (per `devops-rubric.md:33`, flag as `name-mainstream-convention`) and (b) potentially misleading (`sha` could be a content SHA, tree SHA, or commit SHA). Neither rule claims precedence.

**Quote A** — `devops-rubric.md:33`:
> "Flag bare `sha:` inputs as `name-mainstream-convention` with proposed rename to `commit-sha:`."

**Quote B** — `actions-auditor.md:156`:
> "- `name-misleading` — the name does not honestly describe the value it carries."

**Resolution:** Add a tie-breaker sentence to the auditor's Parameter-findings list: "When a single parameter violates more than one name-family rule, cite them in priority order **mainstream-convention > misleading > kebab-case**, and list each applicable rule on the finding — do not pick one and drop the others." This matches the existing mainstream-first principle and keeps reports honest when two rules both apply.

### Finding 4 — "Mandatory explicit `required:` on inputs" vs. YAML reality

**Issue:** The auditor declares `required-implicit` a violation (`actions-auditor.md:79`: "`required:` must be declared explicitly, not left implicit"), but GitHub's own `action.yml` schema treats missing `required:` as "not required" and widely-used `actions/*` actions omit it for optional inputs. Sample checks in the repo (`compose-prerelease-version/action.yml:4–17`) correctly set `required:` on every input — but the rubric rule is stricter than mainstream and `actions/checkout@v4` itself violates it.

**Quote A** — `actions-auditor.md:79`:
> "For inputs: `required:` must be declared explicitly, not left implicit."

**Quote B** — mainstream-first at `devops-rubric.md:11–22` and the specific reminder at `devops-rubric.md:13`:
> "When mainstream GitHub Actions ecosystem conventions conflict with an internal rubric convention, prefer the mainstream convention."

**Resolution:** This is a debatable call. The rule *is* safer (it forces the author to think about optionality) but it *does* diverge from mainstream. Options: (i) keep the rule and mark it explicitly as "an intentional stricter-than-mainstream rubric rule, accepted because latent empty-string defaults have bitten this repo before"; (ii) soften to "prefer explicit `required:`; flag only when the absence is ambiguous *and* no `default:` is set". I recommend (i) — keep the rule but add a one-line rationale at `actions-auditor.md:79` so the rule doesn't look like accidental drift.

## Continuous Delivery alignment findings

### Finding 1 — "Deployment vs. release" honoured; "release stage = make features available" well-cited

The deploy/release distinction is enforced at `devops-rubric.md:34` (`deploy-*` needs env + service + artifact) and `devops-rubric.md:326–332` (`release-*` / `promote-*` / `publish-*` verb meanings). **Aligned.** No finding.

### Finding 2 — Fast-feedback / small-batch alignment is implicit, not explicit

**CD practice:** Fast feedback (Farley & Humble, *Continuous Delivery* ch. 1, 4, 5).

**Source:** *Continuous Delivery* ch. 4 "Implementing a Deployment Pipeline" — the commit stage must run in ~5 minutes and fail fast.

**Rule in the agent:** Partial — `devops-rubric.md:60` covers the "fail fast" dimension ("Fail-fast on cheap preconditions. Input validation, format checks, and reachability probes must happen *before* any API call"). Silent on the complementary rule: **the commit-stage action set should be lightweight enough to run fast**.

**What's off:** The rubric says a lot about what actions should *not* do (heavy rebuilds, API loops, unbounded retries) but never names the overall target — that the commit-stage pipeline under test must itself finish quickly. Actions like `trigger-and-wait-for-github-workflow` and `wait-for-github-workflow` are correctly flagged as rate-limit-aware (§1.3, §1.4), but there's no guidance on *how long a caller should wait* — the default poll intervals (30s / 120s) are authored, not rubric-constrained.

**Proposed change:** Add to `devops-rubric.md:60` (the fail-fast subsection): "**Fast-feedback sizing.** Actions that block a job's progress (polling, waiting, retrying) must expose a `timeout-seconds` or `max-attempts` input with a default that respects the target commit-stage budget of ~5 minutes per Farley & Humble ch. 4. Flag actions whose default wait-times sum could exceed that budget in common cases." Applies to `wait-for-urls`, `trigger-and-wait-for-github-workflow`, `wait-for-github-workflow`.

### Finding 3 — "Everything in version control" not applied to action pins

**CD practice:** Reproducibility — every deploy traces back to a specific commit (Farley & Humble ch. 2, 5).

**Source:** *Continuous Delivery* ch. 2 "Configuration Management".

**Rule in the agent:** `devops-rubric.md:85` requires pinning `uses:` to a major tag or SHA: "Pinning to a major tag (`@v4`) is acceptable for Marketplace-trusted actions; pinning to a SHA is preferred for untrusted sources."

**What's off:** The rule is already there and cites SLSA L3, but the **rubric itself doesn't require its own examples to follow it**. Multiple examples use `@v4`/`@v5`/`@v6` pinning without saying whether the consumer repo is targeting SLSA L3. If the reader is told to choose, the rubric should give them a default — "SHA-pin all untrusted; major-tag-pin `docker/*`, `actions/*`, `google-github-actions/*` until the repo reaches SLSA L3; then SHA-pin everything."

**Proposed change:** Tighten `devops-rubric.md:85` with an explicit default ladder so the auditor gives consistent advice: "Default pin strategy for this repo: major-tag-pin `actions/*`, `docker/*`, `google-github-actions/*`, `softprops/action-gh-release`; SHA-pin everything else; escalate to SHA-pin-everything when the repo commits to SLSA L3." Makes the audit finding mechanical.

## DORA / SRE / Twelve-Factor / Marketplace alignment findings

### Finding 1 — Twelve-Factor III (config in environment) and the "token-via-env" rule

**Practice:** Twelve-Factor Factor III — config stored in environment; Marketplace convention — auth secrets declared as named inputs.

**Source:** [The Twelve-Factor App §III](https://12factor.net/config); `actions/checkout`, `docker/login-action`, `softprops/action-gh-release` all declare `token` / `github-token` as named inputs.

**Rule in the agent:** `devops-rubric.md:67` — correctly draws the distinction: "this is a **Marketplace / action-interface discoverability** convention, not Twelve-Factor Factor III — Factor III is about config *delivery channel* (env), whereas this rule is about the *declared interface* of a composite, which is `action.yml` inputs."

**What's off:** The distinction is right and well-cited. No finding here except to commend it. One small issue: the same paragraph then references the secret-interpolation example at `devops-rubric.md:70–84`, which *does* invoke Factor III ("bridge input to env, never interpolate into `run:`") without saying so. Call it out.

**Proposed change:** Add one line at `devops-rubric.md:84` (after the example block): "The bridge-via-env pattern aligns with Twelve-Factor III for secret *delivery*; the named-input requirement above is distinct, and addresses *interface declaration*." Keeps the two concerns labelled.

### Finding 2 — DORA metric linkage is vague for MTTR-critical rules

**Practice:** DORA four key metrics — specifically MTTR.

**Source:** *Accelerate* (Forsgren, Humble, Kim), DORA State of DevOps reports.

**Rule in the agent:** `devops-rubric.md:171` (§1.7) — "composite opacity → MTTR; missing idempotence → change-failure rate; missing primitive-level reusability → lead time; rebuilding downstream of commit stage → change-failure rate and lead time."

**What's off:** The linkage table is useful but one-way. The rubric has several MTTR-critical rules that are not linked back to DORA: the bounded-retry rule (§1.3, `devops-rubric.md:62`) is MTTR-critical because an unbounded retry loop turns a 30-second outage into a 30-minute one; the rate-limit awareness rule (§1.3, `devops-rubric.md:61`) is similarly MTTR-critical. Add DORA linkages to these rules so the auditor can cite them.

**Proposed change:** At `devops-rubric.md:62` end-of-paragraph, add: "**DORA linkage — MTTR.** Unbounded retries turn a transient outage into a cascading pipeline wedge; a 30s registry outage escalates to a 30min pipeline outage under flat-interval retry. Linked to SRE ch. 22 (cascading failures)." Makes the rule's DORA/SRE citation self-contained rather than deferred to §1.7.

### Finding 3 — Marketplace convention for `type:` declarations is missing

**Practice:** The Marketplace `action.yml` schema supports an (optional, relatively new) `type:` field on outputs in *Docker/JavaScript* actions, but composite actions do not have it — which the auditor correctly notes at `actions-auditor.md:78`.

**Source:** GitHub's [metadata syntax for GitHub Actions](https://docs.github.com/en/actions/creating-actions/metadata-syntax-for-github-actions).

**Rule in the agent:** `actions-auditor.md:78` — "GitHub composite actions do NOT have a formal `type:` field on inputs or outputs — all values are strings at runtime."

**What's off:** This is correct for composites, but the rubric and auditor do not say what to do if the repo ever adds a JavaScript or Docker action (e.g. a `shared/_test-*` harness promoted to an action). The `type-shape-ambiguous` rule would then partially duplicate the new native `type:` field. The rubric's silence on this is OK for now — the repo is bash-only per README.md:17 — but call it out as a known limitation.

**Proposed change:** Add one line at `actions-auditor.md:78` end-of-bullet: "If this repo ever ships a JavaScript or Docker action, revisit this rule — native `type:` fields there may subsume `type-shape-ambiguous`." Future-proofs the rule.

## Portability findings

### Jenkins

**Translates cleanly:** Tier 1/2 naming scheme, bounded-retry + backoff (§1.3), idempotence (§7), ordering ("cheapest-to-reverse first", §7.1).

**Breaks / GitHub-specific leaks:** §7.3's concrete example (`devops-rubric.md:443–476`) embeds `docker/build-push-action@v6` inline — that's a GitHub Marketplace composite, not available in Jenkins. A Jenkins port needs a pipeline step that wraps `docker buildx build --push` directly. The rubric's §1.6 (Docker build/tag/push) is effectively GitHub-only because it mandates `docker/build-push-action`. Jenkins users would use `docker buildx` with similar flags (`--provenance=max`, `--sbom=true`). The rubric should say "use `docker/build-push-action` on GitHub; on Jenkins/GitLab/Azure/CircleCI/Buildkite, use `docker buildx build --push` with equivalent BuildKit flags." Currently the §1.6 guidance is platform-coupled despite the rubric claiming platform-agnostic intent.

**Tier 3 translation pain:** `create-commit-status`, `get-commit-status` → Jenkins has a GitHub-plugin-based equivalent (`githubNotify`) but the schema differs. `trigger-and-wait-for-github-workflow` → Jenkins has no direct analog; the user would use upstream/downstream job triggers. The rubric at `devops-rubric.md:266` already flags this as "start here, not done" — OK.

### GitLab CI

**Translates cleanly:** Tier 1/2 naming, rate-limit awareness (`glab api` vs. `gh api`), bounded retry, ordering, idempotence.

**Breaks / GitHub-specific leaks:** Same §1.6 issue as Jenkins — `docker/build-push-action` is GitHub-only. GitLab CI has a native `kaniko`/`buildah`/`docker:dind` idiom; the rule as written forces a GitHub-only answer.

**Tier 3 translation:** `check-ghcr-packages-exist` → on GitLab this maps to the Container Registry API (`/projects/:id/registry/repositories`). The tier scheme handles it (rename `ghcr` → `gitlab-registry`), but the input shape differs substantially. Acknowledged by `devops-rubric.md:266`.

### Azure Pipelines

**Translates cleanly:** Tier 1/2, idempotence, ordering.

**Breaks:** §1.6 (Docker) again — Azure Pipelines uses the `Docker@2` task. The thin-wrapper rule (§1.8) is narrower on Azure because the `Docker@2` task *is* the mainstream wrapper; hand-rolled composites are much rarer. Neutral impact but worth saying so.

**Tier 3:** "GitHub Release" → Azure Release Pipelines model *deployment stages* (not artifact records). A straight rename `create-github-release` → `create-azure-release` smuggles in a different concept. The rubric correctly warns at `devops-rubric.md:266` ("a Tier 3 concept may not have identical shape"), but the warning is generic. Strengthen for Azure specifically: "On Azure Pipelines, the closest analog to a GitHub Release is a published artifact + a release stage; the two are decoupled, so a single `create-github-release` translates to two Azure actions."

### CircleCI

**Translates cleanly:** Everything above. Orbs are CircleCI's composite primitive and map closely to GitHub Actions' composite actions — the rubric's composition rules (§5–§7) translate almost literally.

**Breaks:** §1.6 Docker — CircleCI uses `docker/build` orb or the `setup_remote_docker` executor. Same pattern as Jenkins/GitLab.

### Buildkite

**Translates cleanly:** Tier 1/2 naming, ordering, idempotence, bounded retry.

**Breaks:** §1.6 Docker — Buildkite uses `docker-compose-plugin` or direct `docker buildx`. Same pattern.

**Tier 3 translation:** Buildkite has no native Release record — users typically push to GitHub Releases or to a separate artifact store. The rubric's Tier 3 concepts assume a forge-provided Release API; on Buildkite-alone pipelines, this doesn't apply. Flag it.

### Cross-platform summary

The **single biggest portability leak** is §1.6's hard-coded dependence on `docker/build-push-action`. The rubric claims tool-agnostic intent at §3.2 ("Prefer VCS-standard commands over platform API") and §3.5 (validated across Jenkins/GitLab/Azure/CircleCI/Buildkite), but §1.6 then mandates a platform-specific mainstream composite. These two are in tension. Fix: reframe §1.6's normative rule as "use BuildKit's build + push + attest capability in one step" and list `docker/build-push-action` as *the GitHub Actions expression of that rule*, with peer expressions on other platforms.

## Practicality findings

### Finding 1 — "Tier 3 porting caveat" is in two places

**Issue:** The "Tier 3 rename is 'start here, not done'" caveat appears once at `devops-rubric.md:266` and again implicitly in the `create-github-release` / `create-azure-release` discussion. Not a conflict, but duplicative.

**Quote:** `devops-rubric.md:266`:
> "Treat Tier 3 renames as **"start here", not "done"** — the rename is the first step; inputs/outputs may also shift when the target concept has a different shape."

**Why it's a problem:** Minor duplication; not a correctness issue. Leaving as-is is fine; just flagged.

**Proposed change:** None required; debatable.

### Finding 2 — "Misleading verb" rule is clear for eight verbs, vague for the rest

**Issue:** `devops-rubric.md:324–332` gives crisp definitions for eight verbs (`deploy-*`, `release-*`, `promote-*`, `publish-*`, `build-*`, `validate-*`, `cleanup-*`, `wait-for-*`), but the generalisation paragraph at `devops-rubric.md:333` says the principle "applies to every verb" with only a spot-check list.

**Quote:** `devops-rubric.md:333`:
> "Generalise the above rule beyond this list. The eight verbs above are the repo's most commonly-abused ones, but the principle … applies to every verb. In particular, spot-check any verb that *sounds* read-only but could have side effects: `resolve-*`, `compose-*`, `generate-*`, `ensure-*`, `read-*`, `get-*`, `find-*`, `list-*`, `has-*`, `is-*`, `check-*`, `inspect-*`."

**Why it's a problem:** "When in doubt, flag it and let the author decide" is the only guidance. That invites inconsistent findings run-to-run — different auditors will flag different verbs.

**Proposed change:** Add a short table of the spot-check verbs with canonical semantics, even if terse (e.g. `resolve-*` = pure lookup, no writes; `compose-*` = pure string transform, no state; `ensure-*` = create-if-missing, idempotent; `get-*` = side-effect-free read). Makes the spot-check mechanical.

### Finding 3 — "Plan file Do not silently clobber" logic is complex

**Issue:** `actions-auditor.md:253–259` describes the coexistence-with-existing-plan policy (read existing, de-duplicate, challenge in report only, write new timestamped file). This is six bullets long and has mutually-entangled rules.

**Quote:** `actions-auditor.md:253`:
> "Do not silently clobber an in-progress plan. Before writing, check `.plans/` for an existing `*-audit-actions.md`. If one exists with open (unchecked) items, it may belong to another agent or a parallel audit run."

**Why it's a problem:** The logic is correct but density makes it easy to miss a sub-rule. The `actions-auditor-consistency.md:244` and `actions-auditor-reviewer.md:162` each describe a slightly different coexistence pattern ("surface to the author" vs. "write new"). They're not in conflict, but a reader cross-referencing them has to reconcile.

**Proposed change:** Debatable. Leaving as-is is fine if the author wants the flexibility. If the author wants a single policy, consolidate into the repo-level CLAUDE.md at `actions/CLAUDE.md` and cite it from all three agents.

### Finding 4 — `required: true` + `default:` "almost always a bug" is too strong

**Issue:** The auditor flags `required: true` with a `default:` as `required-default-contradiction`, saying it's "usually a bug."

**Quote:** `actions-auditor.md:79`:
> "If `required: true`, there must be no `default:` (an always-overridden default is a contradiction and usually a bug)."

**Why it's a problem:** GitHub Actions runtime ignores `default:` when `required: true`, so the `default:` is indeed useless — but there are legitimate patterns where the author uses the `default:` as *documentation* of the expected value shape. Flagging every such case as a bug is over-eager. Mitigated slightly by "usually" but the rule code is still cited as a violation.

**Proposed change:** Soften to: "Flag `required: true` + `default:` as `required-default-contradiction` — the default is ignored at runtime, so either the field is not really required (drop `required:`), the default is documenting expected shape (move to `description:`), or the combination is a latent bug. Ask the author to resolve." Turns the rule from an assertion into a clarification request.

### Finding 5 — Thin-wrapper rule requires §1.8 replacement table to stay current

**Issue:** §1.8 provides a concrete replacement table (`devops-rubric.md:198–202`). When `actions/setup-node@v5` rolls to `@v6`, the rubric will still say `@v5`. Same for every other entry.

**Quote:** `devops-rubric.md:198`:
> "| `setup-dotnet` (1:1 pass-through) | `actions/setup-dotnet` | `@v5` | Direct call; single `dotnet-version` input maps identically. |"

**Why it's a problem:** Pinned versions in docs age out. This isn't critical (the auditor can still flag the pattern) but over 18–24 months the table will drift.

**Proposed change:** Add a preamble line to the table: "Version pins are current as of v8 (2026-04-22); re-validate before citing in audit reports against the latest Marketplace release." Or drop the version column and say "latest stable major tag" — less precise but self-maintaining.

## Additional findings

### Finding 1 — Rubric version history lives in a single paragraph that's now 13 lines long

**Issue:** `devops-rubric.md:3` contains the entire version history in one run-on paragraph (v2 through v8). At v8 it's legible; by v12 it will be hard to skim.

**Quote:** `devops-rubric.md:3`:
> "**Rubric version: 8** (updated 2026-04-22 — added §1.8 'Thin wrappers around mainstream actions — delete in favour of direct use', generalising §1.6 to cover setup/release/deploy wrappers with a concrete replacement table … Previously: v7 2026-04-22 — **posture shift: this repo is production infra, not a teaching vehicle.** …"

**Why it matters:** The version history is load-bearing (the `[RUBRIC-CHANGE v<N>]` tag convention at `devops-rubric.md:3` end depends on readers knowing what changed at each bump), but the current format makes diffing versions tedious.

**Proposed fix:** Move the version history to a bulleted list under a `## Version history` H2 heading, one bullet per version, with the most recent at top. Keep the `[RUBRIC-CHANGE v<N>]` convention and cross-link. Keeps the history machine-readable.

### Finding 2 — "Publication intent = internal-only" is load-bearing but only stated once

**Issue:** `actions-auditor.md:28` establishes that publication intent defaults to internal-only; the reviewer at `actions-auditor-reviewer.md:190` respects it. But the rubric itself (`devops-rubric.md:88`, `branding:` rule) phrases its guidance as "Optional for internal actions; required by the Marketplace publishing flow" without re-stating the repo's default.

**Quote:** `actions-auditor.md:28`:
> "Publication intent for this repo: internal-only. The `optivem/actions` repo is consumed only by sibling repos in this workspace; it is never published to the GitHub Marketplace."

**Why it matters:** The two files don't disagree, but the auditor-file's declaration is easy to miss when reading the rubric standalone. A rubric reader might still flag missing `branding:` by following the rubric's bare text.

**Proposed fix:** Add one line to `devops-rubric.md:88`: "**This repo's publication intent is internal-only** (see `actions-auditor.md:28`); therefore `branding:` is NOT to be flagged here. If the author changes publication intent, revisit this rule."

### Finding 3 — Reviewer has `Edit` in tools but self-improvement boundary is narrow

**Issue:** The reviewer has `Edit` in its `tools:` frontmatter, and the self-improvement policy at `actions-auditor-reviewer.md:171–180` permits edits to two specific files. But there's no guardrail preventing `Edit` from being used against any other file.

**Quote:** `actions-auditor-reviewer.md:4`:
> "tools: Read, Edit, Glob, Grep, Bash, WebFetch, WebSearch, Write"

**Why it matters:** If an agent is ever persuaded (by a subtle prompt-injection in subject files, say) that an action.yml edit is "required by the self-improvement policy," it could act on that. The Hard rules at `actions-auditor-reviewer.md:184` say "Do not modify any file except …" — that's the guardrail, but it's textual rather than structural.

**Proposed fix:** Add a belt-and-braces check to the Hard rules at `actions-auditor-reviewer.md:184`: "If you intend to use `Edit` on any file, verify it is one of: (a) the report file; (b) `.claude/agents/actions-auditor-reviewer.md`; (c) `.claude/agents/docs/review-dimensions.md`. Any other target is a policy violation — do not proceed, and note it in the report's Self-edits section as a declined edit."

### Finding 4 — Review-dimensions §2b says "`get-*` over `read-*`", auditor echoes it — but the rubric §4 silently agrees

**Issue:** The mainstream-first clause about `get-*` vs. `read-*` is stated in two places (`devops-rubric.md:18` and `review-dimensions.md:53`) but the auditor's Process step at `actions-auditor.md:13` cites only `get-*`. The rubric's own §4 at `devops-rubric.md:333` then spot-checks `get-*` and `read-*` as candidates for side-effect auditing without noting the mainstream-first preference. Three near-duplicates that don't quite match.

**Quote A** — `devops-rubric.md:18`:
> "`get-*` is an accepted mainstream verb for side-effect-free reads (HTTP `GET`, `gh api`, `actions/github-script`). Prefer `get-*` over `read-*` unless the repo is actively standardising on `read-*` for a documented reason."

**Quote B** — `devops-rubric.md:333`:
> "spot-check any verb that *sounds* read-only but could have side effects: `resolve-*`, `compose-*`, `generate-*`, `ensure-*`, `read-*`, `get-*`, …"

**Why it matters:** The mainstream-first clause treats `get-*` as preferred over `read-*`; §4 treats them as peer spot-check candidates. Not in conflict but the reader has to integrate both.

**Proposed fix:** At `devops-rubric.md:333`, add a parenthetical: "(prefer `get-*` over `read-*` per the Mainstream-first principle at top-of-file)". One small cross-reference; keeps the rules stitched together.

## Self-edits

None.

The review surfaced flaws in the auditor/rubric, not in the reviewer's own rubric or review-dimensions doc. The dimensions doc held up well — every finding I produced fit cleanly under dimensions 1, 2, 2b, 3, 4, or 5 (with a handful under Additional findings, which is what that section is for). No changes needed to the reviewer's own charter.

## Recommended edits

Ordered highest-impact first.

1. **`devops-rubric.md:349, 381, 426, 449–474, 257` — update stale `create-github-release` examples.** Replace with `softprops/action-gh-release@v2` where the example is a live recommendation, or annotate as "legacy example, now delegated to the mainstream action" where the example is illustrative. Resolves internal consistency Finding 1.
2. **`devops-rubric.md:198–202` — add "Version pins are current as of v8 (2026-04-22); re-validate before citing" preamble** (or drop the version column entirely). Resolves practicality Finding 5.
3. **`devops-rubric.md:60 / §1.3` — add "Fast-feedback sizing" paragraph** mandating `timeout-seconds` / `max-attempts` on any blocking action, with the Farley 5-minute commit-stage budget cited. Resolves CD Finding 2.
4. **`devops-rubric.md:62` — append DORA/MTTR linkage** to the bounded-retry rule ("Unbounded retries turn a transient outage into a cascading pipeline wedge …"). Resolves DORA Finding 2.
5. **`devops-rubric.md:85` — tighten the supply-chain pin strategy** with a default ladder (major-tag-pin mainstream, SHA-pin untrusted, SHA-pin-everything at SLSA L3). Resolves CD Finding 3.
6. **`actions-auditor.md:77` — reformat Process step 3 so each parameter-rule code is on its own line** with a one-line definition, matching the output list at `actions-auditor.md:153–164`. Resolves internal-consistency Finding 2.
7. **`actions-auditor.md:156` — add a rule-precedence tie-breaker sentence** to the Parameter findings list ("When a single parameter violates more than one name-family rule, cite them in priority order mainstream-convention > misleading > kebab-case"). Resolves internal-consistency Finding 3.
8. **`devops-rubric.md:88` — add repo-specific `branding:` carve-out** ("This repo's publication intent is internal-only; therefore `branding:` is NOT to be flagged"). Resolves additional Finding 2.
9. **`devops-rubric.md:333` — add `get-*`-over-`read-*` cross-reference** to the spot-check list ("(prefer `get-*` over `read-*` per the Mainstream-first principle)"). Resolves additional Finding 4.
10. **`devops-rubric.md:123–167 / §1.6` — reframe as "BuildKit-capability rule" with platform expressions** so the Docker guidance doesn't silently bake in GitHub Actions. Resolves portability Jenkins/GitLab/Azure/CircleCI/Buildkite findings.
11. **`actions-auditor.md:79` — document the "stricter-than-mainstream `required:` rule"** with a one-line rationale. Resolves internal-consistency Finding 4.
12. **`actions-auditor.md:79` — soften the `required-default-contradiction` rule** from "usually a bug" to "resolve one of three ways" (ask the author). Resolves practicality Finding 4.
13. **`devops-rubric.md:3` — move version history to a bulleted `## Version history` section.** Resolves additional Finding 1.
14. **`actions-auditor-reviewer.md:184` — add the `Edit`-target check** to the Hard rules. Resolves additional Finding 3.
15. **`devops-rubric.md:333` — add a short canonical-semantics table** for spot-check verbs (`resolve-*`, `compose-*`, `ensure-*`, etc.). Resolves practicality Finding 2.
16. **`actions-auditor.md:78` — add one-line future-proofing note** about native `type:` fields on Docker/JS actions. Resolves DORA/SRE/12-Factor/Marketplace Finding 3.
17. **`devops-rubric.md:84` — one-line Twelve-Factor III linkage** for the bridge-via-env pattern. Resolves DORA/SRE/12-Factor/Marketplace Finding 1.
