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

Common entities: `space`, `unit`, `revision`, `trigger`, `filter`, `target`, `worker`, `function`, `run`, `link`, `variant`, `component`, `resource`, `k8s`, `release`, `changeset`.

## Context

- `cub context get` — show current space + user.
- `cub context set --space <slug>` — set default space.
- `--space <slug>` on any command overrides the default.
- `--space "*"` queries across all spaces (powerful for read / query; use carefully for mutations).

## Where-clauses and filters

Quick sketch here; the full filter vocabulary, named-Filter entities, and current revision/policy recipes (`unreleased-head`, `not-approved`, `has-apply-gates`, `needs-upgrade`, `has-upstream`) are in `references/filters-and-queries.md`. Release/controller/runtime proof is not a Unit Filter.

Three distinct flags. Get them mixed up and cub either rejects the command or silently returns the wrong rows.

### `--where "<expr>"` — on `list` and bulk-operation commands

Filters on entity metadata fields. Used by `cub unit list`, `cub trigger list`, `cub space list`, `cub filter list`, etc., and by bulk-operation commands (`cub unit update --where ...`, `cub run --where ...`, `cub function get --where ...`).

```
cub unit list --where "Slug LIKE 'app-%'"
cub unit list --space "*" --where "Space.Labels.Environment = 'production'"
cub trigger list --space "*" --where "Space.Slug = 'platform' AND FunctionName LIKE 'vet-%'"
```

### `--unit <slug|uuid>[,…]` — slug-targeting for bulk-only commands

On the bulk-operation commands that have no single-unit form — `cub function vet|get|set|do` and `cub run` — prefer `--unit` over `--where "Slug = '<slug>'"` when the Space is pinned. It's shorter, reads like what a human would actually type, and accepts multiple values (repeat the flag or comma-separate).

```
cub function vet|get|set --space <space> --unit <slug> -- <function> [args]
cub function vet|get|set --space <space> --unit a,b,c -- <function> [args]
cub run --space <space> --unit <slug> set-image <container> <image>
```

- Accepts UUIDs as well as slugs. For `--space "*"` (cross-space), slugs aren't unique across spaces — pass UUIDs, or use `--where` against other metadata.
- Composes with `--where` and `--where-data` via AND when you need to narrow further: `--unit <slug> --where "TargetID IS NOT NULL"`.
- For anything other than a slug/UUID list (label selection, `TargetID IS NOT NULL`, `LEN(ApplyGates) > 0`, etc.), stay on `--where`.

### `--where-field "<expr>"` — on `cub filter create` / `update` only

The stored metadata predicate of a named Filter entity. **Not accepted** on `list` commands or bulk operations — those use `--where`. Same SQL-ish syntax as `--where`.

```
cub filter create --space platform -o json standard-vets Trigger \
  --where-field "Space.Slug = 'platform' AND FunctionName LIKE 'vet-%'"
```

### `--where-data "<path expr>"` — on unit/function commands, and on Unit filters

Filters on configuration content (the YAML inside a Unit). Accepted by:

- `cub unit list`, `cub unit update`, `cub function vet|get|set|do`, `cub run`, and similar unit/function verbs.
- `cub filter create --space <space> <slug> Unit --where-data "..."` — valid _only_ when the Filter's `From` is `Unit`. Invalid for `Space`, `Trigger`, `Target`, or `Worker` Filters — configuration data is a Unit-level thing.

```
cub unit list --where-data "spec.replicas > 2"
cub run --where-data "spec.template.spec.containers.*.image#reference LIKE ':v1.2.3'" set-container-image ...
cub filter create --space <space> -o json replicas-hot Unit --where-data "spec.replicas > 2"
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
cub filter create --space <space> -o json deployment-filter Unit --resource-type "apps/v1/Deployment"
```

### `--where-space "<expr>"` — on `cub filter create` bulk mode

Selects destination Spaces when the filter is being bulk-created. Rarely needed; see `cub filter create --help` for the pattern.

### Attribute vocabulary for `--where` / `--where-field`

Entity metadata attributes are entity-specific. Common current Unit fields include `Slug`, `DisplayName`, `SpaceID`, `Space.Slug`, `Space.Labels.<Key>`, `Labels.<Key>`, `ToolchainType`, `TargetID`, `HeadRevisionNum`, `LastAppliedRevisionNum`, `UpstreamRevisionNum`, `ApprovedBy`, and `ApplyGates`. `LiveRevisionNum` is retained legacy bridge-era state, not current runtime proof; `UnappliedChanges` is not a field. Common Trigger fields include `Slug`, `Space.Slug`, `Event`, `FunctionName`, `ToolchainType`, `Validating`, and `Disabled`. Confirm with help and structured reads before composing a new query.

