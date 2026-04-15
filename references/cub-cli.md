# cub CLI discipline

## Agent help mode

Always prefix help queries with `CONFIGHUB_AGENT=1`:

```bash
CONFIGHUB_AGENT=1 cub <command> --help
CONFIGHUB_AGENT=1 cub function explain --toolchain Kubernetes/YAML <function-name>
```

The agent mode emits structured, concise help designed for AI consumption.

## Never invent flags

If a flag isn't in `--help`, it doesn't exist. Re-check `--help` on the current `cub` version before constructing a command; the CLI evolves.

## Global pattern

```
cub <entity-or-area> <verb> [flags] [arguments]
```

Common entities: `space`, `unit`, `revision`, `trigger`, `filter`, `target`, `worker`, `function`, `run`, `link`.

## Context

- `cub context get` — show current space + user.
- `cub context set --space <slug>` — set default space.
- `--space <slug>` on any command overrides the default.
- `--space "*"` queries across all spaces (powerful for read / query; use carefully for mutations).

## Where-clauses and filters

Quick sketch here; the full filter vocabulary, named-Filter entities, and common operational recipes (`apply-not-completed`, `unapplied-changes`, `not-approved`, `has-apply-gates`, `needs-upgrade`, `has-upstream`) are in `references/filters-and-queries.md` — reach for that when building queries.

Three distinct flags. Get them mixed up and cub either rejects the command or silently returns the wrong rows.

### `--where "<expr>"` — on `list` and bulk-operation commands

Filters on entity metadata fields. Used by `cub unit list`, `cub trigger list`, `cub space list`, `cub filter list`, etc., and by bulk-operation commands (`cub unit update --where ...`, `cub run --where ...`, `cub function do --where ...`).

```
cub unit list --where "Slug LIKE 'app-%'"
cub unit list --space "*" --where "Space.Labels.Environment = 'production'"
cub trigger list --space "*" --where "Space.Slug = 'platform' AND FunctionName LIKE 'vet-%'"
```

### `--where-field "<expr>"` — on `cub filter create` / `update` only

The stored metadata predicate of a named Filter entity. **Not accepted** on `list` commands or bulk operations — those use `--where`. Same SQL-ish syntax as `--where`.

```
cub filter create --space platform --json standard-vets Trigger \
  --where-field "Space.Slug = 'platform' AND FunctionName LIKE 'vet-%'"
```

### `--where-data "<path expr>"` — on unit/function commands, and on Unit filters

Filters on configuration content (the YAML inside a Unit). Accepted by:

- `cub unit list`, `cub unit apply`, `cub unit update`, `cub function do`, `cub run`, and similar unit/function verbs.
- `cub filter create --space <space> <slug> Unit --where-data "..."` — valid *only* when the Filter's `From` is `Unit`. Invalid for `Space`, `Trigger`, `Target`, or `Worker` Filters — configuration data is a Unit-level thing.

```
cub unit list --where-data "spec.replicas > 2"
cub run --where-data "spec.template.spec.containers.*.image#reference LIKE ':v1.2.3'" set-container-image ...
cub filter create --space <space> --json replicas-hot Unit --where-data "spec.replicas > 2"
```

`--where-data` expressions also accept a small set of `ConfigHub.*` resource-level pseudo-attributes alongside YAML paths:

- `ConfigHub.ResourceType` — the `<apiVersion>/<Kind>` of a resource inside the Unit (e.g., `apps/v1/Deployment`).
- `ConfigHub.ResourceName` — the resource's `<namespace>/<name>` (e.g., `hello/hello-app`); cluster-scoped resources have an empty namespace part.

```
# Every Unit holding a Deployment anywhere (per-resource match, bundles included).
cub unit list --space "*" --where-data "ConfigHub.ResourceType = 'apps/v1/Deployment'"

# Every Unit that contains a specific named resource.
cub unit list --space "*" --where-data "ConfigHub.ResourceName = 'hello/hello-app'"
```

These work where any other `--where-data` works (unit/function commands, Unit Filters), and compose with YAML-path predicates via `AND`.

### `--resource-type "<apiVersion>/<Kind>"` — on `cub filter create` Unit filters only

Dedicated flag to filter a Unit Filter by Kubernetes resource type. Use this instead of trying to express "Deployments" in a `--where-field` expression.

```
cub filter create --space <space> --json deployment-filter Unit --resource-type "apps/v1/Deployment"
```

### `--where-space "<expr>"` — on `cub filter create` bulk mode

Selects destination Spaces when the filter is being bulk-created. Rarely needed; see `cub filter create --help` for the pattern.

### Attribute vocabulary for `--where` / `--where-field`

Entity metadata attributes are entity-specific. Common ones on Units: `Slug`, `DisplayName`, `SpaceID`, `Space.Slug`, `Space.Labels.<Key>`, `Labels.<Key>`, `ToolchainType`, `TargetID`, `HeadRevisionNum`, `LiveRevisionNum`, `LastAppliedRevisionNum`, `UpstreamRevisionNum`, `UnappliedChanges`, `ApprovedBy`, `ApplyGates`. Common ones on Triggers: `Slug`, `Space.Slug`, `Event`, `FunctionName`, `ToolchainType`, `Validating`, `Disabled`. Confirm with the entity's `--help` and `cub <entity> get --json` when composing a new query.

