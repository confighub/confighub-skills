---
name: worker-bootstrap
description: 'Use when the user needs to install a ConfigHub bridge worker in a Kubernetes cluster so that Units can apply, refresh, or import against real infrastructure — phrases like "set up a worker", "install the ConfigHub worker", "connect ConfigHub to my cluster", "make ConfigHub able to deploy", "add an Argo renderer worker", "add a Flux renderer worker", "I need a worker for OCI publishing", or "the worker isn''t running / is crashing". Creates the worker entity, generates the Kubernetes manifest with the right provider types, installs it (or exports it for review / storage as a ConfigHub Unit), verifies it''s running, and stops before you try to deploy anything through a worker that isn''t healthy. Do not load for creating Targets (use target-bind — Targets reference Workers but are a separate concern) or for day-2 application apply (use cub-apply once the worker is up).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub worker logs *) Bash(cub worker status *) Bash(cub worker create *) Bash(cub worker update *) Bash(cub worker install *) Bash(cub worker upgrade *) Bash(cub worker get-envs *) Bash(cub worker get-secret *) Bash(cub unit create *) Bash(cub unit update *) Bash(kubectl get *) Bash(kubectl describe *) Bash(kubectl logs *)
---

# worker-bootstrap

Gets a bridge worker running in a cluster so ConfigHub can execute target operations against it.

## Why this matters

A Worker is the runtime that actually *does* things — apply a Unit, refresh live state, import existing resources. Without a healthy worker for the right provider type, Targets can't function. Getting the worker set up correctly is a prerequisite to everything in `target-bind` / `cub-apply` / `verify-apply`.

## When to use

- First-time setup: no workers exist yet in this Space or org.
- Adding a renderer worker: ArgoCD, Flux, ArgoCD-via-OCI.
- Adding a provider worker: `Kubernetes` (applies directly), `OpenTofu/AWS`, `ConfigHub`, `ConfigMapRenderer`.
- Diagnosing a crashing or missing worker (`cub worker status`, `cub worker logs`, pod-level `kubectl describe`).
- Upgrading a worker to match the current ConfigHub server version (`cub worker upgrade`).

## Do not load for

- Creating Targets — `target-bind` handles that.
- Applying Units — `cub-apply` handles that.
- Authoring the worker's Kubernetes manifest by hand — `cub worker install` generates it with the right defaults; don't author a competing one.

## Preflight gates

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. `kubectl config current-context` points at the cluster where the worker should run, and the user has permission to create Deployments / ServiceAccounts / RBAC in the worker namespace (defaults to `confighub`).
3. Confirm with the user: which provider types does this worker need? Pick from:
   - `Kubernetes` — applies plain K8s YAML directly to the cluster.
   - `ArgoCDRenderer` — emits Argo Applications; Argo deploys.
   - `FluxRenderer` — emits Flux resources; Flux deploys.
   - `ArgoCDOCI` — packages config as OCI artifacts for Argo to pull.
   - `ConfigMapRenderer`, `ConfigHub`, `OpenTofu/AWS` — others.
   Multiple types can live on one worker (`--provider-types kubernetes,argocdrenderer`).

## The loop

### 1. Create the worker entity

```bash
cub worker create --space <space> <worker-slug>
```

No `--change-desc` on worker create — workers aren't versioned configuration data.

### 2. Install the worker into the cluster

Two paths. Pick based on how you want to govern the worker itself.

**Direct install** (simplest — bootstrap case, first worker):

```bash
cub worker install <worker-slug> \
  --space <space> \
  --provider-types kubernetes \
  --namespace confighub \
  --export --include-secret \
  | kubectl apply -f -
```

`cub worker install` only *generates* the Kubernetes manifest (Deployment, ServiceAccount, RBAC, Secret with worker credentials) — it does not apply it. Pipe `--export` through `kubectl apply -f -` using the user's current kubeconfig to actually install. `--include-secret` inlines the credential Secret so the worker can authenticate; for a production bootstrap, prefer `--export-secret-only` and store the credential in an external SecretStore (see the managed-install path below). Image defaults to the pinned `ghcr.io/confighubai/confighub-worker` release.

