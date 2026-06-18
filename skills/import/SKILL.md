---
name: import
description: 'Onboard existing Kubernetes config into ConfigHub as Units, from a Helm chart ("cub helm install", "upgrade the chart without losing my edits") or a Kustomize overlay ("import my base + overlays", "kustomize build into Units"). Not for authoring new YAML from scratch (use kubernetes-resources).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit data *) Bash(cub helm template *) Bash(cub helm install *) Bash(cub helm upgrade *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub function *) Bash(cub link create *) Bash(helm repo add *) Bash(helm repo update *) Bash(helm repo list) Bash(helm search *) Bash(kustomize build *) Bash(kubectl kustomize *) Bash(mkdir -p /tmp/*) Bash(ls *) Bash(cat *)
---

# import

One onboarding ramp for bringing existing Kubernetes configuration under ConfigHub management. Pick the source, render it into Units, then the rest of the skill set takes over (customize via `cub-mutate`, validate via Triggers, deliver via `cub-apply`).

## Pick the source

| The user has… | Go to |
| --- | --- |
| A Helm chart (`jetstack/cert-manager`, `bitnami/nginx`, a chart repo + version) | **§A Helm** |
| A local `kustomization.yaml` (`base/` + `overlays/`) | **§B Kustomize** |

ArgoCD `Application` / Flux `HelmRelease` GitOps pipelines, and adopting live-cluster resources, are **not** covered by this skill.

## Positioning: this is onboarding, not the destination

Both paths meet the user where they are and get them into ConfigHub without a day-one rewrite. The end state ConfigHub is built for is **configuration as data** — literal-YAML Units + semantic functions for policy and per-environment customization (see `confighub-core`). The chart / overlay is a **bootstrap input**, not an ongoing parameterization surface. After import:

- Customize with `cub-mutate` functions (`set-container-image`, `set-replicas`, `set-env-var`, the defaults functions), not values files or patches.
- Spread across environments by cloning Units upstream→downstream, not per-env values/overlays.
- Re-render (`cub helm upgrade`, re-`kustomize build`) only to pull a deliberate upstream change — a structured, logged event.

Call this trajectory out so the user understands the direction, not just the first command.

Guides: `https://docs.confighub.com/markdown/guide/helm-charts.md` (Helm), `https://docs.confighub.com/markdown/guide/rendered-manifests.md` (DRY rendering model).

## Shared preflight

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. Target Space exists (`cub space list`) and the user has write permission. **Environments are Spaces, not slug suffixes** (`confighub-core` topology): render each env into its own `<app>-<env>[-<region>]` Space; the Unit slug is the workload, not the env.
3. Confirm the verb and flags with `cub <verb> --help` before composing.

## Granularity

Default to **one Kubernetes resource per Unit** (`confighub-core`). Generator output starts coarser, which is fine as an onboarding step:

- `cub helm install` renders a bundle and auto-splits CRDs into `<release>-crds`. Start there; split further later if ownership/lifecycle/blast-radius diverge.
- A `kustomize build` is one rendered stream — store as one Unit per overlay to start, then split per workload/resource with `cub unit create` + `cub-mutate` (no re-render needed).

**CRDs always stand alone** — apply-order (CRDs established before their CRs at the consumer) and wider blast radius. Slug `<app>-crds`.

---

## §A — Helm chart

### Preflight (additional)

- `helm` is on PATH (`cub helm` shells out to it).
- The chart's repo is added (`helm repo list`); if not, `helm repo add <name> <url> --force-update && helm repo update`.
- A chart **version is pinned**. Never install without `--version` — unpinned installs can't be audited on upgrade.
- Namespace strategy decided — default to `--namespace <ns>` (below).

### Namespace — default to `--namespace <ns>`

Many charts bake the namespace into rendered data (ConfigMap contents, Service hostnames, RoleBinding subjects like `system:serviceaccount:<ns>:<sa>`). With `--namespace`, the chart renders as `helm install` would and ConfigHub stores the literal result — predictable and debuggable. `--use-placeholder` (renders `namespace: confighubplaceholder`, resolved via `cub link create`) only works cleanly for charts with no internal namespace references — reach for it only with a `vet-placeholders` strategy in mind.

### Install

```bash
helm search repo <repo>/<chart> --versions     # confirm the version exists
cub helm install <release> <repo>/<chart> \
  --space <app>-<env> --namespace <ns> --version <pinned> [--values <file>] [--set k=v]
```

This creates `<release>` (main resources, + Namespace if `--namespace`) and `<release>-crds` (if the chart ships CRDs). `cub helm` does **not** accept `--change-desc` — provenance is recorded as Unit labels (`helmrelease`, `helmchart`, `helmversion` — verify exact keys with `-o json`). For a human note, follow up with a `set-annotation` function carrying `--change-desc`.

### Per-environment — two patterns

- **Pattern A (per-env values files):** if the user already runs `helm install -f values-<env>.yaml`, preserve it — run one `cub helm install` per env-Space with that env's values. Migrate values into `cub-mutate` functions over time.
- **Pattern B (single install + clones):** install once into a base Space, then clone per env. Clones keep an `--upstream-unit` link so `cub helm upgrade` on the base propagates via `--upgrade` while preserving per-env edits. **Never edit the base Unit** — edits are clobbered by the next upgrade; customize the clone via `cub-mutate`.

