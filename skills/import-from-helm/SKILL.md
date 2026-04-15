---
name: import-from-helm
description: Use when the user wants to bring a Helm chart under ConfigHub management — phrases like "install cert-manager from Helm", "I have a Helm chart, how do I use it with ConfigHub?", "render this chart into ConfigHub", "cub helm install", "upgrade to the new chart version", "how do I customize a chart without losing changes on upgrade?", or "deploy nginx/prometheus/traefik via Helm through ConfigHub". Runs `cub helm install` / `cub helm upgrade` / `cub helm template`, follows the clone-based customization pattern so upgrades preserve user edits, splits CRDs into their own Unit, and hands off applying to `cub-apply`. Do not load for ArgoCD Application or Flux HelmRelease discovery (use `import-from-argocd` / `import-from-flux` — those insert ConfigHub into an existing GitOps pipeline), for adopting already-deployed live resources (use `import-from-cluster`), or for authoring raw Kubernetes YAML with no chart (use `config-as-data`).
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub helm template *) Bash(cub helm install *) Bash(cub helm upgrade *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub link create *) Bash(helm repo add *) Bash(helm repo update *) Bash(helm repo list) Bash(helm search *)
---

# import-from-helm

Onboarding ramp for users who already have Helm charts and want to start managing them with ConfigHub. Renders the chart into Units via `cub helm install`, then the rest of the skill set takes over (customize via clones, validate via Triggers, apply via `cub-apply`).

## Positioning: this is an onboarding tool

This skill exists to meet users where they are — with an existing Helm workflow — and get them into ConfigHub without forcing a rewrite on day one. The end-state that ConfigHub is built for is **configuration as data** (literal YAML Units + semantic functions for policy and customization), not chart-driven deployment. `cub helm install` produces Units, and from that point forward everything is a Unit; the chart is now a bootstrap input, not an ongoing parameterization surface.

Over time, users comfortable with ConfigHub typically:

- Rely less on chart `values.yaml` and more on `cub-mutate` functions (`set-container-image`, `set-replicas`, `set-env-var`, the defaults functions) applied to the rendered Units.
- Use cloning + linking + needs/provides for multi-environment spread instead of per-env `values-*.yaml` files.
- Only re-run `cub helm upgrade` to bring in upstream chart changes (a structured, logged event), not as a regular configuration workflow.

Call this out in your response so the user understands the trajectory, not just the first command.

Published guides:

- `cub helm` walkthrough: `https://docs.confighub.com/guide/helm-charts/`
- DRY-format rendering model (Helm + Kustomize + GitOps): `https://docs.confighub.com/guide/rendered-manifests/`

## When to use

- New-to-ConfigHub user has an existing Helm workflow and wants to adopt ConfigHub without rewriting.
- User has a chart reference (`jetstack/cert-manager`, `bitnami/nginx`, `prometheus-community/kube-prometheus-stack`) and wants it in ConfigHub.
- User is migrating from raw `helm install` to ConfigHub-managed deployment.
- User wants to upgrade a chart version that's already a Unit.
- User asks "how do I customize a chart", "how do I parameterize across environments", or "how do I not lose my changes on upgrade". Answer the immediate question, then note the config-as-data path as the longer-term direction.

## Do not load for

- ArgoCD `Application` discovery — use `import-from-argocd` (inserts ConfigHub into the Argo pipeline via `cub gitops import`).
- Flux `HelmRelease` discovery — use `import-from-flux` (same flow with Flux).
- Adopting already-deployed cluster resources that weren't installed via Helm — use `import-from-cluster` (`cub unit import`).
- Editing rendered YAML by hand (use `cub-mutate` on the clone, never the base).

## Preflight gates

1. `cub context get` returns a user.
2. Target Space exists (`cub space list`). User has write permission.
3. `helm` is on PATH — `cub helm` shells out to it for template rendering.
4. The chart's Helm repo is already added (`helm repo list`). If not, add it: `helm repo add <name> <url> --force-update` and `helm repo update`.
5. Chart version is decided and pinned. Never install a chart without `--version` — unpinned charts make future upgrades hard to audit.
6. Decide namespace strategy (below) before running install.

## Namespace strategy — default to `--namespace <ns>`

Always pass `--namespace <ns>` unless the user has a specific reason not to. Many real-world Helm charts do surprising things with namespace values — hardcoded references inside ConfigMaps / Secrets / cross-service URLs, templates that compute `.Release.Namespace` into Service hostnames, RoleBinding subjects that reference `system:serviceaccount:<ns>:<sa>`, etc. With `--namespace`, the chart renders as it would when installed with `helm install` directly, and ConfigHub stores the literal result. Predictable and debuggable.

