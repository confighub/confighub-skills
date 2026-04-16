# space-topology eval — with-skill

## Scenario

> We have two apps (web and api) and three environments (dev, staging, prod). All three environments are in the same cluster for now, but prod will move to its own cluster soon. How should I lay out my ConfigHub Spaces?

## Preflight

Auth check (NOT `cub info` — that doesn't require auth):

```
$ cub context get
User: <authenticated>
```

Current Spaces:

```
$ cub space list
NAME              ENVIRONMENT    #UNITS  ...
default                          0
platform                         0
test-space                       0
skill-examples    dev            11
```

## Recommendation

**One Space per deployment boundary.** Each `(app, environment)` gets its own Space. With two apps and three environments, that's:

```
platform              ← already exists; org-wide Triggers + Filters, no workloads
web-home              ← web team's home Space — ChangeSets, Tags, Filters, Views
web-dev
web-staging
web-prod
api-home              ← api team's home Space
api-dev
api-staging
api-prod
```

Total: 8 new Spaces (plus the existing `platform`).

### Why not suffix-naming in one Space

Putting `web-dev`, `web-prod` as *Units* in a single `web` Space breaks three things:

1. **Targets** — a Target is Space-scoped and binds to one cluster. Two envs in one Space can't point at different clusters.
2. **ApplyGates / approval flow** — policy (who approves, which Triggers run) varies by env. Per-env Spaces + the `platform` Filter express this cleanly.
3. **Clone-based promotion** — `cub unit create --dest-space web-staging --space web-dev` works at Space granularity. Collapsing envs kills this.

### Why separate home Spaces

Operational artifacts (ChangeSets, Tags, Filters, Views) are cross-environment — a "release 42" ChangeSet spans dev→staging→prod. Putting them in any deployment Space would couple them to that env's lifecycle and permissions. The home Space is neutral ground scoped to the app team.

### Labels

Put structured metadata on Spaces, not in the slug. PascalCase, non-abbreviated:

```bash
cub space create web-dev
cub space update web-dev \
  --label Application=web \
  --label Environment=dev \
  --label Cluster=shared-cluster

cub space create web-staging
cub space update web-staging \
  --label Application=web \
  --label Environment=staging \
  --label Cluster=shared-cluster

cub space create web-prod
cub space update web-prod \
  --label Application=web \
  --label Environment=prod \
  --label Cluster=shared-cluster
```

Same pattern for api-*. When prod moves to its own cluster, update the label:

```bash
cub space update web-prod --label Cluster=prod-cluster
cub space update api-prod --label Cluster=prod-cluster
```

No slug change needed — the label tracks the infrastructure reality.

### Cross-Space queries enabled by labels

```bash
# Every Unit in every prod Space.
cub unit list --space "*" --where "Space.Labels.Environment = 'prod'"

# Everything in the shared cluster.
cub unit list --space "*" --where "Space.Labels.Cluster = 'shared-cluster'"

# Impact of moving prod to its own cluster — what's affected.
cub unit list --space "*" --where "Space.Labels.Environment = 'prod'" --where "Space.Labels.Cluster = 'shared-cluster'"
```

### Workers and Targets

Since all three envs are in one cluster today, one Worker serves all:

**Pattern A (recommended):** Worker in a dedicated Space (`workers-shared-cluster`) with auto-created Targets. App Spaces reference Targets by Space-qualified name: `cub unit set-target workers-shared-cluster/<target>`.

When prod moves to its own cluster, install a second Worker in `workers-prod-cluster` and rebind prod Units.

### Promotion flow

With this layout, promotion is Space-to-Space:

```bash
# Clone web from dev to staging.
cub unit create --dest-space web-staging --space web-dev

# Later, pull in upstream changes.
cub unit update --space web-staging <unit> --upgrade
```

### Platform Filter

Attach the platform Filter to each app Space for baseline vets:

```bash
cub space update web-dev --trigger-filter platform/standard-vets
```

## Tool boundary

This skill decides *where things go*. Creating Units → `config-as-data`. Binding Targets → `target-bind`. Setting up Triggers/Filters → `triggers-and-applygates`.

## Evidence

- `cub space list --web` — the Space tree in the GUI.
- `cub space get web-prod --web` — labels, Trigger Filter, membership.
