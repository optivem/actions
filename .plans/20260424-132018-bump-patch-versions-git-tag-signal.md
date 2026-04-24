# bump-patch-versions: migrate `github-release` signal to git-tag probing

## Context

Follow-up to the 2026-04-24 system-release-signal rollback. That pass established a consistent model across the shop workflows:

- **Git tags** = ceremonial event markers (system release, RC, qa-approved, meta release) — probed via `check-tag-exists` / `validate-tag-exists`
- **GHCR image tags** = component deliverables — probed via `check-ghcr-image-tag-exists`

`bump-patch-versions` is the remaining inconsistency. Its `signal: github-release` branch internally probes GitHub Releases (inline bash, not a `uses:` call — so nothing is broken, but the signal shape doesn't match the rest of the codebase).

Under the consistent model, meta release existence should be probed via git tag, not GitHub Release.

## Scope

**Action: `actions/bump-patch-versions/action.yml`**

- Replace signal enum value `github-release` with `git-tag`.
- Rewrite the inline probe from `probe_github_release` (GitHub Releases API `GET /repos/.../releases/tags/{tag}`) to git-tag probing (`git ls-remote --tags` against the remote, same semantics as `check-tag-exists`).
- Update the action `description` + input docs + signal error message to use the new name.

**Callers: shop/ workflows** (3 files that pass `signal: github-release`)

- `shop/.github/workflows/auto-bump-patch.yml`
- `shop/.github/workflows/bump-versions.yml`
- `shop/.github/workflows/gh-auto-bump-patch.yml`

Each has the meta VERSION entry as `{"path": "VERSION", "signal": "github-release", "value": "meta-v"}` — change to `"signal": "git-tag"`.

**Course references**

Grep courses for `signal: github-release` or `github-release` signal mentions. Update any lesson that teaches the old discriminator name.

## Blast radius

- 1 action rewrite (~30 LoC change in `action.yml` inline bash + docs).
- 3 caller updates (1 line each).
- Unknown course surface — verify by grep.

## Out of scope

- Keeping the `github-release` value as an alias for backward compat. This repo has no external consumers; atomic rename is the policy (per `actions/README.md` top-of-file note).
- Revisiting the component `ghcr-image` signal — it stays as-is.

## Execution order

1. Grep courses to size course-edit scope; include in plan if non-trivial.
2. Rewrite `bump-patch-versions/action.yml`.
3. Update 3 shop callers.
4. Update course content (if any).
5. Commit per-repo: actions, shop, courses (if touched).
