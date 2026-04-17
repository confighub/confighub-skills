---
name: promote-release
description: 'Use when the user wants to promote a release from one env-Space to the next, or push a base revision to every downstream across the fleet — phrases like "promote to staging", "roll forward to prod", "push this release to the next environment", "upgrade the downstream Units to match upstream", "is staging ready to roll forward?", "what do I need to check before promoting to prod?", "preflight before pushing the release to prod", "which Units are behind their upstream?". One skill for the whole promotion arc: runs the preflight checks (source converged, destination in scope, diffs sane, policy + approval ready, upstream linkage matches intent) to produce a go / no-go and a concrete scope; on go, wraps the promotion in a ChangeSet, bulk-runs `cub unit update --patch --upgrade --where ...`, closes the ChangeSet, and hands off to `cub-apply` for the rollout. Do not load for rollback of a prior promotion (use `rollback-revision` + `references/changesets.md`), cluster-ConfigHub drift (use `drift-reconcile`), post-promotion verification (use `verify-apply`), or single-Unit in-place mutations (use `cub-mutate`).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub revision list *) Bash(cub revision get *) Bash(cub unit update *) Bash(cub unit tag *) Bash(cub tag create *) Bash(cub changeset create *) Bash(cub changeset update *) Bash(cub filter create *) Bash(cub filter update *) Bash(kubectl get *) Bash(kubectl describe *)
---

# promote-release

The end-to-end promotion skill: decide, execute, hand off. Preflight the source and destination, produce a concrete scope, wrap the promotion in a ChangeSet, bulk upgrade the Units, close the ChangeSet, and hand off to `cub-apply`.

## Why wrap every promotion in a ChangeSet

Promotions span multiple Units by definition. A ChangeSet:

- **Locks** the scope so a concurrent release can't interleave mutations mid-promotion.
- **Groups** revisions so they can be approved and applied as a set (`--revision ChangeSet:<slug>`).
- **Rolls back atomically** via `--restore Before:ChangeSet:<slug>` across every affected Unit if something goes wrong in the destination env.
- **Audits** as one entity — every touched Unit's revision history carries the ChangeSet's Tags.

If the scope is literally one Unit, skip the ChangeSet and use `cub-mutate` with `--upgrade`; the overhead isn't worth it. Two or more Units: always wrap.

## When to use

- User says "promote to staging / prod", "roll forward", "push the release", "upgrade the downstreams to match upstream".
- User asks the decision question: "is this ready?", "what do I need to check before promoting?", "which Units are behind their upstream?".
- Before any `cub unit update --patch --upgrade` that spans more than one Unit.
- Pushing a shared base revision (e.g., a common chart) out to every downstream across env-Spaces.

## Do not load for

- Rollback of a prior promotion — use `rollback-revision` + `references/changesets.md` (`Before:ChangeSet:<slug>`).
- Drift between ConfigHub and cluster in the _same_ env — use `drift-reconcile`.
- Verifying a promotion _after_ it applied — use `verify-apply`.
- In-place single-Unit changes — use `cub-mutate`.
- Applying to the cluster — this skill hands off to `cub-apply` once the ChangeSet closes.

## Preflight gates (for this skill to do its work)

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. The source env-Space and destination env-Space are known. Promotion data flows `<app>-<source-env>` → `<app>-<destination-env>`. Note this is the *opposite* of ConfigHub's Link direction: a `UpgradeUnit` Link points *from* a downstream Unit *to* its upstream Unit (dependency edge, against the direction of data flow). When a section below reads "the destination Unit's upstream", the upstream is in the source env.
3. The app's home Space is known (`<app>-home`) — the `<app>-app` Filter, release ChangeSets, and Tags live there.
4. User has at least read permission on both env-Spaces and the home Space, and write permission on the destination env-Space and the home Space.
5. No other ChangeSet is currently open against the destination scope:

   ```bash
   cub unit list --space <app>-<destination-env> --filter <app>-home/<app>-app \
     --where "ChangeSetID IS NOT NULL"
   ```

   Any rows = stop; close the open ChangeSet (or narrow the Filter around it) before opening a new one.

## The loop

### 1. Decide — preflight the promotion

The goal of this phase is a concrete go / no-go and a scope that the execution phase can pick up verbatim.

#### A. Source env is actually ready

