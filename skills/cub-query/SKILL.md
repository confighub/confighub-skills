---
name: cub-query
description: 'Use when the user wants to find, count, inspect, read, or audit Kubernetes workloads and application configuration stored in ConfigHub — both fleet-wide sweeps and single-workload lookups. Natural phrasing is workload- or application-centric: "where is checkout v0.4.2 deployed?", "which Deployments run more than 5 replicas?", "find workloads missing resource requests or limits", "what image tag is our nonprod worker running?", "how many replicas does our frontend have in us-east?", "is our api up to date with the latest release?", "show me the YAML / env vars / annotations of our frontend". ConfigHub-native phrasing is equally in scope: "which Units ...", "what''s in Space X", "Units with Label env=prod". Workload-in-environment phrasing like "frontend in us-east" maps to a Unit slug plus a Space slug or Space Label — see space-topology for the conventions. Load any time intent is find / list / show / which / where / how many / audit / inspect / read / what tag / is X up to date over ConfigHub-managed workloads — one workload or the whole fleet. Do not load for: mutating data (cub-mutate), authoring (config-as-data), designing the Space/Label taxonomy itself (space-topology), or live cluster state not in ConfigHub (kubectl).'
phase: verify
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *)
---

# cub-query

The database-like query surface of ConfigHub. Most users don't discover this from the CLI help alone; the skill makes it the first-reach tool for any "find / list / audit" intent.

## Why this matters

Configuration is stored as data. Every field of every resource in every Unit in every Space is queryable — by metadata (`--where`), by content (`--where-data`), by resource type, and via functions that return structured values. This replaces "clone the repo, grep, try to figure out which env does what."

The same toolkit covers two scopes:

- **Fleet sweeps** — "which workloads across the fleet match <condition>?" — think `SELECT ... FROM units WHERE ...` over the database.
- **Single-workload reads** — "what's our frontend running in us-east?" / "what image is our worker on?" — think `SELECT * FROM units WHERE id = ?` or `cat workload.yaml`.

Single-workload lookups belong here too: `cub unit data`, `cub unit livedata`, and getter functions scoped with `--unit` are the right tools, not kubectl and not a hand-edit.

### Translating workload-speak into a ConfigHub query

Users most often phrase questions in workload/application/environment terms: "our frontend in us-east", "checkout in prod", "the nonprod worker". Those map onto ConfigHub primitives:

- **Workload name** → a Unit slug (often the app or service name, sometimes with a suffix) and/or the Kubernetes `metadata.name` inside the Unit's Data.
- **Environment / region / cluster** → a Space. Teams following the one-Space-per-deployment-boundary convention encode region either in the Space slug (e.g., `prod-use2-…`) or as a Space Label (`Region=us-east-2`).
- **Fleet** → `--space "*"`, optionally narrowed with `--where "Space.Labels.Environment = 'prod'"`.

Concrete conventions (slug shapes, which Label keys are in use, whether environment is a slug prefix or a Label) belong to the team — load the `space-topology` skill if the mapping is unclear or needs to be established. Before asking the user to restate in ConfigHub terms, try `cub space list` and `cub unit list --space <candidate>` to discover the actual names.

## When to use

- "Where is <image/release/version> deployed?" — across the fleet.
- "Which Deployments / workloads have <field> <condition>?" — e.g., replicas > 5, missing resource requests or limits, using a specific registry.
- "List every Deployment / Service / Ingress / ConfigMap in <environment / region>."
- "What's the current value of <field> across environments?" — e.g., image tag of `checkout` in dev/staging/prod.
- "Audit the fleet for config violating <rule>."
- "Show the revision history / recent changes for <workload> in <environment>."
- "What's <workload> running in <environment>?" — show its YAML, one field (image, replicas, env var, annotation), or its LiveData from the cluster.
- "Is <workload> up to date with <release / upstream / sibling environment>?" — read the current value, compare to the reference.
- (Same questions phrased in ConfigHub-native terms — "which Units …", "what's in Space X", "Units with Label env=prod" — are equally in scope.)

## Do not load for

- Mutations (`cub-mutate`).
- Authoring (`config-as-data`).
- Designing the Space / Label / slug taxonomy rather than querying against it (`space-topology`).
- Live-cluster state not in ConfigHub (`kubectl get`).

