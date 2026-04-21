# DevOps rubric for auditing GitHub Actions

This is the reference rubric used by the `actions-auditor` agent (and any sibling agent that wants DevOps-aligned reviews). It defines "what correct looks like" so the agent file can stay focused on process and output schema.

Authoritative sources (in rough order of weight): Jez Humble & Dave Farley's *Continuous Delivery* and Farley's *Modern Software Engineering*; Google SRE / DORA research (four key metrics, trunk-based development); GitHub Actions Marketplace conventions; Kubernetes, Terraform, Ansible, and Docker project idioms; the Twelve-Factor App. When these disagree, cite which source you're leaning on.

You are **not restricted** to existing patterns, prefixes, or conventions in the audited codebase — the codebase is being audited precisely because parts of it may drift from industry practice. When uncertain, say so: it's better to flag a debatable issue and let the author decide than to silently accept a questionable pattern because it matches existing repo style.

---

# 1. DevOps alignment dimensions

Apply this alignment across **every dimension of the review**, not just naming.

- **Verbs and names** — see section 4.
- **Pipeline structure and vocabulary** — e.g. `deploy` ≠ `release` (Farley); "release candidate" vs "prerelease" is an audience distinction; "promotion" is Farley's term for moving an RC through stages; "deployment" requires a persistent environment with consumers.
- **Action composition** — prefer small composable primitives over monolithic "do everything" actions. Flag actions that mix concerns (e.g. an action that deploys AND tags AND notifies).
- **Inputs and outputs** — names should match `actions/checkout` / `actions/setup-*` conventions where applicable (`token`, `ref`, `repository`, `path`, `working-directory`), and use DevOps-standard terms (`image-url`, `tag`, `version`, `environment`, `status`) elsewhere. `commit-sha` (over `sha`) is acceptable when disambiguation is needed. Short aliases like `repo` (for `repository`) are permitted as local conventions but should be applied uniformly — either the whole repo uses `repo` or the whole repo uses `repository`. Flag inconsistency between actions.
- **For actions named `deploy-*`:** required inputs must include both an environment identifier (`environment` or equivalent) and a service identifier (`service-name`, `app-name`, etc.), plus the artifact reference. A deploy action without both is a naming-vs-contract mismatch — the name promises a deployment (service × environment), but the contract only models an artifact push. Cite Farley, *Modern Software Engineering* ch. 12.

## 1.1 Dead inputs — classify before recommending removal

An input that no current consumer overrides is NOT automatically droppable. Classify each apparent dead input:

- **Standard config axis — KEEP.** Credentials/auth (registry username, service-account key, token), environment targeting (environment, region, project-id), resource sizing (memory, cpu, min/max-instances, replicas), network config (port, host, url), rate-limit / retry / timeout knobs, cross-repo parameters (repository, owner, sha, ref), lifecycle state (state, status, is-prerelease), SemVer-defined knobs (prerelease `suffix` — `rc`/`alpha`/`beta`/`preview`, build metadata), observability links (target-url). KEPT even when no current caller overrides them — they preserve the action's contract with standards and with *future* callers. Cite Twelve-Factor Factor III for config externalization, Marketplace convention for auth, K8s sizing norms, SemVer §9 for prerelease identifiers, etc.
- **Speculative flexibility — DROP.** Added for an undescribed hypothetical need, doesn't correspond to any established DevOps/CD knob, removal couples the action to no standard workflow. YAGNI applies.
- **Redundant pass-through at the caller — SIMPLIFY the caller.** If multiple callers pass the input with exactly the action's default value, drop the redundant `with:` line at the caller side; keep the input on the action side.

Default recommendation for an input "unused today" is **keep**, not drop. Shifting to drop requires affirmative evidence that the field is speculative. When in doubt, keep.

## 1.2 Dead outputs — classify before recommending removal (stronger bias toward keep)

Outputs have **no caller-surface cost** — callers that don't consume an output simply ignore it. Threshold for dropping an unread output is higher than for inputs.

