---
name: import-from-kustomize
description: 'Use when the user wants to bring a Kustomize overlay or base into ConfigHub as Units — phrases like "I have a kustomization.yaml, how do I use it with ConfigHub?", "import my Kustomize overlays", "migrate from Kustomize to ConfigHub", "render this overlay into ConfigHub", "kustomize build into Units", or "I have a base + overlays directory structure". Runs `kustomize build` locally, splits the result into one or more ConfigHub Units via `cub unit create`, and hands off ongoing customization to `cub-mutate`. Do not load for Flux `Kustomization` CRDs (use `import-from-flux` — that''s the renderer-bridge pipeline), for Helm charts (use `import-from-helm`), for adopting live cluster resources (use `import-from-cluster`), or for authoring raw YAML from scratch (use `config-as-data`).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub function do *) Bash(kustomize build *) Bash(kubectl kustomize *) Bash(mkdir -p /tmp/*) Bash(ls *) Bash(cat *)
---

# import-from-kustomize

Onboarding ramp for users who already have Kustomize overlays and want to start managing them with ConfigHub. Renders the overlay locally via `kustomize build`, stores the result as one or more Units, and from that point forward the user operates on Units, not the `kustomization.yaml` tree.

## Positioning: this is an onboarding tool

This skill exists to meet users where they are — with `base/` + `overlays/` directories — and get them into ConfigHub without forcing a rewrite on day one. The end-state that ConfigHub is built for is **configuration as data** (literal YAML Units + semantic functions for policy and customization across environments), not overlay-driven composition.

Unlike Helm there is no `cub kustomize` subcommand. Kustomize renders happen via the local `kustomize` / `kubectl kustomize` CLI and the result is stored as Units via `cub unit create`. Users comfortable with ConfigHub typically:

- Replace per-overlay `kustomization.yaml` with per-environment Units (cloned from a base Unit) customized via `cub-mutate` functions.
- Drop patch files in favor of named functions (`set-container-image`, `set-replicas`, `set-env-var`, the defaults functions).
- Only re-render from the Kustomize source when an upstream change in the base or overlays warrants it — a structured, logged event, not a daily workflow.

Call this trajectory out in your response so the user understands the destination, not just the first command.

If the user's Kustomize is actually a **Flux `Kustomization` CRD** (i.e., managed by Flux in-cluster, not a local `kustomization.yaml`), hand off to `import-from-flux` — that path uses `cub gitops discover` + `cub gitops import` to insert ConfigHub into the Flux pipeline and preserves Flux's continued role.

Published guide:

- DRY-format rendering model (covers Kustomize): `https://docs.confighub.com/guide/rendered-manifests/`

## When to use

- New-to-ConfigHub user with an existing `base/` + `overlays/` tree in git.
- User has a single `kustomization.yaml` and wants its rendered output in ConfigHub.
- User is evaluating ConfigHub vs. continuing with Kustomize, needs a concrete migration path.

## Do not load for

- Flux `Kustomization` CRDs running in a cluster — use `import-from-flux`.
- Helm charts — use `import-from-helm`.
- Live cluster resources — use `import-from-cluster`.
- Authoring new YAML from scratch — use `config-as-data` directly.

## Preflight gates

1. `cub context get` returns a user.
2. Target Space exists and the user has write permission.
3. `kustomize` or `kubectl kustomize` is on PATH. `kustomize build` and `kubectl kustomize` produce identical output for straightforward overlays; prefer `kustomize` CLI for full feature coverage (plugins, helm inflator, etc.).
4. The overlay path the user points at actually has a `kustomization.yaml`.
5. The per-environment Space layout is decided (`<app>-<env>[-<region>]` slugs per `space-topology`) and, for multi-overlay trees, which overlays map to which env-Spaces.

## Space and Unit granularity — decide before rendering

**Environments belong in different Spaces**, each with its own Target pointing at the appropriate cluster. See `space-topology` for the layout (`<app>-<env>[-<region>]` Space per deployment boundary). Render each overlay into the Space that matches that overlay's environment; the Unit slug inside the Space is what the app is, not which env it's in.

```
overlays/dev      → Space app-a-dev      → Unit(s) named after the workload(s)
overlays/staging  → Space app-a-staging
overlays/prod     → Space app-a-prod
```

Do not render everything into one Space with `-dev` / `-prod` Unit suffixes — that collapses the boundaries that Targets, ApplyGates, and clone-based promotion rely on.

Within each env-Space, pick a Unit-per-what:

| Pattern | What you render | When to use |
|---|---|---|
| One Unit per overlay (recommended onboarding default) | `kustomize build overlays/<env>` → one Unit in `<app>-<env>` | Small-to-medium overlays; gives the user a concrete Unit to customize. |
| One Unit per workload | Split the overlay output per workload (Deployment + Service + ConfigMap bundle) | Large overlays, or when the user needs to govern workloads independently (different ApplyGates, targeted rollouts). Requires more editing post-render; see `import-unit-granularity`. |
| One Unit per resource | Split per document | Rare — only when the user has a specific policy reason (e.g., ConfigMap churn separate from workload churn). |

For onboarding, default to one Unit per overlay per env-Space. The user can split later using `cub unit create` + `cub-mutate` without re-running Kustomize.

### Upstream-linking across env-Spaces (optional)

If the user wants dev→staging→prod promotion with merge-preserving updates, render once and clone:

