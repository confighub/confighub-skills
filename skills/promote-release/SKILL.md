---
name: promote-release
description: Use when the user wants to promote a release from one env-Space to the next — phrases like "promote to staging", "roll forward to prod", "push this release to the next environment", "upgrade the downstream Units to match upstream", "cub unit update --upgrade across the app", "cub unit push-upgrade from the base". Wraps the promotion in a ChangeSet so it is auditable and rollback-able as a set, bulk-runs `cub unit update --upgrade` against the selected Units, closes the ChangeSet, and hands off to `cub-apply` to do the rollout. Do not load for the decision of whether to promote (use `promotion-preflight` first), for rollback of a prior promotion (use `rollback-revision` + `references/changesets.md`), for cluster-ConfigHub drift (use `drift-reconcile`), or for single-Unit in-place mutations (use `cub-mutate`).
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub revision list *) Bash(cub unit update *) Bash(cub unit push-upgrade *) Bash(cub unit tag *) Bash(cub tag create *) Bash(cub changeset create *) Bash(cub changeset update *) Bash(cub filter create *) Bash(cub filter update *)

---

# promote-release

The act-phase skill that executes a promotion. Takes the scope + ChangeSet name produced by `promotion-preflight` and runs the mutation loop: open ChangeSet → bulk upgrade → close ChangeSet → hand off to `cub-apply`.

## Why wrap every promotion in a ChangeSet

Promotions span multiple Units by definition. A ChangeSet:

- **Locks** the scope so a concurrent release can't interleave mutations mid-promotion.
- **Groups** revisions so they can be approved and applied as a set (`--revision ChangeSet:<slug>`).
- **Rolls back atomically** via `--restore Before:ChangeSet:<slug>` across every affected Unit if something goes wrong in the destination env.
- **Audits** as one entity — every touched Unit's revision history carries the ChangeSet's Tags.

If the scope is literally one Unit, skip the ChangeSet and use `cub-mutate` with `--upgrade`; the overhead isn't worth it. Two or more Units: always wrap.

## When to use

- User has cleared `promotion-preflight` and has a concrete scope (Filter + optional narrowing + ChangeSet name).
- User says "run the promotion", "go ahead and roll forward", or "push the release".
- Destination env needs `cub unit update --upgrade` across multiple Units from their upstreams, or `cub unit push-upgrade` from a shared base.

## Do not load for

- The decision of whether to promote — that's `promotion-preflight`.
- Rollback — use `rollback-revision` + `references/changesets.md` (`Before:ChangeSet:<slug>`).
- In-place single-Unit changes — `cub-mutate`.
- Applying to the cluster — this skill hands off to `cub-apply` once the ChangeSet closes.

## Preflight (this skill's own)

1. `promotion-preflight` has completed and produced a scope, a ChangeSet slug, and a `go` recommendation.
2. The `<app>-app` Filter (and any narrowing) from preflight is captured verbatim.
3. No other ChangeSet is currently open against the same Units (`cub unit list --space <app>-<to-env> --filter <app>-home/<app>-app --where "LEN(ChangeSetID) > 0"` should be empty).
4. User has write permission on the destination env-Space *and* the home Space (ChangeSet lives in `<app>-home`).

If any of these fail, stop and route back — don't "try anyway."

## Two promotion shapes

### Shape A — pull via `cub unit update --upgrade` (most common)

Downstream Units have `UpstreamUnitID` pointing at the source env (or a shared base). `--upgrade` resolves each Unit's upstream head and merges it in, preserving downstream customizations.

### Shape B — push via `cub unit push-upgrade`

Upstream Unit (typically a base in a shared Space) pushes to every Unit that has it as `UpstreamUnitID`. Useful when you're rolling a base-chart change out to every env at once, not env-by-env.

The two shapes are mutually exclusive for a given scope. Pick based on intent: env-by-env promotion is Shape A; simultaneous fleet-wide promotion from a base is Shape B.

## The loop — Shape A

```bash
# 0. Context (filled by promotion-preflight).
HOME_SPACE=<app>-home
TO_SPACE=<app>-<to-env>
APP_FILTER=$HOME_SPACE/<app>-app
CHANGESET_SLUG=release-$(date +%Y%m%d)-<shortref>
CHANGESET_REF=$HOME_SPACE/$CHANGESET_SLUG

# 1. Create the ChangeSet in the home Space.
cub changeset create --space $HOME_SPACE $CHANGESET_SLUG \
  --description "<one-line release description from preflight>"

# 2. Open the ChangeSet on the scope.
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --changeset $CHANGESET_REF \
  --change-desc "Open $CHANGESET_SLUG — begin promotion to <to-env>"

# 3. Bulk upgrade: every downstream Unit pulls its upstream head.
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --changeset $CHANGESET_REF \
  --upgrade \
  --change-desc "Upgrade to upstream head as part of $CHANGESET_SLUG.

User prompt: <verbatim>
Clarifications: <condensed, e.g. 'promoting app-a from staging to prod; source last applied rev 47'>"

# 4. Review diffs before closing.
for u in $(cub unit list --space $TO_SPACE --filter $APP_FILTER --quiet --jq '.[].Slug'); do
  echo "=== $u ==="
  cub unit diff "$u" --space $TO_SPACE --from-revision -2   # previous head vs new head
done

# 5. Close the ChangeSet.
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --changeset -
```

After close, each affected Unit's head revision carries `$CHANGESET_SLUG`'s end tag. No cluster changes yet — only ConfigHub state has moved.

## The loop — Shape B

