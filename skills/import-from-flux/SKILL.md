---
name: import-from-flux
description: 'Use when the user has Flux running in a cluster and wants to bring their `HelmRelease` and `Kustomization` resources under ConfigHub management — phrases like "I already use Flux, how do I add ConfigHub?", "import my Flux HelmReleases / Kustomizations into ConfigHub", "gitops import with Flux", "we have 30 HelmReleases", "put ConfigHub in front of Flux", "keep Flux but add ConfigHub validation/approval". Runs `cub gitops discover` + `cub gitops import` against a cluster Target, produces dry/wet Unit pairs linked via MergeUnits, sets wet-Unit ProviderType to `FluxOCI` so that applying a wet Unit re-deploys through ConfigHub''s OCI registry via Flux, and suspends the imported HelmReleases / Kustomizations. Do not load for ArgoCD (use `import-from-argocd`), for direct Helm chart install without Flux (use `import-from-helm`), for plain live-resource adoption without a GitOps tool (use `import-from-cluster`), or for installing the Worker itself (use `worker-bootstrap` first — this skill assumes the Worker is already running with the three bridges).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub gitops discover *) Bash(cub gitops import *) Bash(cub gitops cleanup *) Bash(cub unit update *) Bash(cub worker get *) Bash(cub worker status *) Bash(cub worker list-function *) Bash(kubectl get *) Bash(kubectl describe *) Bash(flux get *) Bash(flux stats *) Bash(flux logs *)
---

# import-from-flux

Onboarding ramp for teams who already use Flux: insert ConfigHub into the middle of the GitOps pipeline so that every rendered manifest lands in ConfigHub for review, validation, policy, and approval *before* it's applied to the cluster. Flux continues to deploy — it just pulls from ConfigHub's OCI registry instead of from git directly.

## Positioning: this is an onboarding tool

The user already has Flux working. This skill does not move them off Flux; it adds ConfigHub as a stage between git and Flux. After the import:

- Every `HelmRelease` and `Kustomization` becomes a **dry Unit** (the CRD itself) + a **wet Unit** (the rendered manifests Flux would have deployed).
- Wet Units are what the user operates on going forward — validation, ApplyGates, approvals, cub-mutate customizations.
- The original in-cluster HelmRelease / Kustomization is kept, but **suspended** (`spec.suspend: true`) — it must not be manually resumed or deleted; ConfigHub now owns the rendered output.
- Applying the wet Unit creates a *new* HelmRelease / Kustomization that fetches an OCI image from ConfigHub's registry, which Flux then deploys.

Long term, as the team gets comfortable with configuration-as-data, they may graduate away from DRY Flux resources entirely toward Units authored directly in ConfigHub. This skill gets them to the point where Flux is still doing the in-cluster work but ConfigHub owns the review surface.

Published guide:

- DRY-format rendering model + `cub gitops` flow: `https://docs.confighub.com/guide/rendered-manifests/`

## When to use

- New-to-ConfigHub user running Flux (source-controller + helm-controller and/or kustomize-controller) and wanting to start governing their deployments.
- User asks "can I keep Flux?", "how do I add ConfigHub to my existing GitOps pipeline?", or "how does cub gitops discover find my HelmReleases?"
- User has N `HelmRelease` / `Kustomization` resources and wants them under ConfigHub in one pass.

## Do not load for

- ArgoCD instead of Flux — use `import-from-argocd`.
- Users with no GitOps tool installed — use `import-from-helm` / `import-from-cluster` / `config-as-data` depending on what they actually have.
- A `kustomization.yaml` file in git (the Kustomize CLI primitive, not a Flux `Kustomization` CRD) — use `import-from-kustomize`.
- Installing the Worker — `worker-bootstrap` handles that. This skill assumes the Worker is already running with the required bridges.

## Preflight gates

Before running `cub gitops discover`:

