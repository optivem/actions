# DevOps rubric for auditing GitHub Actions

**Rubric version: 8** (updated 2026-04-22). See [§ Version history](#version-history) at the end of this file for what changed in each version. When a re-audit produces a finding that was not previously produced against the same action, tag the finding `[RUBRIC-CHANGE v<N>]` in the report so the author can distinguish "always existed, now flagged" from "genuinely drifted" — bump this version any time §1–§8 change materially.

This is the reference rubric used by the `actions-auditor` agent (and any sibling agent that wants DevOps-aligned reviews). It defines "what correct looks like" so the agent file can stay focused on process and output schema.

Authoritative sources (in rough order of weight): Jez Humble & Dave Farley's *Continuous Delivery* and Farley's *Modern Software Engineering*; Google SRE / DORA research (four key metrics, trunk-based development); GitHub Actions Marketplace conventions; Kubernetes, Terraform, Ansible, and Docker project idioms; the Twelve-Factor App. When these disagree, cite which source you're leaning on.

You are **not restricted** to existing patterns, prefixes, or conventions in the audited codebase — the codebase is being audited precisely because parts of it may drift from industry practice. When uncertain, say so: it's better to flag a debatable issue and let the author decide than to silently accept a questionable pattern because it matches existing repo style.

## Mainstream-first principle

**When mainstream GitHub Actions ecosystem conventions conflict with an internal rubric convention, prefer the mainstream convention.** This rubric exists to keep the repo aligned with how practitioners write and consume Actions in the wider world — not to invent a private dialect. If a rule in this file would push the repo away from Marketplace / `actions/*` / widely-adopted third-party conventions for the sake of internal elegance or pedagogical neatness, the rule is wrong; flag the rule (not the action) and propose bringing it into line.

Concrete implications:

- **`check-*` is the preferred mainstream verb for boolean-return query actions** in the GitHub Actions ecosystem (and in mainstream DevOps shell conventions more broadly). It does NOT have to mean "assert-and-fail"; the `check-*` / `has-*` distinction taught by some style guides is not Marketplace convention and must not be enforced. When unifying a mixed `check-*` / `has-*` / `is-*` set, the default target is `check-*`. `has-*` and `is-*` are acceptable aliases but are secondary; existing `has-*` actions do not need to be renamed unless the author wants repo-wide uniformity (explicit opt-in).
- `get-*` is an accepted mainstream verb for side-effect-free reads (HTTP `GET`, `gh api`, `actions/github-script`). Prefer `get-*` over `read-*` unless the repo is actively standardising on `read-*` for a documented reason.
- Input naming should follow `actions/checkout` and `actions/setup-*` precedent first (`repository`, `ref`, `token`, `path`, `working-directory`). Short aliases (`repo`) are acceptable local conventions only when applied uniformly AND documented as a deliberate deviation.
- Prefixing with `github` (or a narrower segment like `ghcr`) is reserved for Tier 3 concepts whose bare noun would be ambiguous — see §3.1 "When a Tier 3 name gets the `github` segment" for the full rule. Do not add `github` to Tier 1/2 names for didactic tier-marking.

When a rule in this rubric contradicts mainstream practice, the mainstream practice wins unless the author has explicitly overridden it as a course-level teaching device (see §2, teaching-clarity override — which is narrow and requires evidence of active curricular use, not just "our style guide says so").

---

# 1. DevOps alignment dimensions

Apply this alignment across **every dimension of the review**, not just naming.

- **Verbs and names** — see section 4.
- **Pipeline structure and vocabulary** — e.g. `deploy` ≠ `release` (Farley); "release candidate" vs "prerelease" is an audience distinction; "promotion" is Farley's term for moving an RC through stages; "deployment" requires a persistent environment with consumers.
- **Action composition** — prefer small composable primitives over monolithic "do everything" actions. Flag actions that mix concerns (e.g. an action that deploys AND tags AND notifies).
- **Inputs and outputs** — names should match `actions/checkout` / `actions/setup-*` conventions where applicable (`token`, `ref`, `repository`, `path`, `working-directory`), and use DevOps-standard terms (`image-url`, `tag`, `version`, `environment`, `status`) elsewhere. **Commit SHA inputs — prefer `commit-sha` in flat namespaces.** Use `commit-sha` for action inputs, `workflow_dispatch` inputs, `workflow_call` inputs, reusable-workflow inputs, and env vars (as `COMMIT_SHA`). Bare `sha` is only appropriate inside a disambiguating namespace — the `github.sha` context variable, REST path params like `/commits/{sha}`, or webhook payload fields where the parent object names the concept. Rationale: every major CI system qualifies in flat namespaces (GitLab `CI_COMMIT_SHA`, CircleCI `CIRCLE_SHA1`, Jenkins `GIT_COMMIT`, Travis `TRAVIS_COMMIT`, Buildkite `BUILDKITE_COMMIT`, Azure DevOps `BUILD_SOURCEVERSION`, AWS CodeBuild `CODEBUILD_RESOLVED_SOURCE_VERSION`); GitHub's own REST API qualifies when the URL no longer disambiguates (`/git/commits/{commit_sha}` alongside `tree_sha`/`blob_sha`/`file_sha`). In `workflow_dispatch` forms the qualified label also reads better as a UI field name. Flag bare `sha:` inputs as `name-mainstream-convention` with proposed rename to `commit-sha:`. **Commit SHA outputs — qualify when ambiguity exists; bare `sha` is acceptable when the producer is unambiguous.** Use `commit-sha` as an action output, job output, or step output when (a) the action/job/step produces multiple SHAs (e.g. commit-sha + content-sha + tree-sha), OR (b) the producer's name does not itself make "which SHA" obvious (e.g. a generic `check` job whose outputs include a SHA alongside tags, versions, etc.). Bare `sha` is acceptable when the producer exists solely to resolve/produce a commit SHA AND its name disambiguates (e.g. `resolve-commit`, `get-commit-status`). Rationale: consumers reach outputs through `steps.<id>.outputs.*` / `needs.<job>.outputs.*`, which carries some disambiguation that input namespaces lack. Industry split: `release-please-action` uses bare `sha`; `actions/checkout@v4+` uses `commit`; `peter-evans/create-pull-request` uses `pull-request-head-sha`. When in doubt, qualify. **Prefer `repository` over the short `repo` alias** — `actions/checkout` and every official `actions/*` action use `repository` as the input name; `repo` is a `gh` CLI flag convention, not an Actions input convention. If the whole repo is already consistently on `repo` that is acceptable, but when unifying from a mixed state, move to `repository`. Flag inconsistency between actions.
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
- **Fast-feedback sizing.** Actions that block a job's progress (polling, waiting, retrying) must expose a `timeout-seconds` (or `max-attempts` + `poll-interval`) input with a default that respects the target commit-stage budget of roughly 5 minutes end-to-end (Farley & Humble ch. 4, *Implementing a Deployment Pipeline*). Applies to `wait-for-urls`, `wait-for-github-workflow`, `trigger-and-wait-for-github-workflow`, and any future blocker. Flag actions whose default wait-times could sum above ~5min under common caller compositions without the caller being able to cap them.
- **Rate-limit awareness for `gh api` actions.** Flag any action that uses `gh api` in a loop (iterating over items, following pagination, or called repeatedly from a caller loop) and does not accept a `rate-limit-threshold` / `poll-interval` input or back off when approaching the limit. Reference pattern: `cleanup-github-prereleases` and `trigger-and-wait-for-github-workflow`. Point callers at `gh api rate_limit` for headroom checks.
- **Bounded retry with backoff.** Flag any action whose `runs:` block retries a transient-failure-prone operation (network call, API request, polling loop) without **(a)** an explicit maximum attempt count or deadline, and **(b)** exponential or jittered backoff between attempts. Unbounded `while true; do ... done` loops and flat-interval retries burn the caller's error budget and inflate MTTR during partial outages — a single wedged action can consume an entire pipeline's retry budget. A healthy retry loop has a ceiling (e.g. `max-attempts: 5` input, or a `timeout-seconds` input) and grows the sleep between attempts (e.g. 2s → 4s → 8s → 16s → 32s, optionally with jitter). **DORA linkage — MTTR.** Unbounded retries are an MTTR amplifier: a 30-second transient registry outage escalates into a 30-minute pipeline wedge under flat-interval retry, so the MTTR observed by the team is dominated by the retry policy rather than the underlying fault. Source: Google SRE book, ch. 22 "Addressing Cascading Failures" (retry amplification) and ch. 3 "Embracing Risk" (error-budget framing); *Accelerate* (Forsgren, Humble, Kim) on MTTR as a DORA metric.

## 1.4 Secrets, supply chain, observability, shell, branding

- **Secrets / auth.** Flag actions that hardcode tokens, require unusual environment shapes, or bypass `GITHUB_TOKEN` conventions.
- **Token contract — input, not implicit env.** Actions that need a token must declare it as a named input (`token`, `github-token`, or domain-specific like `npm-token`), typically with `default: ${{ github.token }}` when `GITHUB_TOKEN`'s default permissions suffice. Flag actions that instead expect the caller to set a step-level `env:` variable that the action reads via `${{ env.X }}` — that pattern has no interface contract visible in `action.yml`, isn't discoverable, and fails silently when a caller forgets to set it. Reference: `actions/checkout`, `actions/setup-node`, `actions/github-script`, `docker/login-action`, `softprops/action-gh-release` — all take the token as a named input. (Sourcing: this is a **Marketplace / action-interface discoverability** convention, not Twelve-Factor Factor III — Factor III is about config *delivery channel* (env), whereas this rule is about the *declared interface* of a composite, which is `action.yml` inputs.)
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

  The bridge-via-env pattern aligns with **Twelve-Factor Factor III** for secret *delivery* (config travels through the environment, not baked into the rendered command); the named-input requirement in the bullet above is a distinct concern and addresses *interface declaration* at the composite's `action.yml` boundary. Both rules are live together — Factor III explains *why* the env bridge is safer; the Marketplace-interface rule explains *why* the input must still be declared.
- **Supply chain.** Flag actions whose `uses:` references point at a mutable ref (`@main`, `@master`, `@latest`, any branch name), or at an action from an untrusted author. Cite GitHub's hardening guide for GitHub Actions and SLSA level-3 build integrity.

  **Default pin-strategy ladder for this repo** (apply consistently when making a finding):

  1. **Mainstream, Marketplace-trusted publishers — major-tag-pin is acceptable.** `actions/*` (official), `docker/*`, `google-github-actions/*`, `softprops/action-gh-release`, `gradle/actions/*`. Use `@v4`/`@v5`/`@v6` etc. The publisher's security posture and move-on-break track record make major-tag acceptable.
  2. **Untrusted / single-maintainer / less-audited sources — SHA-pin.** Full 40-character commit SHA, with a trailing comment recording the intended human-readable tag (`@abcdef1234... # v2.3.1`).
  3. **Escalation — when the repo commits to SLSA Level 3**, SHA-pin *everything* (including tier 1 above) and rotate pins on a cadence. Note this in the finding.

  Flag any `uses:` that violates tiers 1–2 above. Keep "escalate to SHA-pin-everything at SLSA L3" as a forward-looking recommendation rather than a current requirement.
- **Observability — dual surface.** For human review: useful logs and step summaries when the action does significant work. For downstream pipeline decisions: where an action can fail in a recoverable way, expose a structured failure reason as an output (e.g. `status`, `failure-reason`) rather than only exiting non-zero. Flag actions that use `exit 1` for recoverable conditions a caller might want to branch on. Source: SRE ch. 4 "Service Level Objectives", ch. 11 "Being On-Call".
- **Shell portability.** Repo policy is bash-only (see README "Shell choice"); `shell: pwsh` and `.ps1` files are rejected by [check-no-pwsh.sh](../../../shared/_lint/check-no-pwsh.sh). Flag any `shell: pwsh` or `.ps1` found outside the `shared/_test-*` allowlist as a lint-rule escape. Do not recommend keeping pwsh because "the logic benefits from PowerShell object handling" — bash + `jq` is the repo standard for the JSON-munging cases that historically motivated pwsh.
- **`branding:` field.** `branding:` is required by the Marketplace publishing flow but optional for internal actions. **This repo's publication intent is internal-only** (see `actions-auditor.md` "Publication intent for this repo"); therefore missing `branding:` is NOT a finding here. If the author ever flips publication intent to Marketplace, revisit this rule and flag actions lacking `branding:` at that point.

## 1.5 Version-handling actions — follow SemVer

Any action that **composes**, **parses**, **validates**, **compares**, or **emits** a version string must align with [Semantic Versioning 2.0.0](https://semver.org) — the mainstream version-naming standard across the Node, Rust, Go, .NET, and container-image ecosystems this repo's consumers live in. The rubric does not invent a parallel version vocabulary.

Applies to (non-exhaustive): `compose-prerelease-version`, `compose-release-version`, `read-base-version`, `validate-version-unreleased`, `bump-patch-versions`, `resolve-latest-prerelease-tag`, `resolve-latest-tag-from-sha`, `create-component-tags`, and any future action that treats "a version" as a first-class value.

**Input names — use SemVer vocabulary.** When an action accepts a version or its parts, name inputs after the SemVer spec's own terms:

| SemVer concept (spec section) | Input name | Shape | Example |
|---|---|---|---|
| `MAJOR.MINOR.PATCH` (SemVer §2) | `base-version` | `^[0-9]+\.[0-9]+\.[0-9]+$` | `1.0.0` |
| Alphanumeric pre-release identifier (§9) | `suffix` | `[0-9A-Za-z-]+` | `rc`, `dev`, `alpha`, `beta`, `preview` |
| Numeric pre-release identifier (§9) | `build-number` | non-negative integer, no leading zeros | `42`, typically `${{ github.run_number }}` |
| Optional component-tag prefix (extension) | `prefix` | kebab-case identifier | `monolith-java` → `monolith-java-v1.0.0-rc.7` |

Flag as `name-mainstream-convention` any version-handling input named `version`/`ver`/`v` when it actually carries a base-version (ambiguous vs. the full version string), `tag`/`release` when it carries a version (tag and version are distinct), `number`/`counter`/`iteration`/`build` when it carries the numeric pre-release identifier (`number` and `build` are both ambiguous — the former is under-specified, the latter collides with SemVer build metadata), or `release-type`/`channel`/`stage` when it carries the pre-release suffix.

**Composed pre-release format — follow §9.** The canonical output shape for a pre-release is `v{base}-{suffix}.{build-number}` (e.g. `v1.0.0-dev.42`, `v1.0.0-rc.7`). Everything after the hyphen is a series of dot-separated identifiers per SemVer §9. Flag any composer that:

- emits a non-conforming shape (e.g. `v1.0.0-dev-42`, `v1.0.0.dev.42`, `1.0.0+dev.42`) — each breaks the `version-core` / `pre-release` / `build-metadata` grammar.
- drops the leading `v` (repo convention) or adds it inconsistently across sibling actions.
- puts the CI build counter in the **build-metadata** segment (after `+`) rather than the pre-release segment. SemVer §10 explicitly excludes build metadata from precedence comparisons — a `v1.0.0+dev.42` vs `v1.0.0+dev.43` compare as equal under SemVer ordering, which defeats the point of a build counter.

**Prefixed component-tag variants are explicitly permitted.** Names like `monolith-java-v1.0.0-rc.7` are an out-of-band extension for monorepo component-tag namespacing — the segment after the prefix (`v1.0.0-rc.7`) must still conform to SemVer. Flag any prefix design that interleaves with SemVer's own structure (e.g. `v1.0.0-monolith-java-rc.7` — the prefix now masquerades as a pre-release identifier).

**Validation — fail-fast on malformed base versions.** Composer/validator actions must reject bases that don't match `^[0-9]+\.[0-9]+\.[0-9]+$` with an explicit error before doing any other work (cf. §1.3 fail-fast rule). Loose validation (`grep '[0-9]'`, unchecked `split('.')`) is a latent bug.

**Range / comparison semantics — honour SemVer precedence.** Any action that orders versions (latest-tag resolvers, "has version been released" checks, changelog sorters) must implement SemVer §11 precedence — numeric identifiers compared numerically, alphanumeric lexically, shorter pre-release set coming first, build metadata ignored. Flag actions that sort versions as raw strings (`v1.0.0-rc.10` sorts before `v1.0.0-rc.2` lexically but after it per SemVer).

**Out of scope.** Calendar versioning (`2026.04.22`), sequential build numbers without dots (`build-12345`), or non-version identifiers (commit SHAs, content hashes) are not SemVer and this rule does not apply — but an action mixing both (e.g. accepting "either a SemVer or a calver") must say so in its `description:` and not be called `*-version` (use `*-tag` instead).

**Source**: Semantic Versioning 2.0.0 spec, §§2, 9, 10, 11. Authoritative for the naming conventions above; when repo style and spec disagree, the spec wins (per the Mainstream-first principle).

## 1.6 Container image build/tag/push — use BuildKit's fused build+tag+push step

**The rule (platform-agnostic).** Any workflow that builds a container image, labels it, and pushes it to a registry must delegate the three steps to **BuildKit as a single atomic operation** — build, tag, push, and emit attestations (SLSA provenance + SBOM) in one invocation — rather than decomposing them into hand-rolled `build-*` / `tag-*` / `push-*` primitives that shell out to `docker build`, `docker tag`, and `docker push` separately. BuildKit fuses these three steps at the tool level: the build graph already knows the target tags and push destinations, so splitting them externally forces the image through unnecessary local-daemon round-trips and skips BuildKit's remote cache, parallel multi-arch emit, and attestation pipeline.

Applies whenever a workflow or composite action produces a container image that will be consumed downstream (commit-stage → acceptance-stage image handoff, release-stage publication, etc.).

**Platform-specific expressions of the rule.** The rule is universal; each CI platform has its own canonical wrapper around BuildKit's fused capability:

| Platform | BuildKit-capability expression |
|---|---|
| GitHub Actions | `docker/login-action` + `docker/metadata-action` + `docker/build-push-action` |
| GitLab CI | `docker buildx build --push` from a `docker:dind` service (or the Container Registry integration) |
| Jenkins | `docker buildx build --push` pipeline step; Docker Pipeline plugin's BuildKit-aware path |
| Azure Pipelines | `Docker@2` task with `buildAndPush` command (BuildKit-backed when `DOCKER_BUILDKIT=1`) |
| CircleCI | `setup_remote_docker` + `docker buildx build --push`, or the `docker/build` orb |
| Buildkite | `docker buildx build --push` in a shell step, or the `docker-compose` plugin's build+push path |

What they share: a single atomic step that fuses build + tag + push + (where supported) SLSA provenance and SBOM attestation. On any platform, the three-primitive split is wrong because BuildKit collapses the seam; the ecosystem wrapper is the honest representation.

**Rationale — the three-primitive split is the wrong shape for Docker.** Separation of concerns (§6) treats artifact construction, tagging, and push as orthogonal because for some ecosystems (Maven, npm) they genuinely are. For Docker with BuildKit, they are not. The Marketplace composite (on GitHub Actions) and its platform-peer wrappers do not violate §6 — they respect the Docker ecosystem's *actual* build/release seam, which is one step, not three.

**Mainstream-first (see top of file).** `docker/build-push-action` is the ecosystem standard on GitHub Actions (used by `actions/*` examples, by Docker Inc.'s own docs, and by the overwhelming majority of public workflows on GitHub); `docker buildx` is the ecosystem standard everywhere else. Hand-rolled primitives that replicate a subset of either push the repo toward a private dialect for no corresponding gain.

**Capabilities lost when splitting build/tag/push into custom primitives:**

- **Multi-platform builds** (`platforms: linux/amd64,linux/arm64`) — requires BuildKit's cross-arch emit, not `docker build` + `docker tag`.
- **Remote BuildKit cache** (`cache-from`/`cache-to` against `type=registry` or `type=gha`) — shaves minutes off commit-stage rebuilds; not available through the three-step shell split.
- **SLSA provenance attestation** (`provenance: mode=max`) — produces a signed build record attached to the image manifest. SLSA Level 3 requires this to be emitted by the build tool itself, not a post-hoc step.
- **SBOM attestation** (`sbom: true`) — emits a CycloneDX/SPDX SBOM attached to the manifest during build, not bolted on afterwards.
- **Atomic digest output** — `steps.<id>.outputs.digest` returns the registry-resolved digest of the just-pushed image, which is what downstream stages must pin to (see §1 "build-once-promote-many" and the digest-pinning rule below). The three-primitive split requires an extra `resolve-docker-image-digests` round-trip to reconstruct something the Marketplace action already returns for free.

**Companion actions on GitHub Actions — the standard trio.**

| Action | Role | Version pin |
|---|---|---|
| `docker/login-action` | Registry auth (GHCR, Docker Hub, ECR/ACR/GAR via their own auth actions first) | `@v4` (major tag — Marketplace-trusted) |
| `docker/metadata-action` | Compose `tags:` and `labels:` from SemVer, SHA, branch, PR, `latest` rules | `@v5` |
| `docker/build-push-action` | BuildKit-backed build + tag + push + attestations | `@v6` |

`docker/metadata-action` replaces any hand-rolled tag-composition action (`compose-docker-image-urls`, `resolve-prerelease-tag`-into-image-URL, etc.) when the tag set is standard (SemVer + SHA + branch + `latest`). Hand-rolled tag composition is only justified for tag shapes the metadata action cannot express (e.g. component-tag prefixes — see §1.5 prefixed component-tag variants).

**Supply-chain flags — require on every production image build.**

- `provenance: mode=max` — full SLSA provenance (not `mode=min`, which omits materials).
- `sbom: true` — emit SBOM as a manifest attestation.
- Pin companion actions per §1.4 supply-chain pin-strategy ladder (major-tag acceptable for `docker/*`; SHA-pin at SLSA L3).

**Digest-pinned deploy consumers.** Downstream stages (acceptance, release, production) must pin to the image **digest** (`@sha256:...`) emitted by the BuildKit-fused step, not to a mutable tag. Flag any post-commit-stage consumer that references an image by tag alone (exceptions: the repo's documented `:latest` acceptance-stage pull — see §2).

**Flag as DevOps alignment finding → "Separation of concerns" or "Other":**

- Any workflow or composite that uses hand-rolled `build-docker-image` / `tag-docker-image` / `push-docker-image` primitives (or equivalent shelled `docker build` + `docker tag` + `docker push` sequences) in place of the platform's BuildKit-fused expression. Cite this section and recommend migration to the appropriate platform wrapper (GitHub Actions: the Marketplace trio; elsewhere: `docker buildx`).
- Missing `provenance:` or `sbom:` on a fused build step whose output is consumed downstream of the commit stage.
- Downstream stages that reference images by mutable tag instead of digest.

**Does NOT override §6 for non-Docker artifacts.** npm, Maven, NuGet, and zip artifacts retain the build / tag / push separation because their ecosystems model those concerns as genuinely distinct steps (e.g. `npm publish` is tag + push, but `npm pack` is a separate build artifact). This rule is Docker-specific: it recognises that BuildKit collapses the seam, and the Marketplace action (or its platform peer) is the honest representation of that.

**Source:** [`docker/build-push-action` README](https://github.com/docker/build-push-action), [`docker/metadata-action` README](https://github.com/docker/metadata-action), Docker Inc.'s "[Build and push Docker images with GitHub Actions](https://docs.docker.com/build/ci/github-actions/)", [SLSA v1.0 build track](https://slsa.dev/spec/v1.0/levels); BuildKit's [`docker buildx build` reference](https://docs.docker.com/reference/cli/docker/buildx/build/) for cross-platform equivalents.

## 1.7 DORA linkage (sensemaking, not required)

Where useful, link a finding to the DORA metric it moves: composite opacity → MTTR; missing idempotence → change-failure rate; missing primitive-level reusability → lead time; rebuilding downstream of commit stage → change-failure rate and lead time; unbounded retries → MTTR (see §1.3 bounded-retry rule for the specific amplification argument). Source: *Accelerate* (Forsgren, Humble, Kim); DORA State of DevOps reports.

## 1.9 Marketplace-action version currency — pin to the latest major

Every `uses: <owner>/<repo>@<ref>` reference to a marketplace (non-local, non-first-party-internal) action inside an `action.yml` `runs.steps:` block or inside a consumer workflow must pin to the **latest major tag** published upstream. Stale majors silently miss security fixes, bug fixes, Node-runtime upgrades, and (when the ecosystem moves) eventual forced migration under time pressure. The rubric's "no deprecated tools" stance (see repo policy) applies here as a positive duty, not just an avoidance rule.

**In scope for this dimension:**

- `uses:` refs to GitHub-hosted third-party actions (`actions/*`, `docker/*`, `google-github-actions/*`, `softprops/*`, etc.).
- `uses:` refs to reusable workflows (`owner/repo/.github/workflows/foo.yml@ref`).
- Both the top-level workflow `jobs.<job>.steps.uses:` and the composite `runs.steps.uses:` inside this repo's `action.yml` files.

**Out of scope:**

- Local composite refs (`./`, `../`) — no upstream release cadence.
- First-party internal actions owned by this workspace (`optivem/actions/*`, `optivem/<name>-action`) — version cadence is governed by the internal release process documented elsewhere, not by external Marketplace releases.
- Refs pinned to a full commit SHA with a trailing `# v<N>` comment — honour the comment as the intended major; only flag if the comment itself is behind latest.

**How to check.** For each unique `<owner>/<repo>` in scope, query `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name` and extract the leading major. Compare against the major embedded in each `uses:` ref. Deduplicate queries across the audit — one query per distinct repo, not per call site.

**Categories of finding (shared with `workflow-auditor` §2):**

- **D — Behind latest major.** A ref pins an older major than upstream `releases/latest`. Recommend bumping to the new major tag. Note breaking-change risk when the diff is known to be non-mechanical (breaking input renames, removed inputs, runtime bumps).
- **E — Mixed majors within the workspace.** The same action is referenced at two or more majors across the audited repos. Recommend aligning on the latest major already in use (usually matches upstream latest; if not, say so).
- **F — Deprecated / archived upstream.** Upstream is archived, README points to a replacement, or the repo has had no release in >24 months with an open advisory (e.g. `actions/create-release@v1` → migrate to `softprops/action-gh-release`). Recommend naming the maintained replacement and migrating — **not** merely bumping the major — because the interface has likely changed.

**Anti-patterns flagged alongside D/E/F:**

- `@master` / `@main` floating refs on marketplace actions — pins the caller to whatever HEAD happens to be. Recommend a major tag.
- Patch-pinned refs (`@v1.0.2`) without a documented rationale (security review lock, reproducibility guarantee). Prefer the major tag so consumers pick up patches automatically.

**Rate-limit awareness.** `gh api releases/latest` calls count against the 5000/hr authenticated ceiling. Cap at one query per distinct `<owner>/<repo>` per audit run. If the unique-repo count exceeds a reasonable budget (roughly 60 distinct repos for a single pass), split the audit across runs or accept partial results and say so in the report.

**Filing guide.** File findings under the DevOps alignment section's **Other** subsection in the auditor reports, tagged `§1.9`. External-scope (because the fix changes a surface-visible `uses:` ref that consumers can see in reviews, and on a major bump may require synchronised consumer updates when inputs changed). Classify **breaking** when the upstream major changelog documents removed or renamed inputs, **non-breaking** when the major bump is input-compatible (common for `actions/checkout` major bumps). When in doubt, classify as **breaking** per the external-file tie-breaker.

**Source:** repo policy "no deprecated tools"; `workflow-auditor.md` §2 (shares this rubric dimension); workspace audit on 2026-04-23 that surfaced ~170 stale `actions/checkout@v5` refs alongside multiple other behind-latest actions.

## 1.8 Thin wrappers around mainstream actions — delete in favour of direct use

A custom composite that exists only to forward inputs to one or two mainstream actions (no retry, no cross-host handling, no org-specific composition, no material shared logic) is a private dialect and must be replaced by calling the mainstream action directly from the workflow. Generalises §1.6 — what the docker trio rule is for build/tag/push, this rule is for setup, release, and deploy.

**Detection — a wrapper is "thin" when its `runs.steps:` reduces to one of these shapes:**

- A single `uses:` step that forwards inputs 1:1 to a mainstream action (pure pass-through).
- Two `uses:` steps that compose a mainstream pair (e.g. `actions/setup-java` + `gradle/actions/setup-gradle`) with no added customisation beyond forwarding the caller's `*-version` input.
- A `uses:` step plus a trivial follow-on `run:` block (e.g. `setup-node` + `npm ci`) where the follow-on is a project build concern that belongs in the caller, not in a "setup" wrapper.

**Material logic that justifies a custom wrapper — NOT thin:**

- Retry / rate-limit handling (`gh_retry`, bounded backoff) that the mainstream action does not provide.
- Cross-host or cross-tool composition (e.g. an action that drives multiple registries, multiple CI platforms, or multiple package managers from one input).
- Org-specific composition of outputs (e.g. non-SemVer tag shape, component-tag prefix, idempotent no-op on matching SHA).
- Race-safe writes (e.g. Contents API with SHA preconditions, optimistic-concurrency retry).
- Org-specific retention / cleanup policy that expresses a repo-level decision (e.g. prerelease cleanup window).
- Post-hoc verification tightly coupled to the mainstream step (e.g. digest pinning, attestation extraction) that is not expressible through the mainstream action's inputs.

If a wrapper fails the "thin" test and passes the "material logic" test, keep it. If it fails "thin" AND fails "material logic", delete it — but add an `Additional findings` note naming which material-logic category was missing, in case the author meant to add it.

**Concrete replacement table — setup, release, and cloud deploy.**

Version pins below are current as of rubric v8 (2026-04-22). Re-validate against the latest Marketplace release before citing in an audit report — major tags roll (e.g. `actions/setup-node@v5` → `@v6`) and stale pins in a rubric don't invalidate the pattern but can mislead authors following the table literally.

| Thin wrapper pattern | Mainstream replacement | Version pin | Migration notes |
|---|---|---|---|
| `setup-dotnet` (1:1 pass-through) | `actions/setup-dotnet` | `@v5` | Direct call; single `dotnet-version` input maps identically. |
| `setup-java-gradle` (two-step composite, hardcoded distribution) | `actions/setup-java` + `gradle/actions/setup-gradle` | `@v5` + `@v5` | Inline both steps in the workflow; `distribution: temurin` becomes a caller-visible choice. |
| `setup-node` (setup + `npm ci` conflated) | `actions/setup-node` + `npm ci` | `@v5` | Keep `cache: 'npm'` + `cache-dependency-path` on `setup-node`; move `npm ci` to a separate caller step. Separates "setup" from "build". |
| `create-github-release` (thin `gh release create/edit`) | `softprops/action-gh-release` | `@v2` | Idempotent by default when `tag_name` exists; preserves existing assets unless `files:` is set. Input mapping: `tag`→`tag_name`, `title`→`name`, `notes-file`→`body_path`, `is-prerelease`→`prerelease`. Output: consume `steps.<id>.outputs.url`. |
| `deploy-to-cloud-run` (thin `gcloud run deploy`) | `google-github-actions/deploy-cloudrun` | `@v2` | Google's official action covers all current inputs 1:1 (`service`, `image`, `region`, `project_id`, `env_vars`, `secrets`, sizing flags, `--allow-unauthenticated` via `flags`). Lift the embedded readiness poll (`wait-for-endpoints`) into a separate caller step. |

When auditing, apply this lens to any custom wrapper: does it forward inputs to a mainstream action without adding material logic? If yes, delete. Extend the table above when new mainstream actions subsume further custom wrappers in this repo.

**Don't mistake orchestration for a wrapper.** A composite that chains `docker/login-action` + `docker/metadata-action` + `docker/build-push-action` + a post-push verify step (e.g. digest extraction, attestation assertion) may look like "four `uses:` steps" but passes the material-logic test because the post-push verify is not expressible through any single mainstream action. §1.6 governs that case; do not flag it under §1.8.

**Flag as DevOps alignment finding → "Separation of concerns" or "Other":**

- Any custom action whose `runs.steps:` match a "thin" shape and has a mainstream replacement. Cite this section, the specific replacement action, and the version pin.
- Any new wrapper being proposed in a PR that would re-introduce a thin shape (pre-emptive flag — don't wait for it to land).

**Does NOT apply to:**

- Concerns with no maintained mainstream action (e.g. `wait-for-endpoints`, `commit-files` via Contents API with SHA preconditions, org-specific prerelease-retention actions). Pass the "material logic" test → keep.
- Wrappers that exist for a documented, time-bounded reason (migration bridge, deprecation shim). Flag these with an expected removal date and revisit on each audit.
- Unmaintained "alternatives" (last release >18 months old, open security advisories, single-maintainer with no backup). `convictional/trigger-workflow-and-wait` is the canonical example — do not recommend migration to unmaintained actions (see the "no deprecated tools" rule in repo policy).

**Source:** §1.6 precedent; Mainstream-first principle at top of file; `actions/setup-*` README examples; [`softprops/action-gh-release` README](https://github.com/softprops/action-gh-release); [`google-github-actions/deploy-cloudrun` README](https://github.com/google-github-actions/deploy-cloudrun).

---

# 2. Forward-looking context (repo-specific exemptions)

The repo is a teaching vehicle that evolves over time. Some things that look incomplete today are deliberate stepping stones, not gaps. Do not flag them as missing.

- **Docker Compose is a temporary stepping stone.** The current deployment story uses `docker compose up` locally or on a CI runner. Cloud-based deployment (Kubernetes, AWS ECS / Fargate, Azure App Service, Google Cloud Run, etc.) is planned for a later stage of the course. Do **not** recommend adding cloud-deploy actions now, and do **not** flag the absence of one as a gap. What you *should* flag is naming that claims to do something the action doesn't yet do (e.g. calling a docker-compose step `deploy-to-production`).
- **The list of environments is author-determined.** The set of environments (dev, staging, acceptance, production, canary, preview, etc.) is decided by the course author per course, not fixed by this repo. Do **not** recommend adding or removing environments. Only flag inconsistencies *within* the environments that already exist.
- **Future-proofing note for consolidation suggestions.** When proposing consolidated actions, design inputs and outputs so they will extend naturally to a cloud-deploy world and to additional environments. Prefer generic names (`target`, `environment`, `deploy-method`) over Docker-specific ones in the signature, even if the only current implementation is Compose.
- **`:latest` is load-bearing in this pipeline — do NOT flag it as an anti-pattern.** The acceptance stage intentionally pulls `:latest` to exercise the newest post-commit, pre-release image against the system test suite. That's the defined role of `:latest` here: "the most recent passing commit-stage build." Versioned/SHA-pinned tags are used from acceptance-stage onward for reproducibility. The mainstream argument against `:latest` applies to *production* use, which this pipeline does NOT do — prod-stage pins by version/SHA. Do not recommend making `:latest` push opt-in, do not recommend removing the `image-latest-url` output, and do not cite SRE/K8s `imagePullPolicy` guidance against it in this repo.
- **Teaching-clarity override (flag, don't block).** Mainstream consolidation always wins (see the Mainstream-first principle at the top of this file); this "override" does not reverse that. What it does: when a proposed consolidation would flatten a distinction that a course lesson or exercise *actively teaches* as curriculum, the finding must explicitly flag the pedagogical impact and name the lesson/sandbox page(s) that need updating alongside the code change. Do NOT invoke this to protect rubric-internal splits that diverge from mainstream GitHub Actions conventions (e.g. `check-*` = assert vs. `has-*` = query — not Marketplace convention; do not preserve). Evidence that a distinction is "actively taught" is a concrete lesson or sandbox file that relies on it — mere consistency with an internal style preference is not sufficient.

---

# 3. Tool-agnostic vs. platform-specific naming (tiers)

Students may swap the CI/CD platform for their own pipeline (GitHub Actions → Jenkins, GitLab CI, Azure Pipelines, AWS CodePipeline, CircleCI, Buildkite, etc.) and may swap the git host (GitHub → GitLab, Bitbucket, Gitea, self-hosted). The naming convention must make it obvious at a glance which actions carry portable concepts vs. which carry GitHub-platform-specific glue.

## 3.1 Naming tiers

Three conceptual tiers. Only the third gets a prefix.

- **Tier 1 — fully generic** (any CI, any VCS, any host). No prefix. Examples: `build-image`, `push-image`, `wait-for-approval`, `bump-version`, `run-tests`, `deploy-service`, `validate-config`.

  *Tier 1 covers actions whose **concept** is universal. The language-runtime setup primitives (`setup-node`, `setup-java-gradle`, `setup-dotnet`) historically lived in this repo as thin wrappers around `actions/setup-*@v5`, but per §1.8 those wrappers are being deleted — callers now invoke `actions/setup-*` directly. The Tier 1 concept still applies at the workflow level: every CI has a language-runtime setup primitive, and a porting student replaces `actions/setup-*` with the equivalent on their target CI. When auditing a remaining Tier 1 action in this repo that is implemented via a platform-specific mainstream action, flag it as "Tier 1 name, platform-specific implementation" so the porting surface is visible — and apply the §1.8 thin-wrapper test to decide whether the wrapper itself should be deleted.*

- **Tier 2 — git-native** (any CI, any git host, but requires a git VCS). No prefix. Git is the assumed baseline — adding `git-` to names is redundant because the domain nouns (`tag`, `commit`, `sha`, `ref`, `branch`) already imply git. Examples: `validate-tag-exists`, `resolve-latest-tag-from-sha`, `publish-tag`, `validate-version-unreleased`, `bump-patch-versions`.

  *Implementation sub-rule for Tier 2:* Tier 2 actions must not hardcode `github.com` in their implementation. Remote URLs should be parameterised — either accept a `git-host` input with default `github.com`, or derive the host from a `repo` input given in URL form. The pattern `https://x-access-token:${TOKEN}@github.com/...` breaks Tier 2's portability claim: a student porting to GitLab, Bitbucket, Gitea, or self-hosted would have to edit every Tier 2 action. Flag actions that hardcode the git host as a **portability violation** under **DevOps alignment findings** → "Tool-agnostic composition".

- **Tier 3 — platform-API-specific** (requires a forge API, not just git). These are concepts accessed through a platform API rather than git itself: Releases, commit statuses, Deployments, workflow runs, Packages, Issues, PRs, check runs. Most of these concepts exist across forges — GitHub, GitLab, Gitea, and Bitbucket all have Releases and commit statuses; GitLab calls workflow runs "pipeline runs" — so "Tier 3" means "reached via platform API", not "GitHub-exclusive".

  **When a Tier 3 name gets the `github` segment — the ambiguity test:** add `github` (or a narrower segment like `ghcr`) only when the bare core noun would collide with generic English or other domains. Leave it off when the compound noun is already self-disambiguating.

  | Core noun | Ambiguous bare? | Name |
  |---|---|---|
  | release | yes (product release, software release) | `create-github-release` † |
  | deployment | yes (generic software deployments — k8s, Cloud Run) | `cleanup-github-deployments` |
  | prerelease | yes (semver prerelease tag) | `cleanup-github-prereleases` |
  | workflow, workflow-run | yes (business workflows, data workflows, ML workflows) | `wait-for-github-workflow`, `trigger-and-wait-for-github-workflow` |
  | packages | yes (npm, OS, language packages) — use narrower `ghcr` | `check-ghcr-packages-exist` |
  | commit-status | no — compound noun, no collision in any dev domain | `create-commit-status`, `get-commit-status` |

  Rationale: "commit status" means the same thing on GitHub, GitLab, Gitea, and Bitbucket, and nothing else in software uses the compound — so prefixing with `github` would falsely narrow the name without adding clarity. "Release" or "workflow" alone is ambiguous across domains, so the prefix earns its keep.

  † `create-github-release` is retained here as a naming-pattern illustration only. This repo no longer ships it as a local action — per §1.8 it has been replaced by direct calls to `softprops/action-gh-release@v2`. The name remains the canonical example of a Tier 3 concept that needs the `github` segment.

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

## 3.5 Platforms validated / not covered

The tier system and portability claims in §3 have been mentally ported against: **Jenkins**, **GitLab CI**, **Azure Pipelines**, **CircleCI**, **Buildkite**. Findings that cite "portability" without further qualification refer to this set.

Not covered yet: **AWS CodePipeline** (stage/action model is atypical — each stage maps to AWS service actions rather than shell steps), **Spinnaker** (pipeline-graph + manifest-driven — closer to Kubernetes CD than to shell-CI), **Argo Workflows / Argo CD** (GitOps declarative, not imperative), **Tekton** (Kubernetes-native CRDs). A Tier 2 action's portability claim against these platforms is aspirational, not validated — flag any porting advice to them as "best-effort, not validated."

When adding a new validated platform, extend the portability-pass list in the `actions-auditor-reviewer` agent too.

## 3.6 Tags vs commit-statuses — when to use which

A pipeline gate's state ("deployed to QA", "QA-approved", "acceptance-tests passed") can be recorded in two fundamentally different mechanisms. They look similar at a glance but serve different purposes. Pick the right one per gate.

### Decision criterion

Ask: **do downstream workflows need to *find* the thing by name, or just *check if it happened*?**

| Need | Mechanism | Why |
|---|---|---|
| Identifier used for lookup/resolve/trigger (e.g., "deploy the latest `-qa-approved` RC"; `on: push: tags:` triggers) | **Git tag** | Tags have names that workflows can resolve and trigger on. |
| Boolean "has this happened?" bookkeeping (e.g., "skip acceptance-stage re-run if same SHA already tested") | **Commit status** | Statuses live on the specific commit, carry `state`, and never need to be resolved by name. |

### Properties

| | Git tag | Commit status |
|---|---|---|
| Tier (§3.1) | Tier 2 — portable (Git-native) | Tier 3 — GitHub-specific |
| Name-addressable | Yes (`refs/tags/<name>`) | No (query by SHA + context) |
| Carries state field? | No — all meaning must live in the name | Yes (`success` / `failure` / `pending` / `error`) |
| Can be the target of `on: push:` triggers? | Yes | No |
| Visible in `git tag -l` / `gh release list`? | Yes | No (API-only) |
| Cross-host portable? | Yes (works on GitLab, Bitbucket, self-hosted) | No (GitHub only; other hosts have similar but not identical concepts) |
| Cleanup needed? | Yes — the tag namespace grows per-commit (`cleanup-github-prereleases` handles this) | No — statuses ride with the commit |

### Naming convention consequences

Because tags and commit-statuses have different data models, their name conventions diverge:

- **Tag names end in a past-participle verb.** The name carries the full meaning (`v1.0.0-rc.5-qa-deployed`, `v1.0.0-rc.5-qa-approved`) — tags have no `state` field, so the verb IS the state. Failure states typically aren't recorded as tags at all (you just don't create the tag).
- **Commit-status contexts do NOT end in a verb.** The `state` field carries the outcome; the context names the *type of check* (`acceptance-stage`, not `acceptance-stage-passed`). Putting `-passed` in the context is redundant with `state=success` and becomes self-contradictory if you ever record a failure (`context: acceptance-stage-passed, state: failure`).

### When a finding applies

Flag an action/workflow as mechanism-mismatched when:

- A name-addressable gate (something downstream resolves, triggers on, or looks up by name) uses commit-statuses — the caller has to resort to API scans to find what should be a simple `git ls-remote` or `on: push: tags:`.
- A pure boolean-bookkeeping gate (no downstream name-lookup) uses tags — cluttering the tag namespace and forcing cleanup jobs that wouldn't exist if it were a commit-status.
- A commit-status context ends in a past-participle verb (`-passed`, `-approved`, `-deployed`) — propose dropping the verb suffix and relying on `state`.
- A pipeline tag name is a pure noun with no verb (e.g., `v1.0.0-rc.5-qa`) — propose adding the verb so the tag is self-explanatory without context lookups.

### Mixed usage is OK

It's correct for a single pipeline to use both mechanisms — tags for pipeline-stage identifiers (`-qa-deployed`, `-qa-approved`), commit-statuses for "has-this-been-done-yet" bookkeeping. Don't flag the coexistence; flag only individual mechanism-mismatches per the criterion above.

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
  - `release-*` / `ship-*` must make features available to users (not merely produce a tag or artifact, and not merely move a pre-existing artifact between pre-prod environments — that's `promote-*`).
  - `promote-*` must move an already-built artifact (by digest, tag, or reference) from one pipeline stage to the next per Farley's definition — it must NOT rebuild, re-tag-from-source, or re-compile. An action that re-runs `docker build` or fetches source during a "promotion" is mixing build and release stages; cite Farley & Humble, *Continuous Delivery* ch. 5 (build-once-promote-many).
  - `publish-*` must make an artifact available on its publication surface (registry, package index, release feed) for external consumers to fetch. An action that only pushes to a private scratch registry or re-tags without announcing is not `publish-*` — use `push-*` or `tag-*`.
  - `build-*` must produce an artifact — not merely download or reference one. A "build" action that only pulls a prebuilt binary should be `fetch-*` or `pull-*`.
  - `validate-*` must fail the step on invalid input. An action that logs a warning and continues is `check-*` or `inspect-*`, not `validate-*`.
  - `cleanup-*` must remove things. An action that scans and lists candidates without removing is `find-*` or `list-stale-*`.
  - `wait-for-*` must poll until the thing becomes true (or time out). An action that checks once is a one-shot boolean-return query — the preferred verb is `check-*` (mainstream default); `has-*` and `is-*` are acceptable aliases. Do not enforce a rubric-internal distinction between them (the "`check-*` = assert-and-fail vs. `has-*` = query" split is not Marketplace convention).
- **Generalise the above rule beyond this list.** The eight verbs above are the repo's most commonly-abused ones, but the principle — *the verb must honestly describe what `runs:` does, per mainstream DevOps/CD meaning* — applies to every verb. In particular, spot-check any verb that *sounds* read-only but could have side effects: `resolve-*`, `compose-*`, `generate-*`, `ensure-*`, `read-*`, `get-*`, `find-*`, `list-*`, `has-*`, `is-*`, `check-*`, `inspect-*` (prefer `get-*` over `read-*` per the Mainstream-first principle at top-of-file). An `ensure-*` or `resolve-*` action that writes state (creates files, pushes refs, posts commit statuses) should be renamed to the appropriate side-effecting verb (`create-*`, `push-*`, `set-*`). When in doubt, flag it and let the author decide.

  **Canonical semantics for the spot-check verbs** (use this table to judge whether an action's `runs:` block matches its verb):

  | Verb | Canonical meaning | Side effects allowed |
  |---|---|---|
  | `resolve-*` | Look up / compute a value from existing state (e.g. SHA from tag, digest from tag). Pure function of its inputs + read-only queries. | None — read-only. If it writes, rename to `create-*` / `set-*` / `push-*`. |
  | `compose-*` | Pure string / data transform over its inputs (e.g. compose a version string from base + suffix + build-number; compose a list of image URLs). | None — no I/O beyond reading inputs. If it queries the network or filesystem, it's probably `resolve-*`. |
  | `generate-*` | Produce a fresh artifact from inputs (file, token, config). May write locally but shouldn't mutate shared state. | Local writes only (step output, workspace file). If it pushes anywhere, rename to `create-*` / `publish-*`. |
  | `ensure-*` | Idempotent create-if-missing: if already in the desired state, no-op; otherwise converge it. | Creates the thing named in the suffix (tag, file, label). Never deletes. |
  | `read-*` | Read from a declared source (file, env, input). Prefer `get-*` over `read-*` (mainstream-first); `read-*` is acceptable when the source is a specific file by path. | None — read-only. |
  | `get-*` | Side-effect-free read of a remote or computed value (API, VCS, step context). Mainstream ecosystem default for read actions. | None — read-only. |
  | `find-*` | Query that returns matches (zero or more) from a scan over an enumerable space. May require listing; must not mutate. | None — read-only. |
  | `list-*` | Enumerate items in a known collection. | None — read-only. |
  | `has-*` / `is-*` | Boolean-return query. `has-*` for set membership / existence; `is-*` for a state predicate. Acceptable aliases of `check-*`. | None — read-only. |
  | `check-*` | Mainstream boolean-return query verb (see Mainstream-first principle). Does NOT mean "assert-and-fail"; the assert form is `validate-*`. | None — read-only. |
  | `inspect-*` | Read + enrich / summarise (e.g. inspect a tag to report author + timestamp + signed-status). | None — read-only. |

  When a verb's semantics here conflict with what the action's `runs:` block actually does, flag it and propose a better verb.

For each violation, propose a specific better name and say which rule it violates.

---

# 5. Architecture: primitives first, composites optional and thin

> **Terminology.** This rubric uses "primitive", "single-concern action", and "one concern per action" interchangeably — all refer to the same construct: an action that owns exactly one concern from the orthogonal set enumerated in §6.

Prefer small, single-concern **primitive** actions over large composite actions that bundle multiple concerns. Composites are acceptable **only as thin sugar** over primitives that can also be called directly at the call site.

> **Rule:** every behavior exposed by a composite must also be reachable by calling primitives directly. A composite that hides logic that callers cannot otherwise replicate step-by-step is a design smell.

Why:

- **Scales with new artifact types / targets.** A Docker-specific prerelease composite can't accept npm packages. If prerelease creation is decomposed into `compose-prerelease-version` → `tag-<artifact-type>` → `softprops/action-gh-release@v2`, adding a new artifact type means adding one new tagging primitive — not a whole parallel composite.
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
| **Version source** | release | VERSION files / `package.json` / `pom.xml` / Cargo.toml / latest git tag | `read-base-version`, `compose-prerelease-version` |
| **Artifact construction** | build | Docker images / npm packages / Maven JARs / NuGet / zip bundles | For Docker: `docker/build-push-action@v6` (see §1.6 — build/tag/push collapse into one Marketplace step). For npm/Maven: dedicated primitives per ecosystem. |
| **Artifact release tagging** | release | `docker tag :v{version}` / `npm publish --tag` / Maven release plugin | For Docker: `docker/metadata-action@v5` feeding `docker/build-push-action@v6` (§1.6). For other ecosystems: future `tag-npm-package`, `publish-maven-artifact`. |
| **Git tag creation** | release | `git tag` + `git push` / Contents API / `gh release create` (coupled) | `publish-tag`, `validate-tag-exists` |
| **Release record** | release | GitHub Release / GitLab Release / Bitbucket Downloads / none | `softprops/action-gh-release@v2` (GitHub) — per §1.8 the repo no longer ships a local `create-github-release`. |
| **Commit of generated files** | release | `git push` / Contents API / merge-request PR | `commit-files` |
| **Status / approval signalling** | release | GitHub commit statuses / GitLab commit statuses / Slack messages / email | `create-commit-status` |

**Factor V violation signal:** an action named `build-*` that also performs release-stage tagging (e.g. `docker tag :v{version}`) is mixing the *build* and *release* stages. Flag it as a concern-mixing violation and cite Factor V — [The Twelve-Factor App](https://12factor.net/build-release-run). **Docker-specific carve-out:** the Marketplace composite `docker/build-push-action` legitimately bundles build + tag + push because BuildKit collapses the seam at the tool level, not the workflow level — this is not a Factor V violation; see §1.6.

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

## 6.3 Performance exception: don't split when both outputs derive from the same atomic query

The one-concern-per-action rule serves **swappability** — the ability to swap one concern's implementation without touching the others. It is not an end in itself. When two logical outputs come from the same underlying atomic operation (a single API call, a single registry query, a single `git ls-remote`, a single file read), splitting the action into two typically **doubles the cost of that operation without delivering any swappability gain** — both halves would still have to run the same query, and neither is independently replaceable because both depend on the same upstream source of truth.

**Rule:** before proposing a split under §6, apply this test:

> "If I split this, will the two new actions each run the same underlying query/read/call? If yes, the 'two concerns' are actually one atomic operation with two projections — **keep them merged** and flag it as 'merged projections of a single atomic source' rather than as a concern-mixing violation."

**Concrete example (rejected split):** `resolve-docker-image-digests` emits both `image-digest-urls` and `latest-updated-at`. On the surface these look like two concerns (digest resolution vs. newest-timestamp aggregation). But both values are projections of the same `docker manifest inspect`-equivalent registry query. Splitting into `resolve-docker-image-digests` + `get-latest-image-timestamp` would force every caller that reads both outputs (all 18 consumers in shop) to run the query twice. No caller gains swappability — the registry-query implementation is the same atomic thing either way. **Keep merged.**

**When a split IS still correct despite shared data:** if the two projections are consumed by *different* callers (e.g. caller A reads only the digest, caller B reads only the timestamp), splitting may be worthwhile because each caller pays for only what it uses. But that's a caller-profile argument, not a §6 orthogonal-concerns argument — make it explicit when you propose the split.

**Where to apply this test:** any §6-motivated split proposal where the underlying implementation is a single query/read/call. If you cannot point at two *independently reimplementable* backends, you do not have two concerns — you have one concern with two output projections.

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
docker/build-push-action@v6             # 1. artifact exists but nothing references it yet
publish-tag                             # 2. tag points at an already-published image
softprops/action-gh-release@v2          # 3. release references an already-existing tag
notify / announce                       # 4. only after the release record is real
```

If step 3 fails, you have a tagged image and a git tag — both re-runnable. If the order were reversed (release first, then tag, then image), a failure at step 2 leaves a GitHub Release pointing at a tag that doesn't exist, visible to users.

## 7.2 Idempotence rule: every primitive must be safe to rerun

Each primitive must converge to the same end state whether it's the first run or the hundredth:

- **Tag creation** — create-if-missing, otherwise verify-or-update; never fail because "tag already exists" when the existing tag already points at the intended SHA.
- **Artifact push** — pushing an already-published image/package to the same tag is a no-op or an overwrite, not an error.
- **Release record** — create-if-missing, otherwise update-in-place; a rerun must not produce two Releases for the same tag.
- **Status / notification** — either deduplicate on a stable key, or scope the notification to a step that only runs on first success.

Actions that silently succeed on a genuine no-op are fine; actions that *fail* on a rerun because "the thing already exists" are a pipeline-fragility bug.

## 7.3 Concrete example — Marketplace image build + two primitives

```
(external)  docker/build-push-action@v6        # concern: artifact type & push  (see §1.6)
actions/
  publish-tag/action.yml                       # concern: git tag creation
(external)  softprops/action-gh-release@v2     # concern: release record        (see §1.8)
```

Image build + tag + push is owned by the Marketplace composite, not a local primitive (§1.6). Release-record creation is owned by `softprops/action-gh-release` per §1.8, not a local `create-github-release` wrapper. The remaining local primitive (`publish-tag`) accepts only the inputs for its own concern (`tag` and `sha`, not `image-url` or `release-notes`). The caller composes them in reversibility order:

```yaml
jobs:
  release:
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v4
        with: { registry: ghcr.io, username: ${{ github.actor }}, password: ${{ secrets.GITHUB_TOKEN }} }
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/acme/api
          tags: |
            type=semver,pattern={{version}},value=v${{ inputs.version }}
            type=sha,format=long
      - id: push
        uses: docker/build-push-action@v6        # 1. cheapest to reverse — image pushed, digest emitted
        with: { push: true, tags: ${{ steps.meta.outputs.tags }}, provenance: mode=max, sbom: true }
      - uses: optivem/actions/publish-tag@v1     # 2. movable
        with: { tag: v${{ inputs.version }}, sha: ${{ github.sha }} }
      - uses: softprops/action-gh-release@v2     # 3. user-visible (per §1.8 — no local wrapper)
        with:
          tag_name: v${{ inputs.version }}
          body: ${{ inputs.notes }}
```

Downstream stages pin to `steps.push.outputs.digest` (the `@sha256:…` digest), not the mutable tag — see §1.6 "Digest-pinned deploy consumers".

A thin composite wrapper that runs these four steps in this order is acceptable **only if** each step (including the Marketplace ones) remains independently callable and the wrapper adds no behavior beyond the fixed sequence.

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
| Action retries on failure without a bounded retry count / backoff, or polls indefinitely | DevOps alignment → **Idempotence** |
| Action expects caller to set an implicit `env:` for a token instead of declaring it as a named input | DevOps alignment → **Secrets / auth** |
| Action interpolates `${{ inputs.token }}` or `${{ env.TOKEN }}` directly into a `run:` shell line instead of bridging via step-level `env:` | DevOps alignment → **Secrets / auth** |
| Action calls `gh api` in a loop or at high frequency without rate-limit awareness (no backoff, no caching) | DevOps alignment → **Other** |
| Action pins a dependency to a mutable ref (`@main`, `@v1`, branch tag) rather than an immutable SHA | DevOps alignment → **Other** |
| Action uses `exit 1` for a recoverable failure, hiding the specific error from observability | DevOps alignment → **Other** |
| Action uses `shell: pwsh` or `.ps1` outside the `shared/_test-*` scope, violating shell portability | DevOps alignment → **Other** |
| Everything else DevOps-related that doesn't fit above | DevOps alignment → **Other** |

---

# Version history

Newest first. Bump `Rubric version:` at the top of this file whenever §1–§8 change materially, and tag any re-audit findings that exist only because of the bump as `[RUBRIC-CHANGE v<N>]`.

- **v8 (2026-04-22)** — added §1.8 "Thin wrappers around mainstream actions — delete in favour of direct use", generalising §1.6 to cover setup/release/deploy wrappers with a concrete replacement table (`setup-dotnet`/`setup-java-gradle`/`setup-node` → official `actions/setup-*`; `create-github-release` → `softprops/action-gh-release`; `deploy-to-cloud-run` → `google-github-actions/deploy-cloudrun`). Refreshed §3.1 Tier 1 examples to cross-reference §1.8. Reframed §1.6 as a platform-agnostic "BuildKit-capability" rule with per-platform expressions (Jenkins/GitLab/Azure/CircleCI/Buildkite alongside the GitHub Actions Marketplace trio). Added §1.3 "Fast-feedback sizing" rule for blocking actions (Farley 5-minute commit-stage budget). Appended DORA/MTTR linkage to the §1.3 bounded-retry rule. Tightened §1.4 supply-chain rule with a default pin-strategy ladder (mainstream major-tag / untrusted SHA / SLSA-L3 everything-SHA). Carved out the `branding:` rule for internal-only publication intent. Appended a Twelve-Factor III linkage to the §1.4 bridge-via-env example. Added §4 canonical-semantics table for the spot-check verbs (`resolve-*`, `compose-*`, `ensure-*`, `get-*`, `read-*`, etc.) so verb judgments are mechanical. Extracted this version-history section.
- **v7 (2026-04-22)** — **posture shift: this repo is production infra, not a teaching vehicle.** Rewrote §2 "Forward-looking context" to drop the teaching-vehicle framing and the "teaching-clarity override" (real-world best practice is now the default, not a tie-breaker). Added §1.6 "Container image build/tag/push — use mainstream composite actions" requiring `docker/build-push-action` + `docker/metadata-action` over hand-rolled build/tag/push splits, with supply-chain flags (SLSA provenance, SBOM, digest-pinned deploys). Renumbered DORA linkage to §1.7.
- **v6 (2026-04-22)** — added §1.5 "Version-handling actions — follow SemVer": any action that composes, parses, or validates a version string must use SemVer 2.0.0 vocabulary and shape, with concrete input-name guidance (`base-version`, `suffix`, `build-number`) and explicit guidance against using SemVer build metadata for CI counters.
- **v5 (2026-04-22)** — extended the `commit-sha` rule in §1 to cover outputs: qualification now preferred for action outputs / job outputs when the producer is generic or produces multiple SHAs; bare `sha` stays acceptable when a resolver-style action's name already disambiguates.
- **v4 (2026-04-22)** — strengthened the `commit-sha` vs. `sha` rule for inputs.
- **v3 (2026-04-22)** — added ambiguity test for Tier 3 `github` prefix; decoupled "Tier 3" from "name carries `github`".
- **v2 (2026-04-21)** — added Mainstream-first principle, bounded-retry rule, VCS-vs-platform-API renaming, promote/publish/ship verb rules.
