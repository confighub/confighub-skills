# drift-reconcile eval — with-skill

## Scenario

> Someone kubectl edit'd our `payments-api` Deployment in prod to set replicas to 10 during a traffic spike. The spike is over. ConfigHub says replicas should be 3. How do I reconcile this?

## Preflight

```
$ cub context get
User: <authenticated>
```

```bash
cub unit get payments-api --space payments-prod --jq '{TargetID: .Unit.TargetID, BridgeWorker: .BridgeWorker.Slug}'
# TargetID: <uuid>, BridgeWorker: eval-worker
```

Worker is up, Target bound.

## Step 1 — Identify the drift

Read drift as **Data vs LiveData** (both cleaned of status, controller fields):

```bash
cub unit diff payments-api --space payments-prod --from=LastAppliedRevisionNum --to=LiveRevisionNum
```

Expected diff: `spec.replicas: 3 → 10` (and possibly minor controller-managed field noise the Worker already elides).

For a preview of what refresh would bring in:

```bash
opID=$(cub unit refresh --wait --space payments-prod payments-api --dry-run --jq '.QueuedOperationID')
cub unit-action get --space payments-prod payments-api "$opID"
```

## Step 2 — Name the source

This is a **manual `kubectl edit`** — someone scaled up during a traffic spike as a stopgap. The Worker's Kubernetes bridge already strips HPA-managed fields, so if `spec.replicas` shows in the diff, it was set by a human, not the HPA.

## Step 3 — Decide

The spike is over. The replica edit was a stopgap, not an intentional long-term change. This is a **ConfigHub wins** resolution — revert the cluster to match ConfigHub's Data (replicas: 3).

However, consider: should replicas stay at 10? If traffic is expected to return, absorb the change (cluster wins) or update Data to a higher baseline via `cub-mutate`. The decision goes through the user.

## Step 4a — ConfigHub wins (recommended here)

Two options:

**Simple re-apply** (fastest — use when audit trail of what was in the cluster isn't needed):

```bash
cub unit apply payments-api --space payments-prod --wait
```

**Observation + revert** (use when the postmortem needs to see what was in the cluster):

```bash
# Refresh to absorb live state as a new head (records what was there)
cub unit refresh payments-api --space payments-prod

# Restore to pre-refresh head (reverts to replicas: 3)
cub unit update payments-api --space payments-prod --restore -1 \
  --change-desc "Revert out-of-band kubectl edit (replicas 10→3). Spike-time stopgap no longer needed.

User prompt: someone kubectl edit'd replicas to 10 during spike, spike is over
Clarifications: refresh captured live state; restoring to pre-refresh head"

# Apply the restored state
cub unit apply payments-api --space payments-prod --wait
```

## Step 5 — Stop recurrence at the source

The manual kubectl edit was a one-time incident response, but:
- Route the operator through `cub-mutate` for future scaling (`cub function do set-replicas`)
- If traffic spikes are expected, consider an HPA — and remove `spec.replicas` from Data so the HPA owns it unambiguously

## Verify

```bash
# Drift resolved — diff should be empty
cub unit diff payments-api --space payments-prod --from=LastAppliedRevisionNum --to=LiveRevisionNum

# Revision nums aligned
cub unit get payments-api --space payments-prod \
  --jq '.Unit | {HeadRevisionNum, LastAppliedRevisionNum, LiveRevisionNum}'
```

## Tool boundary

Hand off apply to `cub-apply`. Never use `kubectl edit/apply/patch` to "fix" drift — that creates more drift.
