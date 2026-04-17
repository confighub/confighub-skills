---
name: rollback-revision
description: 'Use when the user wants to roll back a change by moving a Unit''s head (or a set of Units'' heads) to a prior revision — phrases like "roll back this change", "revert the last release", "undo the ChangeSet", "restore to the last applied revision", "back out yesterday''s image bump", "put the head back where it was before this ChangeSet", "roll back the promotion". Always rolls back by moving head via `cub unit update --restore <target>` against one Unit or a Filter-scoped set (optionally tagged), then hands off to the `cub-apply` skill to push the restored state. Do not load for drift between ConfigHub and cluster (use `drift-reconcile`) or for rolling back a single-field change where a forward mutation via `cub-mutate` is clearer.'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub revision list *) Bash(cub revision get *) Bash(cub unit update *) Bash(cub unit tag *) Bash(cub tag create *) Bash(cub filter create *)
---

# rollback-revision

Move a Unit's head (or a ChangeSet's worth of heads) back to a prior revision, then apply.

## `cub unit update --restore` is the only rollback mechanism

Rollback always means: create a new head whose data equals some prior revision's data, then apply that head. Every subsequent mutation branches from the restored head, so the "bad" state stays gone.

**Do not use `cub unit apply --revision <N>` as a rollback.** That command applies an older revision to the cluster *without moving the Unit's head* — the "bad" revision is still head, and the next `cub-mutate` / `promote-release` / merge will re-introduce it. Use it only to inspect or diff an older revision's applied state, never to undo a change. Whenever the user asks to "roll back," they want head to move; run `cub unit update --restore`.

## When to use

- User says "roll back", "revert", "undo" — and means it: the restored state should be the new baseline.
- Post-promotion rollback: a ChangeSet went out, the destination env rejects it, restore every affected Unit to `Before:ChangeSet:<slug>`.
- Single-Unit revert: one Unit got a bad revision, restore to `LastAppliedRevisionNum` or a specific prior number.
- Reverting a drift-reconcile outcome that accepted live state and the user changed their mind.

## Do not load for

- Cluster-vs-ConfigHub drift — `drift-reconcile` decides which side wins; this skill only rewinds ConfigHub Unit history.
- Fixing a single wrong field when the forward mutation is obviously cleaner (a `cub-mutate` run with `set-container-image` back to the old tag). Restore is heavier than a one-line change.
- Rolling back a change that hasn't been applied yet — nothing's live, so either do a forward `cub-mutate` or `cub unit update --restore` to the revision before the bad one; no ChangeSet-level rollback narrative needed.