**`ResourceType` is not a `--where` / `--where-field` attribute.** It's a resource-level pseudo-attribute under `--where-data` as `ConfigHub.ResourceType`, or the dedicated `--resource-type` flag on `cub filter create` Unit filters:

```
# Wrong — ResourceType is not a --where attribute:
cub unit list --where "ResourceType = 'apps/v1/Deployment'"

# Right — --where-data pseudo-attribute:
cub unit list --where-data "ConfigHub.ResourceType = 'apps/v1/Deployment'"

# Right — at the Filter entity level:
cub filter create --space <space> -o json deployments Unit --resource-type "apps/v1/Deployment"
```

`ToolchainType` _is_ a valid `--where` attribute (`cub unit list --where "ToolchainType = 'Kubernetes/YAML'"`).

Filters are also first-class entities (`cub filter create …`) that can be referenced by slug via `--filter <space>/<slug>` — see `filters-and-queries.md` for the recipes.

**`--where` / `--where-field` / `--where-data` / `--where-resource` support AND only.** No `OR`, no parenthesized `(a OR b) AND c` compositions. The built-in operators you _can_ use include `=`, `!=`, `<`, `>`, `<=`, `>=`, `LIKE`, `NOT LIKE`, `ILIKE`, the regex family (`~`, `~*`, `!~`, `!~*`), `IN (...)`, `NOT IN (...)`, `IS NULL` / `IS NOT NULL`, and `LEN(...)`. For a disjunction, either:

