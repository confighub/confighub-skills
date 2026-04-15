---
name: target-bind
description: Use when the user wants to bind a Unit (or many Units) to a destination — a specific Kubernetes cluster+namespace, an ArgoCD Application, a Flux Kustomization, an OCI registry, a Tofu workspace. Phrases like "set up a target", "point this unit at my cluster", "bind these units to prod", "hook up Argo/Flux", "change the namespace this deploys to", "promote these to a different target". Creates or updates a Target with the right provider/toolchain and parameter JSON, attaches Units via cub unit set-target (or --where for bulk), and stops without applying — apply is cub-apply's job. Do not load for installing a worker (use worker-bootstrap first — Targets reference Workers), for running apply (use cub-apply), or for authoring the Unit's YAML (use config-as-data).
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub target create *) Bash(cub target update *) Bash(cub unit set-target *) Bash(cub unit update *)
---

# target-bind

Creates the binding between Units and destinations. Once bound, a Unit can be applied through `cub-apply`.

## What a Target is

A Target is a named, parameterized binding that tells ConfigHub *where* a Unit's configuration should land. It references a Worker to do the execution and carries provider-specific parameters (e.g., for `Kubernetes`: `KubeContext`, `KubeNamespace`, `WaitTimeout`).

Best practice: one Target per Kubernetes cluster per Space, since a Target corresponds to a cluster. A Target can live in a different Space than the Units that use it (e.g., a shared `targets` Space).

## When to use

- First time binding Units to a destination.
- Changing where a Unit deploys (different cluster, namespace, controller).
- Adding an additional delivery path (add an Argo Application target to Units that already have a direct-Kubernetes target).
- Copying a Target from one Space to another (`--from-target` / `--from-target-space`).

## Do not load for

- Installing the worker itself (`worker-bootstrap`).
- Running the actual apply (`cub-apply`).
- Authoring or editing the Unit's data (`config-as-data` / `cub-mutate`).

## Preflight gates

1. `cub context get` returns a user.
2. The intended Worker exists in a Space the user can read: `cub worker list --space <worker-space>`. If not, stop and route to `worker-bootstrap`.
3. For Kubernetes-provider targets: the `KubeContext` value matches a context name the worker's kubeconfig knows about. If unsure, `cub target access` can verify.
4. Confirm with the user: single-provider target or multi-provider (e.g., both `Kubernetes` direct apply AND `ArgoCDRenderer` output)?

## The loop

### 1. Establish the provider + toolchain

Pick based on delivery model:

| Delivery model | Provider | Toolchain |
|---|---|---|
| Apply K8s YAML directly to a cluster | `Kubernetes` | `Kubernetes/YAML` |
| Emit ArgoCD Applications for Argo to deploy | `ArgoCDRenderer` | `Kubernetes/YAML` |
| Emit Flux resources for Flux to deploy | `FluxRenderer` | `Kubernetes/YAML` |
| Publish OCI artifacts for Argo to pull | `ArgoCDOCI` | `Kubernetes/YAML` |
| Render ConfigMap bundles | `ConfigMapRenderer` | various AppConfig/* |

Multi-provider targets: repeat `--provider` and `--toolchain` in matching positional order.

### 2. Compose parameters

Parameters are a single JSON string passed positionally after the target slug. Known keys (Kubernetes provider):

- `KubeContext` — kubeconfig context name the worker should use.
- `KubeNamespace` — default namespace for namespaced resources.
- `WaitTimeout` — how long apply waits for the resource to settle (`2m0s`, `30s`).

Other providers define their own keys. Check `references/triggers-recipes.md` and the ConfigHub docs for per-provider parameter sets.

### 3. Create or update the Target

```bash
cub target create <target-slug> \
  '{"KubeContext":"kind-myapp-prod","KubeNamespace":"default","WaitTimeout":"2m0s"}' \
  <worker-slug> \
  --space <target-space> \
  --provider kubernetes \
  --toolchain Kubernetes/YAML
```

Or multi-provider:

```bash
cub target create <target-slug> \
  '{"KubeContext":"kind-myapp-prod","KubeNamespace":"default"}' \
  <worker-slug> \
  --space <target-space> \
  --provider kubernetes --toolchain Kubernetes/YAML \
  --provider argocdrenderer --toolchain Kubernetes/YAML \
  --option 'argoApplicationNamespace=argocd'
```

Targets are not versioned configuration data — **no `--change-desc`** on create/update.

### 4. Optional: scope Triggers to the Target

If you want specific Triggers to run when Units are applied *through* this Target (in addition to or instead of the Space's `TriggerFilterID`), attach a Trigger-filter to the Target:

```bash
cub target update <target-slug> --space <target-space> \
  --trigger-filter platform/standard-vets
```

### 5. Attach Units to the Target

Single Unit:

```bash
cub unit set-target <unit-slug> <target-slug> --space <app-space>
```

Bulk:

```bash
cub unit set-target --space <app-space> --where "Labels.App = 'myapp'" <target-slug>
```

Cross-Space target reference uses `<target-space>/<target-slug>` when the Target lives in a different Space.

Changing a Unit's target is not a configuration-data mutation — `cub unit set-target` doesn't take `--change-desc`. To record *why* the target changed, mutate the Unit's data in a deliberate step (e.g., update an annotation) with a proper `--change-desc`, or rely on the audit log.

### 6. Hand off

Target is created and Units are attached. Next step is almost always `cub-apply`.

## Tool boundary

- Mutations: `cub target create/update`, `cub unit set-target`, `cub unit update` (only when recording target-change rationale in data).
- Read-only: `cub target get/list`, `cub target access` (for kubecontext verification), `cub worker list/get/list-function` (to confirm the Worker supports the provider types this Target needs), `cub unit livestate/livedata` (to confirm a prior Target wasn't surprisingly live).
- Not allowed: bypassing Targets by running `kubectl apply` or `argocd app create` directly.

## Stop conditions

- No Worker exists for the provider types this Target needs. Stop and route to `worker-bootstrap`.
- `KubeContext` names a context the Worker's kubeconfig doesn't recognize. Fix before proceeding.
- User is pointing a prod Target at a dev cluster (context name disagreement). Flag loudly before proceeding.
- `cub unit set-target` across `--space "*"` without a narrow `--where`. Ask the user to confirm blast radius.

## Verify chain

1. `cub target get <target-slug> --space <target-space>` — provider/toolchain/parameters match intent; worker slug is set.
2. `cub target access <target-slug> --space <target-space>` — (for Kubernetes) temporary kubectl access confirms the Worker can reach the cluster.
3. `cub unit get <unit-slug> --space <app-space>` — `TargetID` points at the expected Target.
4. For bulk: `cub unit list --space <app-space> --where "TargetID IS NOT NULL"` count matches the `--where` selection count.

## Evidence

- `cub target get <target-slug> --space <target-space> --web` — Target page in the GUI.
- `cub unit get <unit-slug> --space <app-space> --web` — Unit page shows Target binding and apply state.

## References

- Target entity: `https://docs.confighub.com/background/entities/target/`
- Worker guide: `https://docs.confighub.com/guide/workers/`
- `references/cub-cli.md` — CLI conventions.
- `references/filters-and-queries.md` — the `TargetID IS NOT NULL` field pattern for verifying bulk bindings.