Promoting from an env that isn't itself converged just ships the same problems forward. `--where` supports AND only (no OR). Run one query per condition and union the results in the preflight report. `cub unit list` also takes at most one `--filter` per command — combine a named Filter with `--where` rather than stacking two `--filter`s.

```bash
# Units with unapplied changes (head ahead of live).
cub unit list --space <app>-<source-env> \
  --filter <app>-home/<app>-app \
  --where "HeadRevisionNum > LiveRevisionNum AND TargetID IS NOT NULL"

# Units with open ApplyGates.
cub unit list --space <app>-<source-env> \
  --filter <app>-home/<app>-app \
  --where "LEN(ApplyGates) > 0"

# Units whose last apply hasn't fully completed in the cluster.
cub unit list --space <app>-<source-env> \
  --filter <app>-home/<app>-app \
  --where "LiveRevisionNum != LastAppliedRevisionNum"
```

Any rows from any of the three queries = not ready. Name each problem Unit and which of the three categories it's in (gate / unapplied / lagging `LiveRevisionNum`) in the preflight report.

Cross-check the delivery side — the Unit's `UnitStatus.Status` reflects whether the last apply landed cleanly:

```bash
cub unit list --space <app>-<source-env> \
  --filter <app>-home/<app>-app \
  --jq '[.[] | {Slug: .Unit.Slug, Status: .UnitStatus.Status, SyncStatus: .UnitStatus.SyncStatus, ActionResult: .UnitStatus.ActionResult}
         | select(.Status != "Ready" or .SyncStatus != "Synced")]'
```

Any non-empty result = broken state in the source env. Promoting forward ships the broken state.

In the case of base Units, `TargetID` will be `NULL` and `LiveRevisionNum` will be 0. If there's a `vet-placeholders` ApplyGate on a base, that can be ignored.

#### B. Destination needs what's being promoted

The Units that _would_ change are the ones whose `UpstreamRevisionNum` is behind their upstream's `HeadRevisionNum`. Use the standard `needs-upgrade` filter (`references/filters-and-queries.md`):

```bash
cub unit list --space <app>-<destination-env> \
  --filter platform/needs-upgrade
```

If empty, there's nothing to promote — tell the user and stop.

Narrow further if the user wants to promote only part of the app:

```bash
# Only the API Units, not the workers.
cub unit list --space <app>-<destination-env> \
  --filter platform/needs-upgrade \
  --where "Slug LIKE '%-api%'"
```

The combination of `--filter` + `--where` recorded here is what gets passed to the execution phase.

#### C. Diffs are what the user expects

For each Unit in scope, show the pre-promotion diff:

```bash
for u in $(cub unit list --space <app>-<destination-env> --filter platform/needs-upgrade --quiet --jq '.[].Unit.Slug'); do
  echo "=== $u ==="
  cub unit update --patch --upgrade --dry-run --display-mutations \
    --space <app>-<destination-env> --unit $u
done
```

Read the diffs with the user. Flag anything surprising: images moving by more than one minor version, resource-limit changes not expected, namespace/annotation churn that looks like drift rather than intent.

#### D. Destination policy + approval

Confirm the destination Space has its expected Triggers attached and no lingering ApplyGates from prior runs that would immediately block:

```bash
cub space get <app>-<destination-env> \
  --jq '{AttachedFilter: .TriggerFilter.Slug, ResolvedTriggers: (.Triggers // [] | length), TriggerFilterID: .Space.TriggerFilterID}'

cub unit list --space <app>-<destination-env> --filter <app>-home/<app>-app \
  --where "LEN(ApplyGates) > 0"
```

If approval is required (`vet-approvedby` or `is-approved` Trigger), surface _who_ needs to approve and _how_ (`cub unit approve --revision ChangeSet:<...>`) so it's part of the promotion plan, not a surprise mid-flight.

#### E. Upstream linkage is actually what the user thinks

A Unit gets promoted via its `UpstreamUnitID` — whatever `cub unit update --upgrade` resolves. Confirm the graph:

```bash
cub unit tree --space <app>-<destination-env> --filter <app>-home/<app>-app
cub link list --space <app>-<destination-env> --where "UpdateType = 'UpgradeUnit'"
```

If any destination Unit points upstream at something the user doesn't expect (e.g., it's linked to a shared base rather than to the source env), the "promotion" is going to pull from that base, not from `<app>-<source-env>`. Stop and confirm intent before the mutation.

#### Preflight output