- Run separate commands, one per disjunct, and union the results in the caller (Claude's head, a jq merge, or a shell loop).
- Use `IN (...)` when every disjunct differs only in one value on the same field (e.g., `kind IN ('NetworkPolicy', 'Role', 'RoleBinding')`).
- Move the disjunction out of cub entirely — separate `cub unit import` calls into separate Units, separate filters, etc.

**`--filter` takes at most one argument per command.** Stacking `--filter a --filter b` is not a conjunction — the second one either errors or wins, depending on the command. To combine a named Filter with additional predicates, use `--filter <slug> --where "<extra-expr>"`. If you need two named Filters ANDed together, create a third Filter whose `--where-field` expresses the intersection, or rephrase one as an inline `--where` clause. Also remember that when `--space <specific-space>` is already set, a "this app's Units" filter is often redundant — the Space itself scopes the selection (per `skills/confighub-core`).

## A Unit's desired view and versioned-legacy bridge views

ConfigHub v0.2.11 has sunset bridge/per-Unit delivery. `Data` remains current desired configuration. The other three commands are preserved for historical diagnosis only and must not be used as current Release/controller/runtime proof.

| View            | Command                                   | What it is                                                                                                                                                                                                                                         | When to read it                                                                                                                                                                                                        |
| --------------- | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Data**        | `cub unit data <slug> --space <s>`        | Current head Revision's declared configuration. | Authoring and desired-state review. |
| **LiveData**    | `cub unit livedata <slug> --space <s>`    | `VERSIONED_LEGACY`: retained/elided data from the former bridge path, when present. | Historical bridge diagnosis only. |
| **LiveState**   | `cub unit livestate <slug> --space <s>`   | `VERSIONED_LEGACY`: retained unelided former bridge state, when present. | Historical bridge diagnosis only. |
| **BridgeState** | `cub unit bridgestate <slug> --space <s>` | `VERSIONED_LEGACY`: bridge-implementation blob, when present. | Historical bridge diagnosis only. |

> **Current OCI Release rule.** Legacy LiveData/LiveState/BridgeState are not the running cluster and do not prove a current Space Release. Bind immutable Release/ManifestDigest, controller source, and runtime `confighub.com/origin` plus health through `verify-apply`. Bridge/per-Unit and direct ConfigHub-provider delivery are `VERSIONED_LEGACY/BLOCK`.

Rules of thumb:

- **Desired config = Data.** Compare heads/revisions inside ConfigHub.
- **Published config = exact Release plus selected RevisionIDs/DataHashes.** `LastAppliedRevisionNum` records the Revision captured by publication, not controller convergence.
- **Cluster debug = controller reads plus kubectl.** Bind those reads to ManifestDigest and `confighub.com/origin`.
- **Legacy bridge history = LiveData/LiveState/BridgeState.** Label it historical; never upgrade it into current proof.

## Output flags

`-o/--output <format>` is the single kubectl-style flag for alternative output. Values:

- `-o json` / `-o yaml` — structured output, suppresses default.
- `-o name` — slugs only (one per line). Space-resident entities print as `<space-slug>/<slug>`.
- `-o jq=<expr>` / `-o yq=<expr>` — post-process inside cub. Prefer this over piping to external `jq`/`yq` — one fewer process, one fewer shell-quoting hazard.
- `-o custom-columns=<spec>` — column projection on list commands (same as `--columns`).
- `-o mutations` — the per-path mutation view. On a mutating command (`cub unit update`, `cub function set|do`, `cub run`, `cub variant promote`, `cub unit conflicts --apply`) it is the diff that command produced, with or without `--dry-run`. On `cub unit get` it renders the Unit's stored `MutationSources`, grouped into **Locally overridden (preserved during merges)** and **Eligible for upstream merges** — which is how you read what a Unit currently protects. Add `--verbose` for each field's value and the change that set it.
- `-o wide` — all default columns on list commands.

Other:

- `--quiet` — no default output. Redundant with `-o` (any alternative output already suppresses default), but still meaningful without `-o`.
- `--no-headers` — suppress header row on list output.
- `--columns <fields>` — select columns on list commands with dynamic columns. Comma-separated or repeated.
- `-O`/`--output-file <path>` — write raw payloads (like `--show data` on function commands) to a file. Supports `{space}`, `{unit}`, `{section}` placeholders for per-unit files.

Function-command-only: **`--show <section>`** selects a sub-payload of the FunctionInvocationsResponse. Values: `output` (function Outputs), `values` (AttributeValueList Value fields), `data` (modified ConfigData from mutating functions). Combine with `-o` to format the selected section, e.g. `--show output -o json`, `--show output -o jq=<expr>`.

Deprecated but still functional (they print a migration hint when used):
`--json`, `--yaml`, `--jq`, `--yq`, `--names`, `--no-header` (singular), `--display-mutations`, `--data-only`, `--output-only`, `--output-json`, `--output-jq`, `--output-values-only`.

### `cub get` / `cub list` return an extended envelope — select with `-o jq=<expr>`

`cub <entity> get` and `cub <entity> list` wrap the requested entity alongside related entities in one JSON envelope. `cub unit get` may still expose top-level legacy siblings such as `BridgeWorker`, `UnitStatus`, and `LatestUnitEvent`; their presence does not restore bridge execution or prove current runtime. `cub space get` includes `Space`, `TriggerFilter`, `Triggers`, target counts, and Unit counts. Lists wrap each row in the same shape.

Always **`-o json`** (or `-o jq=<expr>`) first when you don't already know the field layout — the default human output and the `-o json` structure diverge in naming (the display label "Where Trigger" does not correspond to a `WhereTrigger` JSON key, for instance).

Use `-o jq=<expr>` to drill in:

```bash
# One entity field.
cub unit get <slug> --space <s> -o jq='.Unit.TargetID'

# A pick from the core entity.
cub unit get <slug> --space <s> -o jq='.Unit | {Slug, HeadRevisionNum, LiveRevisionNum, TargetID}'

# Combine the entity with related siblings — .BridgeWorker is a sibling of .Unit, not a field of it.
cub unit get <slug> --space <s> -o jq='{target: .Unit.TargetID, worker: .BridgeWorker.Slug}'

# Just the core entity.
cub unit get <slug> --space <s> -o jq='.Unit'

# List — unwrap per-row.
cub unit list --space <s> -o jq='.[].Unit | {Slug, HeadRevisionNum, LiveRevisionNum}'
```

Do **not** write `cub ... -o json | jq '...'` — use `-o jq=<expr>` to avoid the extra pipe and quoting. Do **not** assume bare fields are at top level (`-o jq='.Slug'` on a `cub unit get` response returns `null`; the correct form is `-o jq='.Unit.Slug'`).

### `--show output -o <json|yaml|jq|yq>` wraps each Unit's function output in an envelope

Function output, when formatted structured, is wrapped per Unit so results can be correlated back to their source:

```
{
  "SpaceID":    "<uuid>",
  "UnitID":     "<uuid>",
  "SpaceSlug":  "<slug>",
  "UnitSlug":   "<slug>",
  "OutputType": "ValidationResult" | "ValidationResultList" | "AttributeValueList" | "ResourceInfoList" | "ResourceList" | "YAML",
  "Output":     <decoded payload>
}
```

Reach for `.Output[]` to iterate the underlying list, and `.SpaceSlug` / `.UnitSlug` for identity:

```bash
# Validation results with unit identity. `. as $e` binds the envelope so it's visible inside .Output[].
cub function vet --space "*" vet-cel '<expr>' --show output \
  -o jq='. as $e | .Output[] | select(.Passed == false) | {space: $e.SpaceSlug, unit: $e.UnitSlug, details: .Details}'

# Replica count per Deployment.
cub function get --space "*" --resource-type apps/v1/Deployment get-replicas --show output \
  -o jq='{space: .SpaceSlug, unit: .UnitSlug, replicas: .Output[0].Value}'
```

The envelope is emitted **per Unit** — each Unit prints its own JSON object, not wrapped in an outer array. `jq`'s `.` starts at one envelope at a time. If you need to collect across units, pipe through `jq -s`.

`--show values` (scalar extraction) and `--show data` (modified ConfigData) do **not** wrap — they pass the raw payload through. Envelope only applies to `--show output` combined with `-o json|yaml|jq|yq`.

## Protection and merge conflicts

A merge from upstream — `cub variant promote`, `cub unit update --upgrade`, a resolved
UpgradeUnit/MergeUnits Link, `--merge-source`, `--merge-external-source` — decides per path whether
it may overwrite what the downstream has. **Protection is opt-in.** An ordinary change leaves each
path it writes as protected as it found it, and content arriving from a clone, an upgrade, or a
merge is recorded unprotected. So by default an upstream change reaches the downstream even if
someone here had set that path to something else.

Say a value is this variant's own in one of two ways:

```bash
# As you make the change — every path the change writes becomes a protected local override.
cub function set --space prod --unit backend --protect set-replicas 5

# Afterwards, per path, as RESOURCE_TYPE:RESOURCE_NAME:PATH (repeatable).
cub unit set-protection --space prod backend \
  --protect "apps/v1/Deployment:prod/backend:spec.replicas"

# Re-open a path so the next merge may overwrite it again.
cub unit set-protection --space prod backend \
  --unprotect "apps/v1/Deployment:prod/backend:spec.replicas"
```

`--protect` is also accepted on `cub unit update` and `cub run`. Leave it **off** for anything
applying a value decided somewhere else — a script propagating a release, a promotion — because a
change that protected everything it wrote would turn upstream content into local overrides and
block every merge after it. Neither form touches configuration data, and a new Revision is produced
only if a flag actually changes.

Read what a Unit protects with `cub unit get <slug> --space <space> -o mutations` (see the
`-o mutations` bullet above).

### Conflicts — what a merge could not apply

A merge that cannot place part of its patch does not fail and does not apply it anyway: it applies
the rest and records what it withheld on the Unit, where it stays until dealt with. The next merge
replaces the set; a merge that lands cleanly clears it.

```bash
cub unit conflicts <slug> --space <space>                      # list what is outstanding
cub unit conflicts <slug> --space <space> --apply --dry-run -o mutations
cub unit conflicts <slug> --space <space> --apply --reason ProtectedPath
cub unit conflicts <slug> --space <space> --dismiss --reason ProtectedPath
```

Reasons: `ProtectedPath` (the common one — protection reporting itself), `Subtracted`,
`DeleteShadowed`, `UnresolvedPath` (the source's path could not be located here),
`ExclusiveWithheld` / `ExclusiveCleared` (mutually exclusive fields), and `ReplayFailed`.
`--path` and `--resource` narrow further; with no selector, `--apply`/`--dismiss` act on
everything outstanding.

Applying writes the withheld value and records the path as content that came from elsewhere, so a
later upstream change to it lands normally instead of reporting the same conflict every release.
Dismissing changes no data and leaves the protection in place.

Conflicts are queryable, and `vet-no-merge-conflicts` turns them into an ApplyGate when wired as a
Trigger:

```bash
cub unit list --space "*" --where "Conflicts.*.Reason = 'ProtectedPath'"
```

## Function commands — `vet` / `get` / `set` preferred over `do`

`cub function` has four ways to invoke functions on Units. Pick the verb that matches the kind of function you're running:

- `cub function vet <fn> [args]` — validating functions only (`Validating=true`). Default output is the ValidationResult list.
- `cub function get <fn> [args]` — non-mutating functions only (`Mutating=false`, which includes both plain readonly and validating). Default output is the function's Outputs section.
- `cub function set <fn> [args]` — mutating functions only (`Mutating=true`). Defaults to the human summary; add `-o mutations` to see the diff.
- `cub function do <fn> [args]` — mixed escape hatch, accepts any kind. Use when a single command must invoke both validating/readonly and mutating functions (rare).

Each verb-scoped command validates the function kind client-side against the cached signature catalog (refreshed at login and by `cub function list`). Wrong-kind calls fail fast with a clear error.

`cub function exec <file>` is the batch form; it behaves like `cub function do` for a list of invocations loaded from a file. There is no `exec`-level kind restriction.

The `--show` flag applies only to function commands and selects which sub-payload of the FunctionInvocationsResponse is displayed: `output`, `values`, or `data` (modified ConfigData from mutating functions). Combine with `-o` to format the selected section.

## Change descriptions on mutations

`cub unit update`, `cub function set|do`, `cub run`, `cub unit update --patch` all accept `--change-desc`. **Always pass it** on mutations to configuration data. The description is stored in every affected unit's head revision. For `cub run` across many units, the same description is recorded in every affected unit — phrase it so it reads sensibly at the per-unit level.

## Showing mutation diffs

Commands that mutate configuration data (`cub unit update` / `cub unit update --patch`, `cub function do|set|exec`, `cub run`) accept `-o mutations`, which makes an externally authorized execution return its configuration diff. Include it in governed proposals by default. `--dry-run -o mutations` is a read-only preview where supported; a non-dry run remains blocked until the broker exists, and only a fresh revision read proves what persisted.

## Review links in the GUI

Use the current navigation commands rather than constructing URLs: `cub space open <space> --print-url`, `cub unit open <unit> --space <space> --print-url`, and `cub component open <component> --variant <variant> --print-url`. A navigation URL is not proof until the organization and object identity are verified.

## Read-only diagnosis tools

- `kubectl get` and `kubectl describe` — permitted metadata reads through host `ASK`. Raw `kubectl logs` is not bounded evidence merely because it has `--tail`/`--since`: it still lacks an output-byte cap and secret redaction. Worker-log diagnosis returns `WORKER_LOG_EVIDENCE_BLOCK` until the protected identity-bound wrapper exists; never follow or request all lines.
- `argocd app get`, `argocd app diff` — permitted for delivery verification.
- `flux get`, `flux stats` — permitted for delivery verification.

Do **not** use any of these to mutate. This companion prepares `cub` mutation proposals, but execution requires the external approval broker; none is integrated in the reviewed profile.

## Permission boundary for `allowed-tools` frontmatter

Version 0.4.0 grants **zero raw Bash autoallow**. Every skill declares `allowed-tools: []`. Read-only evidence commands retain their UX through the host's ordinary permission prompt (`ASK`); they are proposal knowledge, not silently trusted execution. Do not reintroduce Bash patterns until a wrapper receives a skill/capability identity and structured final argv or typed fields.

### Per-skill read-capability subsets

The machine-readable subsets are in `compatibility/read-capability-subsets.v1.json`. Each skill names its subset in frontmatter, but no subset currently grants a tool. The settings example has an empty allow array and `hooks/hooks.json` has no Bash `PreToolUse` hook.

Why enumeration matters:

- Raw shell matching cannot see final argv after shell expansion. Prefix/regex patterns are not an authority boundary, even for apparently safe `get`, `list`, or `--help` commands.
- Credentials/secrets, unbounded file reads/writes, plugins/exec, network-source/refresh flags, controller hard refresh, unknown flags, arbitrary `function get|vet`, and every mutation are excluded from any future autoallow.
- A raw read may still be proposed when it is in the skill's subset, but the host prompts. Data-bearing reads must stop if they could expose a Secret; a future wrapper must inspect typed resource/object identity before execution.
- GUI navigation remains `--print-url` plus object/org verification; it is also host-ASK.

### Known ambiguity

`cub function do` and `cub run` can invoke mutating functions. Even `cub function get|vet` is not safe as an arbitrary class: functions such as `generate-kubecontext` can mint credential-bearing output and validators may have side-effect flags. Skills may name only reviewed functions relevant to their job, execution remains host-ASK, and an unknown function/flag is `BLOCK` pending the typed registry/wrapper.

### Do not grant

- `Bash(cub * delete *)` — destructive; put it in a dedicated skill with explicit flow control.
- `Bash(cub *)` — too broad. Skills should declare exactly what they need.
- Any create/update/set-target/approve/promote/publish/install/upgrade/tag/cancel pattern.
- `kubectl exec|apply|create|rollout`, `argocd app sync`, `flux reconcile`, broad `yq`, shell redirection, pipelines, command substitution, or compound shell commands.

The old `hooks/auto-allow.sh` regex/prefix boundary was removed. It permitted credential, secret, file, plugin, refresh, and shell-expansion cases and falsely denied legitimate quoted predicates. The validator now proves that no skill, hook, or settings file can emit silent Bash allow; semantic execution remains blocked pending a final-argv wrapper rather than patched with more regex.
