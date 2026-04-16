---
name: cub-query
description: 'Use whenever the user wants to find, count, inspect, or audit Kubernetes configuration across ConfigHub — "where is release X deployed?", "which units run more than 5 replicas?", "show me every Deployment using the old registry", "find units missing resource limits", "list all spaces with label env=prod", "what''s the current image for checkout in each environment?", "audit what we have". ConfigHub treats configuration as data, so you can query across Units and Spaces the way you''d query a database. Load this any time the user''s intent is "find / list / show / which / where / how many / audit" over ConfigHub state. Do not load for: mutating data (use cub-mutate), authoring new config (use config-as-data), or live cluster queries that don''t involve ConfigHub (use kubectl).'
phase: verify
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *)
---

# cub-query

The database-like query surface of ConfigHub. Most users don't discover this from the CLI help alone; the skill makes it the first-reach tool for any "find / list / audit" intent.

## Why this matters

Configuration is stored as data. Every field of every resource in every Unit in every Space is queryable — by metadata (`--where`), by content (`--where-data`), by resource type, and via functions that return structured values. This replaces "clone the repo, grep, try to figure out which env does what."

## When to use

- "Where is <image/release/version> deployed?"
- "Which units have <field> <condition>?" (e.g., replicas > 5, missing resource limits, using a specific registry)
- "List every Deployment / Service / ConfigMap in <scope>."
- "What's the current value of <field> across environments?"
- "Audit: find config violating <rule> across all spaces."
- "Show the revision history / recent changes for <unit or space>."

## Do not load for

- Mutations (`cub-mutate`).
- Authoring (`config-as-data`).
- Live-cluster state not in ConfigHub (`kubectl get`).

## Preflight gates

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. For cross-space queries (`--space "*"`), user has read permission on the spaces of interest.

## The query toolkit

### 1. Metadata queries — `cub unit list`

```bash
# All Deployments across all spaces.
cub unit list --space "*" --resource-type apps/v1/Deployment

# Units labeled Environment=prod.
cub unit list --space "*" --where "Labels.Environment = 'prod'"

# Units in Spaces matching a pattern.
cub unit list --space "*" --where "Space.Slug LIKE 'myapp-%'"
```

Useful `--where` fields: `Slug`, `DisplayName`, `ToolchainType`, `Labels.<Key>`, `Space.Slug`, `Space.Labels.<Key>`, `UpstreamRevisionNum`, `HeadRevisionNum`, `LiveRevisionNum`, `TargetID`. To filter on a Kubernetes resource kind (Deployment, Service, etc.), use `--where-data "ConfigHub.ResourceType = 'apps/v1/Deployment'"` — `ResourceType` is not a `--where` metadata field. `UnappliedChanges` is also not a field.

### 2. Content queries — `--where-data`

Filters on the actual configuration content using path expressions:

```bash
# Deployments with more than 5 replicas.
cub unit list --space "*" --resource-type apps/v1/Deployment \
  --where-data "spec.replicas > 5"

# Any Unit containing a container image with a specific tag.
cub unit list --space "*" \
  --where-data "spec.template.spec.containers.*.image#reference = ':v1.2.3'"

# Units with an image from a specific registry.
cub unit list --space "*" \
  --where-data "spec.template.spec.containers.*.image#uri ~ 'ghcr.io/acme/'"
```

### 3. Function-based extraction — `cub function do` + getters

`--where` and `--where-data` select units (and other entities). To extract values from configuration data, use getter functions:

```bash
# Get the current image for the "main" container of every Deployment.
cub function do --space "*" --resource-type apps/v1/Deployment \
  get-container-image main \
  --quiet --output-jq '.[] | {unit: .UnitSlug, space: .SpaceSlug, image: .Value}'

# Find placeholder values that still need to be filled.
cub function do --space "*" get-placeholders \
  --quiet --output-jq '.[] | select(.Value != null)'
```

### 4. Linting, Validation, and Policy-style analyses — `vet-` functions

```bash
# Run a validator as a one-off audit (without attaching a gate).
cub function do --space "*" vet-placeholders \
  --quiet --output-jq '.[] | select(.Passed == false)'

# Custom CEL audit with a readable message per failing resource.
cub function do --space "*" \
  vet-cel 'r.kind != "Deployment" || r.spec.replicas >= 2 ? {"passed": true} : {"passed": false, "details": [r.metadata.name + " has < 2 replicas"]}' \
  --quiet --output-jq '.[] | select(.Passed == false) | {unit: .UnitSlug, details: .Details}'
```

### 5. History + audit

```bash
# Recent revisions on a Unit with change descriptions.
cub revision list <slug> --space <space> --where "UpdatedAt > '2026-04-01'"

# Who changed what, when — across a Space.
cub revision list --space <space> --where "UpdatedAt > '2026-04-01'"

# Recent actions on a Unit.
cub unit-action list <slug> --space <space> --where "UpdatedAt > '2026-04-01'"

# Recent apply actions across a Space.
cub unit-action list --space <space> --where "Action = 'Apply'"

# Recent apply progress events across a Space.
cub unit-event list --space <space> --where "Action = 'Apply'"
```

The `--change-desc` captured at mutation time (see `cub-mutate`) makes the revision history self-explaining.

## Output shaping

- `--json` / `--yaml` — structured.
- `--jq <expression>` / `--yq <expression>` - selected structured properties.
- `--quiet` + `--output-jq '<expr>'` — post-process function output with jq.
- `--output-only` / `--output-values-only` — strip the envelope for function results.
- Pipe to `wc -l`, `sort -u`, etc. for quick counts.

## Tool boundary

- Allowed: `cub unit list`, `cub revision list`, `cub space list`, `cub function do` with getter/validator functions, `cub trigger list`, `cub filter list`, etc.
- Not allowed: mutating functions from a query skill. If the answer to a query suggests a fix, hand off to `cub-mutate`.

## Stop conditions

- User's intent has shifted to mutation — hand off to `cub-mutate`.
- Query result set is large and unfiltered. Ask for a narrower scope before dumping thousands of rows.

## Verify chain

Queries are read-only; the "verify" is cross-checking:

1. Summarize the result in plain English ("12 Deployments across 4 spaces run more than 5 replicas; here they are").
2. When counts matter, show the count AND a spot-check of specific entries.
3. Offer the GUI link for deeper exploration: `cub unit get <slug> --space <space> --web`.

## Evidence

- `cub unit get <slug> --space <space> --web` — the Unit page.
- `cub space get <slug> --web` — Space page with attached Triggers/Filter.
- `cub revision list <slug> --space <space> --web` — revision history.

## References

- `references/filters-and-queries.md` — full filter vocabulary, named Filter entities, operational recipes (apply-not-completed, unapplied-changes, not-approved, has-apply-gates, needs-upgrade, has-upstream).
- `references/cub-cli.md` — where/where-data/output flags.
- `references/functions-catalog.md` — getter functions by purpose.