- **Primary return value — KEEP (obvious).** The main answer the action computes: boolean `changed`, resolved `tag` or `sha`, `version`, `service-url`. Dropping breaks the action's contract.
- **Observability metadata — KEEP.** An explanatory companion to a primary return value: *why*, *when*, *what*, *where*. Examples: `baseline-sha` paired with `changed` (which commit was compared); `verified-at` timestamp paired with `changed` (when verified); `release-url` after creating a release (where the result is viewable); commit `timestamp` alongside a resolved SHA. Boolean-only returns force callers to re-derive context later — that cost shows up as pain. When in doubt whether an output is observability metadata, assume yes and keep it.
- **Speculative / vestigial — DROP.** Genuinely isn't the primary return and isn't explanatory metadata. Rare; requires affirmative evidence.

Default recommendation for an output "unread today" is **keep**. An output's cost is paid once on the producer side; its value accrues every time someone needs to debug, audit, or display a result. Dropping and re-adding later is a breaking change for callers who adopted the output in the interim.

## 1.3 Process and pipeline rules

- **Build-once-promote-many.** Flag any action whose name or `runs:` block implies rebuilding an artifact past the commit stage (e.g. `build-image` called from a promote/deploy workflow, or a promote action that shells out to `docker build` or runs a compiler). Promote actions must consume an existing artifact reference (image digest, tag, URL), not rebuild from source. Source: Farley & Humble, *Continuous Delivery* ch. 5.
- **Error handling / idempotence.** DevOps practice expects actions to be idempotent or fail-fast with clear errors. Flag actions that silently succeed on no-op, or that have ambiguous failure semantics.
- **Fail-fast on cheap preconditions.** Input validation, format checks, and reachability probes must happen *before* any API call, docker build, or external side effect. Flag actions whose first side-effecting step can fail on a precondition the action could have validated in a prior, side-effect-free step. Source: Farley & Humble, *Continuous Delivery* ch. 4.
- **Rate-limit awareness for `gh api` actions.** Flag any action that uses `gh api` in a loop (iterating over items, following pagination, or called repeatedly from a caller loop) and does not accept a `rate-limit-threshold` / `poll-interval` input or back off when approaching the limit. Reference pattern: `cleanup-prereleases` and `trigger-and-wait-for-github-workflow`. Point callers at `gh api rate_limit` for headroom checks.

## 1.4 Secrets, supply chain, observability, shell, branding

- **Secrets / auth.** Flag actions that hardcode tokens, require unusual environment shapes, or bypass `GITHUB_TOKEN` conventions.
- **Token contract — input, not implicit env.** Actions that need a token must declare it as a named input (`token`, `github-token`, or domain-specific like `npm-token`), typically with `default: ${{ github.token }}` when `GITHUB_TOKEN`'s default permissions suffice. Flag actions that instead expect the caller to set a step-level `env:` variable that the action reads via `${{ env.X }}` — that pattern has no interface contract visible in `action.yml`, isn't discoverable, and fails silently when a caller forgets to set it. Reference: `actions/checkout`, `actions/setup-node`, `actions/github-script`, `docker/login-action`, `softprops/action-gh-release` — all take the token as a named input.
- **Token usage — bridge input to env, never interpolate into `run:`.** Inside a composite action, do NOT write `${{ inputs.token }}` (or `${{ env.TOKEN }}`) directly in a `run:` shell script. The expression engine renders the literal secret into the command string *before* execution, which leaks under `set -x`, error dumps, or tracing — GitHub's secret masker is best-effort and fails on transforms. Correct pattern: set the token on the step's `env:` block and reference it as a shell variable (`echo "$GH_TOKEN" | ...`). Cite GitHub's [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-secrets-in-a-workflow) — "Consider accessing secrets via environment variables rather than as an input."

  ```yaml
  # WRONG — secret interpolated into rendered command
  - run: echo "${{ inputs.token }}" | docker login ghcr.io -u "${{ github.actor }}" --password-stdin
    shell: bash

  # WRONG — same risk, just sourced from env instead of input; also no interface contract
  - run: echo "${{ env.GITHUB_TOKEN }}" | docker login ghcr.io -u "${{ github.actor }}" --password-stdin
    shell: bash

  # RIGHT — input bridged to env, shell reads env var
  - run: echo "$GH_TOKEN" | docker login ghcr.io -u "${{ github.actor }}" --password-stdin
    shell: bash
    env:
      GH_TOKEN: ${{ inputs.token }}
  ```
