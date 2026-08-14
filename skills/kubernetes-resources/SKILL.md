---
name: kubernetes-resources
description: 'Author a specific Kubernetes resource type as literal YAML in a ConfigHub Unit with best-practice defaults. Use for "create a StatefulSet", "add an Ingress", "set up NetworkPolicy", "I need a CronJob", "add RBAC for my app", "set up autoscaling", "add a PDB". Not for AppConfig-based ConfigMaps (use app-config).'
phase: act
allowed-tools: []
read-capability-subset: kubernetes-resources
---

# kubernetes-resources

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. After the literal resource and exact Unit scope are reviewed, standalone use submits one requested create or update to the host permission system; an external overlay may stop it before Bash.

For an existing Unit, read its current `HeadRevisionNum` and hash immediately before the write and disclose that the stock convenience command does not atomically bind those pre-read values. Do not claim exact reviewed-state protection that the invoked command does not provide.

Author common Kubernetes resource types as ConfigHub Units — literal YAML, best-practice defaults applied via functions, wired into the right Space.

## When to use

- User wants to create a specific Kubernetes resource: Deployment, StatefulSet, DaemonSet, Job, CronJob, Service, Ingress, NetworkPolicy, RBAC (ServiceAccount + Role + RoleBinding), HPA, PDB, PVC, Namespace.
- User asks "how do I set up autoscaling / networking rules / persistent storage / batch jobs in ConfigHub?"
- User wants to expose a service externally (Ingress).
- User needs to lock down namespace networking (NetworkPolicy).
- User wants to add RBAC for an application.

## Do not load for

- AppConfig-based ConfigMaps (`.env`, `.properties`, `.yaml` config files) — use `app-config`.
- Helm chart imports — use `import`.
- General config-as-data doctrine, the component model, or which Space this belongs in — use `confighub-core`.
- Secrets — ConfigHub Units are not a secret vault. Point users to an external SecretStore; see `references/yaml-patterns.md`.
- Custom Resource Definitions (writing operators) — out of scope.

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. Target Space exists and the user has write permission.
3. **Resource type identified.** If the user's request is vague ("set up my app"), ask what specific resources they need before proceeding.

## Live examples

Before showing hardcoded YAML, check whether the `skill-examples` Space has a relevant example Unit:

```bash
cub unit get <example-slug> --space skill-examples -o yaml
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
cub unit get <example-slug> --space skill-examples -o yaml
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
  --change-desc 'Create reviewed Kubernetes resource Unit'
```

### 5. Apply defaults functions

For workload Units (Deployment, StatefulSet, DaemonSet, Job, CronJob):

```text
cub function set --space <space> --unit <slug> \
  --change-desc 'Apply reviewed container resource defaults' -- set-container-resources-defaults
cub function set --space <space> --unit <slug> \
  --change-desc 'Apply reviewed container probe defaults' -- set-container-probe-defaults
cub function set --space <space> --unit <slug> \
  --change-desc 'Apply reviewed pod security defaults' -- set-pod-container-security-context-defaults
cub function set --space <space> --unit <slug> \
  --change-desc 'Disable reviewed service account token automount' -- set-automount-service-account-token-false
cub function set --space <space> --unit <slug> \
  --change-desc 'Apply reviewed namespace defaults' -- ensure-namespaces
```

`set-automount-service-account-token-false` sets `automountServiceAccountToken: false` on every pod spec in the Unit. Apply it to every workload; the ServiceAccount-level setting is a defense-in-depth backstop, not a replacement. Only skip (and explicitly set `true` on the pod spec) when the workload genuinely needs to call the Kubernetes API.

**Writable paths for read-only root filesystems.** `set-pod-container-security-context-defaults` sets `readOnlyRootFilesystem: true`. If the container needs to write anywhere (e.g. `/tmp`, `/var/cache/<app>`, a log dir, a scratch dir), mount a volume at that path. For each write path:

```bash
cub function set --space <space> --unit <slug> \
  --change-desc 'Add reviewed writable container volume mount' \
  -- set-container-volume-mount-path <container-name> <volume-name> <volume-path> \
     --volume-source=emptyDir
```

`set-container-volume-mount-path` adds the `volumeMount` to the named container and — if the named volume is not already in the pod spec — adds the volume too. `--volume-source` accepts `emptyDir` (default for scratch), `configMap`, `secret`, or `persistentVolumeClaim`. Use `*` as the container name to apply to all containers in the pod.

