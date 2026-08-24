---
name: cub-query
description: 'Find, count, inspect, or audit Kubernetes config stored in ConfigHub — cub k8s get and cub resource list to browse resources, cub unit list for Units. Use for fleet sweeps and single-workload lookups; route "currently running/deployed" claims through verify-apply, because ConfigHub metadata alone is not runtime proof.'
phase: verify
allowed-tools: []
read-capability-subset: cub-query
---

# cub-query

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. Run scoped reads through the host's normal permission flow. Route a newly requested write to its owning Skill instead of treating this query Skill as a mutation path.

The database-like query surface of ConfigHub. Most users don't discover this from the CLI help alone; the skill makes it the first-reach tool for any "find / list / audit" intent.

## Why this matters

Configuration is stored as data. Every field of every resource in every Unit in every Space is queryable — by metadata (`--where`), by content (`--where-data`), by resource type, and via functions that return structured values. This replaces "clone the repo, grep, try to figure out which env does what." Also, it is generally unnecessary to list all configuration Units or other entities and post-process locally — prefer server-side `--where` plus `-o jq`/`-o yq`.

**Ask about resources when the question is about resources.** A Unit is a container; the Deployment, Service, or ConfigMap inside it is what users actually ask about. ConfigHub extracts those resources from Unit data and indexes them, so `cub k8s get` and `cub resource list` answer resource questions directly — one row per resource, filtered server-side — instead of listing Units and digging into each one's YAML. Reach for them first for "which Deployments…", "show me the Ingresses in prod", "what's in this namespace". See [Browsing resources](#0-browsing-resources--cub-k8s-get-and-cub-resource-list).

The same toolkit covers two scopes:

- **Fleet sweeps** — "which workloads across the fleet match <condition>?" — think `SELECT ... FROM units WHERE ...` over the database.
- **Single-workload reads** — "what is desired for our frontend in us-east?" / "what image is recorded for our worker?" — think `SELECT * FROM units WHERE id = ?` or `cat workload.yaml`.

Single-workload desired-state lookups belong here too: `cub unit data` and getter functions scoped with `--unit` are the right ConfigHub tools. Legacy `livedata` is historical bridge evidence only. A currently-running claim requires controller and Kubernetes evidence through `verify-apply`.

### Translating workload-speak into a ConfigHub query

Users most often phrase questions in workload/application/environment terms: "our frontend in us-east", "checkout in prod", "the nonprod worker". Those map onto ConfigHub primitives:

- **Workload name** → a Unit slug (often the app or service name, sometimes with a suffix) and/or the Kubernetes `metadata.name` inside the Unit's Data.
- **Environment / region / cluster** → a Space. Teams following the one-Space-per-deployment-boundary convention encode region either in the Space slug (e.g., `prod-use2-…`) or as a Space Label (`Region=us-east-2`).
- **Fleet** → `--space "*"`, optionally narrowed with `--where "Space.Labels.Environment = 'prod'"`.

Concrete conventions (slug shapes, which Label keys are in use, whether environment is a slug prefix or a Label) belong to the team — load the `confighub-core` skill if the mapping is unclear or needs to be established. Before asking the user to restate in ConfigHub terms, try `cub space list` and `cub unit list --space <candidate>` to discover the actual names.

## When to use

- "What Deployments / Services / Ingresses / CRs exist in <scope>?" — the fastest path is `cub k8s get`.
- "Where does desired or published config reference <image/release/version>?" — across the fleet. If the user asks where it is actually deployed, this produces candidates and then routes to `verify-apply`.
- "Which Deployments / workloads have <field> <condition>?" — e.g., replicas > 5, missing resource requests or limits, using a specific registry.
- "List every Deployment / Service / Ingress / ConfigMap in <environment / region>."
- "What's the current value of <field> across environments?" — e.g., image tag of `checkout` in dev/staging/prod.
- "Audit the fleet for config violating <rule>."
- "Show the revision history / recent changes for <workload> in <environment>."
- "What is desired or most recently published for <workload> in <environment>?" — show its YAML or one field (image, replicas, env var, annotation), labeled with the evidence class.
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