- **Supply chain.** Flag actions whose `uses:` references point at a mutable ref (`@main`, `@master`, `@latest`, any branch name), or at an action from an untrusted author. Pinning to a major tag (`@v4`) is acceptable for Marketplace-trusted actions (`actions/*`, well-known vendors); pinning to a SHA is preferred for untrusted sources. Cite GitHub's hardening guide for GitHub Actions and SLSA level-3 build integrity.
- **Observability — dual surface.** For human review: useful logs and step summaries when the action does significant work. For downstream pipeline decisions: where an action can fail in a recoverable way, expose a structured failure reason as an output (e.g. `status`, `failure-reason`) rather than only exiting non-zero. Flag actions that use `exit 1` for recoverable conditions a caller might want to branch on. Source: SRE ch. 4 "Service Level Objectives", ch. 11 "Being On-Call".
- **Shell portability.** Repo policy is bash-only (see README "Shell choice"); `shell: pwsh` and `.ps1` files are rejected by [check-no-pwsh.sh](../../../shared/_lint/check-no-pwsh.sh). Flag any `shell: pwsh` or `.ps1` found outside the `shared/_test-*` allowlist as a lint-rule escape. Do not recommend keeping pwsh because "the logic benefits from PowerShell object handling" — bash + `jq` is the repo standard for the JSON-munging cases that historically motivated pwsh.
- **`branding:` field.** Optional for internal actions; required by the Marketplace publishing flow. If publication intent is Marketplace, flag actions missing `branding:`; if internal-only, the field is a stylistic choice and should not be flagged.

## 1.5 DORA linkage (sensemaking, not required)

Where useful, link a finding to the DORA metric it moves: composite opacity → MTTR; missing idempotence → change-failure rate; missing primitive-level reusability → lead time; rebuilding downstream of commit stage → change-failure rate and lead time. Source: *Accelerate* (Forsgren, Humble, Kim); DORA State of DevOps reports.

---

# 2. Forward-looking context (repo-specific exemptions)

The repo is a teaching vehicle that evolves over time. Some things that look incomplete today are deliberate stepping stones, not gaps. Do not flag them as missing.

- **Docker Compose is a temporary stepping stone.** The current deployment story uses `docker compose up` locally or on a CI runner. Cloud-based deployment (Kubernetes, AWS ECS / Fargate, Azure App Service, Google Cloud Run, etc.) is planned for a later stage of the course. Do **not** recommend adding cloud-deploy actions now, and do **not** flag the absence of one as a gap. What you *should* flag is naming that claims to do something the action doesn't yet do (e.g. calling a docker-compose step `deploy-to-production`).
- **The list of environments is author-determined.** The set of environments (dev, staging, acceptance, production, canary, preview, etc.) is decided by the course author per course, not fixed by this repo. Do **not** recommend adding or removing environments. Only flag inconsistencies *within* the environments that already exist.
- **Future-proofing note for consolidation suggestions.** When proposing consolidated actions, design inputs and outputs so they will extend naturally to a cloud-deploy world and to additional environments. Prefer generic names (`target`, `environment`, `deploy-method`) over Docker-specific ones in the signature, even if the only current implementation is Compose.
- **`:latest` is load-bearing in this pipeline — do NOT flag it as an anti-pattern.** The acceptance stage intentionally pulls `:latest` to exercise the newest post-commit, pre-release image against the system test suite. That's the defined role of `:latest` here: "the most recent passing commit-stage build." Versioned/SHA-pinned tags are used from acceptance-stage onward for reproducibility. The mainstream argument against `:latest` applies to *production* use, which this pipeline does NOT do — prod-stage pins by version/SHA. Do not recommend making `:latest` push opt-in, do not recommend removing the `image-latest-url` output, and do not cite SRE/K8s `imagePullPolicy` guidance against it in this repo.
- **Teaching-clarity override.** If a proposed consolidation would flatten a distinction that the pedagogy relies on (e.g. `check-*` = assert-and-fail vs. `has-*` = boolean-return, or `generate-*` = compute vs. `compose-*` = assemble-from-parts), prefer to leave the primitives separate and note the pedagogical role in the finding. A finding that is "correct by the rubric but bad for the course" must say so explicitly — don't silently merge pedagogically-important distinctions for code-line savings.

