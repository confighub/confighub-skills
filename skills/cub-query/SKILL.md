---
name: cub-query
description: 'Find, count, inspect, or audit Kubernetes workloads and config stored in ConfigHub — fleet sweeps and single-workload lookups. Use for "where is checkout deployed?", "which Deployments run over 5 replicas?", "find workloads missing resource limits", "what image tag is our worker on?". Not for live cluster state (use kubectl).'
phase: verify
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function get *) Bash(cub function vet *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *)
---

# cub-query

The database-like query surface of ConfigHub. Most users don't discover this from the CLI help alone; the skill makes it the first-reach tool for any "find / list / audit" intent.

## Why this matters

Configuration is stored as data. Every field of every resource in every Unit in every Space is queryable — by metadata (`--where`), by content (`--where-data`), by resource type, and via functions that return structured values. This replaces "clone the repo, grep, try to figure out which env does what." Also, it is generally unnecessary to list all configuration Units or other entities, use --json or --yaml to output the whole entities, and then use jq and yq locally to filter entities and extract specific values.

The same toolkit covers two scopes:

- **Fleet sweeps** — "which workloads across the fleet match <condition>?" — think `SELECT ... FROM units WHERE ...` over the database.
- **Single-workload reads** — "what's our frontend running in us-east?" / "what image is our worker on?" — think `SELECT * FROM units WHERE id = ?` or `cat workload.yaml`.

Single-workload lookups belong here too: `cub unit data`, `cub unit livedata`, and getter functions scoped with `--unit` are the right tools, not kubectl and not a hand-edit.

### Translating workload-speak into a ConfigHub query

Users most often phrase questions in workload/application/environment terms: "our frontend in us-east", "checkout in prod", "the nonprod worker". Those map onto ConfigHub primitives:

- **Workload name** → a Unit slug (often the app or service name, sometimes with a suffix) and/or the Kubernetes `metadata.name` inside the Unit's Data.
- **Environment / region / cluster** → a Space. Teams following the one-Space-per-deployment-boundary convention encode region either in the Space slug (e.g., `prod-use2-…`) or as a Space Label (`Region=us-east-2`).
- **Fleet** → `--space "*"`, optionally narrowed with `--where "Space.Labels.Environment = 'prod'"`.

Concrete conventions (slug shapes, which Label keys are in use, whether environment is a slug prefix or a Label) belong to the team — load the `confighub-core` skill if the mapping is unclear or needs to be established. Before asking the user to restate in ConfigHub terms, try `cub space list` and `cub unit list --space <candidate>` to discover the actual names.

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
- Authoring (`confighub-core`).
- Designing the Space / Label / slug taxonomy rather than querying against it (`confighub-core`).
- Live-cluster state not in ConfigHub (`kubectl get`).

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. For cross-space queries (`--space "*"`), user has read permission on the spaces of interest.

## The query toolkit

### 0. Single-workload inspection — `cub unit data` / `livedata` / `livestate` + scoped getters

For "what's our frontend running in us-east?" / "what image is our worker on?" / "show me the YAML of this workload":

```bash
# ConfigHub's latest YAML for a Unit — the content that would be applied. This is the config data at HeadRevisionNum.
# cub unit get -o data is invalid. cub unit get -o jq='.Unit.Data' will return the configuration data base64 encoded and
# is not recommended. The best command to use is cub unit data:
cub unit data <slug> --space <space>

# ConfigHub's data at the applied revision. Use .Unit.LiveRevisionNum for the most recently confirmed live revision,
# if any, and .Unit.PreviousLiveRevisionNum for the previous live revision, if any.
revision=$(cub unit get --space <space> <slug> -o jq=".Unit.LastAppliedRevisionNum")
cub revision data --space <space> <unit-slug> $revision

# What the bridge reported as live at the last action. For OCI/ConfigHub server bridges this echoes the published
# Data (no cluster read); it is the running cluster only for external cluster-reading bridges. See references/cub-cli.md.
cub unit livedata <slug> --space <space>

# The unelided live-state view at the last action. For OCI/ConfigHub Targets this mirrors the published Data;
# for actual running-workload troubleshooting use kubectl / argocd / flux directly (see verify-apply).
cub unit livestate <slug> --space <space>
```