**`ResourceType` is not a `--where` / `--where-field` attribute.** It's a resource-level pseudo-attribute under `--where-data` as `ConfigHub.ResourceType`, or the dedicated `--resource-type` flag on `cub filter create` Unit filters:

```
# Wrong — ResourceType is not a --where attribute:
cub unit list --where "ResourceType = 'apps/v1/Deployment'"

# Right — --where-data pseudo-attribute:
cub unit list --where-data "ConfigHub.ResourceType = 'apps/v1/Deployment'"

# Right — at the Filter entity level:
cub filter create --space <space> --json deployments Unit --resource-type "apps/v1/Deployment"
```

`ToolchainType` *is* a valid `--where` attribute (`cub unit list --where "ToolchainType = 'Kubernetes/YAML'"`).

Filters are also first-class entities (`cub filter create …`) that can be referenced by slug via `--filter <space>/<slug>` — see `filters-and-queries.md` for the recipes.

## Output flags

- `--json` / `--yaml` — structured output, suppresses default.
- `--quiet` — no default output.
- `--jq <expr>` / `--yq <expr>` — post-process output.
- `--output-only` / `--output-values-only` — for function results.
- `--output-jq <expr>` — jq over the raw function result envelope.

## Change descriptions on mutations

`cub unit update`, `cub function do`, `cub run`, `cub unit update --patch` all accept `--change-desc`. **Always pass it** on mutations to configuration data. The description is stored in every affected unit's head revision. For `cub run` across many units, the same description is recorded in every affected unit — phrase it so it reads sensibly at the per-unit level.

## Showing mutation diffs

Any command that mutates configuration data (`cub unit update`, `cub function do`, `cub run`, `cub unit update --patch`) accepts `--display-mutations`, which prints a diff of the configuration change the command just produced. Include it on mutating calls by default — it's the cheapest way to verify the mutation did what you intended and gives the user something concrete to see in session output. The diff is the same one surfaced in the Unit's revision history afterward.

## Review links in the GUI

Prefer `cub unit get --web`, `cub revision list --web`, and similar `--web` flags over hand-built GUI URLs. Those flags open the authoritative page — the canonical place for a user to review state, revisions, approvals, and gates.

## Read-only diagnosis tools

- `kubectl get`, `kubectl describe`, `kubectl logs` — permitted for diagnosis.
- `argocd app get`, `argocd app diff` — permitted for delivery verification.
- `flux get`, `flux stats` — permitted for delivery verification.

Do **not** use any of these to mutate. Mutations always go through `cub`.

## Permission sets for `allowed-tools` frontmatter

Skills split `cub` permissions by read vs write. Read-only skills get only the **Read set**; mutating skills get Read + Write. Delete verbs are deliberately omitted — they belong to a separate opt-in `cleanup` skill with explicit confirmation.

### Read set (read-only cub + help on every subcommand)

```
Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub worker logs *) Bash(cub worker status *)
```

Why the wildcards are safe:

- `Bash(cub * --help)` matches help on any subcommand — help is never mutating.
- `Bash(cub * get)` / `Bash(cub * get *)` cover every entity's read verb (`cub unit get`, `cub space get`, `cub context get`, `cub trigger get`, `cub filter get`, `cub target get`, `cub worker get`, `cub revision get`, `cub link get`, …). `get` is universally read-only across cub entities.
- `Bash(cub * list)` / `Bash(cub * list *)` cover every entity's list verb. `list` is universally read-only.
- `Bash(cub * list-* *)` picks up multi-word list variants like `cub worker list-function`, `cub worker list-status`.
- The five `cub unit <verb>` entries (`diff`, `tree`, `bridgestate`, `livedata`, `livestate`) and the two `cub worker <verb>` entries (`logs`, `status`) are read-only verbs that don't fit the `get`/`list` shape.
- `cub function explain` is read-only but doesn't match the wildcards above (it's not `list` or `get`), so it's listed explicitly.

### Write set (add these to the Read set for mutating skills)

```
Bash(cub space create *) Bash(cub space update *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub trigger create *) Bash(cub trigger update *) Bash(cub filter create *) Bash(cub filter update *) Bash(cub target create *) Bash(cub target update *) Bash(cub worker create *) Bash(cub worker update *) Bash(cub link create *) Bash(cub link update *) Bash(cub function do *) Bash(cub run *)
```

### Known ambiguity

`cub function do` and `cub run` can invoke either getter/validator functions (read) or mutating functions (write). The function name appears after `--`, which shell-glob patterns past the double-dash can't reliably match. Both verbs live in the Write set only. Read-only skills must do queries with `cub unit list --where-data`, `cub unit get`, `cub revision list`, etc. If a read-only skill genuinely needs `cub function do <getter>`, promote it to a mutating skill or add a narrow pattern (e.g., `Bash(cub function do * -- get-*)`) after confirming the matcher handles it.

### Do not grant

- `Bash(cub * delete *)` — destructive; put it in a dedicated skill with explicit flow control.
- `Bash(cub *)` — too broad. Skills should declare exactly what they need.