```bash
# Render the base overlay (or a dev overlay you treat as base) into a base Space.
kustomize build overlays/base > /tmp/kustomize-import/<app>.yaml
cub unit create --space <app>-<base-env> <app> /tmp/kustomize-import/<app>.yaml \
  --change-desc "Import <app> base from Kustomize at <git-ref>. User prompt: <verbatim>. Clarifications: <condensed>"

# Clone into per-env Spaces; edits in the clone survive base re-renders.
cub unit create --space <app>-<staging> <app> --upstream-unit <app>-<base-env>/<app>
cub unit create --space <app>-<prod>    <app> --upstream-unit <app>-<base-env>/<app>
```

This duplicates Kustomize's overlay semantics inside ConfigHub (merge-preserving updates), and moves customization into `cub-mutate` functions / direct edits in the per-env Unit. Alternative: render each overlay separately into its env-Space with no upstream link, if the overlays already differ enough that merging from a common base doesn't make sense.

## The loop

### 1. Inventory the overlays

```bash
ls overlays/         # or whatever the user calls their overlay root
cat overlays/<env>/kustomization.yaml
```

Confirm what you're rendering and catch obvious issues (references to missing bases, secretGenerators that read files that aren't checked in, etc.) before burning cycles.

### 2. Render each overlay (into the matching env-Space's rendered file)

```bash
mkdir -p /tmp/kustomize-import
kustomize build overlays/<env> > /tmp/kustomize-import/<app>.yaml
```

If the user is only on `kubectl` without standalone `kustomize`:

```bash
kubectl kustomize overlays/<env> > /tmp/kustomize-import/<app>.yaml
```

Inspect the output before uploading. Check:

- No `helm template` pass-through artifacts if the overlay includes a Helm inflator (if present, prefer `import-from-helm` instead and manage the chart directly).
- No stale `status:` blocks or `creationTimestamp` fields. Strip with `yq 'del(.status, .metadata.creationTimestamp)'` on a per-document basis if needed.
- Namespace is present on every namespaced resource. Many overlays rely on the `namespace:` transformer; confirm it applied.

### 3. Create the Unit(s) in the env-Space

```bash
cub unit create --space <app>-<env> <app> /tmp/kustomize-import/<app>.yaml \
  --change-desc "Import <app> <env> overlay from Kustomize at <git-ref / commit SHA>.

User prompt: <verbatim>
Clarifications: <condensed, e.g. 'rendered via kustomize v5.4.2 from overlays/<env>'>"
```

Repeat per env-Space — one render + `cub unit create` per overlay. (Or use the upstream-linked pattern above if the user wants merge-preserving promotion between them.)

Record the source reference (git SHA, overlay path) in `--change-desc` — Units don't carry a pointer back to the Kustomize tree otherwise, and future audits will need it.

### 4. Customize via clones + functions, not by re-rendering

From this point on, the overlay is an artifact, not a source of truth. Customizations go through:

- **Cloning** for new environments: `cub unit create --space <app>-<new-env> <app> --upstream-unit <app>-<base-env>/<app>`.
- **Semantic mutations** via `cub-mutate`: `cub function do set-container-image / set-replicas / set-env-var / ...` — these produce named, auditable changes. This is strictly better than adding another overlay and re-rendering.
- **Defaults functions** for policy (resources, probes, security context, namespaces) — see `references/functions-catalog.md`.

If the upstream base or overlay in git changes in a way you need to pull in, re-render that overlay and run the new YAML through `cub unit update --space <app>-<env> <app> <new-rendered.yaml>` with a `--change-desc` explaining the source change. The Unit's merge behavior preserves in-ConfigHub customizations.

### 5. Hand off to apply

From here, `cub-apply` / `verify-delivery` / `reconciliation-check` / `release-verify` take over.

## Tool boundary

- Allowed: `kustomize build`, `kubectl kustomize`, `cub unit create/update`, `cub function do`, read-only `cub unit *` for verification.
- Not allowed: `kubectl apply -k` (that deploys to a cluster bypassing ConfigHub), editing the upstream base / overlays tree as part of this flow (that's a git operation, done outside this skill), `helm template`-inflated overlays without acknowledging that `import-from-helm` is the better path.

## Stop conditions

- The overlay doesn't render (`kustomize build` errors). Report the error verbatim; don't "fix" the overlay as part of this skill.
- The overlay is a Helm inflator — redirect to `import-from-helm`.
- The user wants to keep editing the Kustomize tree as the source of truth long-term. Acknowledge that's possible (Kustomize can be re-rendered into Units indefinitely) but explain the config-as-data trajectory before proceeding — a user committed to Kustomize-as-source may be better served by Flux + `import-from-flux`.

## Verify chain

1. `cub unit list --space <space>` — Units from this import are present.
2. `cub unit get <app> --space <app>-<env> --yaml | diff - /tmp/kustomize-import/<app>-<env>.yaml` — the stored data matches the rendered output.
3. `cub revision list <app> --space <app>-<env>` — Revision 1 exists with the Kustomize-source `--change-desc`.

## Evidence

- `cub unit get <app> --space <app>-<env> --web` — the Unit in the GUI.
- `cub revision list <app> --space <app>-<env> --web` — provenance including the source ref captured in the change-desc.

## References

- `https://docs.confighub.com/guide/rendered-manifests/` — DRY rendering model.
- `references/cub-cli.md` — CLI discipline.
- `references/functions-catalog.md` — which functions replace which kinds of overlay patches.
- Companion skills: `config-as-data` (doctrine), `cub-mutate` (customizing post-render), `cub-apply` (deploy), `import-unit-granularity` (decision helper when the overlay tree is large).
