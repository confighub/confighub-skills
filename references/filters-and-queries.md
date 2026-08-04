# Filters and queries

ConfigHub supports two query languages:

- **`--where`** filters on entity metadata (PascalCase attributes).
- **`--where-data`** filters on the configuration content inside Units (path expressions into the YAML/JSON structure).

Plus free-text search via `--contains`, and named `Filter` entities that persist queries and can be reused or attached to Spaces.

Always verify flag spellings against `CONFIGHUB_AGENT=1 cub <command> --help` on the current cub version.

## `--where` — entity metadata filtering

Used with `list`, `function do`, `run`, and other bulk operations.

### Syntax

Conjunctions of relational expressions using `AND`:

```
ATTRIBUTE OPERATOR VALUE [AND ATTRIBUTE OPERATOR VALUE ...]
```

Attribute names are **case-sensitive PascalCase** as in JSON encoding (`Slug`, `DisplayName`, `Labels.tier`, `HeadRevisionNum`).

**Flat `AND`-only — no parentheses, no `OR`.** The grammar is a flat list of `ATTRIBUTE OPERATOR VALUE` clauses joined by `AND`; there is no grouping or disjunction. Wrapping any clause in parentheses (e.g. `(ToolchainType = 'Kubernetes/YAML')`) is a syntax error — the parser reads the leading `(` as part of the attribute name and rejects it with `invalid attribute name`. When composing a filter from several sources (a base predicate plus caller-supplied clauses), concatenate them with a bare ` AND `, never with parenthesized groups. For `OR`-like needs, run one query per alternative and union the results client-side, or use `IN (...)` where it fits.

### Common attributes

All entities: `CreatedAt`, `UpdatedAt`, `DisplayName`, `Slug`, ID fields.

Unit-specific: `HeadRevisionNum`, `LastAppliedRevisionNum` (Revision most recently captured by publication), `UpstreamRevisionNum`, `ApprovedBy`, `ApplyGates`, `ToolchainType`, `TargetID`, `Labels.*`, `Annotations.*`. `LiveRevisionNum` is retained bridge-era state and is not current runtime proof.

Join references where the entity has a relationship: e.g., `UpstreamUnit.HeadRevisionNum` on a Unit that has an upstream.

### Operators

| Type                     | Operators                                            |
| ------------------------ | ---------------------------------------------------- |
| Comparison               | `=`, `!=`, `<`, `>`, `<=`, `>=`                      |
| Pattern                  | `LIKE`, `NOT LIKE` (wildcards: `%`, `_`)             |
| Case-insensitive pattern | `ILIKE`                                              |
| Regex                    | `~`, `~*` (case-insensitive), `!~`, `!~*`            |
| Membership               | `IN (...)`, `NOT IN (...)`                           |
| Null check               | `IS NULL`, `IS NOT NULL`                             |
| Array contains           | `?`                                                  |
| Array length             | `LEN(attr)`                                          |
| Truth test               | `IS TRUE`, `IS FALSE`, `IS NOT TRUE`, `IS NOT FALSE` |

### Examples

```bash
# Identity
--where "Slug = 'myapp'"
--where "Slug LIKE 'app-%'"
--where "Slug ILIKE '%backend%'"
--where "Slug ~ '^app-[0-9]+$'"
--where "Slug IN ('app1', 'app2', 'app3')"

# Labels
--where "Labels.tier = 'Backend'"
--where "Labels.tier IS NOT NULL"
--where "Labels.Environment NOT IN ('development', 'test')"

# Time
--where "CreatedAt > '2025-01-01T00:00:00'"

# Array operations
--where "LEN(ApprovedBy) > 0"
--where "ApprovedBy ? 'USER_UUID'"
--where "LEN(ApplyGates) > 0"
--where "ApplyGates.require-approval/vet-approvedby = true"

# Revision state
--where "HeadRevisionNum > LiveRevisionNum"   # pending changes
--where "LiveRevisionNum = 0"                 # never applied
--where "UpstreamRevisionNum > 0"             # cloned/downstream units

# Conjunction
--where "CreatedAt >= '2025-01-07' AND Slug = 'test' AND Labels.mykey = 'myvalue'"
```

### Flag-name variant

Most commands use `--where`. `cub filter create` uses `--where-field` for its stored expression (to distinguish from `--where-data`). The SQL-ish body is the same in both cases.

## `--where-data` — configuration content filtering

Available with `cub unit list` (and a few related verbs — check `--help`). Filters by the actual content of configuration data.

### Path syntax

Dot-separated paths into the YAML/JSON structure:

| Feature                 | Syntax               | Example                                                       |
| ----------------------- | -------------------- | ------------------------------------------------------------- |
| Basic path              | `key.subkey`         | `spec.replicas`                                               |
| Array index             | `key.N`              | `spec.containers.0.image`                                     |
| Wildcard                | `key.*`              | `spec.containers.*.image`                                     |
| Associative match       | `key.?field=value`   | `spec.containers.?name=nginx.image`                           |
| Split path              | `path.*.\|subpath`   | `spec.containers.*.\|securityContext.runAsNonRoot`            |
| Escaped dot             | `~1`                 | `metadata.annotations.example~1com/key`                       |
| Reference decomposition | `#reference`, `#uri` | `spec.template.spec.containers.*.image#reference = ':v1.2.3'` |

### Operators

