# Actions audit plan — External — 2026-04-29 07:49 UTC

Derived from `.reports/20260429-074949-audit-actions-external.md`. `backwards_compatible = false`. `scope = all`. `mode = both`.
Internal-scope companion: `plans/20260429-074949-audit-actions-internal.md`.

The plan section below lists only items requiring code change. Items are numbered for stable reference; items resolved during execution should be deleted (do NOT renumber the remainder, leave gaps so `item N` keeps referring to the same work from creation through completion). When this file is empty (excluding the header), it can be deleted.

## Plan — Breaking items (External)

Items that force consumer workflows to be updated. Complete these first and co-ordinate landing with consumer updates in `shop` (and 0 in `gh-optivem`, 0 in `optivem-testing` for these specific items). Ordered by impact (call-site count descending, with DevOps-alignment / contract-correctness above pure-naming at the same call-site count).

- [ ] **2. Rename `resolve-latest-deployed-prerelease` → `resolve-latest-prerelease-with-deployment`** — `name-misleading` per rubric §4: the resolver's qualifier names the *evidence used to verify* (a GitHub Deployments record), mirroring `*-with-check[-run]`. Pairs cleanly with `create-deployment` (write).
  - Affects: `actions/resolve-latest-deployed-prerelease`
  - Consumers to update (6 in shop, 0 in gh-optivem, 0 in optivem-testing):
    - `shop/.github/workflows/*.yml` — 6 call sites grep with `optivem/actions/resolve-latest-deployed-prerelease@`.
  - Category: naming

- [ ] **5. Clarify `resolve-latest-deployed-prerelease.ref` description vs runtime contract** — runtime always `exit 1`s on no match; description says "Empty when none found." Update description to: `'The ref of the latest successful deployment matching the criteria. The action fails the step (exit 1) when none found — `ref` is never empty in practice.'` Then remove or update any defensive `if: steps.x.outputs.ref != ''` consumer guards. Land alongside item 2's directory rename.
  - Affects: `actions/resolve-latest-deployed-prerelease` (which becomes `actions/resolve-latest-prerelease-with-deployment` per item 2)
  - Consumers to update (audit needed — 6 call sites in shop): scan all 6 for `if:` guards branching on the empty-ref case; either remove the guard (no longer reachable) or restructure to a `continue-on-error: true` step that catches the `exit 1` if the caller genuinely needs the no-match path.
    - `shop/.github/workflows/*.yml` — 6 call sites of `resolve-latest-deployed-prerelease`.
  - Category: parameter-deprecation

If you choose to defer items 2 and 5 (e.g. wait for a course migration window before forcing workflow updates), keep them in this plan file; they do not become obsolete. (Items 1, 3, 4 were mooted on 2026-04-29 by the Option A migration that deleted `create-check-run`, `check-run-exists`, and `resolve-latest-prerelease-with-check` outright in favour of commit-statuses; the new resolver `resolve-latest-prerelease-with-status` is a fresh action that does not inherit the redundant `base-tag` output.)

## Plan — Non-breaking items (External)

None this run.
