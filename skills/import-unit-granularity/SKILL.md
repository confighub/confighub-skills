---
name: import-unit-granularity
description: 'Use when the user is deciding how to slice Kubernetes YAML into ConfigHub Units — phrases like "one Unit or many?", "how should I split these resources?", "should Deployment and Service be one Unit?", "where do CRDs go?", "Unit per resource or per bundle?", "should my namespace and its RBAC be together?", "per-app or per-namespace?". Applies a short set of rules (CRDs separate; rendered-from-generator stays bundled; otherwise split by ownership / references / lifecycle / blast radius) and routes the user to the right import skill with a concrete Unit-slug plan. Do not load for authoring new YAML (use `config-as-data`), for executing an import the user has already scoped (use the matching `import-from-*` skill), or when the split is already forced by the tool in use (`cub helm install` and `cub gitops import` split CRDs automatically — just run them).'
phase: decide
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(kubectl get *) Bash(kubectl describe *)
---

# import-unit-granularity

A decision helper for one question: **how many Units, and what goes in each?** Produces a concrete split — Unit slugs + the `--where-resource` predicate (or equivalent) for each — and hands off to the import skill that will execute it.

## When to use

- User has a YAML bundle, a rendered chart, a namespace full of running resources, or a pile of overlays, and is asking "should this be one Unit or several?"
- User has already picked an import path (`import-from-helm` / `-kustomize` / `-argocd` / `-flux` / `-cluster`) but is unsure how many Units it should produce.
- User is mid-import and wants to validate the split before running the command.

## Do not load for

- Authoring new YAML from scratch — use `config-as-data`.
- Running the actual import — hand off to the matching `import-from-*` skill after the decision is made here.
- Decisions about *where* the Units go (which Space) — that's `space-topology`.
- Cases where the tool already decided for the user: `cub helm install` always produces `<release>` + `<release>-crds`; `cub gitops import` always produces dry + wet + crds with the right link predicates. Don't re-litigate their defaults.

## Rules, in priority order

### 1. CRDs always in their own Unit

Independent of everything else, CustomResourceDefinitions go in a Unit separate from anything that uses them. This is not negotiable:

- CRDs must be applied and established before the custom resources that reference them (`kubectl wait --for=condition=established`). Separate Units let you sequence apply cleanly without a shell script around one big Unit.
- CRDs have different lifecycle and blast radius than workloads: deleting a CRD cascades to every CR; deleting a Deployment doesn't.
- `cub helm install` and `cub gitops import` already split CRDs (`<release>-crds` / `-crds` wet Unit linked with `where-resource "kind = 'CustomResourceDefinition'"`). Hand-rolled imports should match.

Slug convention: `<app>-crds`.

### 2. Rendered from a generator → keep as one bundle (minus CRDs)

If the source is Helm, Kustomize, Argo, or Flux, the generator already reasoned about what belongs together. Don't re-split unless there's a concrete reason. One workload-Unit + one CRDs-Unit is the default.

Reasons that *would* justify further splitting from a generator:

- The chart ships with its own cluster-scoped resources (ClusterRole, StorageClass, PriorityClass) mixed with namespaced workloads and you need to grant different permissions — split cluster-scoped into its own Unit.
- The chart bundles an operator *and* instances of the operator's CRs — split the CRs out so they have a different change cadence.
- The user needs ApplyGates or approval policies that differ across parts of the chart.

Otherwise, one Unit. Run `cub helm install` or `cub gitops import` and stop.

### 3. Hand-rolled or `import-from-cluster` → split by Kubernetes best practices

When there's no generator to defer to, split by how the resources actually want to be operated. Axes, in order:

- **Ownership.** Who edits this? Platform team vs. app team. Different owners ⇒ different Units.
- **References.** Does resource A not work without resource B? They stay together.
- **Lifecycle.** Does this change daily vs. monthly vs. yearly? Different cadences ⇒ different Units, so low-churn config doesn't generate revision noise.
- **Blast radius.** If I break this, what else breaks? Contain the blast in a single Unit.

## Recommended groupings (for hand-rolled / cluster imports)

| Unit slug | Contents | Rationale |
|---|---|---|
| `<ns>-namespace` | The `Namespace` resource itself | Cluster-scoped; platform-team owned; changes almost never; different lifecycle from anything inside the namespace. |
| `<ns>-policy` | `NetworkPolicy`, `ServiceAccount`, `Role`, `RoleBinding`, per-namespace `ResourceQuota`, `LimitRange` | Namespace-scoped policy; usually platform- or platform-plus-app co-owned; changes with policy updates, not app releases. |
| `<app>` | `Deployment` (or `StatefulSet` / `DaemonSet`), `Service`, `ConfigMap`, `HorizontalPodAutoscaler`, `PodDisruptionBudget`, `ServiceMonitor` | App-team owned; day-to-day change cadence; tightly cross-referenced. Blast radius is the workload. |
| `<app>-crds` | Any CRDs the app ships | Lifecycle + apply-order distinct from the workload. |
| `<infra>-cluster` | `ClusterRole`, `ClusterRoleBinding`, `StorageClass`, `PriorityClass`, cluster-scoped `CRDs` | Cluster-wide blast radius; typically platform-team owned. |
| `<operator>-crs` | Custom resources (`Certificate`, `HelmRelease`, etc.) | Referenced resources; change independently of the operator itself. |

Multi-workload apps: one `<app>` Unit per workload (`<app>-api`, `<app>-worker`), not one mega-Unit with every workload — they usually have different replica counts, different canary policies, and different incident ownership.

## Anti-patterns