If the function doesn't fit the shape the user needs (e.g. a `projected` volume, a specific `medium: Memory` emptyDir, or an existing PVC with a sub-path), edit the YAML directly via `cub unit update` or a `set-yq` run instead.

For Namespace Units:

```bash
cub function set --space <space> --unit <slug> \
  --change-desc 'Apply reviewed namespace pod security defaults' -- set-pod-security-defaults
```

For non-workload namespaced resources (Ingress, NetworkPolicy, RBAC, HPA, PDB):

```bash
cub function set --space <space> --unit <slug> \
  --change-desc 'Apply reviewed namespace defaults' -- ensure-namespaces
```

Note: `set-container-probe-defaults` adds HTTP GET probes on the first `containerPort`. For databases and other non-HTTP workloads, override with TCP or exec probes afterward via `set-yq` (`get-yq` is its read-only counterpart; the deprecated spellings are `yq-i` and `yq`).

### 6. Validate

```text
cub function vet --space <space> --unit <slug> -- vet-schemas
cub function vet --space <space> --unit <slug> -- vet-placeholders
cub function vet --space <space> --unit <slug> -- vet-format
```

### 7. Guide next steps

Based on what was created, suggest the logical next skill:

- Workloads → `target-bind` + `release-publish` to deliver.
- Ingress → ensure the backing Service Unit exists; link via Needs/Provides.
- NetworkPolicy → apply to the namespace; verify with `kubectl describe networkpolicy`.
- RBAC → reference the ServiceAccount in the workload's `serviceAccountName`.
- HPA/PDB → verify they target the correct workload selector.

## Unit granularity guidance

**Default: one Kubernetes resource per Unit** (the doctrine in `confighub-core`; `cub variant upload --granularity per-resource` produces it for imported manifests). It scopes revisions, ApplyGates, diffs, and blast radius to a single resource, and links resources that reference each other via Links / Needs-Provides rather than co-locating them. Author each resource type below as its own Unit; wire cross-references with `cub link create`.

- **CRDs** — always a separate Unit from their instances (apply-order + blast radius). Slug `<app>-crds`.
- **PVC** — for StatefulSets, prefer `volumeClaimTemplates` inline rather than a separate PVC resource.
- Some seeded `skill-examples` Units (e.g. `hello-app` = Deployment + Service) carry a small bundle for demonstration; treat those as examples, not the recommended granularity for new work.

## Tool boundary

- Host permission: read-only `cub` inspection and `kubectl explain` in this skill's declared capability subset; the pack preapproves no Bash call.
- Standalone mutation steps: Unit/link create/update and function/run changes each use one exact host-permission call. Client-side scaffolding may be shown, but do not mutate the cluster with `kubectl create`.
- Not allowed: `cub * delete *`, mutating `kubectl` (`apply`/`edit`/`patch`/`delete`), `helm`, `kustomize`.

## Stop conditions

- User asks for a resource type this skill doesn't cover (custom operators, service mesh CRDs). Hand back.
- User wants to create a Secret with literal values in the Unit. Stop — Secrets go in an external SecretStore.
- User insists on templating (`{{ }}`, `${VAR}`, values files). Stop and route to `confighub-core` for the doctrine explanation.

## Verify chain

1. `cub unit get <slug> --space <space> -o yaml` — inspect the stored YAML.
2. `cub function vet --space <space> --unit <slug> -- vet-schemas` — valid against target K8s version.
3. `cub function vet --space <space> --unit <slug> -- vet-placeholders` — no stray placeholders.

## Evidence

- `cub unit open <slug> --space <space> --print-url` — Unit in the GUI.
- `cub unit open <slug> --space <space> --revisions --print-url` — provenance chain.

## References

- `references/yaml-patterns.md` — ConfigHub-native YAML patterns for all resource types.
- `references/functions-catalog.md` — defaults functions, setters, validators.
- `references/cub-cli.md` — CLI discipline, `--change-desc`, `-o mutations`.
- Companion skills: `confighub-core` (doctrine), `skill-examples-bootstrap` (seeds the `skill-examples` Space with live examples), `target-bind` (deploy), `release-publish` (publish the OCI bundle Release), `app-config` (ConfigMap from app config files).
