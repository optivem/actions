# Docker primitives removal plan — 2026-04-22 07:23 UTC

Targeted plan (not a full `actions-auditor` run). Scope is the **deletion** of three custom actions — `build-docker-image`, `tag-docker-image`, `push-docker-image` — that are no longer referenced by any live consumer, in favour of the Marketplace trio `docker/login-action@v4` + `docker/metadata-action@v5` + `docker/build-push-action@v6` per the new §1.6 rule in `.claude/agents/docs/devops-rubric.md`.

Reference implementation (already live): [shop/.github/workflows/monolith-java-commit-stage.yml](../../shop/.github/workflows/monolith-java-commit-stage.yml) lines 120–158.

## Consumer audit — re-verified 2026-04-22 07:24 UTC

Greps against **live on-disk** directories only (`shop/`, `actions/`, `optivem-testing/`, `gh-optivem/`):

| Repo | Live consumers of `build-docker-image` / `tag-docker-image` / `push-docker-image` |
|---|---|
| `shop/` | **0** (already migrated) |
| `optivem-testing/` | **0** |
| `gh-optivem/` | **0** |

The earlier draft of this plan listed 8 "greeter-*" consumer repos — those directories do not exist on disk. They were a grep artifact and are dropped.

Course content under `courses/` is **out of scope** per user direction (2026-04-22) and is not addressed here.

## Coexistence with other plans

Coexists with `.plans/20260422-055006-audit-actions.md` (10 open items, unrelated) and `.plans/20260422-045423-audit-actions.md` (2 open items). Both open items in the `045423` plan reference `push-docker-image` (eshop stale contracts, course teaching-material `-tag` → `-url` rename) and are made obsolete by item 1 below — the action they track is being deleted, not renamed. Flag at execution time so the author can manually remove those items from their originating plan (coexistence rules forbid this plan from editing it).

## Items

- [ ] **Force-move the `optivem/actions@v1` tag** — move the `@v1` tag to the post-deletion HEAD (per the "Versioning policy — stay on `@v1`" section now added to `actions/README.md`, the major tag is a moving ref by design, not a release-cut ceremony). The operation is `git tag -f v1 && git push --force origin v1` (no GitHub Release is attached to `@v1`). Verify afterwards with `gh api repos/optivem/actions/git/refs/tags/v1` that the tag points at the post-deletion SHA. **Awaiting user approval — force-push to a shared ref.**
  - Affects: `optivem/actions` tag `v1`
  - Consumers to update: none (consumers re-resolve `@v1` automatically on their next run)
  - Category: release

Per project convention, items are removed from this file as they are executed, the file is deleted when empty, and the `.plans/` directory is deleted when it contains no files.

## Executed items (retained briefly for audit — remove once committed)

- [x] **Delete the three deprecated Docker action directories** — `build-docker-image/`, `tag-docker-image/`, `push-docker-image/` removed (staged as `D action.yml` in all three, no remaining files). Verified 2026-04-22 07:24 UTC that all three had zero live call sites in `shop`, `optivem-testing`, and `gh-optivem`. Archived / `.tmp/` consumers left as-is per plan scope.
- [x] **Remove README sections for the three deleted actions** — the `### build-docker-image`, `### push-docker-image`, and `### tag-docker-image` sections removed from `actions/README.md`; cross-references scrubbed. Grep against `README.md` returns zero matches for the three action names post-edit.
