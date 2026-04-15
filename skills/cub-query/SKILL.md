---
name: cub-query
description: Use whenever the user wants to find, count, inspect, or audit Kubernetes configuration across ConfigHub — "where is release X deployed?", "which units run more than 5 replicas?", "show me every Deployment using the old registry", "find units missing resource limits", "list all spaces with label env=prod", "what's the current image for checkout in each environment?", "audit what we have". ConfigHub treats configuration as data, so you can query across Units and Spaces the way you'd query a database. Load this any time the user's intent is "find / list / show / which / where / how many / audit" over ConfigHub state. Do not load for: mutating data (use cub-mutate), authoring new config (use config-as-data), or live cluster queries that don't involve ConfigHub (use kubectl).
phase: verify
allowed-tools: Bash(cub context get *) Bash(cub space list *) Bash(cub space get *) Bash(cub unit list *) Bash(cub unit get *) Bash(cub revision list *) Bash(cub revision get *) Bash(cub trigger list *) Bash(cub trigger get *) Bash(cub filter list *) Bash(cub filter get *) Bash(cub target list *) Bash(cub target get *) Bash(cub worker list *) Bash(cub worker get *) Bash(cub link list *) Bash(cub link get *) Bash(cub function list *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(CONFIGHUB_AGENT=1 cub function list *) Bash(CONFIGHUB_AGENT=1 cub function explain *)
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

1. `cub context get` returns a user.
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

Useful `--where` fields: `Slug`, `DisplayName`, `ResourceType`, `Labels.<key>`, `Space.Slug`, `Space.Labels.<key>`, `UpstreamRevisionNum`, `HeadRevisionNum`.

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

When `--where-data` isn't enough, use getter functions to extract structured values:

```bash
# Get the current image for every Deployment.
cub function do --space "*" --resource-type apps/v1/Deployment \
  get-container-image main \
  --quiet --output-jq '.[] | {unit: .UnitSlug, space: .SpaceSlug, image: .Value}'

# Find placeholder values that still need to be filled.
cub function do --space "*" get-placeholders \
  --quiet --output-jq '.[] | select(.Value != null)'

# Extract a CEL expression across resources.
cub function do --space "*" --resource-type apps/v1/Deployment \
  get-cel 'resource.spec.template.spec.containers.map(c, {"name": c.name, "image": c.image})' \
  --quiet --output-only
```

### 4. Policy-style queries — `where-filter` + `vet-cel` for dry-run

```bash
# Dry-run policy: flag Deployments violating "replicas >= 2".
cub function do --space "*" \
  where-filter apps/v1/Deployment 'spec.replicas < 2' \
  --quiet --output-jq '.[] | select(.Passed) | .UnitID'

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
cub revision list <slug> --space <space>

# Who changed what, when — across a Space.
cub revision list --space <space> --where "UpdatedAt > '2026-04-01'"
```

The `--change-desc` captured at mutation time (see `cub-mutate`) makes this history self-explaining.

## Output shaping

- `--json` / `--yaml` — structured.
- `--quiet` + `--output-jq '<expr>'` — post-process with jq.
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

## Trust surface

- `cub unit get <slug> --space <space> --web` — the Unit page.
- `cub space get <slug> --web` — Space page with attached Triggers/Filter.
- `cub revision list <slug> --space <space> --web` — revision history.

## References

- `references/filters-and-queries.md` — full filter vocabulary, named Filter entities, operational recipes (apply-not-completed, unapplied-changes, not-approved, has-apply-gates, needs-upgrade, has-upstream).
- `references/cub-cli.md` — where/where-data/output flags.
- `references/functions-catalog.md` — getter functions by purpose.