## Preflight gates

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. For cross-space queries (`--space "*"`), user has read permission on the spaces of interest.

## The query toolkit

### 0. Single-workload inspection — `cub unit data` / `livedata` / `livestate` + scoped getters

For "what's our frontend running in us-east?" / "what image is our worker on?" / "show me the YAML of this workload":

```bash
# ConfigHub's declared YAML for this Unit — the content that would be applied.
cub unit data <slug> --space <space>

# What the cluster actually has, cleaned the same way `cub unit refresh` cleans
# (status stripped, controller-managed fields elided). Apples-to-apples with Data.
cub unit livedata <slug> --space <space>

# Full cluster state with .status, managedFields, everything — debugging only.
cub unit livestate <slug> --space <space>

# ConfigHub's view of Data vs LiveData for drift.
cub unit diff <slug> --space <space>
```

For **extracting one field** from one Unit (cleaner than grepping YAML), scope a getter with `--unit`:

```bash
# Image of container "worker" in one Unit.
cub function do --space <space> --unit <slug> get-container-image worker \
  --quiet --show output -o jq='.[0].Value'

# Just the tag/digest portion.
cub function do --space <space> --unit <slug> get-container-image-reference worker \
  --quiet --show output -o jq='.[0].Value'

# Replica count.
cub function do --space <space> --unit <slug> get-replicas \
  --quiet --show output -o jq='.[0].Value'

# One env var.
cub function do --space <space> --unit <slug> get-env-var worker LOG_LEVEL \
  --quiet --show output -o jq='.[0].Value'

# Any path (generic).
cub function do --space <space> --unit <slug> \
  get-string-path "spec.template.spec.containers.0.image" \
  --quiet --show output -o jq='.[0].Value'
```

If the user named the workload in application/environment terms and you don't yet know the Space or Unit slug, resolve the mapping before querying: `cub space list` to find the Space matching the environment/region (slug pattern or `Space.Labels.Region=...`), then `cub unit list --space <space>` to find the Unit matching the workload name. Do **not** guess a naming convention from another environment's Space — slugs vary. If the layout is unfamiliar, load `space-topology` for the conventions; the canonical name is always whatever `cub unit list` prints.

See `references/cub-cli.md` (Data / LiveData / LiveState / BridgeState rows) for the semantics of each read surface, and `references/functions-catalog.md` for the full getter catalog.

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

`--where` and `--where-data` select units (and other entities). To extract values from configuration data, use getter functions. For the **single-Unit** case, scope with `--unit` (see §0). The examples here sweep across Units:

```bash
# Get the current image for the "main" container of every Deployment.
cub function do --space "*" --resource-type apps/v1/Deployment \
  get-container-image main \
  --quiet --show output -o jq='.[] | {unit: .UnitSlug, space: .SpaceSlug, image: .Value}'

# Find placeholder values that still need to be filled.
cub function do --space "*" get-placeholders \
  --quiet --show output -o jq='.[] | select(.Value != null)'
```

### 4. Linting, Validation, and Policy-style analyses — `vet-` functions

```bash
# Run a validator as a one-off audit (without attaching a gate).
cub function do --space "*" vet-placeholders \
  --quiet --show output -o jq='.[] | select(.Passed == false)'

# Custom CEL audit with a readable message per failing resource.
cub function do --space "*" \
  vet-cel 'r.kind != "Deployment" || r.spec.replicas >= 2 ? {"passed": true} : {"passed": false, "details": [r.metadata.name + " has < 2 replicas"]}' \
  --quiet --show output -o jq='.[] | select(.Passed == false) | {unit: .UnitSlug, details: .Details}'
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

- `-o json` / `-o yaml` — structured.
- `-o jq=<expression>` / `-o yq=<expression>` — selected structured properties.
- `-o name` — slugs only (space-resident entities print as `<space-slug>/<slug>`).
- `--show output -o jq=<expr>` — post-process function output with jq.
- `--show output` / `--show values` — strip the envelope for function results.
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
- `references/cub-cli.md` — `cub unit data` / `livedata` / `livestate` / `bridgestate` semantics (see the "Data / LiveData / LiveState / BridgeState" table) and the where/where-data/output flags.
- `references/functions-catalog.md` — getter functions by purpose (`get-container-image`, `get-container-image-reference`, `get-replicas`, `get-env-var`, `get-*-path`, `get-placeholders`, etc.).