Produce a concrete go / no-go with these fields:

- **Scope**: exact `--space` + `--filter` + `--where` the mutation will use.
- **Count**: how many Units are in scope.
- **Blockers** (if any): per-Unit list of outstanding gates / unapproved / not-yet-live / mis-linked.
- **Diffs**: short summary per Unit; full diffs on request.
- **ChangeSet proposal**: slug (`release-<YYYYMMDD>-<shortref>` in `<app>-home`, or whatever the user names it), description draft.
- **Approval plan** (if relevant): who approves, via what revision reference.
- **Recommendation**: `go`, `go with narrowed scope`, or `no-go` with specific remediation.

If `no-go`, stop and route back to the relevant remediation skill (`cub-apply` for unapplied state, `triggers-and-applygates` for gate blockers, `drift-reconcile` for env drift). Do not try to promote anyway.

### 2. Execute — open, upgrade, close

Every promotion runs the same three-command loop. The only difference between an env-by-env promotion and a fleet-wide base push is the **selector** in `--where` / `--filter` / `--space`.

```bash
# 0. Context (from the preflight output).
HOME_SPACE=<app>-home
APP_FILTER=$HOME_SPACE/<app>-app
CHANGESET_SLUG=release-$(date +%Y%m%d)-<shortref>
CHANGESET_REF=$HOME_SPACE/$CHANGESET_SLUG

# 1. Create the ChangeSet in the home Space.
cub changeset create --space $HOME_SPACE $CHANGESET_SLUG \
  --description "<one-line release description from preflight>"

# 2. Bulk upgrade every in-scope downstream Unit. --patch holds the
#    ChangeSet open on every affected Unit; --upgrade does the per-Unit
#    merge from each Unit's resolved upstream head; --display-mutations
#    prints the diff inline so the user sees what landed.
cub unit update --patch \
  --space <SCOPE_SPACE> \
  <SCOPE_SELECTOR> \
  --changeset $CHANGESET_REF \
  --upgrade \
  --display-mutations \
  --change-desc "Upgrade to upstream head as part of $CHANGESET_SLUG.

User prompt: <verbatim>
Clarifications: <condensed, e.g. 'promoting app-a from staging to prod; source last applied rev 47'>"

# 3. Close the ChangeSet — same scope, no --upgrade, just --changeset -.
cub unit update --patch \
  --space <SCOPE_SPACE> \
  <SCOPE_SELECTOR> \
  --changeset -
```

After close, each affected Unit's head revision carries the ChangeSet's end tag. No cluster changes yet — only ConfigHub state has moved.

#### Selectors for the two common shapes

**Env-by-env** (most common): the destination env-Space contains downstream Units linked to the source env-Space. Promote everything in the app Filter that's behind its upstream.

```
--space <app>-<destination-env>
--filter <app>-home/<app>-app \
  --where "Unit.UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum"
```

**Base → fleet** (push a shared base out everywhere at once): every downstream Unit across all env-Spaces whose `UpstreamUnitID` is the base. Cross-space requires `--space "*"`.

```
--space "*"
--where "Unit.UpstreamUnitID = '<base-unit-uuid>' AND Unit.UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum"
```

The mechanics are identical; only the selector differs. Use the env-by-env selector for controlled env-ladder promotions; use the base-fleet selector when a common base change should hit every env simultaneously.

> `cub unit push-upgrade` is deprecated; do not use it. The selector-based `cub unit update --patch --upgrade` form above is the unified replacement and it composes cleanly with `--dry-run`, `--display-mutations`, and `--changeset`.

### 3. Approval (if required)

If the destination env has an `is-approved` / `vet-approvedby` Trigger, the new end-tag revisions need approval before apply. The ChangeSet makes this one command:

```bash
cub unit approve --space <SCOPE_SPACE> \
  <SCOPE_SELECTOR> \
  --revision ChangeSet:$CHANGESET_REF
```

Route this to the approver per the preflight's approval plan — don't self-approve unless the user explicitly has that role.

### 4. Hand off to cub-apply

Apply the ChangeSet as a set:

```bash
cub unit apply --space <SCOPE_SPACE> \
  <SCOPE_SELECTOR> \
  --revision ChangeSet:$CHANGESET_REF \
  --wait --timeout 10m0s
```

From here, `cub-apply` / `verify-apply` own the runtime.

## Rollback

