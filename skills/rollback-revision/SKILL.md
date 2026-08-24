---
name: rollback-revision
description: 'Roll back by moving one or more Unit heads to bound prior revisions via cub unit update --restore, then hand off to release-publish. Use for "roll back this change", "revert the last release", "undo the ChangeSet", or "restore to the last applied revision". Not for a clearer one-field forward fix.'
phase: act
allowed-tools: []
read-capability-subset: rollback-revision
---

# rollback-revision

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. After binding and diffing the exact restore target, standalone use submits one requested head-moving restore to the host permission system. The later whole-Space publication is a separate host-permission call; an external overlay may stop either step before Bash.

Resolve and preview the exact Unit head or ChangeSet scope to restore. On a
clear standalone rollback request, submit one exact restore through the host
permission system, verify it, and treat the later whole-Space publication as a
separate request.

## `cub unit update --restore` is the only rollback mechanism

Rollback always means: create a new head whose data equals a bound prior Revision, then publish that restored desired state through a newly approved Space Release. Every subsequent mutation branches from the restored head, so the bad state stays gone.

Rollback is a head-moving `cub unit update --restore` followed, after verification, by a separate immutable Space Release. Each is its own host-permission call. Do not try to replay historical runtime data without moving head: the next mutation or promotion would re-introduce the bad state.

Recognize and refuse the `retired-unit-runtime-verbs` anti-pattern retained in
`compatibility/no-loss-inventory.v1.json`; the active skill deliberately does
not reproduce its executable spelling. That historical bridge-era form could
deploy old bytes without moving head, so it is **not rollback**. The current
OCI Release profile has no per-Unit apply fallback. The durable route is to resolve the
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
   - Absolute revision number (`--restore 42`). **Note `--restore 1` restores *empty*:** every Unit now begins with an empty start revision and its created content lands on Revision 2. Units created before that change kept content on Revision 1, so read `cub revision list` rather than assuming which meaning applies.
   - Relative (`--restore -1` = one before head).
   - `LastAppliedRevisionNum` — the Revision most recently captured by ConfigHub publication bookkeeping; not proof of controller consumption or current runtime state.
   - `LiveRevisionNum` — retained bridge-era state only; not current OCI/controller/runtime proof.
   - `Tag:<home-space>/<tag>` — a named release marker.
   - `ChangeSet:<home-space>/<slug>` — the end of a ChangeSet.
   - `Before:ChangeSet:<home-space>/<slug>` — the ChangeSet's start tag, i.e. the head each Unit had immediately before the ChangeSet opened (the standard "undo release X" target). The start tag marks a revision that already existed rather than one manufactured by attaching, so a Unit that joined the ChangeSet and never changed rewinds cleanly along with the rest.
   - A revision UUID.
   Treat relative, `LiveRevisionNum`, and `LastAppliedRevisionNum` forms only as resolution aids: read what each resolves to and bind the exact RevisionNum, RevisionID, and DataHash before approval.
4. The destination currently isn't in the middle of *another* open ChangeSet on the same Units.
5. User has confirmed the exact resolved revisions and understands that the later Release may include additional Units.

## Pick the right target

```text
# Inspect history to pick a target.
cub revision list <unit> --space <space>
# For a bulk rollback scoped to a ChangeSet, list the ChangeSet's revisions:
cub revision list --space <space> --filter <app>-home/<app>-app \
  --where "ChangeSet.Slug = '<changeset-slug>'"
```

Named targets (`Tag:` / `Before:ChangeSet:`) are useful resolution aids, but Tags and ChangeSet metadata are not immutable approval subjects. Resolve any selector now and bind the exact RevisionNum, RevisionID, and DataHash before review; re-resolve before any authorized execution.

The last source-reviewed v0.2.11 Unit update path could transactionally compare
caller-supplied `HeadRevisionNum` and `DataHash`. That older
finding is not projected onto the installed v0.2.21 server. The stock v0.2.15
restore command does not expose those expected current-state fields. Re-read
immediately before the call, name the race, and do not claim exact
preview-to-execution binding.

## Shape A — single-Unit rollback

```bash
cub unit update --space <space> <unit> \
  --restore <target> \
  --change-desc 'Rollback Unit to reviewed revision'
```

Then verify separately:

```bash
cub unit diff <unit> --space <space>
```

After a successful restore, hand fresh state to `release-publish`. A single-Unit restore does not imply a single-Unit Release; `release-publish` must show the complete EffectiveReleaseSet and obtain a separate host permission for publication.

Optionally tag the new head for future reference:

```bash
cub tag create --space <home-space> rollback-<YYYYMMDD>-<unit> \
  --annotation 'description=Record reviewed Unit rollback'
```

After verifying the Tag, attach it in a separate call:

```bash
cub unit tag <home-space>/rollback-<YYYYMMDD>-<unit> --space <space> --unit <unit>
```

## Shape B — ChangeSet rollback (standard post-promotion revert)

This is the standard "undo a release" path, and it's one command per step thanks to the ChangeSet.

