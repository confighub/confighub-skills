---
name: confighub-core
description: 'ConfigHub orientation and routing: vocabulary, the component model (Component / Variant / base / deployment), config-as-data, one resource per Unit, protection and merges, and delete/destroy gates. Use for tours, entity questions, topology, granularity, or broad help. Route concrete tasks to the dedicated skill.'
phase: cross-cutting
allowed-tools: []
read-capability-subset: confighub-core
---

# confighub-core

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. Route a concrete change to its owning Skill; in standalone use that Skill submits one exact requested write to the host permission system, while an external overlay may impose a stricter stop.

The foundational skill: **concepts and routing**. It explains ConfigHub's model, carries the doctrine that every other skill assumes (config as data, one resource per Unit, the component model, opt-in protection), and hands the concrete task to the skill that owns it.

Load this first when the intent is broad. Hand off as soon as the task is concrete — the recipes live in the dedicated skills, not here.

## When to use

- User is new to ConfigHub or asks for a tour ("how does ConfigHub work?").
- User asks what an entity is or how two relate (Component vs Variant vs Space, Target vs Worker, Trigger vs Filter, upstream vs downstream).
- User is **authoring** new config and is about to reach for Helm / Kustomize / Jsonnet / a values file — apply the config-as-data rule below, then route.
- User is deciding **how to organize Spaces** across environments, regions, clusters, or tenants.
- User asks **how many Units** a pile of resources should become ("one Unit or many?").
- User wants to **protect** a Space/Unit from accidental delete or destroy, or asks what "protected path" means.

## Do not load for

- A task that already has an obvious dedicated skill — route instead (see Routing).
- Deep product-support questions that belong in docs (`https://docs.confighub.com/`), not a skill.

## Confirm before you compose

Never compose `cub` commands from memory. Confirm the verb and flags with `cub <verb> --help` before a read or requested mutation. Help is read-only; confirmation does not grant mutation permission.

## The model in one minute

ConfigHub treats configuration as **data**: fully materialized YAML stored in a versioned database, not code or templates. Mutations go through server-side **functions** on that data. Delivery, policy, and audit all hang off that model.