`=`, `!=`, `<`, `>`, `<=`, `>=`

### Examples

```bash
# Simple value check
--where-data "spec.replicas > 1"

# Specific container image
--where-data "spec.template.spec.containers.0.image = 'nginx:latest'"

# Any container
--where-data "spec.template.spec.containers.*.image = 'nginx:latest'"

# Image tag or repository by reference decomposition
--where-data "spec.template.spec.containers.*.image#reference = ':v1.2.3'"
--where-data "spec.template.spec.containers.*.image#uri ~ 'ghcr.io/acme/'"

# Containers without a security context
--where-data "spec.template.spec.containers.*.|securityContext.runAsNonRoot != true"

# Conjunction + resource kind filter
cub unit list --space SPACE --resource-type apps/v1/Deployment \
  --where-data "spec.replicas > 1 AND metadata.labels.tier = 'frontend'"
```

## `--contains` — free-text search

Case-insensitive search across string fields (`Slug`, `DisplayName`) and map fields (`Labels`, `Annotations`). Combinable with `--where`:

```bash
cub unit list --space SPACE --where "CreatedAt > '2025-01-01'" --contains "api"
```

## Named `Filter` entities

Once a `Filter` exists, reference it by slug on list / function / trigger commands, and attach it to a Space as its `TriggerFilterID`.

```bash
cub filter create --space <space> <slug> <From> --where-field "<expr>"
```

`<From>` is one of `Unit`, `Space`, `Trigger`, `Worker`, `Target`. Add `--resource-type` to scope Unit filters to a specific K8s kind, and `--where-data` for content predicates.

### Operational Unit-filter recipes

These filters describe ConfigHub revision/policy state. They do **not** prove a current Space Release, controller sync, or runtime convergence. Filter creation is proposal-only while the external broker is absent.

```bash
# Unit head differs from the revision most recently captured by publication.
cub filter create --space "$space" unreleased-head Unit \
  --where-field "HeadRevisionNum != LastAppliedRevisionNum AND TargetID IS NOT NULL"

# Current Unit revision has no recorded native approver.
cub filter create --space "$space" not-approved Unit \
  --where-field "LEN(ApprovedBy) = 0"

# Blocked by one or more ApplyGates.
cub filter create --space "$space" has-apply-gates Unit \
  --where-field "LEN(ApplyGates) > 0"

# Downstream Unit is behind its upstream — an upgrade is available.
cub filter create --space "$space" needs-upgrade Unit \
  --where-field "Unit.UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum"

# Unit has an upstream relationship (i.e., is part of a promotion chain).
cub filter create --space "$space" has-upstream Unit \
  --where-field "UpstreamRevisionNum > 0"
```

The Release EffectiveReleaseSet cannot be inferred from these generic Filters. Read the Space's exact `ReleaseTargetID`, list Units with TargetID selected, and compare equality. `cub release publish` accepts no Filter.

`VERSIONED_LEGACY`: the old `apply-not-completed` (`LastAppliedRevisionNum != LiveRevisionNum`) and `unapplied-changes` (`HeadRevisionNum > LiveRevisionNum`) recipes are retained in the no-loss inventory as historical Unit-runtime views. Do not use them for Release/controller/runtime proof.

### Using a named Filter

```bash
# List.
cub unit list --space "*" --filter platform/has-apply-gates
cub unit list --space "$app_space" --filter platform/needs-upgrade

# Act in bulk only on the selected set.
cub unit update --patch --space "*" --filter platform/needs-upgrade --upgrade \
  --change-desc "Upgrade all downstream Units to upstream head.

User prompt: <verbatim>
Clarifications: <condensed>"
```

### As a Trigger scope

A Filter over `Trigger` entities (not Units) is what gets attached to a Space via `--trigger-filter`. See `references/triggers-recipes.md`.

## Revision history queries

Change descriptions composed by the mutation skills make revision lookup self-explaining:

```bash
cub revision list --space "$space" --where "UpdatedAt > '2026-04-01'"
cub revision list <unit-slug> --space "$space"
```

The full Revision data model — fields, per-path `MutationSources`, `ApplyGates`/`ApplyWarnings` snapshots, `ApprovedBy`, `LiveAt`, `ChangeSetID`, `Tags` — is in `references/revisions.md`.

## Getter functions for content extraction

For questions `--where-data` cannot answer cleanly, a specifically reviewed getter function may help. Do not treat `cub function get` as a safe arbitrary class: functions such as `generate-kubecontext` can mint credential-bearing output. Name the exact function and flags, ensure it belongs to the active skill's capability subset, and leave execution at host `ASK`; unknown functions are `BLOCK` pending the typed registry/wrapper. Never substitute `function do` or `run`, which can mutate.

```bash
# Current image for every Deployment across all spaces.
cub function get --space "*" --resource-type apps/v1/Deployment \
  get-container-image main \
  --quiet --show output -o jq='. as $e | .Output[] | {unit: $e.UnitSlug, space: $e.SpaceSlug, image: .Value}'

# Every placeholder still present, grouped by Unit.
cub function get --space "*" get-placeholders \
  --quiet --show output -o jq='.Output[] | select(.Value != null)'

# CEL extraction across resources.
cub function get --space "*" --resource-type apps/v1/Deployment \
  get-cel 'resource.spec.template.spec.containers.map(c, {"name": c.name, "image": c.image})' \
  --quiet --show output
```
