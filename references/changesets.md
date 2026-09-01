# ChangeSets — bulk / multi-Unit changes

A ChangeSet groups related mutations across multiple Units so they can be reviewed, restored, and merged *as a set*. Use one any time a single logical change spans more than one Unit: a release, a fleet-wide defaults upgrade, a cross-Space promotion, a coordinated secret rotation. The ChangeSet acts as a lock: while a Unit is in a ChangeSet, another ChangeSet can't open against it until the first is closed. Delivery is now a Component/Variant Space Release, not a per-Unit runtime operation.

**Execution mode:** follow [How commands run](execution-modes.md). Every write in this reference is a separate one-command normal host permission call. This pack preapproves none of them.

Canonical doc: `https://docs.confighub.com/markdown/guide/changes.md`.

## Lifecycle

1. **Create** — `cub changeset create --space <home-space> <slug> --description "<one-line summary>"`. Lives in one Space; Units it covers can be anywhere. `<home-space>` is the app team's home Space (`<app>-home` per `skills/confighub-core`) — cross-environment operational artifacts like ChangeSets, Tags, and Filters belong there, not in any single deployment Space.
2. **Open** — bulk-patch the target Units to add them to the ChangeSet. Attaching creates **no** revision: the ChangeSet's *start tag* goes on each Unit's existing head, so the ChangeSet is the interval `(start, end]` and every Unit it was opened on carries the tag whether or not it later changes.
3. **Mutate** — every `cub function set` / `cub unit update` / `cub run` against those Units passes `--changeset <home-space>/<slug>`. Revisions are tagged as part of the ChangeSet.
4. **Close** — bulk-patch with `--changeset -`. Each Unit's head revision gets the ChangeSet's *end tag*.
5. **Native gate assessment** — installed v0.2.15 help advertises ChangeSet, Tag, numeric, Live, and head selectors. Exact v0.2.21 acceptance and atomic preconditions are not source-reviewed, so confirm the command with current help, inspect the result, and do not claim exact reviewed-artifact binding.
6. **Review / publish** — compute the destination Space's complete EffectiveReleaseSet, disclose the provider race, then submit the separate publish call to the host permission system. Do not claim that the preview is atomically bound to execution.
7. **Rollback (optional)** — restore with `--restore "Before:ChangeSet:<home-space>/<slug>"`; every Unit's head reverts to the pre-open state.

## Open

```text
cub changeset create --space <home-space> <slug> \
  --description 'Prepare reviewed release scope'

cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset <home-space>/<slug> \
  --change-desc 'Start reviewed ChangeSet rollout'
```

Use a named Filter (`cub filter create ... Unit --where-field "..."`) rather than inlining `--where` — you'll reuse the same Filter across open/mutate/close/review.

If any of the selected Units are already in another (open) ChangeSet, the open fails. Close the other one first, or narrow the Filter.

## Mutate

Every mutating call against Units in the ChangeSet must pass `--changeset`. The server rejects mutations that target Units in an open ChangeSet without the flag — that's the lock doing its job.

```bash
cub function set --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset <home-space>/<slug> \
  --change-desc 'Bump reviewed image to v452' \
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

## Review and publish

If a `vet-approvedby` Trigger is installed, preserve the advertised ChangeSet approval form only as historical compatibility knowledge:

```text
# Historical example only; confirm current selector support with installed help.
cub unit approve --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --revision ChangeSet:<home-space>/<slug>
```

Installed v0.2.15 help advertises numeric, live, Tag, and ChangeSet selectors.
Exact v0.2.21 server acceptance and atomic preconditions are not source-reviewed
here. Confirm current help, inspect the result, and do not claim exact
reviewed-artifact binding without provider evidence. Approval, promotion, and
publication are separate host-permission calls.

Next compute the destination Space's EffectiveReleaseSet: all Units whose `TargetID` equals `Space.ReleaseTargetID`. The Release command has no ChangeSet/Filter/Unit selector. If the ChangeSet is narrower than that set, disclose the additional Units and obtain a fresh whole-Space approval; never reuse the ChangeSet approval as though it narrowed the Release.

Once every effective revision, ID/hash, target, and gate is bound in the `release-publish` preview, the current command still cannot atomically bind those reads to provider execution. Refresh the preview immediately before this one standalone host-permission call:

```bash
cub release publish <target-variant-space>
```

After execution, capture the Release ID, bundle Digest, OCI ManifestDigest, digest-matching manifest Target annotation, and exact `Revision.Releases` membership receipt; then prove controller/runtime convergence before declaring the rollout complete. State that the pre-read-to-publish race remains unless a future provider operation accepts atomic expected-target/manifest preconditions.

## Rollback

To undo everything the ChangeSet did across all its Units:

```text
# Tag the rollback for traceability (optional but recommended).
cub tag create --space <home-space> rollback-<slug> \
  --annotation 'description=Rollback reviewed ChangeSet'

