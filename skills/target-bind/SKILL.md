---
name: target-bind
description: 'Bind Units to a delivery Target — ProviderType OCI (publish Unit data to ConfigHub''s OCI registry for ArgoCD/Flux to pull) or ConfigHub (writes ConfigHub/YAML config). Both are server workers, no external worker to run. Phrases: set up a target, publish to OCI, attach units to a target. Creates the Target + server worker and attaches Units via cub unit set-target; stops before publish.'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub worker create *) Bash(cub target create *) Bash(cub target update *) Bash(cub unit set-target *) Bash(cub unit update *)
---

# target-bind

Creates the binding between Units and a delivery destination. Once bound, the Unit is delivered when its Space is published as an OCI bundle Release through `release-publish`.

Confirm verbs and flags with `cub <verb> --help` before composing — never invent flags.

## What a Target is

A Target is a named binding that tells ConfigHub *where* a Unit's configuration lands when published. It references a **server worker** and carries a `ProviderType`. Two ProviderTypes are relevant:

- **`OCI`** — publishes the Unit's data verbatim to ConfigHub's built-in OCI registry. The bridge performs no remote apply (it succeeds immediately and echoes the data back as live state); a puller you configure outside ConfigHub — **ArgoCD or Flux** — fetches the OCI artifact and deploys it to the cluster. This is the primary delivery path. The OCI transport never routes by toolchain, so **a single OCI Target accepts Units of any toolchain** (KRM, AppConfig, ConfigHub/YAML).
- **`ConfigHub`** — applies ConfigHub-native `ConfigHub/YAML` config (e.g. Units whose data *is* ConfigHub entities). Toolchain and live-state type are both `ConfigHub/YAML`.

**You do not need to run an external worker to create or attach a Target.** Both providers are *server workers*: bridges hosted inside the ConfigHub server. You only run an external worker to provide **custom worker functions** — see `worker-bootstrap`.

**Best practice:** one OCI Target per Space (it covers every toolchain in the Space). Add a ConfigHub Target only if the Space also manages ConfigHub-native config. A Target can live in a different Space than the Units that use it and be referenced as `<target-space>/<target-slug>`.

## When to use

- First time binding Units to a delivery destination.
- Setting up OCI publishing for ArgoCD / Flux to consume.
- Changing which Target a Unit publishes through.
- Binding many Units to a Target at once (`--where`).

## Do not load for

- Running an external worker for custom functions (`worker-bootstrap`).
- Publishing the OCI bundle Release (`release-publish`).
- Authoring or editing the Unit's data (`confighub-core` doctrine / `cub-mutate`).
- Rendering an AppConfig file to a ConfigMap (`app-config` — that uses an Upsert link, no Target).

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. A **server worker** exists (or create one — it's a single idempotent command, no process to run):

   ```bash
   cub worker create --space <space> --allow-exists --is-server-worker server-worker
   ```

   Place it in any Space; reference cross-Space as `<space>/server-worker`. Add `--use-user-identity` if the worker should act as the requesting user (required for some ConfigHub-provider operations).
3. For OCI delivery: the user has (or will set up) ArgoCD or Flux configured to pull the published OCI artifact. That configuration lives outside ConfigHub.

## The loop

### 1. Ensure the server worker (preflight step 2)

### 2. Create the Target

**OCI** (toolchain defaults to the `ToolchainAny` wildcard; no parameters needed — it publishes to ConfigHub's OCI registry):

```bash
cub target create <target-slug> '' <space>/server-worker \
  --space <target-space> \
  --provider OCI
```

**ConfigHub** (ConfigHub-native config):

```bash
cub target create <target-slug> '' <space>/server-worker \
  --space <target-space> \
  --provider ConfigHub --toolchain ConfigHub/YAML --livestate-type ConfigHub/YAML
```

Parameters are the JSON string after the slug (`''` = none, the usual case for these providers). Targets are not versioned configuration data — **no `--change-desc`** on create/update. Check `cub target create --help` for the authoritative parameter/option set.

### 3. Attach Units to the Target

Single Unit:

```bash
cub unit set-target <unit-slug> <target-slug> --space <app-space>
```

Bulk:

```bash
cub unit set-target --space <app-space> --where "Labels.App = 'myapp'" <target-slug>
```

Cross-Space reference uses `<target-space>/<target-slug>`. `cub unit set-target` is not a data mutation — it takes no `--change-desc`. To record *why* the target changed, mutate the Unit's data in a separate step, or rely on the audit log.

### 4. Hand off

Target created and Units attached. Next is almost always `release-publish` (which bundles the Space's Units into an immutable OCI bundle Release the Target serves). Cluster convergence from the OCI bundle Release is ArgoCD/Flux's job.

## Tool boundary

- Mutations: `cub worker create --is-server-worker`, `cub target create/update`, `cub unit set-target`, `cub unit update` (only when recording a target-change rationale in data).
- Read-only: `cub target get/list`, `cub worker get/list`, `cub unit livestate/livedata`.
- Not allowed: bypassing Targets with `kubectl apply` / `argocd app create` / `flux create` directly.

## Stop conditions

- No server worker exists and the user can't create one — stop (it should just be the one idempotent command above).
- User asks to bind to a provider other than OCI or ConfigHub — those are the supported delivery providers; clarify intent.
- `cub unit set-target` across `--space "*"` without a narrow `--where` — confirm blast radius first.

## Verify chain

1. `cub target get <target-slug> --space <target-space>` — `ProviderType` (OCI / ConfigHub) and worker are set; for OCI the toolchain is the `ToolchainAny` wildcard.
2. `cub unit get <unit-slug> --space <app-space>` — `TargetID` points at the expected Target.
3. For bulk: `cub unit list --space <app-space> --where "TargetID IS NOT NULL"` count matches the `--where` selection.

## Evidence

- `cub target get <target-slug> --space <target-space> --web` — Target page in the GUI.
- `cub unit get <unit-slug> --space <app-space> --web` — Unit page shows the Target binding and publish state.

## References

- `cub target create --help`, `cub worker create --help` — authoritative flags/parameters.
- Target entity: `https://docs.confighub.com/markdown/background/entities/target.md`.
- `references/cub-cli.md` — CLI conventions.
- `references/filters-and-queries.md` — the `TargetID IS NOT NULL` pattern for verifying bulk bindings.
- Companion skills: `worker-bootstrap` (server workers + external workers for custom functions), `release-publish` (publish the OCI bundle Release).
