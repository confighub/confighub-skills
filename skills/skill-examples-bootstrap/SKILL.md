---
name: skill-examples-bootstrap
description: 'Create or refresh a skill-examples Space with representative Kubernetes Units for exercising the other skills. Use for "set up the skill-examples space", "bootstrap the examples", "give me a Unit to tinker with", or "reset the examples". Not for real application Spaces (use confighub-core).'
phase: cross-cutting
allowed-tools: []
read-capability-subset: skill-examples-bootstrap
---

# skill-examples-bootstrap

**Authority boundary:** this companion may inspect the playground and prepare an idempotent bootstrap proposal, but it must not create or update it. The external mutation broker is `NOT_INTEGRATED`, so executable setup ends in `ASK` or `BLOCK`.

Updates to existing example Units remain `APPROVED_STATE_CAS_NOT_INTEGRATED`: ConfigHub has transactional expected-head/hash checks, but this companion has no protected digest-pinned action and receipt that carries the reviewed values to execution.

Prepares and explains an idempotent ConfigHub playground proposal so users can exercise the other skills against a well-formed example after externally authorized creation.

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

Every mutation call passes `--change-desc` with the user prompt verbatim so the revision history demonstrates provenance end-to-end.

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. Confirm with the user: is this a first-time bootstrap, or a refresh? A refresh preserves the Space but re-runs the recipe against the existing Units.

## The loop

### 1. Detect existing state

```bash
cub space get skill-examples 2>/dev/null
cub unit list --space skill-examples 2>/dev/null
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

Upload each:

```bash
for slug in hello-ns hello-app hello-statefulset hello-daemonset hello-job \
            hello-cronjob hello-ingress hello-netpol hello-rbac hello-hpa hello-pdb; do
  cub unit create --space skill-examples "$slug" \
    "skills/skill-examples-bootstrap/examples/${slug}.yaml" \
    --merge-external-source "confighub-skills/skills/skill-examples-bootstrap/examples/${slug}.yaml" \
    --change-desc "Seed ${slug} for the skill-examples playground.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>"
done
```

`--merge-external-source` records each file as the Unit's external source, so re-running this against an already-seeded Space merges the new file content rather than replacing the Unit — anything you tinkered with in ConfigHub survives, unless the file changed the same path.

> `cub variant upload --granularity per-file` would produce the same file-stem slugs in one command and merge the same way on re-upload. It is the right tool for a real base Space, and the wrong one here: it requires `--component` / `--variant` and stamps those labels, which would make the playground look like a variant of a component it isn't. Use it when you graduate an example into a real component; keep the loop for the playground.

### 4. Apply the defaults chain

Each function call is hermetic and idempotent, so re-running on an already-seeded Space produces no-op revisions (and no noise in the history if nothing changes).

On workload Units (`hello-app`, `hello-statefulset`, `hello-daemonset`, `hello-job`, `hello-cronjob`):

```bash
for slug in hello-app hello-statefulset hello-daemonset hello-job hello-cronjob; do
  for fn in set-container-resources-defaults set-container-probe-defaults \
            set-pod-container-security-context-defaults ensure-namespaces; do
    cub function set --space skill-examples --unit "$slug" \
      --change-desc "Apply $fn to $slug.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>" \
      -- "$fn"
  done
done
```

On `hello-ns`:

```bash
cub function set --space skill-examples --unit hello-ns \
  --change-desc "Apply pod-security labels to hello namespace.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>" \
  -- set-pod-security-defaults
```

On non-workload Units that have namespaced resources (`hello-ingress`, `hello-netpol`, `hello-rbac`, `hello-hpa`, `hello-pdb`):

```bash
for slug in hello-ingress hello-netpol hello-rbac hello-hpa hello-pdb; do
  cub function set --space skill-examples --unit "$slug" \
    --change-desc "Apply ensure-namespaces to $slug.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>" \
    -- ensure-namespaces
done
```

On `hello-rbac`, also disable auto-mounted service account tokens:

```bash
cub function set --space skill-examples --unit hello-rbac \
  --change-desc "Disable automountServiceAccountToken on hello-rbac ServiceAccount.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>" \
  -- set-automount-service-account-token-false
```

### 5. Show the user what to do next

Point them at the GUI and the other skills:

- `cub unit list --space skill-examples` — overview of all seeded Units.
- `cub unit open hello-app --space skill-examples --print-url` — inspect the final literal YAML.
- `cub unit open hello-app --space skill-examples --revisions --print-url` — see the provenance chain.
- Suggest a concrete next move: "Try `cub-mutate` to bump the image tag", "Try `cub-query` to find all Deployments in `skill-examples`", "Set up `triggers-and-applygates` against `skill-examples` to see an ApplyGate in action", "Use `kubernetes-resources` to create a new resource — it'll pull from these examples."

## Tool boundary

- Host-ASK: read-only `cub` evidence in this skill's declared capability subset; no raw Bash is auto-allowed.
- Proposal-only: Space/Unit create/update and function mutations; the external broker is required.
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