# Bulk restore each Unit's head to its pre-ChangeSet revision.
cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --restore "Before:ChangeSet:<home-space>/<slug>" \
  --tag <home-space>/rollback-<slug>

# After verifying the restore and resolving any current gate, publication is a
# separate user request and host-permission call.
cub release publish <target-variant-space>
```

`Before:ChangeSet:<...>` resolves per Unit to the start tag's revision — the head the Unit had right before the ChangeSet opened. Each Unit gets a new head revision carrying the restored data. Because the start tag marks a revision that already existed rather than one manufactured by attaching, a Unit that joined the ChangeSet and never changed rewinds cleanly along with the rest of the set.

## Merge / rebase around a ChangeSet

When changes made after the ChangeSet need to be reapplied on top of a restore (e.g., hotfix applied urgently, then the held-back changes come back), use a 3-way merge:

```bash
cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --merge-source Self \
  --merge-base Before:ChangeSet:<home-space>/<slug> \
  --merge-end ChangeSet:<home-space>/<slug> \
  --change-desc 'Reapply reviewed ChangeSet on current head'
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

- A change spans more than one Unit and you want grouped review and set-wise rollback. Do not call current native approval exact or publication atomic across a subset: a Space Release captures its complete EffectiveReleaseSet.
- A release across many Units — group all revisions so you have one name to roll back or reapply.
- **Any upgrade or promotion.** A merge now *walks* its range by default, recording one downstream revision per upstream revision that has an effect (see `skills/promote-release`). One promotion therefore produces many revisions per Unit, and there is no single "the revision before the promotion" number to restore to. A ChangeSet — `cub variant promote <space> --changeset <home-space>/<slug>`, or the open/mutate/close flow around a bulk `--upgrade` — gives the whole promotion one name and makes `--restore Before:ChangeSet:<slug>` the way back. This is the main reason to reach for one.
- The user asks for a "rollback" across many Units — a prior ChangeSet (or a Tag you set at known-good time) is what you need to restore before.

## When not

- Single-Unit mutation. The per-Unit revision history already gives you named restore targets; a ChangeSet adds overhead without payoff.
- Rollout where Units need strict sequencing or different release approvals — a ChangeSet groups revisions but does not encode controller order or narrow a Space Release.
- Ad-hoc experiments in a scratch Space. Lock semantics are a feature when many operators share Units; noise when one person is iterating.

## Common pitfalls

- **Forgetting `--changeset` on a mutation.** The server rejects, but the error is specific — re-run with the flag.
- **Using `""` instead of `-` to close.** Looks identical, does nothing. Always `-`.
- **Reusing a ChangeSet slug across Spaces.** Slugs are Space-scoped; `acme-home/release-v452` is not the same as `acme-prod/release-v452`. Pick the app team's home Space (`<app>-home`, per `skills/confighub-core`) and put all that app's release ChangeSets there.
- **Opening a ChangeSet before the Filter is right.** Opening tags every selected Unit's head, and the ChangeSet then locks those Units against another ChangeSet. Dry-run the Filter first (`cub unit list --filter <home-space>/<slug>`) and confirm the set before opening.
- **Mixing ChangeSet and ad-hoc Tags on the same release.** Pick one. A ChangeSet already produces start / end Tags; don't also hand-apply a separate `release-v452` Tag to the same revisions.