1. `cub context get` returns a user.
2. `kubectl config current-context` points at the cluster Flux is actually running in.
3. The Flux namespace (usually `flux-system`) has the controllers running, and the HelmRelease / Kustomization resources you expect are visible: `kubectl get helmreleases.helm.toolkit.fluxcd.io -A` and `kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A`.
4. A **Worker is installed in that cluster with the three bridges**: `-t kubernetes,fluxrenderer,fluxoci`. Verify `cub worker list-function --space <workers-space> <worker>` advertises all three provider-type function sets. If not, run `worker-bootstrap` first.
5. Unlike Argo, Flux is not called directly by the Worker — the `FluxRenderer` bridge renders HelmReleases / Kustomizations on its own. **No `FLUX_*` env vars are required on the Worker.** (Contrast with `import-from-argocd` which needs `ARGOCD_SERVER` / `ARGOCD_AUTH_TOKEN`.)
6. A cluster Target exists in some Space (typically a `workers-<cluster>` Space from `space-topology`) pointing at that Worker. Get its slug from `cub target list --space "*"`.
7. **Decide which Space the import lands in.** For an onboarding pass, a single `<app-or-cluster>-imported` Space is fine; post-import you can migrate workloads into per-env Spaces (see `space-topology`) with `cub unit create --dest-space`. Splitting by env up front is hard because `cub gitops import` creates all dry/wet Unit pairs in one Space.
8. Communicate the ownership transfer to teammates: once this runs, imported HelmReleases and Kustomizations will be suspended; anyone who `flux resume`s them will confuse the pipeline.

## The loop

### 1. Discover

```bash
cub gitops discover --space <import-space> <target> \
  [--where-resource "metadata.namespace = 'flux-system'"]
```

- `<target>` is the Space-qualified slug if cross-Space (`workers-<cluster>/<target>`) or unqualified if the Target is in `<import-space>`.
- `--where-resource` filters which Flux CRDs to consider. Scope to `flux-system` (or wherever the user runs Flux) by default; narrow further by label (`metadata.labels.team = 'payments'`) to do a phased import.

The output lists the `HelmRelease` and `Kustomization` resources it would import. Review with the user before running `import`.

### 2. Import

```bash
cub gitops import --space <import-space> <target> [--where-resource "..."] --wait
```

This creates, for each discovered HelmRelease / Kustomization:

- A **dry Unit** holding the CRD itself, with a Target supporting `FluxRenderer`.
- A **wet Unit** to receive the rendered manifests, linked to the dry Unit via `MergeUnits` + `UseLiveState: true`.
- A **CRD wet Unit**, if the chart produces CRDs, split off from the main wet Unit.
- Sets each wet/CRD Unit's `ProviderType` to `FluxOCI` — apply goes through ConfigHub's OCI registry, not direct.
- Suspends the imported HelmRelease / Kustomization resource in the cluster (`spec.suspend: true`).

Verify:

```bash
cub unit list --space <import-space>                    # dry + wet + crd Units all present
cub unit tree --space <import-space>                    # the MergeUnits links
kubectl get helmreleases.helm.toolkit.fluxcd.io -A \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.suspend}{"\n"}{end}'
# imported HelmReleases should show suspend=true
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.suspend}{"\n"}{end}'
```

### 3. Render — apply the dry Units

Applying a dry Unit invokes the `FluxRenderer` bridge: the Worker renders the HelmRelease / Kustomization (pulls the chart or sources the Kustomize tree) and returns the result as LiveState. The linked wet Unit receives that as Data.

```bash
cub unit apply <dry-unit> --space <import-space> --wait
cub unit get <wet-unit> --space <import-space> --yaml     # rendered manifests are now the wet Unit's Data
```

Do this for every dry Unit (or bulk via `cub unit apply --where`). After this round, every wet Unit contains the rendered YAML.

### 4. Review / validate / customize the wet Units

From here, every other skill applies to the wet Units:

