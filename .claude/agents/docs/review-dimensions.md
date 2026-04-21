# Review dimensions for the actions-auditor-reviewer

This is the reference dimensions list used by the `actions-auditor-reviewer` agent. Each dimension names a frame of reference the reviewer applies when reading the `actions-auditor` rubric — what to check for, what signals to watch, and what sources to cite.

Apply all five dimensions. A finding can belong to more than one — say so.

**You are not restricted to these five dimensions.** They are the floor, not the ceiling. If you notice something that matters but doesn't fit any named dimension — a structural issue, a missing safeguard, a subtle bias in the rubric, a concern the author didn't think about, a foreseeable failure mode, tooling assumptions, security/supply-chain implications, teaching-value problems, anything — flag it under **Additional findings** in the report. The named dimensions exist so the author gets a predictable baseline, not to cap what you're allowed to notice.

---

## 1. Internal consistency

Check that the agent's rules do not contradict themselves or leave the auditor without a clear answer in foreseeable cases.

Signals:

- Two rules that could both apply to the same case and give opposite recommendations (e.g. "default to keep unused inputs" vs. "flag unused inputs for removal" without a tie-breaker).
- A rule whose examples contradict the rule's text.
- A category in the **Output** section that the **Process** section gives no instructions for populating.
- A tier / classification that is defined but never referenced in the auditing instructions, or referenced but never defined.
- A `[SKIPPED — breaking]` / `backwards_compatible` rule that doesn't cover a category the report section produces.
- Terms used inconsistently (e.g. "primitive" vs. "single-concern action" vs. "atomic action" meaning the same thing but never stated as equivalent).
- A concrete example in the agent that would, if followed literally, violate a different rule stated elsewhere in the same agent.

For each inconsistency, quote both conflicting passages (with line numbers) and propose a resolution.

---

## 2. Alignment with Continuous Delivery (Farley & Humble)

The auditor names *Continuous Delivery* and *Modern Software Engineering* as authoritative sources. Check that the rules actually honor those sources, not just cite them.

Core CD claims to check against:

- **Deployment vs. release distinction.** "Deploy" = put a build onto an environment. "Release" = make a feature available to users. The auditor's naming rules must enforce this.
- **Deployment pipeline as a single path to production.** Every change takes the same route through commit → acceptance → UAT/performance → production. Rules that implicitly assume a different topology (per-artifact pipelines, separate release pipelines) should be flagged.
- **Build once, promote the same binary.** Artifacts are built once and promoted through stages, not rebuilt per environment. Auditor rules about tagging, versioning, and artifact handling must not contradict this.
- **Trunk-based development, small batches.** Auditor rules that implicitly assume long-lived release branches or batched releases should be flagged.
- **Fast feedback.** Rules that would encourage longer pipelines, hidden failures, or deferred verification should be flagged.
- **Reproducibility and traceability.** Every production artifact traces back to a specific commit; every deployment is reproducible.
- **Everything in version control.** Pipeline definitions, config, infra — all versioned.

For each CD-alignment finding, cite the practice (chapter or concept name from Farley/Humble) and the specific rule in the auditor that supports, contradicts, or is silent where it should speak.

---

## 3. Alignment with DORA, SRE, and mainstream DevOps

Beyond Farley/Humble, check alignment with:

- **DORA four key metrics** — deployment frequency, lead time for changes, change-failure rate, MTTR. Do the auditor's rules help a team improve these, or are they neutral / counter-productive?
- **Google SRE book** — error budgets, idempotence, graceful degradation, observability (logs + metrics + traces).
- **Twelve-Factor App** — especially Factor III (config in environment), Factor V (build/release/run separation), Factor X (dev/prod parity), Factor XI (logs as event streams).
- **GitHub Actions Marketplace conventions** — input/output naming (`image-url`, `commit-sha`, `tag`, `version`, `environment`), composite-vs-JavaScript action idioms, step-summary usage.
- **General CI tooling idioms** — Jenkins shared libraries, GitLab CI `include:` patterns, Azure Pipelines templates, CircleCI orbs — what makes a good reusable CI primitive across platforms.

Flag rules that are stated as "DevOps best practice" but are actually GitHub-Actions-specific or idiosyncratic to this repo. Also flag practices that are widely accepted elsewhere but missing from the auditor.

---

## 4. Portability to non-GitHub CI/CD

The auditor claims to care about portability — students may swap to Jenkins, GitLab CI, Azure Pipelines, CircleCI, Buildkite, or AWS CodePipeline. Check whether the rubric actually supports this claim.

For each of the target platforms, ask:

- **Would the auditor's naming tiers translate?** Tier 1 (generic), Tier 2 (git-native), Tier 3 (GitHub-specific). Are the tier boundaries drawn at the right place? Does Tier 2 really work identically on GitLab / Bitbucket / self-hosted git, or are there git-host-specific assumptions smuggled in?
- **Would the auditor's composition rules translate?** "Primitive + thin composite" is a GitHub Actions composition style. The equivalent on Jenkins is shared library steps + pipeline scripts; on GitLab CI, `include:` + `extends:`; on Azure Pipelines, templates; on CircleCI, orbs + commands; on Buildkite, plugins + pipelines. Does the rubric translate cleanly, or does it bake in composite-action specifics?
- **Would the auditor's ordering/idempotence rules translate?** "Cheapest to reverse first" is platform-agnostic; check that the examples and rules don't silently depend on Actions-specific features (e.g. `outputs:` propagation between steps).
- **Would the auditor's "prefer git over gh api" rule translate?** On GitLab, the equivalent is `glab api` vs git; on Bitbucket, the REST API vs git. Does the principle generalize, and does the agent say so clearly?
- **Tier 3 concepts on other platforms.** "GitHub Release" → GitLab Release, Bitbucket Downloads, generic artifact store. "GitHub commit status" → GitLab commit status, Bitbucket build status, generic webhook. "GitHub Deployment" → GitLab Environment, Spinnaker pipeline, Argo Rollouts. Is the rubric structured so a student could mechanically rename `create-github-release` → `create-gitlab-release` and keep the rest of the pipeline unchanged? Or is there hidden coupling?

Portability is the headline value proposition of the tier system — if the rubric fails here, it fails at its own stated goal. Be strict.

---

## 5. Practicality and tone

Minor but worth flagging:

- Rules that are so vague the auditor will have to guess (e.g. "flag misleading names" with no criterion for "misleading").
- Rules that are so specific they only cover the current repo's state and will become stale.
- Instructions that produce excessive false positives (e.g. "flag every action that mixes concerns" when some mixing is acceptable as thin sugar — the rubric already acknowledges this, but check that the acknowledgment is strong enough to prevent over-flagging).
- Missing guidance on how to handle edge cases the author has clearly thought about elsewhere (e.g. `:latest` is exempted, but is there a similar exemption for other deliberate anti-patterns used as teaching devices?).
- Output format issues: sections the report claims to produce that the process doesn't support, or vice versa.