**Different environments belong in different Spaces**, each attached to its own Target that points at the appropriate cluster/namespace. See `space-topology` for the layout (`<app>-<env>[-<region>]` Space per deployment boundary). Two patterns, picked by what the user has today:

### Pattern A — per-env `cub helm install` (use if the user has per-env values files)

If the user already runs `helm install -f values-dev.yaml` / `-f values-prod.yaml` / etc., preserve that workflow: run one `cub helm install` per env-Space, passing the env's values file. This keeps their existing DRY source of truth in the values files.

```bash
cub helm install <release> <repo>/<chart> \
  --space <app>-<dev>     --namespace <ns> --version <ver> --values values-dev.yaml
cub helm install <release> <repo>/<chart> \
  --space <app>-<staging> --namespace <ns> --version <ver> --values values-staging.yaml
cub helm install <release> <repo>/<chart> \
  --space <app>-<prod>    --namespace <ns> --version <ver> --values values-prod.yaml
```

Unit slug stays `<release>` in every Space; the Space itself encodes the environment. For upgrades, run `cub helm upgrade` the same way in each Space with the same values files (and whichever new `--version`). The user can gradually migrate values out of files and into `cub-mutate` functions as they learn ConfigHub.

### Pattern B — single install + clones (use if the user has a single values shape)

If the user has no per-env values files and wants to customize per-env through ConfigHub rather than through more values files, install once into a base Space and clone per env. The clones keep an `--upstream-unit` link to the base, so `cub helm upgrade` on the base propagates via `cub unit update --upgrade` while preserving per-env edits.

```bash
# Install once into the base Space.
cub helm install <release> <repo>/<chart> \
  --space <app>-<base-env> --namespace <ns> --version <ver>

# Clone per env-Space.
cub unit create --space <app>-<staging> <release> --upstream-unit <app>-<base-env>/<release>
cub unit create --space <app>-<prod>    <release> --upstream-unit <app>-<base-env>/<release>
```

### Slug naming (both patterns)

Unit slug stays `<release>` in every Space; the Space encodes the environment. Do not suffix Unit slugs with `-dev` / `-prod` — that collapses the Space boundaries (see `space-topology` anti-patterns).

`--use-placeholder` (renders `namespace: confighubplaceholder` and expects resolution via `cub link create` into a namespace Unit) exists and is tempting for clean multi-env abstraction, but avoid it as the default: it only works cleanly for charts without internal namespace references, which rules out many popular charts. Reach for it only when the user is familiar with ConfigHub's needs/provides mechanism, knows the chart doesn't bake the namespace into data, and has a `vet-placeholders` strategy in mind.

If `vet-placeholders` is installed in the target Space (see `triggers-and-applygates`), a Unit holding `confighubplaceholder` cannot apply until resolved — one more reason to default to `--namespace`.

## The loop

### 1. Confirm the repo + chart + version

```bash
helm repo list                              # confirm the repo is added
helm search repo <repo>/<chart> --versions  # confirm the version exists
```

If the repo isn't added, add it and update:

```bash
helm repo add <repo> <url> --force-update
helm repo update
```

### 2. Render into ConfigHub Units

```bash
cub helm install <release> <repo>/<chart> \
  --space <space> \
  --namespace <ns> \
  --version <pinned-version> \
  [--values <file>] \
  [--set key=value]
```

This creates one or two Units:

- `<release>` — main resources (+ Namespace if `--namespace` was supplied).
- `<release>-crds` — CRDs from the chart's `crds/` directory, if any.

Verify:

```bash
cub unit list --space <space> --where "Labels.helmrelease = '<release>'"
```

`cub helm` does NOT accept `--change-desc` — the chart provenance (release name, repo/chart, version) is recorded as Unit labels. If the user needs a human-readable note, follow up with a no-op `cub function do set-annotation` on the created Units with `--change-desc` describing the install's motivation.

### 3. Per-env Spaces — pattern-dependent

**Pattern A — per-env `cub helm install`.** Nothing more to do here: step 2 was already run once per env-Space with the env's values file. Each Space contains a `<release>` Unit rendered from that env's values. Customizations post-render still go through `cub-mutate`; edits made directly to these Units will be clobbered by the next `cub helm upgrade` in that Space unless they round-trip back into the values file.

**Pattern B — clone from base.** Clone the base `<release>` Unit into each env-Space:

```bash
cub unit create --space <app>-<staging> <release> --upstream-unit <app>-<base-env>/<release>
cub unit create --space <app>-<prod>    <release> --upstream-unit <app>-<base-env>/<release>
```

Or clone the entire base Space in one call (useful when the chart produced multiple Units — base + crds):

```bash
cub unit create --dest-space <app>-<env> --space <app>-<base-env>
```

