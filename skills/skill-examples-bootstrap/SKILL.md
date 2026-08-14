---
name: skill-examples-bootstrap
description: 'Create or refresh a skill-examples Space with representative Kubernetes Units for exercising the other skills. Use for "set up the skill-examples space", "bootstrap the examples", "give me a Unit to tinker with", or "reset the examples". Not for real application Spaces (use confighub-core).'
phase: cross-cutting
allowed-tools: []
read-capability-subset: skill-examples-bootstrap
---

# skill-examples-bootstrap

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. Standalone use inspects first, then submits one missing or changed playground object at a time to the host permission system; an external overlay may stop it before Bash.

For an existing example Unit, re-read its head and hash before the write and do not claim atomic reviewed-state binding when the stock convenience command does not accept those values as preconditions.

Prepares and explains an idempotent ConfigHub playground so users can exercise the other skills against a well-formed example after the host permits each requested creation step.

## When to use

- User asks for a playground / example / sandbox to try ConfigHub against.
- User is new and needs something concrete to tinker with.
- `skill-examples` Space is missing or has been damaged and the user wants it back.
- User says "reset" or "refresh" the examples.

## Do not load for

- Creating real app Spaces (use `confighub-core` to prepare the governed Space proposal).
- Setting up Triggers / policy (use `triggers-and-applygates`).
- Importing existing Helm or Kustomize configs (use `import`).

## What gets created

**Space:** `skill-examples`

**Units in that Space:**

- `hello-ns` — `v1/Namespace` named `hello`, with pod-security labels applied via `set-pod-security-defaults`.
- `hello-app` — `apps/v1/Deployment` + `v1/Service` bundle for a placeholder app listening on port 8080.
- `hello-statefulset` — `apps/v1/StatefulSet` + headless `v1/Service` for a PostgreSQL-like stateful workload with `volumeClaimTemplates`.
- `hello-daemonset` — `apps/v1/DaemonSet` for a node-exporter-style monitoring agent.
- `hello-job` — `batch/v1/Job` for a one-shot database migration.
- `hello-cronjob` — `batch/v1/CronJob` for a scheduled nightly backup.
- `hello-ingress` — `networking.k8s.io/v1/Ingress` with TLS termination.
- `hello-netpol` — `networking.k8s.io/v1/NetworkPolicy` pair: default-deny + explicit allow.
- `hello-rbac` — `v1/ServiceAccount` + `rbac.authorization.k8s.io/v1/Role` + `RoleBinding` bundle.
- `hello-hpa` — `autoscaling/v2/HorizontalPodAutoscaler` targeting `hello-app`.
- `hello-pdb` — `policy/v1/PodDisruptionBudget` protecting `hello-app`.

All workload Units get the defaults chain: `set-container-resources-defaults`, `set-container-probe-defaults`, `set-pod-container-security-context-defaults`, `ensure-namespaces`.

Every supported Unit-data mutation uses a short safe `--change-desc` summary
from `references/execution-modes.md`. Never interpolate the verbatim prompt
into shell text; the shared transcript and command result retain fuller
context.

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. Confirm with the user: is this a first-time bootstrap, or a refresh? A refresh preserves the Space but re-runs the recipe against the existing Units.

## The loop

### 1. Detect existing state

```bash
cub space get skill-examples
```

If the Space exists, inspect Units in a separate read:

```bash
cub unit list --space skill-examples
```

Branch:

- **Space missing** → go to step 2 (full bootstrap).
- **Space present, Units missing** → skip space create, go to step 3.
- **Space + Units present** → compare current state with the fixture contract and propose only missing/different defaults; do not mutate merely to test idempotence.

### 2. Create the Space

```bash
cub space create skill-examples
```

`cub space create` does not accept `--change-desc`; Spaces aren't versioned data.

### 3. Upload example Units

Example YAML files are stored in `skills/skill-examples-bootstrap/examples/`. Each file maps to one Unit:

| File                     | Unit slug           | Contents                                |
| ------------------------ | ------------------- | --------------------------------------- |
| `hello-ns.yaml`          | `hello-ns`          | Namespace                               |
| `hello-app.yaml`         | `hello-app`         | Deployment + Service bundle             |
| `hello-statefulset.yaml` | `hello-statefulset` | StatefulSet + headless Service          |
| `hello-daemonset.yaml`   | `hello-daemonset`   | DaemonSet                               |
| `hello-job.yaml`         | `hello-job`         | Job                                     |
| `hello-cronjob.yaml`     | `hello-cronjob`     | CronJob                                 |
| `hello-ingress.yaml`     | `hello-ingress`     | Ingress with TLS                        |
| `hello-netpol.yaml`      | `hello-netpol`      | default-deny + allow NetworkPolicy pair |
| `hello-rbac.yaml`        | `hello-rbac`        | ServiceAccount + Role + RoleBinding     |
| `hello-hpa.yaml`         | `hello-hpa`         | HorizontalPodAutoscaler                 |
| `hello-pdb.yaml`         | `hello-pdb`         | PodDisruptionBudget                     |