**A promotion is nearly always Shape B, not Shape A.** An upgrade or `cub variant promote` walks its range and records **one downstream revision per upstream revision that had an effect** — so a single promotion produces many revisions per Unit, and different Units get different numbers of them. There is no revision number that means "just before the promotion" across the set, and `--restore -1` rewinds one hop of the walk rather than the promotion. If the promotion was wrapped in a ChangeSet, `Before:ChangeSet:` is the set-wise rollback target. If it was not, there is no set-wise undo: say so plainly, and reconstruct per Unit from `cub revision list` — the last revision before the first one carrying the promotion's change descriptions.

Resolve the placeholders to literal values. Submit and verify the Tag first:

```bash
cub tag create --space <app>-home rollback-<changeset-slug> --annotation 'description=Record reviewed ChangeSet rollback'
```

Then submit the restore as one separate call:

```bash
cub unit update --patch --space <app>-<environment> \
  --filter <app>-home/<app>-app \
  --restore 'Before:ChangeSet:<app>-home/<changeset-slug>' \
  --tag <app>-home/rollback-<changeset-slug> \
  --change-desc 'Rollback reviewed ChangeSet for incident'
```

After verifying the restored heads, hand fresh state to `release-publish` for
complete EffectiveReleaseSet disclosure and a separate publication decision.

Each Unit head reverts to its pre-ChangeSet data. Current native approval can approve only the head at execution time and has no expected RevisionID/DataHash precondition, so it cannot prove that the revision reviewed earlier was the one approved. Neither native approval nor the restore publishes anything. The rollback Tag remains a retrieval marker.

## Shape C — rollback then reapply held-back changes (merge / rebase)

If changes were made to the affected Units *after* the ChangeSet that you want to keep (e.g., urgent hotfixes applied after the bad release), a plain restore discards them. Use a 3-way merge instead (per `references/changesets.md`):

```bash
cub unit update --patch --space <app>-<environment> \
  --filter <app>-home/<app>-app \
  --merge-source Self \
  --merge-base 'Before:ChangeSet:<app>-home/<changeset-slug>' \
  --merge-end 'ChangeSet:<app>-home/<changeset-slug>' \
  --change-desc 'Merge reviewed changes onto rollback head'
```

This is an advanced path. Only reach for it when you've verified the hotfixes actually need preserving.

## Verify chain

1. `cub unit get <unit> --space <space> -o yaml` — Data matches the target revision's data.
2. `cub revision list <unit> --space <space>` — the new head revision has the rollback `--change-desc` (and Tag, for Shape B).
3. `release-publish` captures the restored heads in an exact new Space Release; `verify-apply` binds its ManifestDigest to controller/runtime proof. Legacy BridgeState/LiveRevision is not cluster proof for OCI delivery.
4. For Shape B: `cub revision list --space <app>-<environment> --filter <app>-home/<app>-app --tag <app>-home/rollback-<changeset-slug>` lists one restored revision per intended Unit.

## Tool boundary

- Host permission: read-only Unit/revision/ChangeSet inspection; the pack preapproves no Bash call.
- Standalone mutation steps: `cub unit update --restore`, tags, native approval, and the new Release are separate one-command host-permission calls. The restore has the pre-read race described above; `release-publish` owns exact publication scope.
- Not allowed: historical runtime replay as a rollback, manually matching old data, or rolling back across applications in one scope.

## Stop conditions

- The ChangeSet being rolled back is still *open*. Stop. Close it first (`cub unit update --patch --filter <f> --changeset -`) — you can't restore across an open ChangeSet without violating the lock.
- Scope includes Units from multiple apps' `<app>-home`s. Split the rollback per app; one rollback per app.
- User wants to delete the rolled-back revisions from history. Not possible, and not desirable — restore creates a new head; the "bad" revisions stay in the audit trail.
- Rollback target is the Unit's current head (no-op). Tell the user and stop.
- The promotion being rolled back was not wrapped in a ChangeSet. There is no set-wise restore target; confirm the per-Unit targets with the user before submitting a reconstructed scope.
- The restore would rewind past protection or conflict state the user has not seen. Restore rewinds `MutationSources` — including each path's `Protected` flag — along with `Data`, so a restore also restores which paths the variant owned at that point. Read `cub unit get <unit> -o mutations` before and name the difference.

## Evidence

- `cub space open <space> --print-url` — restored Space.
- `cub unit open <unit> --space <space> --revisions --print-url` — restored head history.

## References

- `references/changesets.md` — `Before:ChangeSet:<slug>` target, bulk restore pattern, 3-way merge for held-back changes.
- `references/revisions.md` — current restore-target syntax (`Tag:`, `ChangeSet:`, relative / absolute numbers, UUIDs), the empty start revision, and how restore rewinds `MutationSources` with `Data`.
- `references/filters-and-queries.md` — scoping the rollback via Filter.
- `references/cub-cli.md` — `--change-desc` scope, `-` sentinel for `--changeset` close.
- Companion skills: `release-publish` (post-restore whole-Space Release), `cub-mutate` (forward fix when clearer), `promote-release` (the forward counterpart), `verify-apply` (post-rollback checks).
