# import-unit-granularity eval — baseline (no skill)

## Scenario

> I want to import the `payments-prod` namespace from my cluster into ConfigHub. It has 3 Deployments, 3 Services, 4 ConfigMaps, an HPA, a PDB, a ServiceAccount + Role + RoleBinding, a NetworkPolicy, and a ResourceQuota. How should I split this into Units?

## Response

For importing a namespace into ConfigHub, I'd recommend grouping related resources together:

### Option A: Two Units

1. **`payments-prod`** — all the workload resources: the 3 Deployments, 3 Services, 4 ConfigMaps, HPA, PDB
2. **`payments-prod-rbac`** — ServiceAccount, Role, RoleBinding, NetworkPolicy, ResourceQuota

This keeps things simple while separating the access control from the workloads.

### Option B: One Unit per Deployment

1. **`payments-api`** — Deployment + Service + ConfigMap
2. **`payments-worker`** — Deployment + Service + ConfigMap
3. **`payments-cron`** — Deployment + Service + ConfigMap
4. **`payments-shared`** — HPA, PDB, NetworkPolicy, ResourceQuota, ServiceAccount, Role, RoleBinding, remaining ConfigMaps

This gives more granularity per service.

### Importing

```bash
# Export the namespace
kubectl get all -n payments-prod -o yaml > payments-prod.yaml

# Import into ConfigHub
cub unit create payments-prod --space payments-prod
cub unit import payments-prod --space payments-prod
```

I'd go with Option A for simplicity unless you need per-service granularity.