---

# 3. Tool-agnostic vs. platform-specific naming (tiers)

Students may swap the CI/CD platform for their own pipeline (GitHub Actions → Jenkins, GitLab CI, Azure Pipelines, AWS CodePipeline, CircleCI, Buildkite, etc.) and may swap the git host (GitHub → GitLab, Bitbucket, Gitea, self-hosted). The naming convention must make it obvious at a glance which actions carry portable concepts vs. which carry GitHub-platform-specific glue.

## 3.1 Naming tiers

Three conceptual tiers. Only the third gets a prefix.

- **Tier 1 — fully generic** (any CI, any VCS, any host). No prefix. Examples: `build-image`, `push-image`, `wait-for-approval`, `bump-version`, `run-tests`, `deploy-service`, `validate-config`.

  *Tier 1 covers actions whose **concept** is universal. Some Tier 1 actions in this repo (e.g. `setup-node`, `setup-java-gradle`, `setup-dotnet`) are implemented via Marketplace setup actions (`actions/setup-*@v5`), which are GitHub-Actions-specific under the hood. The **name** is still Tier 1 because the concept ports (every CI has a language-runtime setup primitive), but a porting student must rewrite the implementation. Flag such cases as "Tier 1 name, platform-specific implementation" so the porting surface is visible.*

- **Tier 2 — git-native** (any CI, any git host, but requires a git VCS). No prefix. Git is the assumed baseline — adding `git-` to names is redundant because the domain nouns (`tag`, `commit`, `sha`, `ref`, `branch`) already imply git. Examples: `ensure-tag-exists`, `resolve-tag-from-sha`, `create-and-push-tag`, `check-version-unreleased`, `bump-patch-versions`.

  *Implementation sub-rule for Tier 2:* Tier 2 actions must not hardcode `github.com` in their implementation. Remote URLs should be parameterised — either accept a `git-host` input with default `github.com`, or derive the host from a `repo` input given in URL form. The pattern `https://x-access-token:${TOKEN}@github.com/...` breaks Tier 2's portability claim: a student porting to GitLab, Bitbucket, Gitea, or self-hosted would have to edit every Tier 2 action. Flag actions that hardcode the git host as a **portability violation** under **DevOps alignment findings** → "Tool-agnostic composition".

- **Tier 3 — GitHub-platform-specific** (requires GitHub, not just git). `github` segment required. These are concepts that genuinely do not exist in vanilla git: Releases, commit statuses, Deployments, workflow runs, Packages, Issues, PRs, check runs. Examples: `create-github-release`, `create-github-commit-status`, `trigger-and-wait-for-github-workflow`, `cleanup-github-deployments`, `check-github-container-packages-exist`.

  *Porting caveat for Tier 3:* a Tier 3 concept may not have identical shape on other platforms. `create-github-release` ports to an Azure DevOps "Release" but Azure Releases model deployment stages, which GitHub Releases do not; `has-update-since-last-github-workflow-run` ports to GitLab as pipeline-runs, which contain jobs rather than runs. Treat Tier 3 renames as **"start here", not "done"** — the rename is the first step; inputs/outputs may also shift when the target concept has a different shape.

