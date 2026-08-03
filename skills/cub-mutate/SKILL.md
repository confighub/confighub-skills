---
name: cub-mutate
description: 'Change data inside an existing ConfigHub Unit, preferring a function over a hand-edit. Use for "update the image", "bump the replicas", "change the env var", "set the annotation", "run the defaults", "edit this unit", or a bulk edit across many units. Not for creating a brand-new Unit (use confighub-core).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit update *) Bash(cub function *) Bash(cub run *) Bash(cub unit tag *) Bash(cub tag create *) Bash(cub changeset create *) Bash(cub changeset update *) Bash(cub filter create *) Bash(cub link create *) Bash(cub link update *)
---

# cub-mutate

The get / modify / write-back loop for ConfigHub Units.

## The rule

**Prefer a function over a hand-edit.** Functions like `set-container-image`, `set-replicas`, `set-env-var`, the defaults family — hermetic, idempotent, comment-preserving, and produce clean revisions. Hand-editing YAML is the fallback when no function fits.

## When to use

- Any single-field change: image, replicas, env var, port, annotation, label, resource requests/limits, probe, security context, hostname.
- Running the defaults functions against one or many Units.
- Bulk changes across multiple Units via `--where` / `--where-data` — usually inside a ChangeSet (see below).
- Restoring a Unit to a prior revision (or a ChangeSet's pre-open state).
- Patching metadata (labels, annotations) on one or many Units.

## Do not load for

- Creating a new Unit (`confighub-core`).
- Pure inspection / query (`cub-query`).
- Setting up Triggers or ApplyGates (`triggers-and-applygates`).

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. User has write permission on the target Space(s).
3. The Space is covered by a `TriggerFilterID` (or its Triggers are otherwise in place) so validation will enforce the change. If not, suggest `triggers-and-applygates` — but don't block.

## Decision tree

```
Does a purpose-built function do this (set-container-image, set-replicas, defaults family, …)?
         │
    ┌────┴────┐
   yes       no
    │         │
    ▼         ▼
cub function set <fn>    Is this a small, surgical path edit (1–3 fields)?
                               │
                          ┌────┴────┐
                         yes       no
                          │         │
                          ▼         ▼
             cub function set set-bool-path / set-int-path / set-string-path / set-cel
                          │
                          no again
                          ▼
             cub function set -- yq-i '<yq-i expression>'   (catch-all; still via a function)
                          │
                          genuinely needs a whole-unit rewrite
                          ▼
             cub unit data … → edit locally → cub unit update
                          │
                          ▼
Restoring history instead? cub unit update --restore <revision-or-tag>
```

`yq-i` is the escape-hatch mutator: full yq expression power, still invoked via `cub function set`, still records a proper revision with your `--change-desc`. Its non-mutating counterpart `yq` is in `cub-query`'s territory (reading a value out). Don't confuse the two — the `-i` suffix is the only difference and it's the difference between read and write.

## The loop

### 1. Clarify intent briefly

Ask only what you need to compose the mutation:

- Which Unit(s)? (Single slug, a `--where` filter, or a `--where-data` filter.)
- What field or behavior changes?
- Which Space? (Single Space vs. `--space "*"` for fleet-wide.)

Record answers as condensed clarifications for `--change-desc`.

### 2. Pick the function

Consult `references/functions-catalog.md`. Examples:

| Change                   | Function                                                                  |
| ------------------------ | ------------------------------------------------------------------------- |
| Container image          | `set-container-image <container> <image>`                                 |
| Image tag only           | `set-container-image-reference <container> <ref>`                         |
| Replicas                 | `set-replicas <replicas>`                                                 |
| Env var                  | `set-env-var <container> <var> <value>` / `set-env <container> key=value` |
| Resource requests/limits | `set-container-resources`                                                 |
| Probe                    | `set-container-probe-defaults` (defaults) or `set-starlark` (surgical)    |
| Annotation / label       | `set-annotation` / `set-label`                                            |
| Generic path             | `set-string-path` / `set-int-path` / `set-bool-path` / `set-starlark`     |

Deprecated — don't reach for: `set-image`, `set-image-reference`, `set-image-uri`, `cel-validate`, `no-placeholders`, `is-approved`.

### 3. Scope the target

- Single unit: `--space <space> --unit <slug>` (bulk-only commands like `cub function set` / `cub run` accept `--unit` as a shortcut for `--where "Slug = '<slug>'"`; also takes a comma list or UUID).
- Many units by metadata: `--space <space> --where "Labels.Environment = 'prod'"`.
- Cross-space: `--space "*" --where …`.
- By content: `--where-data "spec.replicas > 5"`.

### 4. Compose change description

Always required. Format:

```
<summary line>

User prompt: <verbatim user prompt, trimmed if very long>
Clarifications: <condensed — one line per resolved ambiguity, or "none">
```

For bulk `cub run` / `cub function set` across many Units: phrase the summary so it reads sensibly at the per-unit granularity (the same description is recorded in every affected Unit's head revision).

### 5. Run

```bash
cub function set \
  --space <space> \
  --unit <slug> \
  --change-desc "<composed description>" \
  -o mutations \
  -- \
  <function-name> [function args]
```

`-o mutations` prints a diff of the configuration change, so you and the user can see exactly what landed. Include it on mutating calls by default — it's the same diff that will show up in the Unit's revision history, surfaced inline so you don't have to chase it with `cub unit diff` afterward.

`--dry-run` will return what the modified data would look like, but without persisting the change. It can be used with `-o mutations`.

For multi-Unit runs, add `--wait` so you see completion.

### 6. Whole-unit replacement (fallback)

Only when no function composition does the job:

```bash
cub unit get <slug> --space <space> -o yaml > /tmp/edit.yaml
# edit /tmp/edit.yaml preserving literal values
cub unit update --space <space> <slug> /tmp/edit.yaml \
  --change-desc "<composed description>"
```

`cub unit update` also supports `-o mutations`, `--dry-run`, and `--wait`.

### 7. Restore a prior revision

```bash
cub unit update --space <space> <slug> --restore <rev-num-or-tag> \
  --change-desc "Restore to rev <N>. User prompt: …  Clarifications: …"
```

Valid `--restore` targets: a number (absolute or negative-relative), `LiveRevisionNum`, `LastAppliedRevisionNum`, `Tag:<tag>`, `ChangeSet:<name>`, `Before:ChangeSet:<name>` (pre-open state), a revision UUID.

## Running a saved Invocation

An [Invocation](https://docs.confighub.com/markdown/background/entities/invocation.md) is a saved function call (function name + arguments). Run a **mutating** one with:

```bash
cub invocation invoke set <slug> \
  --space <space> --unit <slug-or-where> \
  --change-desc "<composed description>" \
  -o mutations \
  --param <name>=<value>          # repeat per declared parameter
```

`cub invocation invoke` is verb-scoped like `cub function get/set/vet`: `set` runs only mutating Invocations, `get` only non-mutating, `vet` only validating — so the verb both picks the right Invocation kind and scopes agent permissions to the operation class. For mutations, always use `set`. It reuses the same flags as `cub function set` (`--space`, `--where`/`--unit`/`--filter`, `--changeset`, `--dry-run`, `-o mutations`, `--change-desc`).

- **Fully-bound Invocation** (no parameters): run via `cub invocation invoke set <slug>` with no `--param`, or `cub function set --invocation <slug>`.
- **Parameterized Invocation**: declares its own parameters; supply each with `--param name=value`. Values are validated (required present, no unknown names) and coerced to the declared type. A parameterized Invocation cannot be referenced by a Trigger (no caller to supply values).

Author a parameterized Invocation with `cub invocation create`, declaring parameters with `--parameter name[:datatype[:required]]` and referencing them from templated argument values via `{{ .Params.<name> }}`:

```bash
cub invocation create --space <space> scale Kubernetes/YAML \
  --parameter replicas:int:true \
  -- set-int-path apps/v1/Deployment spec.replicas 'template:{{ .Params.replicas }}'
```

Prefer a saved Invocation when the same parameterized change is run repeatedly or must be a single reviewed, permissionable operation; otherwise compose the function call inline with `cub function set` (step 5 above).

## ChangeSets — when changes span multiple Units

Any time a logical change touches more than one Unit (a release, a defaults rollout, a cross-Space upgrade, a coordinated secret rotation), wrap it in a ChangeSet. Reasons:

- **Lock.** While a Unit is in an open ChangeSet, another ChangeSet can't open against it — protects you from concurrent releases stepping on each other.
- **Atomic rollback.** A single `--restore Before:ChangeSet:<name>` against the Filter rewinds every affected Unit to its pre-open state.
- **Grouped approval.** `--revision ChangeSet:<name>` approves the end-tag revision per Unit as one set — and the end tag is a meaningful name to pin a publish to, rather than the `release-<ReleaseNum>` Tag publish creates by default.
- **Audit.** The ChangeSet's start / end Tags are recorded on every affected Unit's revision history — one name to search by, across Units and Spaces.

Lifecycle:

```bash
# 1. Create the ChangeSet (lives in one home Space; Units can be anywhere).
cub changeset create --space <home-space> <slug> \
  --description "<one-line release description>"

# 2. Open: bulk-patch target Units into the ChangeSet via a saved Filter.
cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset <home-space>/<slug> \
  --change-desc "Starting <slug> rollout"

# 3. Mutate: every function do / unit update / run must pass --changeset.
cub function set --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset <home-space>/<slug> \
  --change-desc "<summary>. User prompt: <verbatim>. Clarifications: <condensed>" \
  -o mutations \
  -- set-container-image <container> <image>:<tag>

# 4. Close with the "-" sentinel (empty string does not clear).
cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset -

# 5. Approve as a set.
cub unit approve --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --revision ChangeSet:<home-space>/<slug>

# Hand off to release-publish to ship it.
```

**Don't** use a ChangeSet for single-Unit edits (overhead without payoff) or for rolling per-Unit releases that need different approvals per Unit. See `references/changesets.md` for rollback via `Before:ChangeSet:<...>`, the merge / rebase pattern around a restored ChangeSet, and listing revisions by ChangeSet membership.

Use a **named Filter** (`cub filter create --space <home-space> <slug> Unit --where-field "…"`) over inlined `--where` so the same selection flows through open / mutate / close / approve. See `references/filters-and-queries.md`.

The `release-publish` skill goes into publishing the OCI bundle Release in more detail.

## Tool boundary

- Allowed: `cub unit / function / run / revision` — always with `--change-desc` when mutating.
- Not allowed: `kubectl apply/edit/patch/delete`, `argocd app sync` as a mutation, editing YAML outside ConfigHub and re-uploading wholesale without a function-composed path when one exists.

## Stop conditions

- The change would fill the Unit with a placeholder the user didn't ask for.
- The chosen function isn't in `cub function list` for `Kubernetes/YAML` (wrong name — re-check via `CONFIGHUB_AGENT=1 cub function list` / `cub function explain`).
- The operation is across `--space "*"` and the user hasn't confirmed the blast radius.
- An ApplyGate attaches due to validation failure. Stop, diagnose (via `triggers-and-applygates`), and fix the data — do not bypass.

## Verify chain

1. `cub unit get <slug> --space <space>` — confirm the field now reflects the intended value.
2. `cub revision list <slug> --space <space>` — new revision present, `--change-desc` matches what you composed.
3. `cub function vet --space <space> --unit <slug> vet-schemas`, `vet-placeholders`, `vet-format`, `vet-merge-keys` (or rely on Triggers) — validation passes.

## Evidence

- `cub unit get <slug> --space <space> --web` — opens the Unit's current state.
- `cub revision list <slug> --space <space> --web` — shows the revision history and the `--change-desc` recorded for each.

## References

- `references/functions-catalog.md` — the canonical function index.
- `references/cub-cli.md` — agent-mode help and flag discipline.
- `references/changesets.md` — full ChangeSet lifecycle, rollback, merge / rebase.
- `references/filters-and-queries.md` — named Filters (use these with ChangeSets).
- `references/yaml-patterns.md` — for hand-edit fallback.
- https://docs.confighub.com/markdown/guide/change-apply.md
- https://docs.confighub.com/markdown/guide/functions.md