```bash
cub unit create --space <app>-staging <release> --upstream-unit <app>-base/<release>
cub unit create --dest-space <app>-staging --space <app>-base   # clone the whole base Space (base + crds)
```

### Upgrade

- **Pattern A:** `cub helm upgrade <release> <repo>/<chart> --space <app>-<env> --version <new> --values values-<env>.yaml [--update-crds]` per env-Space.
- **Pattern B:** `cub helm upgrade` the base, then `cub unit update <release> --space <env-space> --upgrade --change-desc "…"` per clone (merge preserves clone edits). Review with `cub unit diff`.

`--update-crds` is off by default — set it only when the chart's CRD schemas changed and you want them in.

### Deliver

Hand off to `cub-apply` for delivery (which publishes the Units to OCI for Argo/Flux to pull, or applies via a ConfigHub Target). When CRDs are present, apply the `<release>-crds` Unit before the workload Unit so the consumer sees the CRDs first; the GitOps tool (Argo sync waves / Flux `dependsOn`) handles establishment ordering at the cluster. `cub-apply` / `verify-apply` own the rollout.

---

## §B — Kustomize overlay

There is no `cub kustomize` — render locally with `kustomize` / `kubectl kustomize`, store via `cub unit create`. If the user's "Kustomize" is actually a **Flux `Kustomization` CRD** (managed in-cluster), this skill doesn't cover that GitOps pipeline.

### Preflight (additional)

- `kustomize` or `kubectl kustomize` on PATH. Prefer standalone `kustomize` for full feature coverage.
- The overlay path actually has a `kustomization.yaml`.
- Which overlays map to which env-Spaces is decided.

### The loop

```bash
# 1. Inventory.
ls overlays/ ; cat overlays/<env>/kustomization.yaml

# 2. Render the overlay for this env.
mkdir -p /tmp/kustomize-import
kustomize build overlays/<env> > /tmp/kustomize-import/<app>.yaml     # or: kubectl kustomize overlays/<env>
```

Inspect the output before uploading: strip `status:` / `creationTimestamp` (`yq 'del(.status, .metadata.creationTimestamp)'`), confirm `namespace:` applied to every namespaced resource, and bail to **§A** if it's a Helm-inflator overlay.

```bash
# 3. Create the Unit in the env-Space (default: one Unit per overlay; split later).
cub unit create --space <app>-<env> <app> /tmp/kustomize-import/<app>.yaml \
  --change-desc "Import <app> <env> overlay from Kustomize at <git-ref / SHA>.

User prompt: <verbatim>
Clarifications: <e.g. rendered via kustomize v5.4.2 from overlays/<env>, or 'none'>"
```

Record the source ref (git SHA, overlay path) in `--change-desc` — Units carry no pointer back to the Kustomize tree otherwise.

### Promotion (optional)

For merge-preserving dev→staging→prod, render a base once into a base Space and clone per env with `--upstream-unit <app>-base/<app>`. Pull upstream changes later with `cub unit update --space <app>-<env> <app> <new-rendered.yaml> --change-desc "…"` (merge preserves in-ConfigHub edits) — or `--upgrade` from the upstream Unit. From here, customize via `cub-mutate` functions instead of new overlays.

Then hand off to `cub-apply` / `verify-apply`.

---

## Tool boundary

- Allowed: `cub helm install/upgrade/template`, `cub unit create/update`, `cub function …`, `cub link create`, `helm repo add/update/list`, `helm search`, `kustomize build`, `kubectl kustomize`; read-only `cub unit get/list/data/diff/tree`.
- Not allowed: `helm install` / `kubectl apply` / `kubectl apply -k` (deploys outside ConfigHub), editing a Pattern-B base Unit, adopting live-cluster or GitOps-tool-managed resources (out of scope for this skill).

## Stop conditions

- §A: repo not added and the user won't add it; install without `--version`; request to edit the base Unit (offer the clone instead); slug collides with an existing Unit (did they mean upgrade?).
- §B: overlay won't `kustomize build` (report the error verbatim, don't "fix" it); Helm-inflator overlay (→ §A).

## Verify chain

- §A: `cub unit list --space <space> --where "Labels.helmrelease = '<release>'"` (base + crds present); `cub unit diff <release> <app>-base/<release> --space <app>-<env>` (clone customizations); after upgrade, `cub revision list <release>` shows the new version.
- §B: `cub unit get <app> --space <app>-<env> -o yaml | diff - /tmp/kustomize-import/<app>.yaml`; `cub revision list <app>` shows Revision 1 with the Kustomize-source change-desc.

## Evidence

- `cub unit get <slug> --space <space> --web` — the imported Unit in the GUI.
- `cub revision list <slug> --space <space> --web` — provenance starting at import.

## References

- `cub helm install --help` — authoritative flags.
- `https://docs.confighub.com/markdown/guide/helm-charts.md`, `.../guide/rendered-manifests.md`.
- `references/cub-cli.md` — CLI discipline; `--change-desc`; `-o mutations`.
- `references/functions-catalog.md` — post-import customization functions.
- Companion skills: `confighub-core` (config-as-data doctrine, Space topology, granularity), `cub-mutate` (customize), `target-bind` + `cub-apply` + `verify-apply` (deliver), `triggers-and-applygates` (`vet-placeholders` / `standard-vets`).