## Preflight gates

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one). User has write permission on the target Space(s).
2. The rollback scope is explicit: single Unit slug, or a Filter (usually the `<app>-home/<app>-app` Filter from the promotion that's being rolled back) + optional `--where` narrowing.
3. The rollback target is explicit. Valid `--restore` targets:
   - Absolute revision number (`--restore 42`).
   - Relative (`--restore -1` = one before head).
   - `LastAppliedRevisionNum` — revert to what's currently live.
   - `LiveRevisionNum` — same as above for non-drift cases.
   - `Tag:<home-space>/<tag>` — a named release marker.
   - `ChangeSet:<home-space>/<slug>` — the end of a ChangeSet.
   - `Before:ChangeSet:<home-space>/<slug>` — the revision immediately before a ChangeSet opened (the standard "undo release X" target).
   - A revision UUID.
4. The destination currently isn't in the middle of *another* open ChangeSet on the same Units.
5. User has confirmed the target revision (see "Pick the right target" below).

## Pick the right target

```bash
# Inspect history to pick a target.
cub revision list <unit> --space <space>
# For a bulk rollback scoped to a ChangeSet, list the ChangeSet's revisions:
cub revision list --space <space> --filter <app>-home/<app>-app \
  --where "ChangeSet.Slug = '<changeset-slug>'"
```

Prefer named targets (`Tag:` / `Before:ChangeSet:`) over raw revision numbers when one exists — they survive later promotions / merges that would shift absolute numbers.

## Shape A — single-Unit rollback

```bash
cub unit update --space <space> <unit> \
  --restore <target> \
  --change-desc "Rollback <unit> to <target>.

User prompt: <verbatim>
Clarifications: <condensed — e.g. 'reverting 2026-04-15 image bump; cert-manager v1.17.3 crashed on prod'>"

cub unit diff <unit> --space <space>       # confirm head == target's data
cub unit apply <unit> --space <space> --wait
```

Optionally tag the new head for future reference:

```bash
cub tag create --space <home-space> rollback-$(date +%Y%m%d)-<unit> \
  --annotation "description=Rollback of <unit> to <target>"
cub unit tag <home-space>/rollback-<...> --space <space> --unit <unit>
```

## Shape B — ChangeSet rollback (standard post-promotion revert)

This is the standard "undo a release" path, and it's one command per step thanks to the ChangeSet.

```bash
HOME_SPACE=<app>-home
TO_SPACE=<app>-<env-being-rolled-back>
APP_FILTER=$HOME_SPACE/<app>-app
CHANGESET_SLUG=<the-release-being-rolled-back>
CHANGESET_REF=$HOME_SPACE/$CHANGESET_SLUG
ROLLBACK_TAG=rollback-$CHANGESET_SLUG

# 1. Tag the rollback ahead of the restore so every restored head carries the tag.
cub tag create --space $HOME_SPACE $ROLLBACK_TAG \
  --annotation "description=Rollback $CHANGESET_SLUG"

# 2. Bulk restore every Unit in the scope to Before:ChangeSet.
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --restore "Before:ChangeSet:$CHANGESET_REF" \
  --tag $HOME_SPACE/$ROLLBACK_TAG \
  --change-desc "Rollback $CHANGESET_SLUG.

User prompt: <verbatim>
Clarifications: <condensed — e.g. 'cert-manager crash in prod; reverting per incident #512; staging unaffected'>"

# 3. Approve + apply the new head revisions (no --revision = head).
cub unit approve --space $TO_SPACE --filter $APP_FILTER   # only if approval Trigger required
cub unit apply   --space $TO_SPACE --filter $APP_FILTER --wait --timeout 10m0s
```

Each Unit's head reverts to its pre-ChangeSet data; the apply pushes that to the cluster. The rollback Tag lets you refer to this rollback later (`cub revision list --tag $HOME_SPACE/$ROLLBACK_TAG`).

## Shape C — rollback then reapply held-back changes (merge / rebase)

If changes were made to the affected Units *after* the ChangeSet that you want to keep (e.g., urgent hotfixes applied after the bad release), a plain restore discards them. Use a 3-way merge instead (per `references/changesets.md`):

```bash
# Restore per Shape B, then merge back the kept changes.
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --merge-source Self \
  --merge-base "Before:ChangeSet:$CHANGESET_REF" \
  --merge-end "ChangeSet:$CHANGESET_REF" \
  --change-desc "Merge post-$CHANGESET_SLUG changes onto rollback head"
```

This is an advanced path. Only reach for it when you've verified the hotfixes actually need preserving.

## Verify chain

1. `cub unit get <unit> --space <space> -o yaml` — Data matches the target revision's data.
2. `cub revision list <unit> --space <space>` — the new head revision has the rollback `--change-desc` (and Tag, for Shape B).
3. `cub unit bridgestate --space <space> --filter <...>` — after apply, every Unit is `Ready`, `LiveRevisionNum` = new head.
4. For Shape B: `cub revision list --space $TO_SPACE --filter $APP_FILTER --tag $HOME_SPACE/$ROLLBACK_TAG` lists one revision per Unit — all tagged.

## Tool boundary

- Allowed: `cub unit update --restore` (+ `--patch` + `--tag`), `cub unit tag`, `cub tag create`, `cub changeset` read-only, read-only `cub unit/revision`, `cub unit approve` for the apply gate path. `cub unit apply` is the `cub-apply` skill's territory — hand off.
- Not allowed: `cub unit apply --revision <N>` as a rollback mechanism — it leaves head unchanged, so the "bad" state returns on the next forward change. Editing Unit data to "manually match" an older revision (defeats the audit point of `--restore`). Rolling back across different applications in one scope (separate ChangeSets per app; one rollback command per app).

## Stop conditions

- The ChangeSet being rolled back is still *open*. Stop. Close it first (`cub unit update --patch --filter <f> --changeset -`) — you can't restore across an open ChangeSet without violating the lock.
- Scope includes Units from multiple apps' `<app>-home`s. Split the rollback per app; one rollback per app.
- User wants to delete the rolled-back revisions from history. Not possible, and not desirable — restore creates a new head; the "bad" revisions stay in the audit trail.
- Rollback target is the Unit's current head (no-op). Tell the user and stop.

## Evidence

- `cub revision list <unit> --space <space> --web` — new head revision with the rollback `--change-desc`.
- `cub changeset get --space <home-space> <slug> --web` — the rolled-back ChangeSet plus the rollback Tag attached.
- `cub unit get <unit> --space <space> --web` — current state showing the restored data.

## References

- `references/changesets.md` — `Before:ChangeSet:<slug>` target, bulk restore pattern, 3-way merge for held-back changes.
- `references/revisions.md` — restore-target syntax (`Tag:`, `ChangeSet:`, relative / absolute numbers, UUIDs).
- `references/filters-and-queries.md` — scoping the rollback via Filter.
- `references/cub-cli.md` — `--change-desc` scope, `-` sentinel for `--changeset` close.
- Companion skills: `cub-apply` (runtime for the post-restore apply), `cub-mutate` (forward fix when it's clearer than restore), `promote-release` (the forward counterpart — this rolls back what that promoted), `drift-reconcile` (divergence between ConfigHub and cluster, different problem), `verify-apply` (post-rollback checks).
