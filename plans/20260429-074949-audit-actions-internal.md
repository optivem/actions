# Actions audit plan — Internal — 2026-04-29 07:49 UTC

Derived from `.reports/20260429-074949-audit-actions-internal.md`. `backwards_compatible = false`. `scope = all`. `mode = both`.
External-scope companion: `plans/20260429-074949-audit-actions-external.md`.

The plan section below lists only items requiring code change. Items are numbered for stable reference (numbering continues from the external plan); items resolved during execution should be deleted (do NOT renumber the remainder, leave gaps so `item N` keeps referring to the same work from creation through completion). When this file is empty (excluding the header), it can be deleted.

## Plan — Internal items

Items with no consumer-visible surface change. Safe to land independently of consumer updates. Numbering continues from the External plan.

- [ ] **6. Replace hardcoded `origin` in `publish-tag/action.yml` lines 50 and 72** — replace `git ls-remote --tags origin "refs/tags/$TAG"` with `git ls-remote --tags "$push_target" "refs/tags/$TAG"`. Re-uses the auth-bearing URL the action already composes for `git push`. Behaviour-preserving for the current caller set (all 26 call sites use `repository == github.repository`) but fixes the contract for any future caller wiring up a non-default `repository`. Mirrors the pattern that the (now-deleted) `create-component-tags` was previously flagged for — same bug shape, different action.
  - Affects: `actions/publish-tag`
  - Consumers to update: none (the change is purely internal to the action; the contract surface is unchanged for callers passing `repository == github.repository`, which is every caller today).
  - Category: devops-alignment

- [ ] **7. Tighten `create-deployment.description` to document the dual-write shape** — the current input description does not say that the value is written to BOTH the deployment record AND its initial status update. Update to: `'Human-readable description recorded on **both** the deployment record AND its initial status update. Empty -> defaults to "Deploy of <ref>".'`
  - Affects: `actions/create-deployment`
  - Consumers to update: none (description-only).
  - Category: parameter-description
