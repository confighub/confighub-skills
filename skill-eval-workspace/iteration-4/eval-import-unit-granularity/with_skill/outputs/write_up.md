# import-unit-granularity eval — with-skill

## Scenario

> I want to import the `payments-prod` namespace from my cluster into ConfigHub. It has 3 Deployments, 3 Services, 4 ConfigMaps, an HPA, a PDB, a ServiceAccount + Role + RoleBinding, a NetworkPolicy, and a ResourceQuota. How should I split this into Units?

## Preflight

Source: live cluster (cluster import path). No generator — so we apply the hand-rolled / cluster-import splitting rules, not a generator's default.

Need to understand the workloads before recommending:

```
$ kubectl get deploy -n payments-prod
NAME              READY   UP-TO-DATE
payments-api      3/3     3
payments-worker   2/2     2
payments-cron     1/1     1
```

Three distinct workloads — different replica counts, likely different change cadences.

## Recommended split

Walk the four axes: ownership, references, lifecycle, blast radius.

| Unit slug | Resources | Rationale |
|---|---|---|
| `payments-prod-namespace` | `Namespace` (cluster-scoped) | Platform-team owned. Changes almost never. Different lifecycle from anything inside the namespace. Needs `import.include_cluster = true`. |
| `payments-prod-policy` | `NetworkPolicy`, `ServiceAccount`, `Role`, `RoleBinding`, `ResourceQuota` | Namespace-scoped policy. Platform/SRE owned. Changes with policy updates, not app releases. |
| `payments-api` | `Deployment(payments-api)`, `Service(payments-api)`, relevant `ConfigMap`s, `HPA`, `PDB` | App-team owned. Day-to-day change cadence. HPA/PDB are tightly coupled to the deployment they scale/protect. |
| `payments-worker` | `Deployment(payments-worker)`, `Service(payments-worker)`, relevant `ConfigMap`s | App-team owned. Different replica count and scaling profile from the API. |
| `payments-cron` | `Deployment(payments-cron)`, `Service(payments-cron)`, relevant `ConfigMap`s | App-team owned. Likely batch-oriented, different change cadence from real-time API. |

**5 Units total.** No CRDs mentioned, so no CRD Unit needed.

### Why not fewer

- **One mega-Unit for everything**: changes to a ConfigMap for the cron job would create a revision touching all three workloads. Rollback of one workload pulls along unrelated changes. Different ownership (platform policy vs. app workloads) collapses.
- **Namespace + policy in with the workloads**: different owners, different change cadence. Policy changes monthly; deployments change daily.

### Why not more (one per resource)

Anti-pattern per the skill. "Only split that far when a specific resource truly has its own lifecycle." A Deployment's Service and ConfigMap are tightly cross-referenced — splitting them apart means you can't roll back the Deployment without separately rolling back its ConfigMap, and you get twice the revisions for a single logical change.

### Execution plan (hand off to import-from-cluster)

```bash
SPACE=payments-prod
TARGET=workers-prod/<cluster-target>

# Create and bind Units
for u in payments-prod-namespace payments-prod-policy payments-api payments-worker payments-cron; do
  cub unit create --space "$SPACE" "$u"
  cub unit set-target --space "$SPACE" "$u" "$TARGET"
done

# Import namespace (cluster-scoped)
cub unit import --space "$SPACE" payments-prod-namespace \
  --where-resource "kind = 'Namespace' AND metadata.name = 'payments-prod' AND import.include_cluster = true" \
  --dry-run

# Import policy resources
cub unit import --space "$SPACE" payments-prod-policy \
  --where-resource "metadata.namespace = 'payments-prod' AND kind IN ('NetworkPolicy','ServiceAccount','Role','RoleBinding','ResourceQuota')" \
  --dry-run

# Import workloads (scoped by labels or name)
cub unit import --space "$SPACE" payments-api \
  --where-resource "metadata.namespace = 'payments-prod' AND kind IN ('Deployment','Service','ConfigMap','HorizontalPodAutoscaler','PodDisruptionBudget') AND metadata.labels.app = 'payments-api'" \
  --dry-run

# ... similar for payments-worker and payments-cron
```

Dry-run each, confirm the resource set, then re-run without `--dry-run`.

## Tool boundary

This skill produces the split recommendation. Actual `cub unit create / import` belongs to `import-from-cluster`. Space layout belongs to `space-topology`.