Upload one missing or changed Unit at a time. Resolve `<slug>` to one literal
name from the table; submit and verify each call before moving to the next:

```bash
cub unit create --space skill-examples <slug> \
  skills/skill-examples-bootstrap/examples/<slug>.yaml \
  --merge-external-source confighub-skills/skills/skill-examples-bootstrap/examples/<slug>.yaml \
  --change-desc 'Seed reviewed Unit in skill examples playground'
```

`--merge-external-source` records each file as the Unit's external source, so re-running this against an already-seeded Space merges the new file content rather than replacing the Unit — anything you tinkered with in ConfigHub survives, unless the file changed the same path.

> `cub variant upload --granularity per-file` would produce the same file-stem slugs in one command and merge the same way on re-upload. It is the right tool for a real base Space, and the wrong one here: it requires `--component` / `--variant` and stamps those labels, which would make the playground look like a variant of a component it isn't. Use it when you graduate an example into a real component; keep the loop for the playground.

### 4. Apply the defaults chain

Each function call is hermetic and idempotent, so re-running on an already-seeded Space produces no-op revisions (and no noise in the history if nothing changes).

On workload Units (`hello-app`, `hello-statefulset`, `hello-daemonset`,
`hello-job`, `hello-cronjob`), run one function for one Unit per call. Resolve
`<workload-slug>` and `<defaults-function>` to literal values from those lists,
then verify before the next call:

```bash
cub function set --space skill-examples --unit <workload-slug> \
  --change-desc 'Apply reviewed workload defaults in skill examples' \
  -- <defaults-function>
```

On `hello-ns`:

```bash
cub function set --space skill-examples --unit hello-ns \
  --change-desc 'Apply pod security labels to hello namespace' \
  -- set-pod-security-defaults
```

On non-workload Units that have namespaced resources (`hello-ingress`,
`hello-netpol`, `hello-rbac`, `hello-hpa`, `hello-pdb`), resolve
`<namespaced-slug>` and submit one call at a time:

```bash
cub function set --space skill-examples --unit <namespaced-slug> \
  --change-desc 'Apply namespace defaults in skill examples' \
  -- ensure-namespaces
```

On `hello-rbac`, also disable auto-mounted service account tokens:

```bash
cub function set --space skill-examples --unit hello-rbac \
  --change-desc 'Disable token automount on hello rbac ServiceAccount' \
  -- set-automount-service-account-token-false
```

### 5. Show the user what to do next

Point them at the GUI and the other skills:

- `cub unit list --space skill-examples` — overview of all seeded Units.
- `cub unit open hello-app --space skill-examples --print-url` — inspect the final literal YAML.
- `cub unit open hello-app --space skill-examples --revisions --print-url` — see the provenance chain.
- Suggest a concrete next move: "Try `cub-mutate` to bump the image tag", "Try `cub-query` to find all Deployments in `skill-examples`", "Set up `triggers-and-applygates` against `skill-examples` to see an ApplyGate in action", "Use `kubernetes-resources` to create a new resource — it'll pull from these examples."

## Tool boundary

- Host permission: read-only `cub` evidence in this skill's declared capability subset; the pack preapproves no Bash call.
- Standalone mutation steps: Space/Unit create/update and function mutations each use one exact host-permission call after the idempotent read/compare step.
- Not allowed: `cub * delete *` (users who want to clean up should do it explicitly), any mutating `kubectl`, any `helm`/`kustomize`.

## Stop conditions

- User is not authenticated (`cub auth status` fails). Tell them to run `cub auth login`.
- User lacks permission to create Spaces in the current organization.

## Verify chain

1. `cub space get skill-examples` — Space exists.
2. `cub unit list --space skill-examples` — all 11 Units present.
3. `cub unit get hello-app --space skill-examples -o yaml` — YAML contains `resources.requests`, all three probes, `securityContext`, and `namespace: confighubplaceholder`.
4. `cub unit get hello-statefulset --space skill-examples -o yaml` — StatefulSet has `volumeClaimTemplates` and headless Service has `clusterIP: None`.
5. `cub revision list hello-app --space skill-examples` — revision history includes the defaults functions with user-prompt-bearing change descriptions.

## Evidence

- `cub space open skill-examples --print-url` — Space overview.
- `cub unit open hello-app --space skill-examples --print-url` — literal Unit YAML.
- `cub unit open hello-app --space skill-examples --revisions --print-url` — provenance chain.

## References

- `references/cub-cli.md` — CLI discipline + Read/Write permission sets.
- `references/yaml-patterns.md` — what makes the scaffolded YAML "good" literal YAML.
- `references/functions-catalog.md` — defaults functions used.
- Companion skill: `confighub-core` — the doctrine this recipe demonstrates.