- `config-as-data` doctrine — wet Units are literal YAML, customize via `cub-mutate` functions, never re-author by hand.
- `triggers-and-applygates` — attach `platform/standard-vets` to `<import-space>` to validate every wet Unit on mutation.
- `cub-mutate` — change images, replicas, env vars through semantic functions with `--change-desc`.
- `cub-apply` — deploy the wet Unit (the `FluxOCI` bridge creates a new HelmRelease / Kustomization that pulls from ConfigHub's OCI registry).
- `verify-delivery` / `reconciliation-check` / `release-verify` — confirm the rollout.

Modifications previously made to a wet Unit are preserved across re-renders (from a later `cub unit apply <dry>`), with the same merge semantics as Unit upgrades.

### 5. Ongoing updates after a git change

When DRY config in git changes (Helm values, chart version, kustomization):

```bash
# 1. Re-apply the dry Unit to re-render.
cub unit apply <dry-unit> --space <import-space> --wait

# 2. Review the diff on the linked wet Unit — your customizations are preserved.
cub unit diff <wet-unit> --space <import-space>

# 3. Approve and apply the updated wet Unit.
cub unit apply <wet-unit> --space <import-space> --wait
```

## Reorganizing into per-env Spaces (optional, post-import)

`cub gitops import` creates everything in one Space. To align with `space-topology` (one Space per env-deployment-boundary):

```bash
# Move a wet Unit into its env-Space; keeps the MergeUnits link by UUID.
cub unit create --dest-space <app>-<env> --space <import-space> --where "Slug = '<wet-unit>'"
```

Dry Units typically stay in the import Space or move into a `<app>-renderers` Space shared across envs, since they're about "what to render" not "where to deploy". Confirm the dry/wet link survives the move (`cub unit tree`) before cleaning up.

## Tool boundary

- Allowed: `cub gitops discover/import/cleanup`, `cub unit apply/update/get/list/diff/tree/bridgestate/livestate`, `cub worker get/status/list-function`, read-only `kubectl get/describe`, read-only `flux get/stats/logs`.
- Not allowed: `flux resume` on an imported HelmRelease / Kustomization (ConfigHub now owns it; resuming creates a split-brain pipeline), `flux reconcile` as a mutation on imported resources, `kubectl delete` on imported CRDs.

## Stop conditions

- Worker isn't up or doesn't advertise all three bridges — stop, run `worker-bootstrap` with `-t kubernetes,fluxrenderer,fluxoci`.
- Flux controllers aren't actually running in the cluster (discover returns empty because there's nothing to discover). Stop and confirm the user's Flux installation.
- User can't confirm nobody else is resuming suspended HelmReleases / Kustomizations manually — stop until the team is aligned on the ownership transfer.
- `cub gitops import` partially fails midway — do not re-run blind. Inspect `cub unit list --space <import-space>`, identify which Units were created, and pick up from there (or `cub gitops cleanup` to reset the discover unit and start over).

## Verify chain

1. `cub worker list-function --space <workers-space> <worker>` — includes `FluxRenderer` + `FluxOCI` + `Kubernetes` function sets.
2. `cub unit list --space <import-space>` — dry / wet / crd Units present for each imported HelmRelease / Kustomization.
3. `cub unit tree --space <import-space>` — shows the MergeUnits link back to the dry Unit.
4. `kubectl get helmrelease <imported-hr> -n flux-system -o jsonpath='{.spec.suspend}'` → `true`. Same for Kustomization.
5. After first `cub unit apply <dry>`: `cub unit get <wet> --space <import-space> --yaml` — contains rendered Deployment/Service/etc.
6. After first `cub unit apply <wet>`: `kubectl get helmreleases,kustomizations -A` — a *new* resource exists that references ConfigHub's OCI registry URL.

## Evidence

- `cub unit get <wet> --space <import-space> --web` — the wet Unit's rendered data + Revision history.
- `cub unit tree --space <import-space> --web` — dry/wet link in the GUI.
- Flux UI or `flux get helmreleases` output — confirms Flux is now pulling from ConfigHub's OCI registry.

## References

- `https://docs.confighub.com/guide/rendered-manifests/` — unit-level model + `cub gitops` flow.
- `references/cub-cli.md` — CLI discipline.
- Companion skills: `worker-bootstrap` (prereq), `space-topology` (Space layout), `target-bind` (Worker/Target), `config-as-data` (wet-Unit doctrine), `triggers-and-applygates` (adding policy post-import), `cub-apply` / `verify-delivery` / `reconciliation-check` / `release-verify` (runtime), `import-from-argocd` (ArgoCD equivalent).
