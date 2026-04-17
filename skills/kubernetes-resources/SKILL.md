---
name: kubernetes-resources
description: 'Use when the user wants to create or modify a specific Kubernetes resource type in ConfigHub — phrases like "create a StatefulSet", "add an Ingress", "set up NetworkPolicy", "I need a CronJob", "add RBAC for my app", "set up autoscaling", "create a DaemonSet", "expose my service externally", "add a PDB", "create a Job for data migration", "I need a headless Service", "set up persistent storage". Walks the user through authoring the resource as literal YAML in a ConfigHub Unit, applying best-practice defaults via functions, and wiring it into the Space. Pulls live examples from the `skill-examples` Space when available (seeded by `skill-examples-bootstrap`); falls back to `references/yaml-patterns.md`. Do not load for: AppConfig-based ConfigMaps (use `app-config`), Helm chart imports (use `import-from-helm`), raw config-as-data doctrine questions without a specific resource type (use `config-as-data`).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub unit diff *) Bash(cub function do *) Bash(cub run *) Bash(cub link create *) Bash(cub link update *) Bash(kubectl create *) Bash(kubectl explain *)
---

# kubernetes-resources

Author common Kubernetes resource types as ConfigHub Units — literal YAML, best-practice defaults applied via functions, wired into the right Space.

## When to use

- User wants to create a specific Kubernetes resource: Deployment, StatefulSet, DaemonSet, Job, CronJob, Service, Ingress, NetworkPolicy, RBAC (ServiceAccount + Role + RoleBinding), HPA, PDB, PVC, Namespace.
- User asks "how do I set up autoscaling / networking rules / persistent storage / batch jobs in ConfigHub?"
- User wants to expose a service externally (Ingress).
- User needs to lock down namespace networking (NetworkPolicy).
- User wants to add RBAC for an application.

## Do not load for

- AppConfig-based ConfigMaps (`.env`, `.properties`, `.yaml` config files) — use `app-config`.
- Helm chart imports — use `import-from-helm`.
- General config-as-data doctrine without a specific resource type — use `config-as-data`.
- Secrets — ConfigHub Units are not a secret vault. Point users to an external SecretStore; see `references/yaml-patterns.md`.
- Custom Resource Definitions (writing operators) — out of scope.

## Preflight gates

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. Target Space exists and the user has write permission.
3. **Resource type identified.** If the user's request is vague ("set up my app"), ask what specific resources they need before proceeding.

## Live examples

Before showing hardcoded YAML, check whether the `skill-examples` Space has a relevant example Unit:

```bash
cub unit get <example-slug> --space skill-examples -o yaml 2>/dev/null
```

| Resource type                  | Example slug        | Contents                                                 |
| ------------------------------ | ------------------- | -------------------------------------------------------- |
| Deployment + Service           | `hello-app`         | Deployment + ClusterIP Service bundle                    |
| StatefulSet + headless Service | `hello-statefulset` | StatefulSet with volumeClaimTemplates + headless Service |
| DaemonSet                      | `hello-daemonset`   | Node-level DaemonSet with hostPath volumes               |
| Job                            | `hello-job`         | One-shot Job with backoffLimit + activeDeadlineSeconds   |
| CronJob                        | `hello-cronjob`     | Scheduled CronJob with concurrencyPolicy                 |
| Ingress                        | `hello-ingress`     | Ingress with TLS + cert-manager annotation               |
| NetworkPolicy                  | `hello-netpol`      | Default-deny + explicit-allow pair                       |
| RBAC                           | `hello-rbac`        | ServiceAccount + Role + RoleBinding bundle               |
| HPA                            | `hello-hpa`         | HorizontalPodAutoscaler with scale behavior              |
| PDB                            | `hello-pdb`         | PodDisruptionBudget                                      |
| Namespace                      | `hello-ns`          | Namespace with pod-security labels                       |

If the example Unit exists, show it to the user as the starting point and adapt it. If `skill-examples` doesn't exist or the Unit isn't there, use the patterns from `references/yaml-patterns.md`.

## The loop

### 1. Identify the resource type and gather requirements