```bash
# 1. Create the ChangeSet.
cub changeset create --space $HOME_SPACE $CHANGESET_SLUG \
  --description "<release description>"

# 2. Open against every downstream Unit of the base.
# (Use the same Filter <app>-app but narrow to downstream Units.)
cub unit update --patch --space "*" \
  --filter $APP_FILTER \
  --where "UpstreamUnitID = '<base-unit-uuid>'" \
  --changeset $CHANGESET_REF \
  --change-desc "Open $CHANGESET_SLUG — fleet promotion from base"

# 3. Push-upgrade from the base. This does the per-downstream merge for us.
cub unit push-upgrade <base-unit-slug> --space <base-space>
# (push-upgrade does NOT accept --changeset directly in current cub; the lock is
#  already in place from step 2, which the server enforces on every update.)

# 4. Review diffs per downstream Unit.
# ... same pattern as Shape A step 4 ...

# 5. Close.
cub unit update --patch --space "*" \
  --filter $APP_FILTER \
  --where "UpstreamUnitID = '<base-unit-uuid>'" \
  --changeset -
```

If `cub unit push-upgrade` rejects mutations under an open ChangeSet on your cub version, fall back to Shape A — iterate the downstream env-Spaces one by one.

## Approval (if required)

If the destination env has an `is-approved` / `vet-approvedby` Trigger, the new end-tag revisions need approval before apply. The ChangeSet makes this one command:

```bash
cub unit approve --space $TO_SPACE \
  --filter $APP_FILTER \
  --revision ChangeSet:$CHANGESET_REF
```

Route this to the approver per the preflight's approval plan — don't self-approve unless the user explicitly has that role.

## Hand off to cub-apply

Apply the ChangeSet as a set:

```bash
cub unit apply --space $TO_SPACE \
  --filter $APP_FILTER \
  --revision ChangeSet:$CHANGESET_REF \
  --wait --timeout 10m0s
```

From here, `cub-apply` / `verify-delivery` / `reconciliation-check` / `release-verify` own the runtime.

## Rollback

If the destination env rejects the release, the ChangeSet makes rollback one command (per `references/changesets.md`):

```bash
cub tag create --space $HOME_SPACE rollback-$CHANGESET_SLUG \
  --annotation "description=Rollback $CHANGESET_SLUG"

cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --restore "Before:ChangeSet:$CHANGESET_REF" \
  --tag $HOME_SPACE/rollback-$CHANGESET_SLUG \
  --change-desc "Rollback $CHANGESET_SLUG. User prompt: <verbatim>. Clarifications: <condensed>"

cub unit apply --space $TO_SPACE --filter $APP_FILTER --wait
```

Each Unit's head reverts to its pre-ChangeSet state and the subsequent apply pushes that back to the cluster. Full detail: `rollback-revision` + `references/changesets.md`.

## Tool boundary

- Allowed: `cub changeset create/update`, `cub unit update` (patch + upgrade + restore), `cub unit push-upgrade`, `cub filter create/update`, `cub tag create`, `cub unit tag`, read-only `cub unit/revision list/get/diff/tree/bridgestate`.
- Not allowed: `cub unit apply` (hand off to `cub-apply`), `kubectl apply` / other out-of-band cluster mutation, editing Unit data mid-promotion without a function (if the upgrade merge has conflicts requiring data edits, those go through `cub-mutate` *inside* the open ChangeSet, not here).

## Stop conditions

- Preflight didn't run, or ran with `no-go` — route back.
- Another ChangeSet is already open against the scope — close it (or narrow the Filter around it); do not open a second one.
- Upgrade merge leaves conflicts (`cub unit diff` shows `<<<<<<<` markers or the Unit's `MergeConflicts` field is non-empty) — stop, resolve in `cub-mutate` (still within the open ChangeSet), then re-diff and close.
- User wants to skip the ChangeSet for a >1-Unit promotion. Push back: loses lock + atomic rollback.
- Approval is required and the user tries to self-approve without the role — stop and route to the approver.

## Verify chain

1. `cub unit list --space $TO_SPACE --filter $APP_FILTER` — every scoped Unit's `UpstreamRevisionNum` now matches the upstream's head (no rows in `platform/needs-upgrade` for the scope).
2. `cub revision list --space $TO_SPACE --filter $APP_FILTER --where "ChangeSet.Slug = '$CHANGESET_SLUG'"` — revisions for every Unit are tagged with the ChangeSet.
3. `cub changeset get --space $HOME_SPACE $CHANGESET_SLUG` — shows both start and end tags set, open state = closed.

## Evidence

- `cub changeset get --space $HOME_SPACE $CHANGESET_SLUG --web` — the release entity in the GUI, linking to every Unit revision.
- `cub unit diff <u> --space $TO_SPACE --from-revision Tag:<start-tag>` per Unit — what landed vs. what was there.

## References

- `references/changesets.md` — lifecycle, rollback, merge / rebase.
- `references/filters-and-queries.md` — `needs-upgrade`, `unapplied-changes`, `has-upstream` recipes.
- `references/cub-cli.md` — `--where` vs `--filter` vs `--changeset`, `-` sentinel for close.
- `references/revisions.md` — revision references (`ChangeSet:<name>`, `Before:ChangeSet:<name>`, `Tag:<name>`).
- Companion skills: `promotion-preflight` (prerequisite), `space-topology` (home / env Space layout), `cub-mutate` (conflict resolution within an open ChangeSet), `cub-apply` (runtime), `rollback-revision` (post-promotion rollback path), `verify-delivery` / `reconciliation-check` / `release-verify` (post-rollout).
