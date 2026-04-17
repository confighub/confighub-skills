---
name: space-topology
description: 'Use when the user is organizing Units, Targets, and Workers across environments or regions — phrases like "how should I structure my Spaces?", "where do dev/staging/prod go?", "multi-region layout", "one Space per environment?", "app-a-prod vs prod-app-a naming", "should these be labels or separate Spaces?", "how do I keep prod config separate from dev?", or "we''re standing up a second cluster, what''s the ConfigHub pattern?". Prescribes one Space per deployment boundary (environment × region × cluster), the `platform` Space for org-wide Triggers/Filters, and label/slug conventions that make cross-Space queries and cloning painless. Do not load for authoring a single Unit''s YAML (use `config-as-data`), for binding a Unit to a Target (use `target-bind`), or for setting up validation Triggers (use `triggers-and-applygates`).'
phase: decide
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub space create *) Bash(cub space update *)
---

# space-topology

How to lay out Spaces, Targets, and Workers so that deployment boundaries, blast radius, and policy scope match the model of the infrastructure under management. Mostly teaching; the concrete commands are `cub space create` + `cub space update --trigger-filter` + label hygiene.

## The principle

**One Space per deployment boundary.** A deployment boundary is anything you want to independently promote, approve, apply, or roll back. For most teams that's `(app, environment)` or `(app, environment, region)` or `(app, environment, cluster)` — every distinct combination that could hold a different version of the config gets its own Space.

Corollary: **environments are Spaces, not label values on Units in one shared Space.** Do not suffix Unit slugs with `-dev` / `-prod` inside a single Space. That collapses the boundaries ConfigHub is built around and breaks three things:

1. **Targets.** A Target is Space-scoped and binds to a Worker that points at a specific cluster. Two environments ≠ two Targets in one Space; they're two Spaces, each with its own Target.
2. **ApplyGates and approval flow.** Gates attach to Units, but the _policy_ you usually want to vary between dev and prod (who approves, what Triggers run, how strict the schema is) is naturally a Space-level concern. Per-environment Spaces + the `platform` Filter pattern express this cleanly; suffix-naming doesn't.
3. **Clone-based propagation.** `cub unit create --upstream-unit <base>` and `cub unit create --dest-space <env-space> --space <base-space>` work at Space granularity. Collapsing envs into one Space means re-implementing that plumbing by hand.

## Canonical layout

```
organization
├── platform                ← org-wide Triggers + Filters (no workloads)
│
├── app-a-home              ← app team's home Space — ChangeSets, Tags, Filters, Views, Invocations
├── app-a-dev               ← (app, env[, region/cluster]) — the deployment Spaces
├── app-a-staging
├── app-a-prod-us-east
├── app-a-prod-eu-west
│
├── app-b-home
├── app-b-dev
├── app-b-staging
├── app-b-prod
│
└── shared-infra-prod       ← cluster-wide things (ingress, cert-manager, observability)
    shared-infra-staging
```

