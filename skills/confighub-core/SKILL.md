---
name: confighub-core
description: 'ConfigHub orientation and routing: vocabulary, Component/Variant/Release, Space layout, literal config-as-data, one resource per Unit, and delete/destroy gates. Use for tours, entity questions, topology, granularity, or broad help. Route obvious image edits to cub-mutate and searches to cub-query.'
phase: cross-cutting
allowed-tools: []
read-capability-subset: confighub-core
---

# confighub-core

**Authority boundary:** this companion is knowledge/read-only. It may inspect and prepare an exact proposal, but it must not execute create, update, approve, promote, publish, withdraw, install, or delete operations. The external mutation broker is `NOT_INTEGRATED`, so every mutation path ends in `ASK` or `BLOCK`.

The foundational skill. Explains ConfigHub's model in plain language, carries the load-bearing doctrine (config-as-data authoring, Space topology, one resource per Unit), covers delete/destroy gates, and routes concrete tasks to the right dedicated skill.

Load this first when the intent is broad. Hand off as soon as the task is concrete.

## When to use

- User is new to ConfigHub or asks for a tour ("how does ConfigHub work?").
- User asks what an entity is or how two relate (Target vs Worker, Trigger vs Filter, upstream vs downstream).
- User is **authoring** new config and is about to reach for Helm / Kustomize / Jsonnet / a values file — apply the config-as-data rule below.
- User is deciding **how to lay out Spaces** across dev/staging/prod, regions, or clusters.
- User asks **how many Units** a pile of resources should become ("one Unit or many?").
- User wants to **protect** a Space/Unit from accidental delete or destroy.

## Do not load for

- A task that already has an obvious dedicated skill — route instead (see Routing).
- Deep product-support questions that belong in docs (`https://docs.confighub.com/`), not a skill.

## Confirm before you compose

Never compose `cub` commands from memory. Confirm the verb and flags with `cub <verb> --help` (or `CONFIGHUB_AGENT=1 cub <verb> --help`) before a read or mutation proposal. Help is read-only; confirmation does not grant mutation authority.

## The model in one minute

ConfigHub treats configuration as **data**: fully materialized YAML stored in a versioned database, not code or templates. Mutations go through server-side **functions** on that data. Delivery, policy, and audit all hang off that model.