## 3.2 Implementation rule: prefer VCS-standard commands over platform API

> **If a VCS-standard command (git, or the portable CLI equivalent on your platform) achieves the same outcome as a platform API call, use the VCS command.** Reserve the platform API for concepts that genuinely do not exist in the VCS.

On GitHub Actions this rule reads "prefer `git` over `gh api`" — `gh api` is the concrete platform API. On GitLab CI it reads "prefer `git` over `glab api`"; on Bitbucket "prefer `git` over `bb api` / `curl https://api.bitbucket.org/...`". The *principle* is VCS-vs-platform-API; the CLI names are illustrative.

**Tier is determined by the concept accessed, not the tool used.** An action named `has-update-since-last-commit` (Tier 2) may use `gh api` internally for speed or convenience — the tier promise is that a port to GitLab replaces only the implementation, not the name. (See also the note at the end of §3.3 on `GITHUB_TOKEN`-for-git-auth: same principle — auth tool ≠ tier.)

Why:

- **Portability.** VCS-standard commands (git) work identically against GitHub, GitLab, Bitbucket, Gitea, self-hosted. Students porting elsewhere rewrite nothing for Tier 2 actions.
- **No rate limits.** GitHub API has 5000 req/hour per authenticated user (GitLab, Bitbucket, etc. impose their own caps); VCS operations don't count toward them. Matters for cleanup jobs and loops.
- **Fewer moving parts.** No platform-CLI version drift, no token scope surprises.
- **Honest names.** Using the platform API where the VCS would work drags a misleading platform label onto logic that is in fact portable.

Use the platform API when the concept is genuinely platform metadata (examples shown for GitHub; analogs apply on GitLab/Bitbucket/etc.):

- Releases, commit statuses, Deployments, workflow runs, Packages, Issues, PRs, check runs, review comments.
- Push timestamps (distinct from committer timestamps — git only has the latter).
- Searches that require GitHub's search indexes (e.g. cross-repo commit search without cloning).

## 3.3 Signals that a behavior is GitHub-platform-specific (Tier 3)

- Calls `gh api` or the GitHub REST/GraphQL API **for a concept that has no git equivalent** (Release, commit status, Deployment, workflow run, PR, Package, check run, Issue).
- Invokes `gh release`, `gh workflow run`, `gh run list/watch`, `gh pr`, `gh issue`.
- Reads/writes GitHub commit statuses, Deployments, PR comments, workflow-dispatch inputs.
- Depends on `GITHUB_*` environment variables beyond the universal ones every runner provides (`GITHUB_WORKSPACE`, `GITHUB_SHA`, `GITHUB_REF` are considered baseline-universal in this repo; `GITHUB_RUN_ID` is GitHub-specific because workflow runs are).

Note: consuming `GITHUB_TOKEN` for git auth (via `https://x-access-token:${TOKEN}@github.com/...`) does NOT by itself make an action Tier 3. The auth pattern is portable (swap URL + token source), and the git operation itself is git-native. Only the platform concept being accessed determines the tier.

## 3.4 Performance caveat for git remote scans

`git ls-remote` fetches the full ref list and filters client-side. For repos with thousands of tags, a paginated `gh api /repos/.../tags` or `/releases` can be faster.

- For this repo's scale (dozens of tags), this is irrelevant; prefer git.
- Actions that enumerate all tags should carry a TODO comment noting the tradeoff so the next maintainer knows to revisit when tag counts grow.

---

# 4. Naming rules

For each action directory, check:

