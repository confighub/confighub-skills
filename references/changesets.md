# ChangeSets — bulk / multi-Unit changes

A ChangeSet groups related mutations across multiple Units so they can be approved, applied, restored, and merged *as a set*. Use one any time a single logical change spans more than one Unit: a release, a fleet-wide defaults upgrade, a cross-Space promotion, a coordinated secret rotation. The ChangeSet acts as a lock: while a Unit is in a ChangeSet, another ChangeSet can't open against it until the first is closed.

Canonical doc: `https://docs.confighub.com/markdown/guide/change-apply.md`.

## Lifecycle

1. **Create** — `cub changeset create --space <home-space> <slug> --description "<one-line summary>"`. Lives in one Space; Units it covers can be anywhere. `<home-space>` is the app team's home Space (`<app>-home` per `skills/space-topology`) — cross-environment operational artifacts like ChangeSets, Tags, and Filters belong there, not in any single deployment Space.
2. **Open** — bulk-patch the target Units to add them to the ChangeSet. This creates a revision per Unit tagged with the ChangeSet's *start tag*, even if data doesn't change.
3. **Mutate** — every `cub function do` / `cub unit update` / `cub run` against those Units passes `--changeset <home-space>/<slug>`. Revisions are tagged as part of the ChangeSet.
4. **Close** — bulk-patch with `--changeset -`. Each Unit's head revision gets the ChangeSet's *end tag*.
5. **Approve / apply** — reference `ChangeSet:<home-space>/<slug>` as the revision. Approves or applies the end-tag revision per Unit.
6. **Rollback (optional)** — restore with `--restore "Before:ChangeSet:<home-space>/<slug>"`; every Unit's head reverts to the pre-open state.

## Open

```bash
cub changeset create --space <home-space> <slug> \
  --description "Release 452: fix X, feature Y, upgrade Z"

cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset <home-space>/<slug> \
  --change-desc "Starting <slug> rollout"
```

Use a named Filter (`cub filter create ... Unit --where-field "..."`) rather than inlining `--where` — you'll reuse the same Filter across open/mutate/close/approve/apply.

If any of the selected Units are already in another (open) ChangeSet, the open fails. Close the other one first, or narrow the Filter.

## Mutate

Every mutating call against Units in the ChangeSet must pass `--changeset`. The server rejects mutations that target Units in an open ChangeSet without the flag — that's the lock doing its job.

```bash
cub function do --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset <home-space>/<slug> \
  --change-desc "Bump image to v452. User prompt: <verbatim>. Clarifications: <condensed>" \
  -o mutations \
  -- set-container-image <container> <image>:v452
```

Calls can come from multiple operators / sessions as long as they all pass the same `--changeset`. Multiple revisions per Unit are fine — they're all part of the ChangeSet until close.

## Close

```bash
cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset -
```

The `-` sentinel means "null ChangeSetID." Cub can't distinguish `""` from "flag unset," so always use `-` to clear.

After close, every Unit's head revision carries the ChangeSet's end tag. No further mutations need the `--changeset` flag.

## Approve

If an `is-approved` / `vet-approvedby` Trigger is installed, the end-tag revision per Unit needs approval before apply. Bulk approve references the ChangeSet:

```bash
cub unit approve --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --revision ChangeSet:<home-space>/<slug>
```

## Apply

```bash
cub unit apply --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --revision ChangeSet:<home-space>/<slug> --wait
```

Apply targets the end-tag revision per Unit. If some Units were in the ChangeSet but had no data change, the per-Unit apply is a no-op for those — still recorded in the apply history with the ChangeSet reference.

## Rollback

To undo everything the ChangeSet did across all its Units:

```bash
# Tag the rollback for traceability (optional but recommended).
cub tag create --space <home-space> rollback-<slug> \
  --description "Rollback <slug>"

# Bulk restore each Unit's head to its pre-ChangeSet revision.
cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --restore "Before:ChangeSet:<home-space>/<slug>" \
  --tag <home-space>/rollback-<slug>

# Approve and apply the new restore revisions (no --revision -> head).
cub unit approve --space <target-space> --filter <home-space>/<filter-slug>
cub unit apply   --space <target-space> --filter <home-space>/<filter-slug> --wait
```

`Before:ChangeSet:<...>` resolves per Unit to "the revision that was head right before the ChangeSet opened." Each Unit gets a new head revision carrying the restored data.

## Merge / rebase around a ChangeSet

When changes made after the ChangeSet need to be reapplied on top of a restore (e.g., hotfix applied urgently, then the held-back changes come back), use a 3-way merge:

```bash
cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --merge-source Self \
  --merge-base Before:ChangeSet:<home-space>/<slug> \
  --merge-end ChangeSet:<home-space>/<slug> \
  --change-desc "Reapply <slug> on current head"
```

`merge-base` + `merge-end` define the range of changes to rebase onto the current head.

## Listing

Per-Unit (revisions in a ChangeSet for one Unit):

```bash
cub revision list --space <target-space> <unit-slug> \
  --where "ChangeSet.Slug = '<slug>'"
```

Cross-Unit (uses the start/end tag — organization-level revision listing):

```bash
cub revision list --space <target-space> --filter <home-space>/<filter-slug> \
  --tag <home-space>/<slug>
```

## When to reach for a ChangeSet

- A change spans more than one Unit and you want to approve / apply / rollback *atomically* (at least in audit terms — applies still go per-Unit).
- A release across many Units — group all revisions so you have one name to roll back or reapply.
- A bulk upgrade (`cub unit update --upgrade`) applied across a filter — opening a ChangeSet first makes the "before / after" auditable as one set.
- The user asks for a "rollback" across many Units — a prior ChangeSet (or a Tag you set at known-good time) is what you need to restore before.

## When not

- Single-Unit mutation. The per-Unit revision history already gives you named restore targets; a ChangeSet adds overhead without payoff.
- Rolling release where Units must apply in strict sequence with different approvals — ChangeSets apply as a set, not a sequence.
- Ad-hoc experiments in a scratch Space. Lock semantics are a feature when many operators share Units; noise when one person is iterating.

## Common pitfalls

- **Forgetting `--changeset` on a mutation.** The server rejects, but the error is specific — re-run with the flag.
- **Using `""` instead of `-` to close.** Looks identical, does nothing. Always `-`.
- **Reusing a ChangeSet slug across Spaces.** Slugs are Space-scoped; `acme-home/release-v452` is not the same as `acme-prod/release-v452`. Pick the app team's home Space (`<app>-home`, per `skills/space-topology`) and put all that app's release ChangeSets there.
- **Opening a ChangeSet before the Filter is right.** Opening creates revisions on every selected Unit. Dry-run the Filter first (`cub unit list --filter <home-space>/<slug>`) and confirm the set before opening.
- **Mixing ChangeSet and ad-hoc Tags on the same release.** Pick one. A ChangeSet already produces start / end Tags; don't also hand-apply a separate `release-v452` Tag to the same revisions.
