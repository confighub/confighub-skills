---
name: import-from-cluster
description: 'Use when the user has live Kubernetes resources already running in a cluster — applied by `kubectl apply`, installed via a different workflow, or inherited from a previous operator — and wants to bring them under ConfigHub management without a GitOps tool or a Helm chart in hand. Phrases like "adopt these existing resources into ConfigHub", "I have stuff in the cluster, how do I get it into cub?", "reverse engineer my namespace into Units", "import from the cluster", "cub unit import", "we kubectl-apply''d everything and want to migrate", or "bring the running state into ConfigHub". Creates Units pre-bound to a cluster Target, runs `cub unit import` with `--where-resource` filters to pull live manifests, then hands off to `config-as-data` doctrine for ongoing management. Do not load for Helm-installed charts (use `import-from-helm`), ArgoCD Applications (use `import-from-argocd`), Flux HelmReleases / Kustomizations (use `import-from-flux`), or new YAML being authored from scratch (use `config-as-data`).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub unit set-target *) Bash(cub unit import *) Bash(cub worker get *) Bash(cub worker status *) Bash(cub worker list-function *) Bash(kubectl get *) Bash(kubectl describe *)
---

# import-from-cluster

Onboarding ramp for teams whose workloads are running in Kubernetes but are *not* managed by Helm, ArgoCD, or Flux — typically `kubectl apply`-driven setups, or configurations inherited from a previous operator. Pulls the current live state of selected resources into ConfigHub Units so that configuration-as-data management can start from what's actually running.

## Positioning: this is an onboarding tool

This skill targets users with existing cluster state and no DRY source of truth. The import captures **the live state as literal YAML** in ConfigHub Units. From that point forward:

- The Units, not the cluster, are the source of truth.
- Changes go through `cub-mutate` + `cub-apply`, not ad-hoc `kubectl apply`.
- The imported state includes everything the cluster API reports — default fields, defaulted limits, admission-webhook-added annotations. Use `--where-resource` filters to scope the import to what the user actually wants to own, not everything in a namespace.

If the user's cluster state came from a Helm chart, ArgoCD, or Flux — even if they're not sure — route them to those skills instead. `import-from-cluster` is the path of last resort; a chart/GitOps history is better preserved by the specialized import skills.

## When to use

- User has `kubectl apply`-driven workloads and wants to start managing them with ConfigHub.
- User inherited a cluster without a git-backed source of truth and wants to capture what's live.
- User has a mix: some workloads Helm-installed (handle with `import-from-helm`), some kubectl-applied (handle here).
- User asks "how do I get my existing cluster into ConfigHub?" without naming a GitOps tool.

## Do not load for

- Helm charts — use `import-from-helm`.
- ArgoCD Applications — use `import-from-argocd`.
- Flux HelmReleases / Kustomizations — use `import-from-flux`.
- Authoring new YAML — use `config-as-data`.
- Pulling a single Unit's current live state for drift diagnosis — use `cub unit refresh` + the forthcoming `drift-reconcile` skill.

## Preflight gates

1. `cub context get` returns a user.
2. `kubectl config current-context` points at the right cluster.
3. A **Worker with the `Kubernetes` bridge** is installed in that cluster (`cub worker list-function <worker>` advertises Kubernetes/YAML functions). If not, run `worker-bootstrap` first — the Worker is what performs the import.
4. A cluster **Target** exists (typically in a `workers-<cluster>` Space per `space-topology`) backed by that Worker. Confirm with `cub target list --space "*"`.
5. The target Space for the imported Units is decided. For onboarding, use a single landing Space (e.g., `<app>-imported-<env>`); split into env-Spaces later via `cub unit create --dest-space` if the layout from `space-topology` applies.
6. The user has decided the import scope — which namespaces, which kinds, whether to include cluster-scoped resources, whether to include custom resources, whether to include system namespaces. Never import everything blindly.

## Scoping — `--where-resource`

`cub unit import` takes a `--where-resource` expression that filters which cluster resources are pulled into the Unit. SQL-ish, similar to `--where-data`. Key toggles (Kubernetes-specific):

- `import.include_system` — default `false`. When `true`, pulls resources from system namespaces (`kube-system`, `kube-public`, `kube-node-lease`). Almost never what the user wants.
- `import.include_cluster` — default `false`. When `true`, pulls cluster-scoped resources (ClusterRole, ClusterRoleBinding, CRD, StorageClass, Namespace, etc.). Reach for this only when intentionally adopting cluster-wide state.
- `import.include_custom` — default `false`. When `true`, pulls custom resources (CRs). Usually needed when adopting an operator's state (e.g., cert-manager Certificates, Flux HelmReleases — though if those are Flux-managed you should be using `import-from-flux`).

Typical scopes:

```
# Everything user-land in one namespace.
--where-resource "metadata.namespace = 'payments-prod'"

# Workloads only (Deployments + Services + ConfigMaps) in a namespace.
--where-resource "metadata.namespace = 'payments-prod' AND kind IN ('Deployment','Service','ConfigMap')"

# Multiple namespaces, include the operator's custom resources.
--where-resource "metadata.namespace IN ('payments-prod','payments-staging') AND import.include_custom = true"

# Everything pinned to a specific image (audit use).
--where-resource "spec.template.spec.containers.*.image = 'ghcr.io/acme/payments:v1.2.3'"
```

## The loop

### 1. Pre-create the Unit(s) and bind to the cluster Target

`cub unit import` works on a Unit that already exists and has a Target bound. For onboarding, choose one of:

- **One Unit holds the whole slice.** Simplest for a scoped import ("everything in `payments-prod`"). Easy to review as a block; ongoing changes mutate one big Unit.
- **Unit per workload.** Import into separate Units per Deployment+Service bundle. Better long-term hygiene, more setup steps — see `import-unit-granularity`.
- **Unit per kind.** Deployments, Services, ConfigMaps each in their own Unit. Useful when change cadences differ.