- **One Unit per resource by default.** Only split that far when a specific resource truly has its own lifecycle (e.g., a ConfigMap rotated by a separate process). Otherwise it's noise: twice the revisions, twice the ApplyGates, cross-referenced resources that must be applied in order but live in different Units.
- **Everything in one Unit (including CRDs).** Apply-order breaks (`CRD` not established before `CR`), rollback of a workload accidentally takes down its CRDs.
- **Cluster-scoped mixed with namespaced.** Different permissions to apply; different ownership; different blast radius. Splits cleanly along the line cub already draws for `import.include_cluster`.
- **Splitting purely by `kind`.** Doesn't map to ownership or lifecycle; produces "all ConfigMaps" or "all Services" Units that cut across unrelated apps.

## The splitting trick (for `cub unit import` and hand rolls)

To execute a split with `cub unit import`: pre-create each Unit, bind it to the same cluster Target, then call `cub unit import` per Unit with a scoped `--where-resource`. This is exactly what `cub gitops import` does internally when it splits CRDs off the wet Unit.

Example for splitting a namespace's state into three Units:

```bash
SPACE=<app>-<env>
TARGET=<workers-space>/<cluster-target>
NS=<namespace>

# Shell
for u in <ns>-namespace <ns>-policy <app> <app>-crds; do
  cub unit create --space "$SPACE" "$u"
  cub unit set-target --space "$SPACE" "$u" "$TARGET"
done

# CRDs (cluster-scoped; needs include_cluster)
cub unit import --space "$SPACE" <app>-crds \
  --where-resource "kind = 'CustomResourceDefinition' AND import.include_cluster = true AND metadata.labels.app = '<app>'" \
  --dry-run

# Namespace (cluster-scoped; platform-team owned).
cub unit import --space "$SPACE" <ns>-namespace \
  --where-resource "kind = 'Namespace' AND metadata.name = '$NS' AND import.include_cluster = true" \
  --dry-run

# Namespace-scoped policy (NetworkPolicy, RBAC, ResourceQuota, LimitRange).
# `--where-resource` supports AND only — if you'd want Namespace + policy in a
# single Unit, do two imports into separate Units rather than trying to OR.
cub unit import --space "$SPACE" <ns>-policy \
  --where-resource "metadata.namespace = '$NS' AND kind IN ('NetworkPolicy','ServiceAccount','Role','RoleBinding','ResourceQuota','LimitRange')" \
  --dry-run

# Workload
cub unit import --space "$SPACE" <app> \
  --where-resource "metadata.namespace = '$NS' AND kind IN ('Deployment','StatefulSet','DaemonSet','Service','ConfigMap','HorizontalPodAutoscaler','PodDisruptionBudget','ServiceMonitor') AND metadata.labels.app = '<app>'" \
  --dry-run
```

Dry-run each, confirm the resource set, then re-run without `--dry-run`. Same pattern for Helm-rendered bundles split by hand: store the output of `helm template` in files, then `cub unit create` each from its scoped file. (Though unless you have a specific reason, `cub helm install` already does CRD splitting correctly — prefer it.)

## The decision flow

1. What's the source? → Helm / Kustomize / ArgoCD / Flux / live cluster / hand-rolled YAML.
2. If a generator, default to `<release>` + `<release>-crds` (Helm) or dry/wet/crds (Argo/Flux) per the matching import skill. Only split further if ownership / lifecycle / blast radius diverge within the render.
3. If hand-rolled or cluster-imported: walk the four axes (ownership, references, lifecycle, blast radius). Map to the recommended groupings above. Produce slugs and `--where-resource` predicates.
4. Hand off to the right `import-from-*` skill for execution.

## Preflight (for making a recommendation)

1. User has told you the source (Helm / Kustomize / ArgoCD / Flux / cluster / hand-rolled). If not, ask once.
2. For cluster / hand-rolled cases: `kubectl get -n <ns> -o yaml > /tmp/inventory.yaml` or a similar inventory is available for reference — you need to see what's actually there before prescribing a split.
3. User has picked a Space layout per `space-topology` (or will as part of this). Units don't exist in a vacuum.

## Tool boundary

Read-only and decision-making only. `kubectl get`, `cub ... list/get` to inspect inventory. No `cub unit create / import / update` — hand that off to the specialized import skill after the decision is made.

## Stop conditions

- User hasn't disclosed the source. Ask; don't guess.
- User is importing generator-rendered output and wants a per-resource split without a stated reason. Push back: match the generator's bundle + CRD split.
- User is hand-rolling and insists on one mega-Unit including CRDs. Push back: CRD separation is non-negotiable for apply-order correctness.

## Verify chain

There's nothing to apply here; the skill's output is a split proposal. The user (or the import skill called next) verifies by running `--dry-run` and reviewing the per-Unit resource set before importing.

## Evidence

- `kubectl get -n <ns> --show-labels` — source inventory the recommendation was based on.
- The matching import skill's Evidence section once execution starts.

## References

- `references/cub-cli.md` — `--where-resource` / `--where-data` scoping mechanics (including `ConfigHub.ResourceType`, `ConfigHub.ResourceName`, `import.include_system`, `import.include_cluster`, `import.include_custom`).
- `https://docs.confighub.com/markdown/guide/rendered-manifests.md` — the `cub gitops import` splitting flow this skill mirrors.
- `https://docs.confighub.com/markdown/guide/helm-charts.md` — `cub helm install` release + crds default.
- Companion skills: `space-topology` (where the Units go), `import-from-helm`, `import-from-kustomize`, `import-from-argocd`, `import-from-flux`, `import-from-cluster`, `config-as-data` (post-import doctrine).