- **kebab-case only.**
- **verb-first prefix.** The prefix set is **not closed**: use the verb that best describes what the action actually does, per mainstream DevOps / CD vocabulary. Prefer clarity over conformance — if the honest verb is new to this repo, use it anyway and call out the new verb in the report with the reason.
- **`name:` field** in `action.yml` is the Title Case of the directory name.
- **Prefer general spec terminology over narrow convention.** When a concept has a standard name (SemVer, Twelve-Factor, HTTP, Marketplace), name the action after the general concept, not the specific instance the repo happens to use today. Example: SemVer defines `prerelease` as the umbrella term covering `rc`, `alpha`, `beta`, `preview`, etc. Name composites `*-prerelease-version`, not `*-rc-version`, even when the sole current caller uses `rc`. Narrow names (`rc-*`, `qa-*`, `ghcr-*`) force a rename the moment a second variant appears; general names cost nothing today and absorb future variants for free. Flag any name that bakes a specific value of a standard config axis into the identifier when the action's internals already take that value as an input.
- **Directory name accurately reflects what the action actually does** — based on `runs:` steps, not just the description.
- **The name must not be misleading vs. mainstream DevOps/CD terminology.** When a verb's CD-meaning is load-bearing, the action's `runs:` block must honour it:
  - `deploy-*` must deploy to an environment (persistent target, reachable by consumers) per Farley's definition. `docker compose up` on a CI runner is a test-harness spin-up, not a deployment.
  - `release-*` must make features available to users (not merely produce a tag or artifact).
  - `build-*` must produce an artifact — not merely download or reference one. A "build" action that only pulls a prebuilt binary should be `fetch-*` or `pull-*`.
  - `validate-*` must fail the step on invalid input. An action that logs a warning and continues is `check-*` or `inspect-*`, not `validate-*`.
  - `cleanup-*` must remove things. An action that scans and lists candidates without removing is `find-*` or `list-stale-*`.
  - `wait-for-*` must poll until the thing becomes true (or time out). An action that checks once is `has-*` or `is-*`.

For each violation, propose a specific better name and say which rule it violates.

---

# 5. Architecture: primitives first, composites optional and thin

Prefer small, single-concern **primitive** actions over large composite actions that bundle multiple concerns. Composites are acceptable **only as thin sugar** over primitives that can also be called directly at the call site.

> **Rule:** every behavior exposed by a composite must also be reachable by calling primitives directly. A composite that hides logic that callers cannot otherwise replicate step-by-step is a design smell.

Why:

- **Scales with new artifact types / targets.** A Docker-specific prerelease composite can't accept npm packages. If prerelease creation is decomposed into `compose-prerelease-version` → `tag-<artifact-type>` → `create-github-release`, adding a new artifact type means adding one new tagging primitive — not a whole parallel composite.
- **Composition across artifact types.** When a project ships Docker images *and* npm packages under the same release version, primitives compose naturally. Monolithic composites cannot — calling two of them generates two versions.
- **No hidden magic.** Readers see the actual steps at the call site. Debugging a broken release doesn't require opening the composite's `action.yml`.
- **Independent testability.** Each primitive has a narrow contract and can be tested in isolation.

Composites are allowed when:

- They wrap 2–4 primitives in a fixed, well-known order that is genuinely universal (not just common for the current caller set).
- They add no behavior beyond calling primitives — no conditional logic, no artifact-type branching, no "smart" defaults that hide a primitive's input.
- Their name honestly reflects the specialization (e.g. `publish-docker-prerelease`, not `create-prerelease` if Docker is hardcoded).
- The primitives remain first-class citizens — callers must be able to bypass the composite without loss of capability.

Signals that a composite is violating this rule:

- Its inputs include an artifact-type-specific shape (e.g. `image-urls:` where a generic `artifact-urls:` would be enough) but the name is generic.
- A caller wanting a different artifact type would have to fork it or write a parallel composite.
- Removing the composite and inlining its steps at call sites loses no capability — only brevity.

---

# 6. Architecture: one concern per action, swappable at the seams

Each primitive action addresses exactly **one** concern from the orthogonal set of concerns a release pipeline juggles. A reader should be able to point at any action and say which single concern it owns. A reviewer should be able to swap the implementation of any one concern without touching the others.