Ask the user:

- What resource type do they need?
- What Space should it go in?
- For workloads: what image, ports, replicas? Do the containers need to write to disk (logs, caches, scratch space, temp files)? `set-pod-container-security-context-defaults` sets `readOnlyRootFilesystem: true`, so any write paths must be backed by a volume (see step 5).
- For StatefulSets: storage size, access mode?
- For Ingress: hostname, TLS required? Which `ingressClassName`? Note: the community `ingress-nginx` controller is being retired (https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) — new clusters should prefer Gateway API or a maintained alternative (InGate, NGINX Inc.'s NGINX Ingress Controller, Traefik, HAProxy, etc.).
- For NetworkPolicy: what traffic to allow?
- For RBAC: what API resources and verbs does the app need?
- For HPA/PDB: what scaling thresholds?

### 2. Pull or adapt an example

```bash
cub unit get <example-slug> --space skill-examples -o yaml 2>/dev/null
```

If the example exists, use it as a starting template. Adapt names, images, ports, and other fields to the user's requirements. If the example doesn't exist, author the YAML from scratch following `references/yaml-patterns.md`.

### 3. Write the YAML file

Write literal YAML to a temp file. Follow these rules:

- Use `confighubplaceholder` for `namespace` fields — `ensure-namespaces` will add it where missing.
- Use explicit values for everything else — no templates, no placeholders except where a value genuinely isn't known yet and there is not a reasonable default.
- Set `metadata.labels` using the [Kubernetes recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/): at minimum `app.kubernetes.io/name` (matching the workload selector). Add `app.kubernetes.io/instance`, `app.kubernetes.io/version`, `app.kubernetes.io/component`, `app.kubernetes.io/part-of`, `app.kubernetes.io/managed-by` where they apply. Do not use the bare `app` label.
- For Jobs/CronJobs: always set `restartPolicy: Never` (or `OnFailure`), `backoffLimit`, and `activeDeadlineSeconds`.
- For NetworkPolicy: always allow DNS egress (port 53 UDP + TCP).
- For RBAC: set `automountServiceAccountToken: false` on the ServiceAccount **and** on the workload pod spec (see step 5); grant only needed verbs; use `resourceNames` for Secrets.
- For Ingress: always set `ingressClassName` explicitly; always configure TLS for production. Prefer a maintained controller — community `ingress-nginx` is retired (see https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

### 4. Create the Unit

```bash
cub unit create --space <space> <unit-slug> /tmp/<file>.yaml \
  --change-desc "<summary>

User prompt: <verbatim>
Clarifications: <condensed>"
```

### 5. Apply defaults functions

For workload Units (Deployment, StatefulSet, DaemonSet, Job, CronJob):

```bash
cub function do --space <space> --unit <slug> \
  -- set-container-resources-defaults --change-desc "..."
cub function do --space <space> --unit <slug> \
  -- set-container-probe-defaults --change-desc "..."
cub function do --space <space> --unit <slug> \
  -- set-pod-container-security-context-defaults --change-desc "..."
cub function do --space <space> --unit <slug> \
  -- set-automount-service-account-token-false --change-desc "..."
cub function do --space <space> --unit <slug> \
  -- ensure-namespaces --change-desc "..."
```

`set-automount-service-account-token-false` sets `automountServiceAccountToken: false` on every pod spec in the Unit. Apply it to every workload; the ServiceAccount-level setting is a defense-in-depth backstop, not a replacement. Only skip (and explicitly set `true` on the pod spec) when the workload genuinely needs to call the Kubernetes API.

**Writable paths for read-only root filesystems.** `set-pod-container-security-context-defaults` sets `readOnlyRootFilesystem: true`. If the container needs to write anywhere (e.g. `/tmp`, `/var/cache/<app>`, a log dir, a scratch dir), mount a volume at that path. For each write path:

```bash
cub function do --space <space> --unit <slug> \
  -- set-container-volume-mount-path <container-name> <volume-name> <volume-path> \
     --volume-source=emptyDir \
     --change-desc "..."
```

`set-container-volume-mount-path` adds the `volumeMount` to the named container and — if the named volume is not already in the pod spec — adds the volume too. `--volume-source` accepts `emptyDir` (default for scratch), `configMap`, `secret`, or `persistentVolumeClaim`. Use `*` as the container name to apply to all containers in the pod.

If the function doesn't fit the shape the user needs (e.g. a `projected` volume, a specific `medium: Memory` emptyDir, or an existing PVC with a sub-path), edit the YAML directly via `cub unit update` or a `yq-i` run instead.

For Namespace Units:

```bash
cub function do --space <space> --unit <slug> \
  -- set-pod-security-defaults --change-desc "..."
```

For non-workload namespaced resources (Ingress, NetworkPolicy, RBAC, HPA, PDB):

```bash
cub function do --space <space> --unit <slug> \
  -- ensure-namespaces --change-desc "..."
```

Note: `set-container-probe-defaults` adds HTTP GET probes on the first `containerPort`. For databases and other non-HTTP workloads, override with TCP or exec probes afterward via `yq-i`.

### 6. Validate

```bash
cub function do --space <space> --unit <slug> -- vet-schemas
cub function do --space <space> --unit <slug> -- vet-placeholders
cub function do --space <space> --unit <slug> -- vet-format
```

### 7. Guide next steps

Based on what was created, suggest the logical next skill:

- Workloads → `target-bind` + `cub-apply` to deploy.
- Ingress → ensure the backing Service Unit exists; link via Needs/Provides.
- NetworkPolicy → apply to the namespace; verify with `kubectl describe networkpolicy`.
- RBAC → reference the ServiceAccount in the workload's `serviceAccountName`.
- HPA/PDB → verify they target the correct workload selector.

## Unit granularity guidance

- **Namespace** — always one per Unit.
- **Deployment + Service** — bundle when they share the same selector and lifecycle.
- **StatefulSet + headless Service** — bundle (headless Service is required by the StatefulSet).
- **RBAC (SA + Role + Binding)** — bundle when they only make sense together.
- **Ingress** — separate Unit (TLS config and routing rules version independently from the Service).
- **NetworkPolicy** — separate Unit per policy (default-deny can share a Unit as a multi-doc bundle).
- **HPA, PDB** — separate Units (scaling and disruption config change independently from the workload).
- **PVC** — separate Unit when the PVC outlives the workload. For StatefulSets, use `volumeClaimTemplates` instead.
- **Job / CronJob** — one per Unit.
- **CRDs** — always separate Unit from instances.

## Tool boundary

- Allowed: `cub` read + create/update + `function do` + `run` + `link create/update`, `kubectl create --dry-run=client` and `kubectl explain` for scaffolding.
- Not allowed: `cub * delete *`, mutating `kubectl` (`apply`/`edit`/`patch`/`delete`), `helm`, `kustomize`.

## Stop conditions

- User asks for a resource type this skill doesn't cover (custom operators, service mesh CRDs). Hand back.
- User wants to create a Secret with literal values in the Unit. Stop — Secrets go in an external SecretStore.
- User insists on templating (`{{ }}`, `${VAR}`, values files). Stop and route to `config-as-data` for the doctrine explanation.

## Verify chain

1. `cub unit get <slug> --space <space> -o yaml` — inspect the stored YAML.
2. `cub function do --space <space> --unit <slug> -- vet-schemas` — valid against target K8s version.
3. `cub function do --space <space> --unit <slug> -- vet-placeholders` — no stray placeholders.

## Evidence

- `cub unit get <slug> --space <space> --web` — Unit in the GUI.
- `cub revision list <slug> --space <space> --web` — provenance chain.

## References

- `references/yaml-patterns.md` — ConfigHub-native YAML patterns for all resource types.
- `references/functions-catalog.md` — defaults functions, setters, validators.
- `references/cub-cli.md` — CLI discipline, `--change-desc`, `-o mutations`.
- Companion skills: `config-as-data` (doctrine), `skill-examples-bootstrap` (seeds the `skill-examples` Space with live examples), `target-bind` (deploy), `cub-apply` (apply), `app-config` (ConfigMap from app config files).