For the first pass, default to one Unit per logical workload (`<app>` slug, contents = that app's resources):

```bash
cub unit create --space <app>-<env> <app>
cub unit set-target --space <app>-<env> <app> <workers-space>/<cluster-target>
```

The Unit starts empty; the target binding tells `cub unit import` which cluster to pull from.

### 2. Dry-run

```bash
cub unit import <app> --space <app>-<env> \
  --where-resource "metadata.namespace = '<ns>' AND metadata.labels.app = '<app>'" \
  --dry-run
```

Inspect the dry-run output. Confirm:

- The right resources are listed (no `kube-system` leakage, no unexpected CRs, no Service-of-loadBalancer-in-spec kinds of pulls).
- No resource you expect to own is missing.
- Matches aren't pulling admission-controller-added annotations you don't want (e.g., `kubectl.kubernetes.io/last-applied-configuration`). These can be cleaned up post-import via `cub-mutate` / a `cub function do strip-annotations`-style function.

Tighten the filter and re-dry-run until the set is right.

### 3. Import

```bash
cub unit import <app> --space <app>-<env> \
  --where-resource "metadata.namespace = '<ns>' AND metadata.labels.app = '<app>'" \
  --wait
```

The Worker pulls the matching resources, strips transient fields, and sets the Unit's Data to the resulting YAML. The Unit's LiveState also reflects what's currently running (same content, assuming nothing changed between the import start and finish).

### 4. Review the imported data

```bash
cub unit get <app> --space <app>-<env> --yaml
```

Scan for:

- **Defaults the cluster added** that the user may or may not want to own (e.g., `imagePullPolicy: Always`, `schedulerName: default-scheduler`, resources with defaulted limits). Decide per field: keep as-is, or strip via `cub function do`.
- **Controller-managed fields** that shouldn't be in Data (status-ish metadata, generated names, etc.). Clean with `strip-metadata` functions (see `references/functions-catalog.md`).
- **Secrets.** If Secrets came in, their `data` values are base64-encoded but unencrypted. Do not commit these — manage via an external SecretStore (see `references/yaml-patterns.md`).

### 5. Apply `config-as-data` discipline

From here, ongoing management follows `config-as-data`:

- **Never round-trip through the cluster.** Don't `kubectl edit`; don't `kubectl apply` directly. Changes go through `cub-mutate` + `cub-apply`.
- Attach the `platform/standard-vets` Filter to the Space (see `triggers-and-applygates`) so every future mutation runs schema and policy validation.
- If the initial import failed a `vet-schemas` gate (common — live resources often have admission-added fields that trip schema validation), use `cub-mutate` to clean the data, not a re-import.

### 6. Hand off to apply

Applying the Unit is now a no-op (the data matches live state). The first *meaningful* apply comes when the user makes their first ConfigHub-driven change:

```bash
cub unit apply <app> --space <app>-<env> --wait
```

From there, `verify-delivery` / `reconciliation-check` / `release-verify` take over.

## Tool boundary

- Allowed: `cub unit create/update/set-target/import/apply`, `cub worker get/list-function`, read-only `kubectl get/describe` for scoping confirmation.
- Not allowed: `kubectl apply/edit/delete` on the resources being adopted (breaks the single-source-of-truth assumption), importing into a Space without a Target (`cub unit import` will fail), importing resources still actively managed by Helm / ArgoCD / Flux (route to the right skill instead — importing them here creates a split-brain between that controller and ConfigHub).

## Stop conditions

- Worker isn't up or doesn't advertise `Kubernetes` bridge — stop, run `worker-bootstrap`.
- Target isn't bound to the Unit before `cub unit import` is called — cub will reject with "target must be attached". Pre-create and bind first.
- Dry-run shows resources the user doesn't intend to own. Tighten the filter; do not import and clean up afterward (noisy audit trail).
- User wants to import Helm / ArgoCD / Flux-managed resources — redirect to the specialized skill. These here would create split-brain ownership.
- User asks to include system namespaces for a "complete backup". Push back — that's outside ConfigHub's scope; use cluster backup tooling (Velero etc.).

## Verify chain

1. `cub unit list --space <app>-<env>` — the Unit exists.
2. `cub unit get <app> --space <app>-<env> --yaml` — Data contains the expected resources, stripped of transient fields.
3. `cub unit bridgestate <app> --space <app>-<env>` — target binding healthy.
4. `cub unit livestate <app> --space <app>-<env>` — LiveState matches Data (no drift at import time).
5. After attaching `platform/standard-vets`: `cub function do vet-schemas --space <app>-<env> --unit <app>` — passes, or produces a readable set of cleanup items for `cub-mutate`.

## Evidence

- `cub unit get <app> --space <app>-<env> --web` — the imported Unit with revision 1 showing the import source.
- `cub revision list <app> --space <app>-<env> --web` — provenance starting at import.

## References

- `cub unit import --help` — full `--where-resource` syntax and Kubernetes-specific toggles (authoritative over anything this skill says about flag names).
- `references/cub-cli.md` — CLI discipline; `--where-data` vs `--where-resource` scoping.
- `references/functions-catalog.md` — cleanup functions for post-import (strip-metadata, etc.).
- `references/yaml-patterns.md` — Secrets handling.
- Companion skills: `worker-bootstrap` (prereq), `space-topology` (Space layout), `target-bind` (pre-bind the Unit), `config-as-data` (post-import doctrine), `cub-mutate` (cleanup), `triggers-and-applygates` (add policy post-import), `import-unit-granularity` (one-Unit-per-what decision).
