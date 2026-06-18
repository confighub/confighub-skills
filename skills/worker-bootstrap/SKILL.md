---
name: worker-bootstrap
description: 'Set up a ConfigHub worker. Default: a server worker (cub worker create --is-server-worker) — no process to run, and all that OCI / ConfigHub Targets need. Run an external worker (cub worker run / install) only to host custom worker functions. Phrases: set up a worker, do I need to run a worker, add custom functions. Not for creating Targets (use target-bind).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub worker logs *) Bash(cub worker status *) Bash(cub worker create *) Bash(cub worker update *) Bash(cub worker install *) Bash(cub worker upgrade *) Bash(cub worker get-envs *) Bash(cub worker get-secret *) Bash(cub unit create *) Bash(cub unit update *) Bash(kubectl get *) Bash(kubectl describe *) Bash(kubectl logs *)
---

# worker-bootstrap

Get a ConfigHub worker in place so Targets can function. In the common case there is **nothing to run**.

Confirm verbs and flags with `cub <verb> --help` before composing.

## The key fact

OCI and ConfigHub Targets are served by **server workers** — bridges hosted inside the ConfigHub server. You **do not run a process** to create or use them. A worker entity is still required (a Target references one), but for delivery it's a one-line `--is-server-worker` create.

You only run an **external worker** to host **custom worker functions** — your own function implementations that aren't built into the server.

So pick the path:

| Goal | Path |
| --- | --- |
| Publish Units to OCI for Argo/Flux, or apply ConfigHub-native config | **Server worker** (below) — no process |
| Provide custom worker functions of your own | **External worker** (below) — runs a process |

## When to use

- "Do I need to run a worker?" — usually no; create a server worker.
- First-time delivery setup (OCI / ConfigHub Targets).
- You have custom worker functions to host.
- Diagnosing an external worker that isn't advertising its functions.

## Do not load for

- Creating Targets — `target-bind` (Targets reference a worker but are a separate step).
- Applying Units — `cub-apply`.

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. For an external worker only: `kubectl config current-context` points at the intended cluster (if installing in-cluster), or you have a host to run `cub worker run` on.

## Server worker (default — no process)

```bash
cub worker create --space <space> --allow-exists --is-server-worker server-worker
```

- `--allow-exists` makes it idempotent. Place it in any Space (`default` is a common home); reference cross-Space as `<space>/server-worker`.
- Add `--use-user-identity` if the worker should operate as the requesting user (required for some ConfigHub-provider operations).
- No `--change-desc` — workers aren't versioned configuration data.

That's it. Hand off to `target-bind` to create an OCI or ConfigHub Target against `<space>/server-worker`.

## External worker (only for custom functions)

Run an external worker when you need it to host **custom worker functions**. Create the entity, then run or install it, then confirm it advertises its functions.

```bash
cub worker create --space <space> <worker-slug>          # the entity (no --is-server-worker)
```

**Run locally** (simplest for development):

```bash
cub worker run --space <space> <worker-slug>             # see `cub worker run --help` for type/function flags
```

**Install into a cluster** (`cub worker install` generates the manifest — Deployment, ServiceAccount, RBAC, credential Secret — it does not apply it):

```bash
# Direct install (bootstrap):
cub worker install <worker-slug> --space <space> --namespace confighub --export --include-secret | kubectl apply -f -

# Or store the manifest as a ConfigHub-managed Unit and apply it via cub-apply:
cub worker install <worker-slug> --space <space> --namespace confighub --export > /tmp/worker-manifest.yaml
cub unit create --space <space> <worker-slug>-manifest /tmp/worker-manifest.yaml -o mutations \
  --change-desc "Store worker manifest as a ConfigHub-managed Unit.

User prompt: <verbatim>
Clarifications: <condensed>"
```

The credential Secret is redacted by default; use `--include-secret` only when you genuinely need it inlined, and keep credentials in an external SecretStore rather than Unit data (see `references/yaml-patterns.md`). Image defaults to the pinned `ghcr.io/confighubai/confighub-worker` release.

Verify it's healthy and advertising the expected custom functions:

```bash
cub worker get --space <space> <worker-slug>             # condition: Ready
cub worker status --space <space> <worker-slug>          # recent heartbeat
cub worker list-function --space <space> <worker-slug>   # custom functions present
```

Pod-level fallback for an in-cluster worker that won't start: `kubectl -n confighub describe pod <worker-pod>` + `cub worker logs --space <space> <worker-slug>`.

## Tool boundary

- Mutations: `cub worker create` (incl. `--is-server-worker`), `cub worker install/upgrade/update`, `cub unit create/update` for the managed-manifest variant.
- Read-only: `cub worker get/list/logs/status/list-function`, `cub worker get-envs/get-secret`, `kubectl get/describe/logs` on the worker namespace.
- Not allowed: `kubectl apply/edit/delete` against worker resources except the documented direct-install pipe; otherwise flow through a Unit.

## Stop conditions

- External worker only: `kubectl config current-context` disagrees with the intended cluster — reconcile first.
- External worker pod keeps crashing (`CrashLoopBackOff`) — collect `kubectl describe pod` + `cub worker logs`, surface the error, stop.
- User asks to run a process for OCI/ConfigHub delivery — they don't need to; a server worker suffices.

## Verify chain

- Server worker: `cub worker get --space <space> server-worker` shows it exists; that's all a delivery Target needs.
- External worker: `cub worker status` (recent heartbeat) + `cub worker list-function` (custom functions present).

## Evidence

- `cub worker get --space <space> <worker-slug> --web` — worker details in the GUI.
- `cub unit get --space <space> <worker-slug>-manifest --web` — for the managed-manifest variant.

## References

- `cub worker create --help`, `cub worker run --help`, `cub worker install --help` — authoritative flags.
- ConfigHub worker guide: `https://docs.confighub.com/markdown/guide/workers.md`.
- `references/cub-cli.md` — CLI conventions.
- `references/yaml-patterns.md` — Secret handling in Units.
- Companion skills: `target-bind` (create the OCI / ConfigHub Target against the worker), `cub-apply` (apply/publish).