If the destination env rejects the release, the ChangeSet makes rollback one command (per `references/changesets.md`):

```bash
cub tag create --space $HOME_SPACE rollback-$CHANGESET_SLUG \
  --annotation "description=Rollback $CHANGESET_SLUG"

cub unit update --patch \
  --space <SCOPE_SPACE> \
  <SCOPE_SELECTOR> \
  --restore "Before:ChangeSet:$CHANGESET_REF" \
  --tag $HOME_SPACE/rollback-$CHANGESET_SLUG \
  --change-desc "Rollback $CHANGESET_SLUG. User prompt: <verbatim>. Clarifications: <condensed>"

cub unit apply --space <SCOPE_SPACE> <SCOPE_SELECTOR> --wait
```

Each Unit's head reverts to its pre-ChangeSet state and the subsequent apply pushes that back to the cluster. Full detail: `rollback-revision` + `references/changesets.md`.

## Tool boundary

- Allowed: `cub changeset create/update`, `cub unit update` (patch + upgrade + restore), `cub filter create/update`, `cub tag create`, `cub unit tag`, read-only `cub unit/revision/link list/get/tree/bridgestate/diff`, `kubectl get`/`describe` for the preflight cluster cross-check.
- Not allowed: `cub unit push-upgrade` (deprecated — use the selector-based `cub unit update --patch --upgrade` instead), `cub unit apply` (hand off to `cub-apply`), `kubectl apply` / other out-of-band cluster mutation. If the upgrade merge has conflicts requiring data edits, those go through `cub-mutate` _inside_ the open ChangeSet, not here.

## Stop conditions

- Preflight recommendation is `no-go` — route back to the relevant remediation skill (`cub-apply`, `triggers-and-applygates`, `drift-reconcile`).
- Another ChangeSet is already open against the scope — close it (or narrow the Filter around it); do not open a second one.
- Destination scope is empty — nothing to promote. Tell the user and stop.
- Upgrade merge leaves conflicts (`cub unit diff` shows `<<<<<<<` markers or the Unit's `MergeConflicts` field is non-empty) — stop, resolve in `cub-mutate` (still within the open ChangeSet), then re-diff and close.
- User wants to skip the ChangeSet for a >1-Unit promotion. Push back: loses lock + atomic rollback.
- Approval is required and the user tries to self-approve without the role — stop and route to the approver.
- Upstream linkage doesn't match intent. Stop and ask.

## Verify chain

1. `cub unit list --space <SCOPE_SPACE> --filter $APP_FILTER` (or the fleet selector) — every scoped Unit's `UpstreamRevisionNum` now matches the upstream's head (no rows in `platform/needs-upgrade` for the scope).
2. `cub revision list --space <SCOPE_SPACE> --filter $APP_FILTER --where "ChangeSet.Slug = '$CHANGESET_SLUG'"` — revisions for every Unit are tagged with the ChangeSet.
3. `cub changeset get --space $HOME_SPACE $CHANGESET_SLUG` — shows both start and end tags set, open state = closed.

## Evidence

- `cub changeset get --space $HOME_SPACE $CHANGESET_SLUG --web` — the release entity in the GUI, linking to every Unit revision.
- `cub unit list --space <SCOPE_SPACE> --filter platform/needs-upgrade --web` — the exact set that was in scope (should be empty post-close).
- `cub unit tree --space <SCOPE_SPACE> --filter $APP_FILTER --web` — upstream linkage the promotion followed.
- `cub unit diff <u> --space <SCOPE_SPACE> --from-revision Tag:<start-tag>` per Unit — what landed vs. what was there.

## References

- `references/changesets.md` — lifecycle, rollback, merge / rebase.
- `references/filters-and-queries.md` — `needs-upgrade`, `unapplied-changes`, `has-apply-gates`, `has-upstream`, `not-approved` recipes.
- `references/cub-cli.md` — `--where` vs `--filter` vs `--changeset`, `-` sentinel for close.
- `references/revisions.md` — revision references (`ChangeSet:<name>`, `Before:ChangeSet:<name>`, `Tag:<name>`).
- Companion skills: `space-topology` (home / env Space layout), `cub-mutate` (conflict resolution within an open ChangeSet), `cub-apply` (runtime), `rollback-revision` (post-promotion rollback path), `verify-apply` (post-rollout).
- https://docs.confighub.com/guide/variants/
- https://docs.confighub.com/guide/dependencies/