- **Space** — container for Units. One Space per deployment boundary (app × environment[, region/cluster]). Labels slice across them.
- **Unit** — a versioned, atomic chunk of configuration. Default: **one Kubernetes resource per Unit** (see below). Applied as a single operation.
- **Revision** — every Unit mutation produces a new Revision carrying its `--change-desc` and the data diff.
- **Function** — server-side operation over config data: getters (`get-container-image`), setters (`set-container-image`, `set-replicas`), defaults (`set-container-resources-defaults`), validators (`vet-schemas`, `vet-cel`), helpers (`yq`, `yq-i`).
- **Trigger** — a function (usually a validator) wired to fire automatically on `Mutation` or `PostClone`. A failing validator attaches an **ApplyGate**.
- **Filter** — a saved query. Filters over Units power bulk ops; Filters over Triggers attach to a Space via `TriggerFilterID`.
- **Link** — a relationship between Units whose resources reference each other (a Deployment's `serviceAccountName` → a ServiceAccount Unit). Enables cross-Unit integrity and needs/provides.
- **Target** — a delivery binding. In the current Release model, a Space's `ReleaseTargetID` names one **OCI** Target and effective Units carry the same TargetID; Argo CD/Flux consumes the resulting OCI manifest. Earlier ProviderType `ConfigHub` delivery is `VERSIONED_LEGACY/BLOCK`.
- **Worker** — backs Target or custom-function operations. Built-in OCI Release delivery uses a **server-worker entity**, so no external process runs. Run an external worker only to host custom worker functions.
- **ApplyGate** — a block on apply from a failing Trigger or an approval requirement. Fix the data or the rule; never bypass.

### Operational invariants

- **Data is authoritative.** Edit the data, not a template. Re-rendering is an import-time convenience, not an ongoing workflow.
- **Mutations go through `cub`.** `kubectl` / `argocd` / `flux` are read-only for diagnosis.
- **Every Unit-data mutation carries `--change-desc`** (summary line, verbatim user prompt, condensed clarifications).
- **Every mutating call passes `-o mutations`** to show the diff inline.
- **Critical entities carry Delete Gates (and, for Units, Destroy Gates).**

## Configuration as data — the authoring doctrine

A Unit contains **fully materialized YAML with literal values for every field**. Code (functions) operates on data; data is the record. This is what makes ConfigHub's query, validation, mutation-graph, and revision-history features work — templated or re-rendered Units break all of them.

If you're tempted to reach for Helm, Kustomize, Jsonnet, cdk8s, or a values file to **author** new config, stop. Those are one-shot onboarding ramps (the `import` skill), not an ongoing format.

### The authoring loop

1. **Check for an example.** `cub unit get <example-slug> --space skill-examples -o yaml` — `skill-examples-bootstrap` seeds Units for common resource types. Adapt one if it fits.
2. **Produce literal YAML.** Scaffold with `kubectl create … --dry-run=client -o yaml | yq 'del(.metadata.creationTimestamp, .status)'`, then hand-author the fields `kubectl` won't generate. Never template. Use `confighubplaceholder` (strings) / `999999999` (numbers) for values supplied later — `vet-placeholders` blocks apply while any remain. For specific resource types, hand off to `kubernetes-resources`.
3. **Store it.** `cub unit create --space <space> <unit-slug> file.yaml --change-desc "…"`.
4. **Fill defaults via functions, not by hand** — hermetic, idempotent, clean revision: `set-container-resources-defaults`, `set-container-probe-defaults`, `set-pod-container-security-context-defaults` (Namespaces: `set-pod-security-defaults`; guarantee `namespace:` with `ensure-namespaces`).
5. **Vary across environments via Spaces, not templates.** One Space per env; clone baseline upstream→downstream; apply differences with `set-container-image`, `set-replicas`, `set-env-var`. The Space is the parameterization boundary — never a values file or overlay.

If the user insists on keeping a values file or template inside a Unit, explain the rule once; if they still want it, stop — this isn't the skill for that.

## One resource per Unit

**Default: one Kubernetes resource per Unit.** It keeps revisions, ApplyGates, diffs, and blast radius scoped to a single resource, and makes promotion and rollback surgical. A multi-workload app becomes one Unit per workload + one per Service/ConfigMap/etc., not one mega-Unit.

Two facts that follow naturally:

- **CRDs always stand alone.** A CustomResourceDefinition must be applied and established before any custom resource that references it, and it has a wider blast radius (deleting a CRD cascades to every CR). One resource per Unit already gives this for free. Slug convention: `<app>-crds`.
- **Generator imports may start coarser.** `cub helm install` and similar render a bundle and split CRDs automatically; the `import` skill owns that. You can split further afterward, but for new authoring, one resource per Unit is the rule — don't hand-bundle.

## Space topology

**One Space per deployment boundary** — anything you independently promote, approve, apply, or roll back. For most teams that's `(app, environment)` or `(app, environment, region/cluster)`.

Corollary: **environments are Spaces, not slug suffixes.** Don't put `web-dev` and `web-prod` in one Space — that collapses Target separation, ApplyGate/approval scoping, and clone-based promotion.

### Canonical layout

```
platform                ← org-wide Triggers + Filters (no workloads)
app-a-home              ← app team's home: ChangeSets, Tags, Filters, Views, Invocations
app-a-dev               ← (app, env[, region/cluster]) deployment Spaces
app-a-staging
app-a-prod-us-east
shared-infra-prod       ← cluster-wide things (ingress, cert-manager, observability)
```

- **`platform`** — baseline `vet-*` / CEL / approval Triggers + the Filters that select them. App Spaces attach via `--trigger-filter platform/standard-vets`. No workloads.
- **`<app>-home`** — neutral, app-team-scoped home for cross-environment operational artifacts (ChangeSets spanning dev→prod, Tags, the `<app>-app` Filter, Views, Invocations). No workload Units. Referenced cross-Space by slug: `--filter <app>-home/<slug>`, `--changeset <app>-home/<slug>`.
- **Deployment Spaces** — one per `(app, env[, region/cluster])`. Add region/cluster suffixes only when you deploy separately per region.
- **Shared infrastructure** — its own per-env Space, same pattern.

### Naming and labels

Slug: **`<app>-<env>[-<region-or-cluster>]`**, lowercase, hyphenated. Reserve `platform`. Don't encode `space-`/`config-`/`cub-` in slugs. Put structured metadata on the **Space** (not the slug) with **PascalCase, non-abbreviated** keys:

```bash
cub space update app-a-prod-us-east \
  --label Application=app-a --label Environment=prod \
  --label Region=us-east --label Cluster=prod-us-east-1
```

This enables cross-Space queries slug-parsing can't: `cub unit list --space "*" --where "Space.Labels.Environment = 'prod'"`. Recommended set: `Application`, `Environment`, plus `Region` / `Cluster` / `Tier` when relevant.

### Workers and Targets

Current Space Release delivery uses an **OCI Target** backed by a server-worker entity; no external worker process runs for that built-in path. The deployment Space's `ReleaseTargetID` names the OCI Target, and the Release includes Units whose TargetID matches it. Argo CD or Flux pulls the OCI manifest and converges the cluster outside ConfigHub. External workers remain available for custom functions. Earlier bridge/per-Unit and direct ConfigHub-provider delivery are preserved as `VERSIONED_LEGACY/BLOCK`, not current Release paths. See `worker-bootstrap`, `target-bind`, and `release-publish`.

### Promotion

```bash
cub unit create --dest-space app-a-staging --space app-a-dev      # clone a Space forward
cub unit create --space app-a-staging <unit> --upstream-unit app-a-dev/<unit>   # single Unit
cub unit update --space app-a-staging <unit> --upgrade            # later, pull upstream changes
```

The `upstream-unit` link makes `--upgrade` propagate while preserving per-Space customizations. Note: a Link points downstream→upstream (dependency edge), the **opposite** of data-flow direction. For the full promotion arc, use `promote-release`.

## Delete Gates and Destroy Gates

ConfigHub makes bulk and cross-Space operations easy — which is also how you accidentally delete a prod Space or destroy live resources. Gates are the opt-in protection (`https://docs.confighub.com/markdown/guide/protecting.md`).

- **Delete Gates** — on any entity. Block `cub <entity> delete` until removed.
- **Destroy Gates** — **Units only**. Protect a Unit's destructive lifecycle operation. Orthogonal to Delete Gates; verify the active CLI before any destructive proposal.

```bash
# Unit — protect prod data and its live resources.
cub unit update --patch --space <app>-prod <unit> --delete-gate prod-critical --destroy-gate prod-critical
# Space — delete only (Spaces have no destroy).
cub space update --patch <space> --delete-gate used-until-dec25
# Remove with the '-' sentinel (empty string won't clear), then delete.
cub space update --patch <space> --delete-gate used-until-dec25=-
```

The gate **name carries the why** — prefer specific (`used-until-dec25`, `team-payments-owns`, `in-use-by-argocd`) over a generic `critical` everywhere. Gates stack; all must be removed. Recommend a gate in the same turn you create any prod-bound Space/Unit, shared-infra Space, platform Trigger/Filter, or hard-to-replace Worker.

## Routing — pick the right skill

| User intent | Skill |
| --- | --- |
| Authoring a specific K8s resource type (StatefulSet, Ingress, NetworkPolicy, …) | `kubernetes-resources` |
| App config files (.env / .properties / .yaml) → ConfigMap | `app-config` |
| Validation/policy that actually blocks bad config | `triggers-and-applygates` |
| Changing data in an existing Unit (image, replicas, env, defaults) | `cub-mutate` |
| Finding, listing, auditing, inspecting config across Units/Spaces | `cub-query` |
| A playground Space to tinker with | `skill-examples-bootstrap` |
| Setting up a worker (server worker for delivery; external for custom functions) | `worker-bootstrap` |
| Creating a Target / binding a Unit to one | `target-bind` |
| Applying/deploying a Unit or set (prepare an exact whole-Space OCI Release proposal) | `release-publish` |
| Post-apply verification, troubleshooting, close-out | `verify-apply` |
| Onboarding existing Helm / Kustomize config | `import` |
| Promoting a release env-to-env or fleet-wide; variants | `promote-release` |
| Rolling back by moving head | `rollback-revision` |
| Orchestrating a production incident | `incident-management` |

## Tool boundary

- Orientation/doctrine: read-only. Hand off the task to the dedicated skill.
- Authoring (when this skill does it): `cub unit create/update`, `cub function …`, `cub run`, `cub link …` (always `--change-desc` + `-o mutations`); `cub space create/update`; `kubectl create --dry-run=client` / `kubectl explain` for scaffolding only.
- Not allowed: `helm install/upgrade`, `kustomize build` piped into ongoing editing, values files, template syntax inside a Unit, mutating `kubectl`/`argocd`/`flux`.

## Change description

Every mutation passes `--change-desc`:

```
<summary line>

User prompt: <verbatim user prompt>
Clarifications: <one line per resolved ambiguity, or "none">
```

## Stop conditions

- Intent is concrete enough to route — hand off and exit.
- User insists on a template/values file in a Unit, or product depth that belongs in docs.

## Verify chain

- Authoring: `cub unit get <slug> --space <space>` — confirm literal YAML; run `vet-placeholders` / `vet-schemas` / `vet-format` (or rely on the Space's Triggers).
- Topology: `cub space list`; `cub space get <space> -o json` (labels); a cross-Space `--where "Space.Labels.X = ..."` query returns the expected set.

## Evidence

- `cub unit open <unit> --space <space> --print-url`, `cub space open <space> --print-url`, `cub component open <component> --print-url` — verified GUI handoffs.
- Docs: `https://docs.confighub.com/markdown/index.md`; SDK: `https://github.com/confighub/sdk`.

## References

- `references/cub-cli.md` — CLI discipline, Read/Write permission sets, `--change-desc`, `-o mutations`, `--where` AND-only, `--trigger-filter` / `--where-trigger`.
- `references/functions-catalog.md` — the function surface.
- `references/filters-and-queries.md` — query vocabulary.
- `references/triggers-recipes.md` — platform-Space pattern.
- `references/yaml-patterns.md` — literal-value authoring for all common resource types.
- `https://docs.confighub.com/markdown/background/config-as-data.md`, `.../guide/environments.md`, `.../guide/protecting.md`.
