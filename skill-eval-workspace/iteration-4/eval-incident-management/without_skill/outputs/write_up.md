# incident-management eval — baseline (no skill)

## Scenario

> Production is crashing — pods are CrashLoopBackOff in `orders-prod`. We pushed a release ChangeSet `release-20260415-a3b2c1` 30 minutes ago. On-call is paging. What do I do?

## Response

Since you just pushed a release and now production is crashing, the fastest fix is to roll back to the previous version.

### 1. Check what's running

```bash
kubectl get pods -n orders-prod
kubectl describe pod <crashing-pod> -n orders-prod
kubectl logs <crashing-pod> -n orders-prod --previous
```

Confirm the crash is related to the release.

### 2. Roll back

```bash
cub unit list --space orders-prod
# Find the affected Units and their previous revisions

# For each affected Unit, apply the previous revision
cub unit apply orders-api --space orders-prod --revision 10  # whatever the previous revision was
cub unit apply orders-worker --space orders-prod --revision 8
```

This should bring back the previous version.

### 3. Verify

```bash
kubectl get pods -n orders-prod
```

Wait for pods to come back healthy.

### 4. Investigate

After things are stable, look at what changed in the release that caused the crash and fix it before re-deploying.