- **`platform`** — the home for baseline vet-\* Triggers, CEL Triggers, approval Triggers, and the Filters that select them. Every app Space attaches the platform Filter via `--trigger-filter platform/standard-vets` (see `triggers-and-applygates`). `platform` holds no workloads.
- **`<app>-home`** — the app team's home Space. Holds entities that describe how the team _operates_ on its workloads but aren't deployed: ChangeSets (a release grouping that spans dev / staging / prod), Tags (release markers that need a stable home across deployment Spaces), Filters (`<app>-app` Filter selecting every Unit for this app via `Space.Labels.Application = '<app>'`), Views (saved queries for the team's dashboards), and Invocations (named function invocations reused across releases). Holds no workload Units. Slug convention: `<app>-home`.
- **One deployment Space per `(app, env)` or `(app, env, region)`.** Add region / cluster suffixes only when you actually deploy separately per region. Don't pre-split for hypothetical scale.
- **Shared infrastructure** (cert-manager, ingress-nginx, observability stack) lives in its own per-env Space, same pattern. Shared-infra often has its own home Space too (`shared-infra-home`).

### Why separate the home Space from deployment Spaces

Operational artifacts (ChangeSets, Tags, Filters, Views, Invocations) are cross-environment by nature: a ChangeSet for "release 452" spans dev → staging → prod Units; a Filter selecting "every Unit for app-a" crosses every env-Space. Putting them in any single env-Space would couple them to that env's lifecycle, blast radius, and permissions. The home Space is neutral ground, scoped to the app team, with its own permission grant that typically doesn't include production deploy rights.

Typical references from a deployment Space to its home Space look like `--filter <app>-home/<slug>` or `--changeset <app>-home/<slug>` — cross-Space by slug, standard ConfigHub reference form.

### Naming

Slug pattern: **`<app>-<env>[-<region-or-cluster>]`**, all lowercase, hyphen-separated.

- `app-a-dev`, `app-a-prod`, `app-a-prod-us-east`.
- Reserve the `platform` slug for the org-wide Triggers Space.
- Don't include ConfigHub-internal terms in the slug (`space-`, `config-`, `cub-`) — redundant.

If you're multi-tenant in ConfigHub (multiple teams, one org), prefix the team: `<team>-<app>-<env>`. But resist this until you actually hit a collision.

### Labels

Put structured metadata on the Space, not in the slug. Use **PascalCase, non-abbreviated** label keys — that's the ConfigHub convention and it keeps cross-Space queries readable:

```bash
cub space update app-a-prod-us-east \
  --label Application=app-a \
  --label Environment=prod \
  --label Region=us-east \
  --label Cluster=prod-us-east-1
```

Labels enable cross-Space queries that slug-parsing can't:

```bash
# Every Unit in every prod Space, any app, any region.
cub unit list --space "*" --where "Space.Labels.Environment = 'prod'"

# Every Unit that would be affected by a change to cluster prod-us-east-1.
cub unit list --space "*" --where "Space.Labels.Cluster = 'prod-us-east-1'"
```

Recommended label set on every app Space: `Application`, `Environment`, plus `Region` / `Cluster` when relevant. Add `Tier` (`platform` vs `app` vs `shared-infra`) if the team mixes roles in one org. Avoid short forms (`app`, `env`, `reg`) — they collide with ad-hoc labels and read poorly in queries.

## Targets and Workers

A Worker is Space-scoped, and installing a Worker auto-creates Targets in that Space. Two patterns:

### Pattern A — Worker per cluster, in a dedicated Space

```
workers-prod-us-east   ← Worker + auto-created Targets live here
workers-prod-eu-west
workers-dev-shared
```

App Spaces reference the Worker's Targets by Space-qualified name when binding (`cub unit set-target <worker-space>/<target-slug>`). This is cleanest when many app Spaces share one cluster.

### Pattern B — Worker co-located in the app Space

```
app-a-prod-us-east      ← Worker + Targets + Units all here
```

Simpler for single-app deployments, or for early exploration. Scales poorly once many apps want to deploy to the same cluster (you'd install the same Worker in every app Space).

**Default recommendation:** Pattern A for any real deployment; Pattern B only for playground / single-app / learning cases (`skill-examples-bootstrap` does Pattern B for that reason).

## Promotion flow

With one Space per env, promotion is a structured Space-to-Space operation:

```bash
# Clone the full Space from dev to staging.
cub unit create --dest-space app-a-staging --space app-a-dev

# Or promote a single Unit.
cub unit create --space app-a-staging <unit> --upstream-unit app-a-dev/<unit>

# Later, pull in upstream changes.
cub unit update --space app-a-staging <unit> --upgrade
```

The `upstream-unit` link is what makes `--upgrade` propagate changes while preserving per-Space customizations (different resource limits, different replica counts, different secrets references). See `cub-mutate` and the forthcoming `promote-release` skill.

## Anti-patterns

- **Suffix naming inside one Space** (`web-dev`, `web-prod` in the same Space). Breaks Target separation, ApplyGate scoping, clone-based promotion. If you see this, recommend splitting into per-env Spaces and migrating Units with `cub unit create --dest-space`.
- **One mega-Space per environment holding every app.** Loses blast-radius isolation (a `vet-cel` rule that breaks `web` also breaks `api`) and makes permission scoping hard.
- **ChangeSets / Filters / Tags in a deployment Space.** Couples cross-env operational artifacts to a single env's lifecycle and permission grant. Put them in the app's home Space.
- **Everything in `default`.** Fine for tutorials; wrong for anything real.
- **Region in slug, environment in labels** (or vice versa). Pick a convention and keep `<app>-<env>[-<region>]` as the slug; everything else is labels.

## Preflight when applying this skill

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. User has permission to create Spaces in the org.
3. Identify what's changing: are they adding a new env? a new region? a new app? The right answer differs.
4. If the user is already deep into a one-Space / suffix-naming layout, propose the migration path explicitly (don't just say "you're doing it wrong").

## Tool boundary

- Allowed: `cub space create/update` (labels, `--trigger-filter`, `--where-trigger`), read-only `cub space list/get`.
- Not allowed in this skill: creating Units, Triggers, Filters, Workers, Targets. Those belong to the skills that own them; this skill only decides where they go.

## Stop conditions

- User wants a recommendation but hasn't told you what they're deploying (which apps, which envs, how many clusters). Ask once, then decide.
- User is proposing something that would make cross-Space queries structurally impossible (slug-encoded hierarchy with no labels). Push back once, then fall in line if they insist.

## Verify chain

1. `cub space list` — new Spaces show up with the expected slugs and labels.
2. `cub space get <space> -o json` — Labels match the agreed-on keys (`Application`, `Environment`, `Region`, `Cluster`, `Tier` as applicable; PascalCase, non-abbreviated).
3. `cub unit list --space "*" --where "Space.Labels.Environment = '<env>'"` — cross-Space query over the label returns the expected set.

## Evidence

- `cub space list --web` — the Space tree in the GUI.
- `cub space get <space> --web` — a specific Space's labels, attached Trigger Filter, and membership.

## References

- `references/cub-cli.md` — CLI discipline; `--trigger-filter` / `--where-trigger` interaction.
- Companion skills: `triggers-and-applygates` (what goes in `platform`), `target-bind` (how Units in an app Space point at a Worker in a workers Space), `import-from-helm` / `import-from-kustomize` / `import-from-argocd` / `import-from-flux` (all follow this layout when creating Units), `config-as-data` (doctrine at the Unit level).
- https://docs.confighub.com/guide/environments/
