# incident-management eval — with-skill

## Scenario

> Production is crashing — pods are CrashLoopBackOff in `orders-prod`. We pushed a release ChangeSet `release-20260415-a3b2c1` 30 minutes ago. On-call is paging. What do I do?

## Principle: stabilize first, diagnose later

The bleeding stops by getting to a known-good state. Root cause comes after.

## Triage — first five questions

### 1. What was applied to the cluster most recently?

```bash
cub unit list --space "*" --filter orders-home/orders-app \
  --jq '[.[] | select(.UnitStatus.Action == "Apply"
                      and .UnitStatus.ActionStartedAt >= "2026-04-15T19:30:00Z")
         | {UnitID: .Unit.UnitID, SpaceID: .Unit.SpaceID, Slug: .Unit.Slug,
            ActionStartedAt: .UnitStatus.ActionStartedAt,
            ActionResult: .UnitStatus.ActionResult,
            LastChangeDescription: .Unit.LastChangeDescription}]'
```

If rows from `orders-prod` show applies in the last 30 minutes tied to `release-20260415-a3b2c1` → **Path A (rollback)**, since the release is the suspected cause.

### 2. Out-of-band cluster changes?

Ask the on-call. If yes (kubectl edit, manual hotfix), note for Path C after containment.

### 3. Wide or narrow?

Confirm whether the apply rows share `ChangeSet.Slug = release-20260415-a3b2c1` on their end-tag revisions:

```bash
cub revision list --space orders-prod --filter orders-home/orders-app \
  --where "ChangeSet.Slug = 'release-20260415-a3b2c1'"
```

Wide + tied to one ChangeSet → restore the ChangeSet as a unit.

### 4. ConfigHub itself healthy?

```bash
cub worker status --space workers-prod <worker-slug>
cub space list  # server reachable
```

If Worker is down, mutations can't apply — fix Worker first via `worker-bootstrap`.

### 5. Paging or post-mortem?

Actively paging — **minimize steps, defer tagging until green.**

## Path A — rollback (recent ChangeSet apply, causal)

The release ChangeSet is the natural restore scope.

### Hand off to rollback-revision

Compose the scope + restore target + change-desc and route to `rollback-revision`:

```
Scope: --space orders-prod --filter orders-home/orders-app
Restore target: Before:ChangeSet:orders-home/release-20260415-a3b2c1
Change-desc draft:

Incident rollback — pods CrashLoopBackOff in orders-prod since release-20260415-a3b2c1 apply at ~19:30Z. Reverting full ChangeSet per on-call decision.

User prompt: prod is crashing, pushed release 30 min ago, on-call paging
Clarifications: ticket INC-512; widespread CrashLoopBackOff; reverting full release ChangeSet, not per-Unit
```

`rollback-revision` will:
1. `cub tag create rollback-release-20260415-a3b2c1` in orders-home
2. Bulk `cub unit update --restore Before:ChangeSet:orders-home/release-20260415-a3b2c1` with --tag and --change-desc
3. Hand off to `cub-apply` for the apply

**Doctrinal reminder:** Rollback means `cub unit update --restore`. `cub unit apply --revision <N>` is NOT a rollback — it leaves head unchanged and the bad state returns on the next forward change.

## After green — close-out

Once symptoms are gone:

### 1. Tag the resolution

```bash
cub tag create --space orders-home incident-20260415-INC512 \
  --annotation "description=CrashLoopBackOff after release-20260415-a3b2c1 apply — resolution: rollback"

cub unit tag orders-home/incident-20260415-INC512 \
  --space orders-prod --filter orders-home/orders-app
```

### 2. Reconciliation check

Run `reconciliation-check` on orders-prod scope. ConfigHub, controller, cluster must agree.

### 3. Release verify

Run `release-verify` to produce the post-incident audit record.

### 4. If anyone made out-of-band cluster fixes during the incident

Run `drift-reconcile` to decide cluster-wins or ConfigHub-wins per change. Lean cluster-wins for stabilizing edits that should stick; ConfigHub-wins for temporary stopgaps.

### 5. Plan the root-cause investigation

The rollback restores service. The forward fix (whatever was wrong in `release-20260415-a3b2c1`) comes after a postmortem and a new release ChangeSet, going through `promotion-preflight` + `promote-release` again.

## Tool boundary

This skill orchestrates and decides. It does **not mutate**. Every mutation goes through the hand-off skill:
- Rollback → `rollback-revision`
- Apply → `cub-apply`
- Forward fix → `cub-mutate` + `cub-apply`
- Drift reconciliation → `drift-reconcile`
- Verification → `verify-delivery` / `reconciliation-check` / `release-verify`

If I find myself about to run `cub unit update / function do / unit apply` — stop and hand off.
