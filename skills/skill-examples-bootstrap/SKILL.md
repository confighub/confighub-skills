---
name: skill-examples-bootstrap
description: 'Use when the user wants a working ConfigHub playground to exercise the other skills against — phrases like "set up the skill-examples space", "bootstrap the examples", "give me a Unit to tinker with", "walk me through with a real example", "I''m new to ConfigHub, show me something I can poke at", or "reset the examples". Creates (or refreshes) a `skill-examples` Space with seed Units covering common Kubernetes resource types — Deployment, StatefulSet, DaemonSet, Job, CronJob, Ingress, NetworkPolicy, RBAC, HPA, PDB — and applies the canonical defaults-function chain so the end state demonstrates config-as-data with provenance intact. Other skills (like `kubernetes-resources`) pull from these live examples in preference to hardcoded YAML. Idempotent: re-running is safe. Do not load for creating real application Spaces (use config-as-data + space setup directly) or for bootstrapping triggers/policy (use triggers-and-applygates).'
phase: cross-cutting
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub space create *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub function *)
---

# skill-examples-bootstrap

Creates a ConfigHub playground Space so users can exercise the other skills against a real, well-formed example.

## When to use

- User asks for a playground / example / sandbox to try ConfigHub against.
- User is new and needs something concrete to tinker with.
- `skill-examples` Space is missing or has been damaged and the user wants it back.
- User says "reset" or "refresh" the examples.

## Do not load for

- Creating real app Spaces (use `config-as-data` + direct `cub space create`).
- Setting up Triggers / policy (use `triggers-and-applygates`).
- Importing existing Helm or Kustomize configs (future `import-*` skills).

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

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
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
- **Space + Units present** → go to step 4 (re-apply defaults; idempotent).

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
- `cub unit get hello-app --space skill-examples --web` — inspect the final literal YAML.
- `cub revision list hello-app --space skill-examples --web` — see the provenance chain.
- Suggest a concrete next move: "Try `cub-mutate` to bump the image tag", "Try `cub-query` to find all Deployments in `skill-examples`", "Set up `triggers-and-applygates` against `skill-examples` to see an ApplyGate in action", "Use `kubernetes-resources` to create a new resource — it'll pull from these examples."

## Tool boundary

- Allowed: `cub` read + create/update + `function do` (per frontmatter).
- Not allowed: `cub * delete *` (users who want to clean up should do it explicitly), any mutating `kubectl`, any `helm`/`kustomize`.

## Stop conditions

- User is not authenticated (`cub organization list` fails). Tell them to run `cub auth login`.
- User lacks permission to create Spaces in the current organization.

## Verify chain

1. `cub space get skill-examples` — Space exists.
2. `cub unit list --space skill-examples` — all 11 Units present.
3. `cub unit get hello-app --space skill-examples -o yaml` — YAML contains `resources.requests`, all three probes, `securityContext`, and `namespace: confighubplaceholder`.
4. `cub unit get hello-statefulset --space skill-examples -o yaml` — StatefulSet has `volumeClaimTemplates` and headless Service has `clusterIP: None`.
5. `cub revision list hello-app --space skill-examples` — revision history includes the defaults functions with user-prompt-bearing change descriptions.

## Evidence

- `cub space get skill-examples --web` — Space overview.
- `cub unit get hello-app --space skill-examples --web` — literal Unit YAML.
- `cub revision list hello-app --space skill-examples --web` — provenance chain.

## References

- `references/cub-cli.md` — CLI discipline + Read/Write permission sets.
- `references/yaml-patterns.md` — what makes the scaffolded YAML "good" literal YAML.
- `references/functions-catalog.md` — defaults functions used.
- Companion skill: `config-as-data` — the doctrine this recipe demonstrates.
