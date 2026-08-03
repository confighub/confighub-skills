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

Quick sketch here; the full filter vocabulary, named-Filter entities, and common operational recipes (`unpublished-changes`, `not-approved`, `has-apply-gates`, `needs-upgrade`, `has-upstream`) are in `references/filters-and-queries.md` — reach for that when building queries.

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

Entity metadata attributes are entity-specific. Common ones on Units: `Slug`, `DisplayName`, `SpaceID`, `Space.Slug`, `Space.Labels.<Key>`, `Labels.<Key>`, `ToolchainType`, `TargetID`, `HeadRevisionNum`, `LiveRevisionNum`, `LastAppliedRevisionNum`, `UpstreamRevisionNum`, `UnappliedChanges`, `ApprovedBy`, `ApplyGates`. Common ones on Triggers: `Slug`, `Space.Slug`, `Event`, `FunctionName`, `ToolchainType`, `Validating`, `Disabled`. Confirm with the entity's `--help` and `cub <entity> get -o json` when composing a new query.

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

## A Unit's four "what's in it" views

Four related but distinct blobs a Unit can expose. Confusing them leads to wrong diffs and wrong decisions during drift / verification / rollback.

| View            | Command                                   | What it is                                                                                                                                                                                                                                         | When to read it                                                                                                                                                                                                        |
| --------------- | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Data**        | `cub unit data <slug> --space <s>`        | The current head revision's declared configuration — the YAML ConfigHub would bundle in a Release.                                                                                                                                                               | Authoring, reviewing a pending change, comparing to LiveData to assess drift.                                                                                                                                          |
| **LiveData**    | `cub unit livedata <slug> --space <s>`    | The cluster's current resources, cleaned up the same way the Worker cleans during refresh / import (status stripped, controller-managed fields elided per `ignoredFieldManagers`). **This is what a `cub unit refresh` would write back to Data.** | Comparing to Data for drift: same shape as Data, apples-to-apples.                                                                                                                                                     |
| **LiveState**   | `cub unit livestate <slug> --space <s>`   | The cluster's resources with nothing elided — full `.status`, `.metadata.managedFields`, controller-written fields, everything.                                                                                                                    | Debugging the workload itself (is a controller reporting an error? is status wedged? what managers own which fields?). Not for drift diffs against Data — too noisy.                                                   |
| **BridgeState** | `cub unit bridgestate <slug> --space <s>` | A bridge-implementation blob whose contents vary by bridge. | Bridge-specific diagnosis. Not a health check for Worker or Target connectivity. |

> **OCI / ConfigHub delivery caveat.** The OCI and ConfigHub bridges are *server workers* that perform no remote read — on refresh they echo the published `Data` back as `LiveData` / `LiveState`. So for an OCI Target these "live" views reflect what ConfigHub published, **not** the running cluster. The actual cluster state is converged and observed via ArgoCD / Flux / `kubectl` (read-only), outside ConfigHub. The cluster-read descriptions in the rows above apply only to external cluster-reading bridges, which aren't part of the OCI/ConfigHub delivery model.

Rules of thumb:

- **Drift diff = Data vs LiveData.** Stripping status / controller fields on both sides avoids false positives.
- **Cluster debug = LiveState.** When you need to see what Kubernetes actually reports, including `.status` and managedFields.
- **Ownership check = BridgeState.** Mostly when answering "did ConfigHub's bridge create / register / track this?"

## Output flags

`-o/--output <format>` is the single kubectl-style flag for alternative output. Values:

- `-o json` / `-o yaml` — structured output, suppresses default.
- `-o name` — slugs only (one per line). Space-resident entities print as `<space-slug>/<slug>`.
- `-o jq=<expr>` / `-o yq=<expr>` — post-process inside cub. Prefer this over piping to external `jq`/`yq` — one fewer process, one fewer shell-quoting hazard.
- `-o custom-columns=<spec>` — column projection on list commands (same as `--columns`).
- `-o mutations` — diff of the configuration mutations a mutating command just produced. Works on `cub unit update`, `cub unit refresh`, `cub function do|set`, `cub run`, with or without `--dry-run`.
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

`cub <entity> get` and `cub <entity> list` wrap the requested entity alongside related entities in one JSON envelope. `cub unit get` returns an object with top-level keys like `Unit`, `Space`, `Target`, `BridgeWorker`, `UnitStatus`, `LatestUnitEvent`. `cub space get` has `Space`, `TriggerFilter`, `Triggers`, `TargetCountByToolchainType`, `TotalUnitCount`, etc. Lists wrap each row in the same shape.

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

Any command that mutates configuration data (`cub unit update` / `cub unit update --patch`, `cub unit refresh`, `cub function do|set|exec`, `cub run`) accepts `-o mutations`, which prints a diff of the configuration change the command just produced. Include it on mutating calls by default — it's the cheapest way to verify the mutation did what you intended and gives the user something concrete to see in session output. Works with or without `--dry-run`. The diff is the same one surfaced in the Unit's revision history afterward.

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
- `cub function vet|get` are read-only but haven't yet been added to all of the skill permissions lists.

### Write set (add these to the Read set for mutating skills)

```
Bash(cub space create *) Bash(cub space update *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub trigger create *) Bash(cub trigger update *) Bash(cub filter create *) Bash(cub filter update *) Bash(cub target create *) Bash(cub target update *) Bash(cub worker create *) Bash(cub worker update *) Bash(cub link create *) Bash(cub link update *) Bash(cub function *) Bash(cub run *)
```

### Known ambiguity

`cub function do` and `cub run` can invoke either getter/validator functions (read) or mutating functions (write). The function name appears after `--`, which shell-glob patterns past the double-dash can't reliably match. Both verbs live in the Write set only. Read-only skills must do queries with `cub function get` or `cub function vet`, or `cub unit list --where-data`, `cub unit get`, `cub revision list`, etc. `cub function set|do --dry-run` is also read-only, but has the difficulty previously mentioned with glob patterns.

### Do not grant

- `Bash(cub * delete *)` — destructive; put it in a dedicated skill with explicit flow control.
- `Bash(cub *)` — too broad. Skills should declare exactly what they need.