The orthogonal concerns (maps onto Twelve-Factor Factor V — build / release / run separation):

| Concern | Factor V stage | Example sources that vary | Example primitives |
|---|---|---|---|
| **Version source** | release | VERSION files / `package.json` / `pom.xml` / Cargo.toml / latest git tag | `read-target-version`, `compose-prerelease-version` |
| **Artifact construction** | build | Docker images / npm packages / Maven JARs / NuGet / zip bundles | `build-docker-image` (build step only — NOT tag-with-release-version) |
| **Artifact release tagging** | release | `docker tag :v{version}` / `npm publish --tag` / Maven release plugin | `tag-docker-images`, future: `tag-npm-package`, `publish-maven-artifact` |
| **Git tag creation** | release | `git tag` + `git push` / Contents API / `gh release create` (coupled) | `create-and-push-tag`, `ensure-tag-exists` |
| **Release record** | release | GitHub Release / GitLab Release / Bitbucket Downloads / none | `create-github-release` |
| **Commit of generated files** | release | `git push` / Contents API / merge-request PR | `commit-files-via-github-contents-api` |
| **Status / approval signalling** | release | GitHub commit statuses / GitLab commit statuses / Slack messages / email | `create-github-commit-status` |

**Factor V violation signal:** an action named `build-*` that also performs release-stage tagging (e.g. `docker tag :v{version}`) is mixing the *build* and *release* stages. Flag it as a concern-mixing violation and cite Factor V — [The Twelve-Factor App](https://12factor.net/build-release-run).

> **Rule:** no single action may own more than one of these concerns. If it does, it's a **concern-mixing violation** and must be split.

## 6.1 Swappability payoff

- Moving from VERSION files to `package.json` touches only the version-source primitive.
- Moving from GitHub Releases to GitLab Releases touches primarily the release-record primitive, possibly with input/output shape differences if the target platform models the concept differently (e.g. Azure Releases include deployment stages that GitHub Releases do not).
- Adding a new artifact type touches only the tagging primitive set.
- Porting to Jenkins or GitLab CI touches the Tier 3 primitives and the implementation of any Tier 2 primitive that hardcodes `github.com` — Tier 1/2 *names* remain identical, but implementations must parameterise the git host.

## 6.2 Signals that an action mixes concerns

- Its inputs span two or more concerns (e.g. both `version-file-path:` and `image-urls:` and `release-notes:`).
- Its `runs:` block reads a VERSION file **and** calls `gh api /releases` **and** does `docker tag` in the same action.
- Its name is a noun-phrase glue word like "prerelease", "release", "pipeline", or "stage" that bundles multiple primitives by convention.

When you find a concern-mixing action: identify which concerns it spans (from the table above), recommend splitting it into one primitive per concern, and if a thin composite is still desirable for the common-case caller, recommend rebuilding it **on top of** the primitives — never as a replacement. Flag it in **DevOps alignment findings** → "Separation of concerns".

---

# 7. Architecture: composition order and idempotence

Once concerns are split into primitives, the caller workflow (or a thin composite wrapper) must compose them in an order that **minimises the blast radius of partial failure**, and each primitive must be **idempotent** so a rerun of the same workflow is safe.

## 7.1 Ordering rule: cheapest-to-reverse first, hardest-to-reverse last

Release-style pipelines bundle several side effects that are not equally reversible. Order the steps so that if step N fails, steps 1…N-1 left the world in a state that is cheap to re-enter, not a partial "release" that is now visible to users.

Rough reversibility ranking (cheapest → hardest):

1. **Building/pushing an artifact** (docker image, npm tarball, Maven JAR) — overwritable by the next push of the same tag; nobody has consumed it yet.
2. **Creating/updating a git tag** — movable with a force-push; visible only to git consumers.
3. **Creating a platform release record** (GitHub Release, GitLab Release) — user-visible, appears in "Releases" UI, may trigger notifications and downstream webhooks.
4. **Announcing / notifying** (Slack, email, status page, changelog commit) — pushes information to humans; cannot be un-sent.

A concrete ordering for a Docker + GitHub release:

```
build-and-push docker image   # 1. artifact exists but nothing references it yet
create-and-push git tag       # 2. tag points at an already-published image
create-github-release         # 3. release references an already-existing tag
notify / announce             # 4. only after the release record is real
```

If step 3 fails, you have a tagged image and a git tag — both re-runnable. If the order were reversed (release first, then tag, then image), a failure at step 2 leaves a GitHub Release pointing at a tag that doesn't exist, visible to users.

## 7.2 Idempotence rule: every primitive must be safe to rerun

Each primitive must converge to the same end state whether it's the first run or the hundredth:

- **Tag creation** — create-if-missing, otherwise verify-or-update; never fail because "tag already exists" when the existing tag already points at the intended SHA.
- **Artifact push** — pushing an already-published image/package to the same tag is a no-op or an overwrite, not an error.
- **Release record** — create-if-missing, otherwise update-in-place; a rerun must not produce two Releases for the same tag.
- **Status / notification** — either deduplicate on a stable key, or scope the notification to a step that only runs on first success.

Actions that silently succeed on a genuine no-op are fine; actions that *fail* on a rerun because "the thing already exists" are a pipeline-fragility bug.

## 7.3 Concrete example — three primitives + thin caller

```
actions/
  build-and-push-image/action.yml     # concern: artifact type & push
  create-and-push-tag/action.yml      # concern: git tag creation
  create-github-release/action.yml    # concern: release record
```

Each primitive accepts only the inputs for its own concern (e.g. `create-and-push-tag` takes `tag` and `sha`, not `image-url` or `release-notes`). The caller composes them in reversibility order:

```yaml
jobs:
  release:
    steps:
      - uses: actions/checkout@v4
      - uses: optivem/actions/build-and-push-image@v1    # 1. cheapest to reverse
        with: { image: ghcr.io/acme/api, tag: ${{ inputs.version }} }
      - uses: optivem/actions/create-and-push-tag@v1     # 2. movable
        with: { tag: v${{ inputs.version }}, sha: ${{ github.sha }} }
      - uses: optivem/actions/create-github-release@v1   # 3. user-visible
        with: { tag: v${{ inputs.version }}, notes: ${{ inputs.notes }} }
```

A thin composite wrapper (`publish-docker-release`) that runs these three in this order is acceptable **only if** each primitive remains independently callable and the wrapper adds no behavior beyond the fixed sequence.

---

# 8. Filing findings: which subsection goes where

| Situation | Report section / subsection |
|---|---|
| Pure rename (Tier mismatch: `github` in name but Tier 1/2 runs, or no `github` but Tier 3 runs) | **Naming violations** |
| Action mixes Tier 1/2 logic with Tier 3 glue (composition violation) | DevOps alignment → **Tool-agnostic composition** |
| Action hardcodes `github.com` git host (portability violation) | DevOps alignment → **Tool-agnostic composition** |
| Action uses the platform API (e.g. `gh api`) for something a VCS-standard command (`git`) can do | DevOps alignment → **Prefer VCS over platform API** |
| Action bundles more than one concern from the table in §6 | DevOps alignment → **Separation of concerns** |
| Composite hides logic that can't be replicated step-by-step | DevOps alignment → **Composite opacity** |
| Composite runs steps in an order where early-step failure leaves a dangling reference | DevOps alignment → **Composition ordering** |
| Primitive fails on rerun because "the thing already exists" | DevOps alignment → **Idempotence** |
| Action expects caller to set an implicit `env:` for a token instead of declaring it as a named input | DevOps alignment → **Secrets / auth** |
| Action interpolates `${{ inputs.token }}` or `${{ env.TOKEN }}` directly into a `run:` shell line instead of bridging via step-level `env:` | DevOps alignment → **Secrets / auth** |
| Everything else DevOps-related that doesn't fit above | DevOps alignment → **Other** |
