# promotion-preflight eval — with-skill

## Scenario

> We want to promote our `orders` app from staging to prod. Is staging ready? What do I need to check?

## Preflight

```
$ cub context get
User: <authenticated>
```

Source Space: `orders-staging`. Destination Space: `orders-prod`. Home Space: `orders-home`.

## Structured preflight checks

### A. Source env (orders-staging) is actually ready

Promoting from an env that isn't converged ships the same problems forward.

```bash
# Units with unapplied changes (head ahead of live)
cub unit list --space orders-staging \
  --filter orders-home/orders-app \
  --where "HeadRevisionNum > LiveRevisionNum AND TargetID IS NOT NULL"

# Units with open ApplyGates
cub unit list --space orders-staging \
  --filter orders-home/orders-app \
  --where "LEN(ApplyGates) > 0"

# Units whose last apply hasn't fully completed
cub unit list --space orders-staging \
  --filter orders-home/orders-app \
  --where "LiveRevisionNum != LastAppliedRevisionNum"
```

Any rows from any query = not ready. Name each problem Unit and which category (gate / unapplied / lagging LiveRevisionNum).

Cross-check delivery status:

```bash
cub unit list --space orders-staging \
  --filter orders-home/orders-app \
  --jq '[.[] | {Slug: .Unit.Slug, Status: .UnitStatus.Status, SyncStatus: .UnitStatus.SyncStatus, ActionResult: .UnitStatus.ActionResult}
         | select(.Status != "Ready" or .SyncStatus != "Synced")]'
```

Non-empty = broken state in staging.

### B. Destination (orders-prod) needs what's being promoted

```bash
cub unit list --space orders-prod \
  --filter platform/needs-upgrade
```

If empty, nothing to promote — stop.

### C. Diffs are what you expect

```bash
for u in $(cub unit list --space orders-prod --filter platform/needs-upgrade --quiet --jq '.[].Slug'); do
  echo "=== $u ==="
  cub unit diff "$u" --space orders-prod --from Upstream
done
```

Flag anything surprising: images moving more than one minor version, resource-limit changes, namespace/annotation churn that looks like drift.

### D. Destination policy outstanding

```bash
cub space get orders-prod --jq '{AttachedFilter: .TriggerFilter.Slug, ResolvedTriggers: (.Triggers // [] | length), TriggerFilterID: .Space.TriggerFilterID}'

cub unit list --space orders-prod --filter orders-home/orders-app --where "LEN(ApplyGates) > 0"
```

If approval is required (vet-approvedby Trigger), surface who needs to approve and how.

### E. Upstream linkage is correct

```bash
cub unit tree --space orders-prod --filter orders-home/orders-app
```

Confirm every destination Unit's upstream points at orders-staging (or wherever the user expects), not a shared base or wrong env.

## Output

- **Scope**: `--filter orders-home/orders-app` against `orders-prod`
- **Count**: N Units in scope
- **Blockers**: (per-Unit list from checks A-D)
- **Diffs**: summary per Unit
- **ChangeSet proposal**: `orders-home/release-20260415-<shortref>`
- **Approval plan**: (if vet-approvedby is active)
- **Recommendation**: `go` / `go with narrowed scope` / `no-go` with specific remediation

Hand the scope to `promote-release`.

## Tool boundary

Read-only. No `cub unit update / apply / changeset create`. Those belong to promote-release.