After applying, wait for the worker to become Ready:

```bash
kubectl -n confighub rollout status deploy/<worker-slug>
cub worker get --space <space> <worker-slug>   # condition: Ready
```

**Managed install** (preferred once a bootstrap worker exists):

```bash
cub worker install <worker-slug> \
  --space <space> \
  --provider-types kubernetes \
  --namespace confighub \
  --export > /tmp/worker-manifest.yaml

cub unit create --space <space> <worker-slug>-manifest /tmp/worker-manifest.yaml \
  --change-desc "Store worker manifest as a ConfigHub-managed Unit.

User prompt: <verbatim>
Clarifications: <condensed>" \
  -o mutations

# Apply via an existing worker through cub-apply in a subsequent step.
```

The `--export` form produces the same manifest without applying it, so you can store it as a Unit and manage it under ConfigHub like any other workload.

The Secret resource is redacted by default in the manifest. Use `--include-secret` when you genuinely need it in the exported Unit (then protect it via external secret storage, not Unit data — see `references/yaml-patterns.md`), or use `--export-secret-only` plus an external SecretStore to keep credentials out of the Unit body.

### 3. Verify the worker is healthy

```bash
cub worker get --space <space> <worker-slug>
cub worker status --space <space> <worker-slug>
cub worker list-function --space <space> <worker-slug>
```

`list-function` confirms which functions the worker can run (varies by provider type). If it's empty or missing expected functions, the worker is likely still starting or misconfigured.

Pod-level fallback for diagnosing startup failures:

```bash
kubectl -n confighub get pods -l app=<worker-slug>
kubectl -n confighub describe pod <worker-pod>
cub worker logs --space <space> <worker-slug>
```

### 4. Hand off

Worker is running and advertising functions. Next steps depend on user intent:

- Need to bind a Unit to a destination → `target-bind`.
- Need to actually apply a Unit → `cub-apply` (requires a Target, so usually goes through `target-bind` first).
- Upgrading after a server update → `cub worker upgrade <worker-slug>`.

## Tool boundary

- Mutations: `cub worker create/install/upgrade/update`, `cub unit create/update` for the managed-install variant.
- Read-only: `cub worker get/list/logs/status/list-function/list-status`, `cub worker get-envs/get-secret` (credential read), `kubectl get/describe/logs` on the worker namespace.
- Not allowed: `kubectl apply` / `edit` / `delete` against the worker's resources. `cub worker install` handles the direct-install case; everything else flows through a Unit.

## Stop conditions

- User isn't pointing at the intended cluster (`kubectl config current-context` disagrees with what the user described). Stop and reconcile before installing.
- Worker Secret is missing or malformed after install — don't retry blind. Read `cub worker get-envs` / `get-secret` to diagnose.
- Worker pod keeps crashing (`CrashLoopBackOff`). Collect `kubectl describe pod` + `cub worker logs` output, surface the actual error, and stop.
- User asks to bypass the worker image pin to chase a bleeding-edge feature. Warn and only proceed with explicit confirmation.

## Verify chain

1. `cub worker get --space <space> <worker-slug>` — status field shows `Ready` or equivalent.
2. `cub worker status --space <space> <worker-slug>` — heartbeat is recent.
3. `cub worker list-function --space <space> <worker-slug>` — function list includes the expected provider-type functions.
4. If managed install: `cub unit get --space <space> <worker-slug>-manifest --web` opens the Unit that holds the manifest.

## Evidence

- `cub worker get --space <space> <worker-slug> --web` — worker details in the GUI.
- `cub unit get --space <space> <worker-slug>-manifest --web` — for the managed-install variant.

## References

- ConfigHub worker guide: `https://docs.confighub.com/markdown/guide/workers.md`
- Worker entity: `https://docs.confighub.com/markdown/background/entities/worker.md`
- `references/cub-cli.md` — CLI conventions, `--change-desc`, `-o mutations`.
- `references/yaml-patterns.md` — handling of Secret resources in Units.