### 0. Browsing resources — `cub k8s get` and `cub resource list`

Two read surfaces over the resources **inside** Units. Both filter server-side, so a fleet-wide sweep does not read every Unit's configuration.

**`cub k8s get`** names resource types the way `kubectl` does and is the friendlier of the two — reach for it whenever the user's question is phrased in Kubernetes terms:

```text
# Deployments in a Space. Plural, singular, short name, Kind, or full type all resolve.
cub k8s get deploy --space <space>

# Two types at once, across every Space.
cub k8s get deploy,sts --space "*"

# Everything except CRDs in one Unit ("all" excludes CustomResourceDefinition; ask for "crd" to see those).
cub k8s get all --space <space> --where "Unit.Slug = '<slug>'"

# Everything headed for one target.
cub k8s get netpol --target <space>/<target>

# Describe one resource, or print its stored YAML.
cub k8s get deploy <name> --space <space> --show detail
cub k8s get cm -n kube-system --space "*" --show data

# Deployments over one replica, in prod, whose Unit name ends in -backend.
cub k8s get deploy --space "*" \
  --where "Unit.Slug LIKE '%-backend' AND Space.Labels.Environment = 'prod'" \
  --where-resource "spec.replicas > 1"
```

Types not built in still resolve by Kind across any API group, so custom resources work: `cub k8s get externalsecrets --space "*"`. `--show` picks the view: `list` (default, one row per resource), `detail` (a `kubectl describe`-style summary), `data` (the YAML as stored). Filtering combines four independent scopes, all ANDed: `--space`/`--target`, the type/name/`--namespace`, `--where` (conditions on the resource or its containing `Unit.`/`Space.`/`Target.`), and `--where-resource` (a condition on the resource's own configuration).

**`cub resource list`** is the general form — no Kubernetes vocabulary, full `--where` reach over resource metadata and data paths. Use it for toolchains other than Kubernetes, and when you want data-path predicates:

```text
# Every Deployment in the organization.
cub resource list --space "*" --where "ResourceType = 'apps/v1/Deployment'"

# Resources not bound to any target yet.
cub resource list --space "*" --where "TargetID IS NULL"

# A named container's image, wherever it sits in the containers array.
cub resource list --space "*" \
  --where "Data.spec.template.spec.containers.?name=nginx.image LIKE 'nginx:1.%'"

# Any container running an image from a given registry.
cub resource list --space "*" --where "Data.spec.template.spec.containers.*.image LIKE 'ghcr.io/%'"

# Include the configuration data, which the default output omits.
cub resource list --space <space> --select "ResourceType,ResourceName,Data" -o json
```

Filterable metadata: `ResourceType`, `ResourceName`, `ToolchainType`, `UnitID`, `SpaceID`, `TargetID` (mirrors the containing Unit's, so it selects by where the resource will be applied). Attributes of the containing Unit and Space take a prefix — `Unit.Labels.App`, `Unit.Slug`, `Space.Labels.Environment` — and only the named fields are fetched, so filtering on a Unit label does not drag its configuration data along. `Data.` paths use the same syntax as `--where-data` on Units, including array indexes, `*` wildcards, associative matching (`?name=nginx`), and split paths; embedded accessors (`#accessor`) and parameter bindings (`@key:name`) are the exceptions — use `cub unit list --where-data` for those.

Resources are **derived from Unit data**, read-only, and re-extracted whenever a Unit changes. There is no create/update/delete: change the Unit. And like everything else here, this is configuration, not live cluster state — route "is it running?" through `verify-apply`.

Use `cub unit list` (§1–2 below) when the answer is about Units themselves: revision numbers, gates, upstream linkage, targets, ChangeSet membership.

### 0.1. Single-workload inspection — desired, published, and runtime are separate

For "what is desired for our frontend in us-east?" / "what image is recorded for our worker?" / "show me the YAML of this workload":

```text
# ConfigHub's latest YAML for a Unit — the content that would be applied. This is the config data at HeadRevisionNum.
# Configuration data is not a field on the Unit, so no `cub unit get` output format returns it.
# `cub unit data` is the command that serves it, as plain text:
cub unit data <slug> --space <space>

# ConfigHub's data at the revision most recently captured by a Space Release.
# This is publication state, not proof that a controller or cluster consumed it.
revision=$(cub unit get --space <space> <slug> -o jq=".Unit.LastAppliedRevisionNum")
cub revision data --space <space> <unit-slug> $revision

# Historical bridge reads. The current OCI Release profile does not use
# bridge/per-Unit delivery; these are not current runtime proof.
cub unit livedata <slug> --space <space>
cub unit livestate <slug> --space <space>
cub unit bridgestate <slug> --space <space>
```

For “what is running?”, bind the immutable Release/ManifestDigest, inspect Argo CD or Flux, and read the cluster through `verify-apply`. Do not answer from `LastAppliedRevisionNum`, LiveData, LiveState, or BridgeState alone.

For **extracting one field** from one Unit (cleaner than grepping YAML), scope a getter with `--unit`:

```text
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

```text
# All Deployments across all spaces.
cub unit list --space "*" --resource-type apps/v1/Deployment

# Units labeled Environment=prod.
cub unit list --space "*" --where "Labels.Environment = 'prod'"

# Units in Spaces matching a pattern.
cub unit list --space "*" --where "Space.Slug LIKE 'myapp-%'"
```

Useful current `--where` fields include `Slug`, `DisplayName`, `ToolchainType`, `Labels.<Key>`, `Space.Slug`, `Space.Labels.<Key>`, `UpstreamRevisionNum`, `HeadRevisionNum`, `LastAppliedRevisionNum` (most recently captured by publication), and `TargetID`. `LiveRevisionNum` is retained legacy bridge state, not current runtime proof. To filter on a Kubernetes resource kind, use `--where-data "ConfigHub.ResourceType = 'apps/v1/Deployment'"`; `ResourceType` is not a metadata field. `UnappliedChanges` is not a field.

### 2. Content queries — `--where-data`

Filters on the actual configuration content using path expressions:

```text
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

```text
# Get the current image for the "main" container of every Deployment.
cub function get --space "*" --resource-type apps/v1/Deployment \
  get-container-image main \
  --show values

# Find placeholder values that still need to be filled.
cub function get --space "*" get-placeholders \
  --show values
```

### 4. Linting, Validation, and Policy-style analyses — `vet-` functions

```text
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

```text
# Recent revisions on a Unit with change descriptions.
cub revision list <slug> --space <space> --where "UpdatedAt > '2026-04-01'"

# Who changed what, when — across a Space.
cub revision list --space <space> --where "UpdatedAt > '2026-04-01'"

# Historical only: retained bridge/per-Unit action history.
cub unit-action list <slug> --space <space> --where "UpdatedAt > '2026-04-01'"

# Historical apply actions across a Space.
cub unit-action list --space <space> --where "Action = 'Apply'"

# Historical apply progress events across a Space.
cub unit-event list --space <space> --where "Action = 'Apply'"
```

These historical reads do not describe current v0.2.21
Release/controller/runtime state. The short safe `--change-desc` captured at
mutation time (see `cub-mutate`) makes revision history scannable; use Release
records and receipts for publication history and the shared transcript for
fuller request context.

### 6. Protection and outstanding merge conflicts

What a variant owns, and what a merge could not deliver to it, are both queryable:

```text
# What does this Unit protect from upstream merges, and what may a merge still update?
cub unit get <slug> --space <space> -o mutations

# What did the last merge fail to apply here?
cub unit conflicts <slug> --space <space>

# Which variants have something outstanding, fleet-wide?
cub unit list --space "*" --where "Conflicts.*.Reason = 'ProtectedPath'"
cub unit list --space "*" --where "Conflicts.*.Reason = 'UnresolvedPath'"

# Which Units are behind their upstream?
cub unit list --space "*" --where "UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum"
```

`-o mutations` splits the Unit's paths into **Locally overridden (preserved during merges)** and **Eligible for upstream merges**; add `--verbose` for each value and the change that set it. Resolving a conflict is a mutation — hand it to `promote-release` or `cub-mutate`. See `references/cub-cli.md` → "Protection and merge conflicts".

## Output shaping

- `-o json` / `-o yaml` — structured output. It carries entity metadata only; configuration data is not part of any entity, so read it with `cub unit data` / `cub revision data`.
- `--select "<fields>"` / `--select "*"` — choose which metadata fields a **`list`** retrieves (comma-separated; IDs + Slug always included), e.g. a Unit's `ApplyGates`/`ApplyWarnings`, a View's `DisplayName`, or a Worker's `ProvidedInfo.FunctionWorkerInfo.SupportedFunctions`. `--select "*"` returns all of them. `Data` and `MutationSources` are not field names — naming either is a 400.
- `-o jq=<expression>` / `-o yq=<expression>` — selected structured properties. When filtering metadata like .Slug note that list and get commands return an envelope structure that contains the requested entity and related entities, so a Unit Slug would be extracted with `-o jq=.Unit.Slug`.
- `-o name` — slugs only (space-resident entities print as `<space-slug>/<slug>`).
- `--show output -o jq=<expr>` — post-process function output with jq. Each Unit's output is wrapped in a per-Unit envelope (`SpaceSlug` / `UnitSlug` / `OutputType` / `Output`), so use `.Output[]` to iterate results and `.SpaceSlug` / `.UnitSlug` for identity. See `references/cub-cli.md`.
- `--show values` — strip the envelope and emit raw scalar values from AttributeValueList outputs (one per line).
- Pipe to `wc -l`, `sort -u`, etc. for quick counts.

## Tool boundary

- Host permission: `cub unit/revision/space/trigger/filter/resource/k8s get/component` reads and specifically named, reviewed `cub function get|vet` getters/validators in this Skill's declared capability subset. Arbitrary functions are not permitted; the pack preapproves no Bash call. `cub k8s source` / `cub k8s collect` reach a cluster and are not part of this Skill — route those through `verify-apply`.
- Not allowed: mutating functions from a query skill. If the answer to a query suggests a fix, hand off to `cub-mutate`.

## Stop conditions

- User's intent has shifted to mutation — hand off to `cub-mutate`.
- Query result set is large and unfiltered. Ask for a narrower scope before dumping thousands of rows.

## Verify chain

Queries are read-only; the "verify" is cross-checking:

1. Summarize the result in plain English ("12 Deployments across 4 spaces run more than 5 replicas; here they are").
2. When counts matter, show the count AND a spot-check of specific entries.
3. Offer the GUI handoff for deeper exploration: `cub unit open <slug> --space <space> --print-url`.

## Evidence

- `cub unit open <slug> --space <space> --print-url` — Unit page.
- `cub space open <slug> --print-url` — Space page.
- `cub unit open <slug> --space <space> --revisions --print-url` — revision history.

## References

- `references/filters-and-queries.md` — full filter vocabulary and current revision/policy recipes (`unreleased-head`, `not-approved`, `has-apply-gates`, `needs-upgrade`, `has-upstream`); Release/controller/runtime proof belongs to `verify-apply`.
- `references/cub-cli.md` — `cub unit data` / `livedata` / `livestate` / `bridgestate` semantics (see the "Data / LiveData / LiveState / BridgeState" table) and the where/where-data/output flags.
- `references/functions-catalog.md` — getter functions by purpose (`get-container-image`, `get-container-image-reference`, `get-replicas`, `get-env-var`, `get-*-path`, `get-yq`, `get-placeholders`, etc.).
- `cub k8s get --help`, `cub resource list --help` — the resource-browsing surfaces above; confirm flags before composing.
