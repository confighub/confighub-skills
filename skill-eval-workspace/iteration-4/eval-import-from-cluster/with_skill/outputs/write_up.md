# import-from-cluster eval — with-skill

## Scenario

> We've been kubectl-applying everything in our `payments` namespace for two years. There's no Helm chart, no ArgoCD — just a bunch of YAML files in a git repo that someone applies. How do I bring this under ConfigHub management?

## Preflight

```
$ cub context get
User: <authenticated>
```

```
$ kubectl config current-context
kind-confighub-eval
```

```
$ cub worker get eval-worker --space skill-examples
Condition: Ready
ConfigType[0]: Kubernetes / Kubernetes/YAML / Kubernetes/YAML
```

Worker is up with Kubernetes bridge. Target exists.

## Approach

This is the classic `import-from-cluster` case — live resources with no generator behind them. We'll:

1. Inventory what's running
2. Decide the split per `import-unit-granularity`
3. Pre-create Units and bind to the cluster Target
4. Dry-run the import per Unit with scoped `--where-resource`
5. Import
6. Review and clean up
7. Hand off to config-as-data discipline

### Step 1 — Inventory

```bash
kubectl get all -n payments --show-labels
kubectl get networkpolicy,serviceaccount,role,rolebinding,resourcequota -n payments
```

This tells us what's in the namespace and how it's labeled, which informs the split.

### Step 2 — Decide the split

Per `import-unit-granularity`, for hand-rolled cluster imports split by ownership / references / lifecycle / blast radius:

| Unit slug | Resources | Rationale |
|---|---|---|
| `payments-namespace` | Namespace (cluster-scoped) | Platform-owned, changes almost never. Needs `import.include_cluster = true`. |
| `payments-policy` | NetworkPolicy, ServiceAccount, Role, RoleBinding, ResourceQuota | Namespace-scoped policy. Platform/SRE owned. |
| `payments-api` | Deployment(payments-api) + Service + ConfigMaps for api | App-team owned. Day-to-day change cadence. |
| `payments-worker` | Deployment(payments-worker) + Service + ConfigMaps for worker | Different scaling profile. |

### Step 3 — Pre-create and bind

```bash
SPACE=payments-prod
TARGET=workers-prod/k8s-cluster

for u in payments-namespace payments-policy payments-api payments-worker; do
  cub unit create --space "$SPACE" "$u"
  cub unit set-target --space "$SPACE" "$u" "$TARGET"
done
```

Units must exist and have a Target before `cub unit import` can pull.

### Step 4 — Dry-run each

```bash
# Namespace (cluster-scoped)
cub unit import payments-namespace --space "$SPACE" \
  --where-resource "kind = 'Namespace' AND metadata.name = 'payments' AND import.include_cluster = true" \
  --dry-run

# Policy
cub unit import payments-policy --space "$SPACE" \
  --where-resource "metadata.namespace = 'payments' AND kind IN ('NetworkPolicy','ServiceAccount','Role','RoleBinding','ResourceQuota')" \
  --dry-run

# API workload
cub unit import payments-api --space "$SPACE" \
  --where-resource "metadata.namespace = 'payments' AND metadata.labels.app = 'payments-api' AND kind IN ('Deployment','Service','ConfigMap','HorizontalPodAutoscaler','PodDisruptionBudget')" \
  --dry-run

# Worker workload
cub unit import payments-worker --space "$SPACE" \
  --where-resource "metadata.namespace = 'payments' AND metadata.labels.app = 'payments-worker' AND kind IN ('Deployment','Service','ConfigMap')" \
  --dry-run
```

Inspect each dry-run. Confirm the resource set matches intent — no kube-system leakage, no unexpected CRs, no admission-controller-added junk.

### Step 5 — Import (drop --dry-run)

Re-run the same commands without `--dry-run` and with `--wait`:

```bash
cub unit import payments-namespace --space "$SPACE" \
  --where-resource "kind = 'Namespace' AND metadata.name = 'payments' AND import.include_cluster = true" \
  --wait
```

(Repeat for each Unit.)

### Step 6 — Review

```bash
cub unit get payments-api --space "$SPACE" --yaml
```

Scan for:
- Cluster-added defaults you may not want to own (imagePullPolicy: Always, schedulerName, etc.)
- `kubectl.kubernetes.io/last-applied-configuration` annotation — clean with `cub function do` strip-annotations
- Secrets — if present, data is base64 but unencrypted. Manage via external SecretStore.

### Step 7 — Establish config-as-data discipline

From here:
- **Never round-trip through the cluster.** Changes go through `cub-mutate` + `cub-apply`.
- Attach `platform/standard-vets` Filter to the Space for schema and policy validation.
- First meaningful apply comes when you make your first ConfigHub-driven change.

## Tool boundary

- Allowed: `cub unit create/set-target/import`, `kubectl get/describe` for scoping.
- Not allowed: `kubectl apply/edit/delete` on the adopted resources (breaks single-source-of-truth).
- If any of these resources turn out to be Helm-installed or Flux-managed, redirect to the specialized import skill.

## Evidence

- `cub unit get payments-api --space payments-prod --web` — imported Unit in GUI.
- `cub unit livestate payments-api --space payments-prod` — LiveState matches Data (no drift at import time).
