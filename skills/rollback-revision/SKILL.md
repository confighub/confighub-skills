---
name: rollback-revision
description: 'Roll back by moving one or more Unit heads to bound prior revisions via cub unit update --restore, then hand off to release-publish. Use for "roll back this change", "revert the last release", "undo the ChangeSet", or "restore to the last applied revision". Not for a clearer one-field forward fix.'
phase: act
allowed-tools: []
read-capability-subset: rollback-revision
---

# rollback-revision

**Authority boundary:** this companion may identify and diff the exact restore target, but it must not execute the head-moving restore, approval, or release. The external mutation broker is `NOT_INTEGRATED`, so the exact rollback proposal ends in `ASK` or `BLOCK`.

Prepare an exact proposal to move a Unit head (or a ChangeSet's worth of heads) back to prior revisions, then prepare a new whole-Space Release proposal.

## `cub unit update --restore` is the only rollback mechanism

Rollback always means: create a new head whose data equals a bound prior Revision, then publish that restored desired state through a newly approved Space Release. Every subsequent mutation branches from the restored head, so the bad state stays gone.

Rollback is a governed head-moving `cub unit update --restore` proposal followed, after external authorization and verification, by a separately approved immutable Space Release proposal. Do not try to replay historical runtime data without moving head: the next mutation or promotion would re-introduce the bad state.

Recognize and refuse the `retired-unit-runtime-verbs` anti-pattern retained in
`compatibility/no-loss-inventory.v1.json`; the active skill deliberately does
not reproduce its executable spelling. That versioned bridge-era form could
deploy old bytes without moving head, so it is **not rollback**. In current
v0.2.11 the per-Unit apply verb is absent. The durable route is to resolve the
requested prior revision to RevisionID/DataHash, create a new head with
`cub unit update --restore 47`, and then prepare a fresh Space Release.

## When to use

- User says "roll back", "revert", "undo" — and means it: the restored state should be the new baseline.
- Post-promotion rollback: a ChangeSet went out, the destination env rejects it, restore every affected Unit to `Before:ChangeSet:<slug>`.
- Single-Unit revert: one Unit got a bad revision, restore to `LastAppliedRevisionNum` or a specific prior number.

## Do not load for

- Fixing a single wrong field when the forward mutation is obviously cleaner (a `cub-mutate` run with `set-container-image` back to the old tag). Restore is heavier than a one-line change.
- Reversing a change that has not been captured by publication and has not been proven at runtime — use a forward `cub-mutate` or restore to the revision before the bad one; do not claim anything about what is live from Unit metadata alone.

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete). User has write permission on the target Space(s).
2. The rollback scope is explicit: single Unit slug, or a Filter (usually the `<app>-home/<app>-app` Filter from the promotion that's being rolled back) + optional `--where` narrowing.
3. The rollback target is explicit. Installed `--restore` selectors include:
   - Absolute revision number (`--restore 42`).
   - Relative (`--restore -1` = one before head).
   - `LastAppliedRevisionNum` — the Revision most recently captured by ConfigHub publication bookkeeping; not proof of controller consumption or current runtime state.
   - `LiveRevisionNum` — retained bridge-era state only; not current OCI/controller/runtime proof.
   - `Tag:<home-space>/<tag>` — a named release marker.
   - `ChangeSet:<home-space>/<slug>` — the end of a ChangeSet.
   - `Before:ChangeSet:<home-space>/<slug>` — the revision immediately before a ChangeSet opened (the standard "undo release X" target).
   - A revision UUID.
   Treat relative, `LiveRevisionNum`, and `LastAppliedRevisionNum` forms only as resolution aids: read what each resolves to and bind the exact RevisionNum, RevisionID, and DataHash before approval.
4. The destination currently isn't in the middle of *another* open ChangeSet on the same Units.
5. User has confirmed the exact resolved revisions and understands that the later Release may include additional Units.

## Pick the right target

```bash
# Inspect history to pick a target.
cub revision list <unit> --space <space>
# For a bulk rollback scoped to a ChangeSet, list the ChangeSet's revisions:
cub revision list --space <space> --filter <app>-home/<app>-app \
  --where "ChangeSet.Slug = '<changeset-slug>'"
```

Named targets (`Tag:` / `Before:ChangeSet:`) are useful resolution aids, but Tags and ChangeSet metadata are not immutable approval subjects. Resolve any selector now and bind the exact RevisionNum, RevisionID, and DataHash before review; re-resolve before any authorized execution.

Server v0.2.11 can transactionally compare caller-supplied `HeadRevisionNum` and `DataHash`/`ContentHash` during a Unit update, and raw patch entries can carry them. The stock restore path and this companion do not yet bind those expected current-state fields from the approved artifact through the final request and receipt. Keep the restore advisory and return `APPROVED_STATE_CAS_NOT_INTEGRATED`; do not misdescribe this as a missing provider CAS primitive.

## Shape A — single-Unit rollback

```bash
cub unit update --space <space> <unit> \
  --restore <target> \
  --change-desc "Rollback <unit> to <target>.

User prompt: <verbatim>
Clarifications: <condensed — e.g. 'reverting 2026-04-15 image bump; cert-manager v1.17.3 crashed on prod'>"

cub unit diff <unit> --space <space>       # proposed postcondition read
```

After externally authorized restore, hand fresh state to `release-publish`. A single-Unit restore does not imply a single-Unit Release; `release-publish` must show the complete EffectiveReleaseSet and obtain a new approval.

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

# 3. Hand fresh restored state to release-publish for gate assessment,
# complete EffectiveReleaseSet disclosure, and a distinct Release proposal.
```

Each proposed Unit head reverts to its pre-ChangeSet data. Current native approval can approve only the head at execution time and has no expected RevisionID/DataHash CAS, so exact approval remains `APPROVAL_HEAD_RACE_BLOCK`; neither native approval nor the restore authorizes publication. The rollback Tag remains a retrieval marker.

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
3. `release-publish` captures the restored heads in an exact new Space Release; `verify-apply` binds its ManifestDigest to controller/runtime proof. Legacy BridgeState/LiveRevision is not cluster proof for OCI delivery.
4. For Shape B: `cub revision list --space $TO_SPACE --filter $APP_FILTER --tag $HOME_SPACE/$ROLLBACK_TAG` lists one restored revision per intended Unit.

## Tool boundary

- Host-ASK: read-only Unit/revision/ChangeSet inspection; this candidate has zero raw Bash autoallow pending a typed wrapper.
- Proposal-only: `cub unit update --restore`, tags, native approval, and the new Release. Restore execution remains `APPROVED_STATE_CAS_NOT_INTEGRATED`; `release-publish` owns exact publication scope.
- Not allowed: historical runtime replay as a rollback, manually matching old data, or rolling back across applications in one scope.

## Stop conditions

- The ChangeSet being rolled back is still *open*. Stop. Close it first (`cub unit update --patch --filter <f> --changeset -`) — you can't restore across an open ChangeSet without violating the lock.
- Scope includes Units from multiple apps' `<app>-home`s. Split the rollback per app; one rollback per app.
- User wants to delete the rolled-back revisions from history. Not possible, and not desirable — restore creates a new head; the "bad" revisions stay in the audit trail.
- Rollback target is the Unit's current head (no-op). Tell the user and stop.

## Evidence

- `cub space open <space> --print-url` — restored Space.
- `cub unit open <unit> --space <space> --revisions --print-url` — restored head history.

## References

- `references/changesets.md` — `Before:ChangeSet:<slug>` target, bulk restore pattern, 3-way merge for held-back changes.
- `references/revisions.md` — restore-target syntax (`Tag:`, `ChangeSet:`, relative / absolute numbers, UUIDs).
- `references/filters-and-queries.md` — scoping the rollback via Filter.
- `references/cub-cli.md` — `--change-desc` scope, `-` sentinel for `--changeset` close.
- Companion skills: `release-publish` (post-restore whole-Space Release), `cub-mutate` (forward fix when clearer), `promote-release` (the forward counterpart), `verify-apply` (post-rollback checks).
