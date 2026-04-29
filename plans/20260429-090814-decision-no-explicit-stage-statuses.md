# Decision: don't add explicit `acceptance/tested` / `commit/passed` commit statuses — 2026-04-29 09:08 UTC

**Status:** Decided. No action. Recorded for future reference.

## Question

After migrating `qa/signoff` from check-runs to commit statuses, should we *additionally* post explicit commit statuses for the other CI stages (`acceptance/tested` after acceptance-stage, `commit/passed` after commit-stage, etc.) for symmetry?

## Decision

**No.** The current architecture is correct as-is.

## Reasoning

### 1. The signal already exists for free

When any GitHub Actions workflow runs, GitHub automatically posts a check run on the commit it ran against — one per job, named after the workflow + job. So `monolith-typescript-acceptance-stage / check`, `monolith-typescript-acceptance-stage / run`, `monolith-typescript-acceptance-stage / publish-tag` already appear as check runs on every commit they run against. They're queryable via the Checks API and visible in GitHub's UI.

**No explicit `create-check-run` or `create-commit-status` call is needed for "this stage's CI passed."** That signal is already recorded automatically.

### 2. Explicit status posts are reserved for verdicts that aren't a workflow's own success

The mainstream rule of thumb:

- **Mainstream / correct:** explicit commit status when the verdict is *not* reducible to a single workflow's success/failure.
  - ✅ `qa/signoff` — a human approval recorded *by* a workflow but not the workflow's own pass/fail. The qa-signoff workflow always succeeds (it just dispatches the verdict the human entered); the actual judgment is the input.
  - ✅ External SaaS verdicts (e.g. SonarCloud posting `security/sonar`).
  - ✅ Cross-workflow aggregations.
- **Anti-pattern:** explicit status posted by the same workflow that already automatically generates a check run for its own success.
  - ❌ `acceptance/tested` posted by `monolith-typescript-acceptance-stage` — the workflow's own automatic check run already records this.
  - ❌ `commit/passed` posted by `monolith-typescript-commit-stage` — same.

Adding these would be re-posting information GitHub already records for us.

### 3. The current architecture is already well-aligned with mainstream practice

- **RC tags** (`<prefix>-v<X.Y.Z>-rc.N`) — artifact identity. Mainstream.
- **Automatic per-workflow check runs** — stage-pass signals. Mainstream and free.
- **Explicit commit statuses** — reserved for verdicts that aren't a single workflow's pass/fail (currently: `qa/signoff` only). Mainstream.
- **GitHub Deployments API** — deployment state tracking. Mainstream.

Mixing tags-for-identity + auto-check-runs-for-stage-verdicts + explicit-statuses-for-external-verdicts is the idiomatic GitHub-native split.

### 4. What we'd pay vs. what we'd gain

If we *did* add explicit `acceptance/tested` / `commit/passed`:

**Cost:**
- One more action call per stage per RC across 18 acceptance-stage + 7 commit-stage workflows = 25 files to maintain.
- State duplication — "RC tag exists" *and* "acceptance/tested status exists" mean the same thing. If the status post fails after the tag is created, downstream readers see conflicting signals; you'd need a tie-breaker rule.
- More API calls per pipeline run.

**Gain:**
- Aesthetic symmetry with `qa/signoff`.
- Per-commit status badge on GitHub's commit-detail UI (low value for this team's workflow).
- Statuses queryable on a SHA without parsing tag names (already redundant — `resolve-latest-prerelease-tag` works fine, and the auto check runs are also queryable).

ROI is negative. Symmetry alone doesn't justify the work.

## When to revisit this decision

Add explicit per-stage commit statuses **only if** one of the following becomes true:

1. **Recording state on commits without creating tags** — e.g. feature-branch builds where you want a "tests passed" signal on a SHA but don't want to create a permanent git tag.
2. **A reader requires a status specifically** — a third-party tool integrated via the Statuses API that can't read check runs, or branch-protection-required-checks adoption on a branch.
3. **Branch protection on `main`** — if you turn on branch protection requiring `acceptance/tested` etc. as required status checks. (Currently the pipeline uses tag-based promotion, not branch-merge gating, so this isn't relevant.)
4. **Cross-repo verdict aggregation** — if a downstream pipeline needs to check "did all these per-stack acceptance stages pass?" via a single API query, an aggregating status posted by a meta-workflow could be cleaner than querying N tags.

If none of these apply, leave the architecture alone.

## Related

- `qa/signoff` migration from check-runs → commit statuses (2026-04-29) — addressed real breakage, justified by 403 from check-runs API requiring GitHub App authentication. Not a precedent for migrating other gates.
- Memory record: `project_promotion_state_uses_commit_statuses.md` — documents the broader decision to standardize on commit statuses where explicit verdict-recording is needed (not as a directive to add explicit posts everywhere).