- **Component** — a logical piece of software and the configuration that describes how it runs, tracked across every place it is deployed. Not a stored entity: it is the set of Spaces sharing a `Component` label value. See [the component model](#the-component-model).
- **Variant** — one complete copy of a Component's configuration, implemented as a **Space**. Either a **base** (no Target; exists to be cloned from) or a **deployment** (has a Target; can be released).
- **Space** — container for Units, and the unit of variant identity. Labels (`Component`, `Variant`, `Environment`, `Region`, `Layer`, `Owner`) slice across them.
- **Unit** — a versioned, atomic chunk of configuration. Default: **one Kubernetes resource per Unit** (see below).
- **Revision** — every Unit mutation produces a new Revision carrying its `--change-desc` and the data diff. **Revision 1 is an empty start revision**; a Unit's created content lands on Revision 2.
- **Function** — server-side operation over config data: getters (`get-container-image`), setters (`set-container-image`, `set-replicas`), defaults (`set-container-resources-defaults`), validators (`vet-schemas`, `vet-cel`), escape hatches (`get-yq` to read, `set-yq` to write). Invoke by kind: `cub function get` (non-mutating), `cub function set` (mutating), `cub function vet` (validating).
- **MutationSources** — a per-path record of which change last set each value in a Unit, and whether that path is **protected**. This is what a merge consults to decide what it may overwrite. `cub unit get <slug> -o mutations` renders it.
- **Conflict** — a change a merge brought but could not apply (a protected path, an unlocatable path, a failed replay). It is recorded on the Unit and stays there until applied or dismissed with `cub unit conflicts`.
- **Trigger** — a function (usually a validator) wired to fire automatically on `Mutation` or `PostClone`. A failing validator attaches an **ApplyGate**.
- **Filter** — a saved query. Filters over Units power bulk ops; Filters over Triggers attach to a Space via `TriggerFilterID`.
- **Link** — a relationship between Units whose resources reference each other (a Deployment's `serviceAccountName` → a ServiceAccount Unit). Enables cross-Unit integrity, needs/provides, and — as an `UpgradeUnit` Link — the upstream relationship a promotion merges along.
- **ChangeSet** — a name for a set of revisions across many Units, and the practical way to undo a promotion. See [ChangeSets](#changesets-name-the-change-you-may-need-to-undo).
- **Target** — a delivery binding. In the current Release model, a Space's `ReleaseTargetID` names one **OCI** Target and effective Units carry the same TargetID; Argo CD/Flux consumes the resulting OCI manifest. Earlier ProviderType `ConfigHub` delivery is historical and unsupported in the reviewed current profile.
- **Worker** — backs Target or custom-function operations. Built-in OCI Release delivery uses a **server-worker entity**, so no external process runs. Run an external worker only to host custom worker functions.
- **ApplyGate** — a block on publish from a failing Trigger or an approval requirement. Fix the data or the rule; never bypass.

### Operational invariants

- **Data is authoritative.** Edit the data, not a template. Re-rendering is an onboarding convenience, not an ongoing workflow.
- **Mutations go through `cub`.** `kubectl` / `argocd` / `flux` are read-only for diagnosis.
- **Every Unit-data mutation carries a short safe `--change-desc` summary** as defined in `references/execution-modes.md`; never interpolate the verbatim prompt into shell text.
- **Every mutating call passes `-o mutations`** to show the diff inline.
- **Protection is opt-in.** A change claims nothing unless it passes `--protect`.
- **Critical entities carry Delete Gates (and, for Units, Destroy Gates).**

## Configuration as data — the authoring doctrine

A Unit contains **fully materialized YAML with literal values for every field**. Code (functions) operates on data; data is the record. This is what makes ConfigHub's query, validation, mutation-graph, and revision-history features work — templated or re-rendered Units break all of them.

If you're tempted to reach for Helm, Kustomize, Jsonnet, cdk8s, or a values file to **author** new config, stop. Those are onboarding ramps (the `import` skill), not an ongoing format.

Two rules follow, and both are owned elsewhere:

- **Author literal YAML, then fill defaults with functions** rather than by hand — `set-container-resources-defaults`, `set-container-probe-defaults`, `set-pod-container-security-context-defaults`, `ensure-namespaces`. Use `confighubplaceholder` (strings) / `999999999` (numbers) for values supplied later; `vet-placeholders` blocks publish while any remain. The step-by-step loop is in **`kubernetes-resources`**.
- **Vary across deployments via variants, not templates.** The variant Space is the parameterization boundary — never a values file or overlay. The mechanics are in **`promote-release`**.

If the user insists on keeping a values file or template inside a Unit, explain the rule once; if they still want it, stop — this isn't the skill for that.

## One resource per Unit

**Default: one Kubernetes resource per Unit.** It keeps revisions, ApplyGates, diffs, and blast radius scoped to a single resource, and makes promotion and rollback surgical. A multi-workload app becomes one Unit per workload plus one per Service/ConfigMap/etc., not one mega-Unit. `cub variant upload --granularity per-resource` produces exactly this.

Two facts that follow naturally:

- **CRDs always stand alone.** A CustomResourceDefinition must be applied and established before any custom resource that references it, and it has a wider blast radius (deleting a CRD cascades to every CR). One resource per Unit already gives this for free.
- **Generator imports may start coarser.** The `import` skill owns rendering a bundle into Units, and `cub variant upload`'s default `minimal` granularity packs a whole render into one Unit with CRDs and AppConfig files split out. You can split further afterward, but for new authoring, one resource per Unit is the rule — don't hand-bundle.

## The component model

A **Component** is a logical piece of software — an application, a service, a workload, a piece of infrastructure — together with the configuration that describes how it runs. It is not tied to any deployment. The same component is normally deployed many times, and each deployment has its own complete copy of the configuration. Each such copy is a **variant**.

Variants come in two kinds:

- A **base** is a variant not meant to be deployed. It exists to be cloned. It holds complete configuration, with deployment-specific values usually left as placeholders. **A base has no Target** — that is what makes it a base.
- A **deployment** is a variant meant to be deployed to a Target. It is typically cloned from a base, with placeholders replaced by concrete values.

A component can have several bases and several deployments — a root base, a prod base and a non-prod base cloned from it, deployments cloned from those. The relationships form a **tree**: a variant has at most one upstream.

### How it is represented

A component is a convention over Spaces and labels, not a stored entity:

- Each **variant is a Space**. The Units in that Space are the whole of that variant's configuration.
- The **component** is the group of Spaces sharing a `Component` label value; `Variant` names each variant within it. The recommended Space slug is `{{.Labels.Component}}-{{.Labels.Variant}}` — `web-app-prod-us`. `Environment`, `Region`, `Layer`, and `Owner` capture the other dimensions.
- Base vs deployment is decided by whether the Space's Units have a Target.
- Upstream/downstream is maintained **per Unit**, via each clone's upstream reference and its `UpgradeUnit` Link. Note the direction gotcha: a Link points downstream→upstream (a dependency edge), the **opposite** of data-flow direction.

Because the implementation is Spaces, Units, and labels, everything that operates on those works across components: a Filter on `Labels.Component = 'web-app'` selects every variant of the app, and `Labels.Environment = 'prod'` cuts across components to select every production deployment.

```bash
cub space update web-app-prod-us \
  --label Component=web-app --label Variant=prod-us \
  --label Environment=Prod --label Region=us-east2
```

### The component/target matrix

Components on one axis, deployment targets (environments, regions, clusters, tenants) on the other. Each populated cell is a deployment variant; the bases sit alongside as the sources the deployments are cloned from. The matrix is rarely full — a component deployed in one region only occupies one cell.

| Component | Base | Dev | Staging | Prod (us) | Prod (eu) |
|---|---|---|---|---|---|
| web-app | ✓ | ✓ | ✓ | ✓ | ✓ |
| inference-engine | ✓ | ✓ | | ✓ | |
| docs-site | ✓ | | | ✓ | |

### One component or two?

Variants of a component are meant to be alike: the same logical software adapted to different deployment contexts. If two variants differ wildly — different resource types, different topology, little shared configuration — they are probably not the same piece of software and should be split into separate components. **The test:** would a change to the component normally need to flow to all of its variants?

### Commands

`cub variant` operates at the variant level; `cub component` is a read/navigate view over the labels.

```text
cub variant upload   # seed a base from rendered manifests, stamping Component/Variant labels
cub variant create   # clone a variant into a new downstream variant, attaching a Target
cub variant promote  # bring a downstream variant up to date with its upstream
cub component list   # the components in the org (equivalently: cub space list --where "Labels.Component = '<name>'")
```

Prefer these over hand-rolling the same thing out of `cub space create` + `cub unit create`. The full workflow — including what promotion merges and what it withholds — is **`promote-release`**.

### Alongside the variants

Two Spaces hold things that are not a variant of anything:

- **`platform`** — org-wide `vet-*` / CEL / approval Triggers plus the Filters that select them. Variant Spaces attach via `--trigger-filter platform/standard-vets`. No workloads. See `triggers-and-applygates`.
- **`<component>-home`** — the team's home for cross-variant operational artifacts: ChangeSets spanning dev→prod, Tags, the component's Filter, Views, Invocations. No workload Units. Referenced cross-Space by slug: `--filter <component>-home/<slug>`, `--changeset <component>-home/<slug>`.

## Protection: which values a variant owns

A variant exists to differ from its base. Every promotion asks which of those differences are the variant's to keep — and ConfigHub answers per path, from what someone said, not by guessing from the data.

**Protection is opt-in.** An ordinary change — a hand edit, a function invocation, a Trigger, a needs/provides binding — leaves each path it writes as protected as it found it, and content arriving from a clone, an upgrade, or a merge is recorded unprotected. So **by default an upstream change reaches the variant even if someone here had set that path to something else.** That is right for a value the variant is only carrying; it is wrong for a value the variant chose.

Say a value is this variant's own, either as you write it (`--protect`) or afterwards per path (`cub unit set-protection --protect`). Read what a Unit currently protects with `cub unit get <slug> -o mutations`. What a merge withheld to honor protection is recorded as a **conflict**, listed and resolved with `cub unit conflicts`.

The mechanics, flag forms, and conflict reasons are in `references/cub-cli.md` → "Protection and merge conflicts"; the promotion workflow is in `promote-release`.

## ChangeSets: name the change you may need to undo

An upgrade or promotion now **walks** its range by default, recording one downstream revision per upstream revision that had an effect there — so a variant's history reads like the upstream's. That is good for audit and bad for "restore to just before the promotion," because there is no single revision number to name.

Wrap any multi-Unit change — and any promotion — in a ChangeSet. It gives the whole change one name, locks the Units against a concurrent ChangeSet, and makes `--restore Before:ChangeSet:<slug>` the way back across every affected Unit. The start tag marks each Unit's head as it was before the ChangeSet opened, so attaching creates no revision and Units that never changed still rewind cleanly. See `references/changesets.md`.

## Delete Gates and Destroy Gates

ConfigHub makes bulk and cross-Space operations easy — which is also how you accidentally delete a prod Space or destroy live resources. Gates are the opt-in protection (`https://docs.confighub.com/markdown/guide/protecting.md`). They are unrelated to path protection above: gates guard the entity, protection guards a field.

- **Delete Gates** — on any entity. Block `cub <entity> delete` until removed.
- **Destroy Gates** — **Units only**. Protect a Unit's destructive lifecycle operation. Orthogonal to Delete Gates; verify the active CLI before any destructive proposal.

```text
# Unit — protect prod data and its live resources.
cub unit update --patch --space <component>-prod <unit> --delete-gate prod-critical --destroy-gate prod-critical
# Space — delete only (Spaces have no destroy).
cub space update --patch <space> --delete-gate used-until-dec25
# Remove with the '-' sentinel (empty string won't clear), then delete.
cub space update --patch <space> --delete-gate used-until-dec25=-
```

`cub variant create` sets them on the whole clone at once: `--unit-delete-gate` / `--unit-destroy-gate` on every cloned Unit, `--space-delete-gate` on the Space.

The gate **name carries the why** — prefer specific (`used-until-dec25`, `team-payments-owns`, `in-use-by-argocd`) over a generic `critical` everywhere. Gates stack; all must be removed. Recommend a gate in the same turn you create any prod-bound variant, shared-infra Space, platform Trigger/Filter, or hard-to-replace Worker.

## Routing — pick the right skill

| User intent | Skill |
| --- | --- |
| Authoring a specific K8s resource type (StatefulSet, Ingress, NetworkPolicy, …) — including the full authoring loop | `kubernetes-resources` |
| App config files (.env / .properties / .yaml) → ConfigMap; hashing a ConfigMap to roll a workload | `app-config` |
| Validation/policy that actually blocks bad config | `triggers-and-applygates` |
| Changing data in an existing Unit (image, replicas, env, defaults); writing invocations that generalize | `cub-mutate` |
| Finding, listing, auditing, inspecting config across Units/Spaces; browsing resources | `cub-query` |
| A playground Space to tinker with | `skill-examples-bootstrap` |
| Setting up a worker (server worker for delivery; external for custom functions) | `worker-bootstrap` |
| Creating a Target / binding a Unit to one | `target-bind` |
| Applying/deploying a Unit or set (prepare an exact whole-Space OCI Release proposal) | `release-publish` |
| Post-publish verification, troubleshooting, close-out | `verify-apply` |
| Onboarding existing Helm / Kustomize config | `import` |
| Seeding a base, cloning a variant, promoting; resolving merge conflicts from a promotion | `promote-release` |
| Rolling back by moving head | `rollback-revision` |
| Orchestrating a production incident | `incident-management` |

## Tool boundary

- Orientation/doctrine: read-only. Hand off the task to the dedicated skill.
- Route writes to their owning Skill: `cub space create/update`, `cub unit create/update`, `cub function set|vet`, `cub run`, and `cub link …` each become one exact host-permission call (always `--change-desc` + `-o mutations` where supported); `kubectl create --dry-run=client` / `kubectl explain` are scaffolding only.
- Not allowed: `helm install/upgrade`, `kustomize build` piped into ongoing editing, values files, template syntax inside a Unit, mutating `kubectl`/`argocd`/`flux`.

## Change description

Every supported Unit-data mutation passes a short, model-authored
`--change-desc` that follows `references/execution-modes.md`:

```
Set checkout image to v2 for prod rollout
```

## Stop conditions

- Intent is concrete enough to route — hand off and exit.
- User insists on a template/values file in a Unit, or product depth that belongs in docs.

## Verify chain

- Authoring: `cub unit get <slug> --space <space>` — confirm literal YAML; run `vet-placeholders` / `vet-schemas` / `vet-format` (or rely on the Space's Triggers).
- Component model: `cub component list`; `cub space get <space> -o json` (labels); a cross-Space `--where "Space.Labels.Component = ..."` query returns the expected variants.

## Evidence

- `cub unit open <unit> --space <space> --print-url`, `cub space open <space> --print-url`, `cub component open <component> --print-url` — verified GUI handoffs.
- Docs: `https://docs.confighub.com/markdown/index.md`; SDK: `https://github.com/confighub/sdk`.

## References

- `references/cub-cli.md` — CLI discipline, `--change-desc`, `-o mutations`, protection and merge conflicts, `--where` AND-only, `--trigger-filter` / `--where-trigger`.
- `references/functions-catalog.md` — the function surface.
- `references/filters-and-queries.md` — query vocabulary.
- `references/changesets.md` — grouping a change so it can be undone.
- `references/revisions.md` — the empty start revision, provenance, gates.
- `references/triggers-recipes.md` — platform-Space pattern.
- `references/yaml-patterns.md` — literal-value authoring for all common resource types.
- `https://docs.confighub.com/markdown/background/concepts/component.md`, `.../background/concepts/variant.md`, `.../background/concepts/mutation-sources.md`, `.../guide/variants.md`, `.../guide/protecting.md`.