**Never edit the base Unit in Pattern B.** Edits on the base are clobbered by the next `cub helm upgrade`. Apply customizations to the clone via `cub-mutate` (functions) or `cub unit update` with a proper `--change-desc`. Each clone keeps the `--upstream-unit` link, which is what makes `cub helm upgrade` on the base propagate through `cub unit update --upgrade` on the clones while preserving per-env edits.

### 4. Hand off to apply

Apply order matters when CRDs are present:

```bash
# CRDs first (from whichever Space they live in), wait for establishment, then main
# (from the env-specific Space).
cub unit apply <release>-crds --space <app>-<base-env> --wait
kubectl wait --for=condition=established --timeout=60s \
  crd/<some-crd-from-this-chart>
cub unit apply <release> --space <app>-<env> --wait
```

From here, `cub-apply` / `verify-delivery` / `reconciliation-check` / `release-verify` take over.

## Upgrade loop

When a new chart version is released:

**Pattern A — per-env values files.** Run `cub helm upgrade` once per env-Space with the same values file used at install:

```bash
for env in dev staging prod; do
  cub helm upgrade <release> <repo>/<chart> \
    --space "<app>-$env" \
    --version <new-version> \
    --values "values-$env.yaml" \
    [--update-crds]
done
```

Each Space gets a re-rendered `<release>` Unit at the new version with that env's values; apply per env via `cub-apply`.

**Pattern B — upstream-linked clones.** Upgrade the base, then propagate via `cub unit update --upgrade` in each env-Space:

```bash
# 1. Re-render the base Unit (in the base Space) at the new version.
cub helm upgrade <release> <repo>/<chart> \
  --space <app>-<base-env> \
  --version <new-version> \
  [--update-crds] \
  [--values <file>]

# 2. Propagate into each env-Space clone — merge preserves clone edits.
for s in <app>-<staging> <app>-<prod>; do
  cub unit update <release> --space "$s" --upgrade \
    --change-desc "Upgrade <release> to <new-version>.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>"
done

# 3. Review, apply via cub-apply (per-env rollout).
cub unit diff <release> --space <app>-<staging>
```

`--update-crds` is off by default on `cub helm upgrade`. Set it explicitly when the chart's CRD schemas changed and you want the upgrade to bring them in; otherwise skip to avoid surprise CRD changes.

## Tool boundary

- Allowed: `cub helm install/upgrade/template`, `cub unit create/update`, `cub link create`, `helm repo add/update/list`, `helm search`.
- Read-only diagnosis: `cub unit get/list/diff/tree`, `cub function explain`.
- Not allowed: `helm install` (the Helm CLI install path, which would actually deploy to a cluster and bypass ConfigHub), editing the base Unit, `cub helm upgrade` on a chart installed outside ConfigHub.

## Stop conditions

- The chart's repo isn't added and the user can't / won't add it (cub helm has nowhere to resolve the chart from).
- User wants to install without `--version`. Push back: unpinned installs make future audits impossible.
- User asks to edit the base `<release>` Unit directly. Explain the clone pattern; offer to create the clone and move the edit there.
- `cub helm install` would create a Unit that collides with an existing Unit of the same slug in the Space — confirm whether the user intended an upgrade instead.

## Verify chain

1. `cub unit list --space <space> --where "Labels.helmrelease = '<release>'"` — both base and CRDs Units present.
2. `cub unit get <release> --space <space>` — `Labels` include `helmrelease=<release>`, `helmchart=<repo>/<chart>`, `helmversion=<pinned>` (exact label keys may vary — verify with `--json`).
3. `cub unit diff <release> <app>-<base-env>/<release> --space <app>-<env>` — shows per-env clone's customizations as a diff against the base-Space release.
4. After upgrade: `cub revision list <release> --space <space>` — revision N+1 appears with the new chart version.

## Evidence

- `cub unit get <release> --space <space> --web` — base Unit in the GUI.
- `cub unit get <release> --space <app>-<env> --web` — per-env clone with customizations.
- `cub revision list <release> --space <space> --web` — version-upgrade history.

## References

- `https://docs.confighub.com/guide/helm-charts/` — canonical walkthrough.
- `https://docs.confighub.com/guide/rendered-manifests/` — DRY rendering model across Helm / Kustomize / GitOps.
- `references/cub-cli.md` — CLI discipline, `--change-desc`, `--display-mutations`.
- `references/yaml-patterns.md` — needs/provides for placeholder resolution.
- Companion skills: `space-topology` (where the base + per-env Spaces go), `config-as-data` (doctrine), `cub-mutate` (customizing the clone), `cub-apply` (deploy), `triggers-and-applygates` (vet-placeholders gate).