For **extracting one field** from one Unit (cleaner than grepping YAML), scope a getter with `--unit`:

```bash
# Image of container "worker" in one Unit.
cub function get --space <space> --unit <slug> get-container-image worker \
  --show values

# Just the tag/digest portion.
cub function get --space <space> --unit <slug> get-container-image-reference worker \
  --show values

# Replica count.
cub function get --space <space> --unit <slug> get-replicas \
  --show values

# One env var.
cub function get --space <space> --unit <slug> get-env-var worker LOG_LEVEL \
  --show values

# Any path (generic).
cub function get --space <space> --unit <slug> \
  get-string-path "spec.template.spec.containers.0.image" \
  --show values
```

If the user named the workload in application/environment terms and you don't yet know the Space or Unit slug, resolve the mapping before querying: `cub space list` to find the Space matching the environment/region (slug pattern or `Space.Labels.Region=...`), then `cub unit list --space <space>` to find the Unit matching the workload name. Do **not** guess a naming convention from another environment's Space — slugs vary. If the layout is unfamiliar, load `confighub-core` for the conventions; the canonical name is always whatever `cub unit list` prints.

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

### 3. Function-based extraction — `cub function get` + getters

`--where` and `--where-data` select units (and other entities). To extract values from configuration data, use getter functions. For the **single-Unit** case, scope with `--unit` (see §0). The examples here sweep across Units:

```bash
# Get the current image for the "main" container of every Deployment.
cub function get --space "*" --resource-type apps/v1/Deployment \
  get-container-image main \
  --show values

# Find placeholder values that still need to be filled.
cub function get --space "*" get-placeholders \
  --show values
```

### 4. Linting, Validation, and Policy-style analyses — `vet-` functions

```bash
# Run a validator as a one-off audit (without attaching a gate).
cub function vet --space "*" vet-placeholders \
  --show output -o jq='.Output[] | select(.Passed == false)'

# Custom CEL audit with a readable message per failing resource, correlated to its Space and Unit.
cub function vet --space "*" \
  vet-cel 'r.kind != "Deployment" || r.spec.replicas >= 2 ? {"passed": true} : {"passed": false, "details": [r.metadata.name + " has < 2 replicas"]}' \
  --show output -o jq='. as $e | .Output[] | select(.Passed == false) | {space: $e.SpaceSlug, unit: $e.UnitSlug, details: .Details}'
```

Each Unit's output is wrapped in an envelope with `SpaceID` / `UnitID` / `SpaceSlug` / `UnitSlug` / `OutputType` / `Output`. Use `.Output[]` to iterate the underlying list, and `. as $e` to bind the envelope so identity fields stay in scope inside the list. See `references/cub-cli.md` for the full schema.

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
- `-o jq=<expression>` / `-o yq=<expression>` — selected structured properties. When filtering metadata like .Slug note that list and get commands return an envelope structure that contains the requested entity and related entities, so a Unit Slug would be extracted with `-o jq=.Unit.Slug`.
- `-o name` — slugs only (space-resident entities print as `<space-slug>/<slug>`).
- `--show output -o jq=<expr>` — post-process function output with jq. Each Unit's output is wrapped in a per-Unit envelope (`SpaceSlug` / `UnitSlug` / `OutputType` / `Output`), so use `.Output[]` to iterate results and `.SpaceSlug` / `.UnitSlug` for identity. See `references/cub-cli.md`.
- `--show values` — strip the envelope and emit raw scalar values from AttributeValueList outputs (one per line).
- Pipe to `wc -l`, `sort -u`, etc. for quick counts.

## Tool boundary

- Allowed: `cub unit list`, `cub revision list`, `cub space list`, `cub function get/vet` with getter/validator functions, `cub trigger list`, `cub filter list`, etc.
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
