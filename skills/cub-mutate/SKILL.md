---
name: cub-mutate
description: 'Use whenever the user wants to change data inside a ConfigHub Unit — update an image, adjust replicas, set environment variables, add labels/annotations, change a resource field, apply defaults, or make a bulk edit across many units. This skill enforces the "prefer a function over a hand-edit" rule, composes a proper change description that captures the user''s prompt and clarifications, and chooses between `cub function do` (single function, targeted or bulk) and `cub unit update` (whole-unit replacement or restore). Load proactively any time the user says "update the image", "bump the replicas", "change the env var", "set the annotation", "apply defaults", "edit this unit", or any natural request that will end in a write to ConfigHub. Do not load for: creating a brand-new Unit (use config-as-data), reading/inspecting config (use cub-query), or setting up validation (use triggers-and-applygates).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit update *) Bash(cub function do *) Bash(cub run *) Bash(cub unit tag *) Bash(cub tag create *) Bash(cub changeset create *) Bash(cub changeset update *) Bash(cub filter create *) Bash(cub link create *) Bash(cub link update *)
---

# cub-mutate

The get / modify / write-back loop for ConfigHub Units.

## The rule

**Prefer a function over a hand-edit.** Functions like `set-container-image`, `set-replicas`, `set-env-var`, the defaults family — hermetic, idempotent, comment-preserving, and produce clean revisions. Hand-editing YAML is the fallback when no function fits.

## When to use

- Any single-field change: image, replicas, env var, port, annotation, label, resource requests/limits, probe, security context, hostname.
- Applying the defaults functions to one or many Units.
- Bulk changes across multiple Units via `--where` / `--where-data` — usually inside a ChangeSet (see below).
- Restoring a Unit to a prior revision (or a ChangeSet's pre-open state).
- Patching metadata (labels, annotations) on one or many Units.

## Do not load for

- Creating a new Unit (`config-as-data`).
- Pure inspection / query (`cub-query`).
- Setting up Triggers or ApplyGates (`triggers-and-applygates`).

## Preflight gates

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
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
cub function do <fn>    Is this a small, surgical path edit (1–3 fields)?
                               │
                          ┌────┴────┐
                         yes       no
                          │         │
                          ▼         ▼
             cub function do set-bool-path / set-int-path / set-string-path / set-cel
                          │
                          no again
                          ▼
             cub function do -- yq-i '<yq-i expression>'   (catch-all; still via a function)
                          │
                          genuinely needs a whole-unit rewrite
                          ▼
             cub unit get --data-only … → edit locally → cub unit update
                          │
                          ▼
Restoring history instead? cub unit update --restore <revision-or-tag>
```

`yq-i` is the escape-hatch mutator: full yq expression power, still invoked via `cub function do`, still records a proper revision with your `--change-desc`. Its non-mutating counterpart `yq` is in `cub-query`'s territory (reading a value out). Don't confuse the two — the `-i` suffix is the only difference and it's the difference between read and write.

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

- Single unit: `--space <space> --unit <slug>` (bulk-only commands like `cub function do` / `cub run` accept `--unit` as a shortcut for `--where "Slug = '<slug>'"`; also takes a comma list or UUID).
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

For bulk `cub run` / `cub function do` across many Units: phrase the summary so it reads sensibly at the per-unit granularity (the same description is recorded in every affected Unit's head revision).

### 5. Run

```bash
cub function do \
  --space <space> \
  --unit <slug> \
  --change-desc "<composed description>" \
  --display-mutations \
  -- \
  <function-name> [function args]
```

`--display-mutations` prints a diff of the configuration change, so you and the user can see exactly what landed. Include it on mutating calls by default — it's the same diff that will show up in the Unit's revision history, surfaced inline so you don't have to chase it with `cub unit diff` afterward.

`--dry-run` will return what the modified data would look like, but without persisting the change. It can be used with `--display-mutations`.

For multi-Unit runs, add `--wait` so you see completion.

### 6. Whole-unit replacement (fallback)

Only when no function composition does the job:

```bash
cub unit get <slug> --space <space> --yaml > /tmp/edit.yaml
# edit /tmp/edit.yaml preserving literal values
cub unit update --space <space> <slug> /tmp/edit.yaml \
  --change-desc "<composed description>"
```

`cub unit update` also supports `--display-mutations`, `--dry-run`, and `--wait`.

### 7. Restore a prior revision

```bash
cub unit update --space <space> <slug> --restore <rev-num-or-tag> \
  --change-desc "Restore to rev <N>. User prompt: …  Clarifications: …"
```

Valid `--restore` targets: a number (absolute or negative-relative), `LiveRevisionNum`, `LastAppliedRevisionNum`, `Tag:<tag>`, `ChangeSet:<name>`, `Before:ChangeSet:<name>` (pre-open state), a revision UUID.

## ChangeSets — when changes span multiple Units

Any time a logical change touches more than one Unit (a release, a defaults rollout, a cross-Space upgrade, a coordinated secret rotation), wrap it in a ChangeSet. Reasons:

- **Lock.** While a Unit is in an open ChangeSet, another ChangeSet can't open against it — protects you from concurrent releases stepping on each other.
- **Atomic rollback.** A single `--restore Before:ChangeSet:<name>` against the Filter rewinds every affected Unit to its pre-open state.
- **Grouped apply / approve.** `--revision ChangeSet:<name>` applies or approves the end-tag revision per Unit as one set.
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
cub function do --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset <home-space>/<slug> \
  --change-desc "<summary>. User prompt: <verbatim>. Clarifications: <condensed>" \
  --display-mutations \
  -- set-container-image <container> <image>:<tag>

# 4. Close with the "-" sentinel (empty string does not clear).
cub unit update --patch --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --changeset -

# 5. Apply / approve as a set.
cub unit apply --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --revision ChangeSet:<home-space>/<slug> --wait
```

**Don't** use a ChangeSet for single-Unit edits (overhead without payoff) or for rolling per-Unit releases that need different approvals per Unit. See `references/changesets.md` for rollback via `Before:ChangeSet:<...>`, the merge / rebase pattern around a restored ChangeSet, and listing revisions by ChangeSet membership.

Use a **named Filter** (`cub filter create --space <home-space> <slug> Unit --where-field "…"`) over inlined `--where` so the same selection flows through open / mutate / close / approve / apply. See `references/filters-and-queries.md`.

The `cub-apply` skill goes into the use of apply in more detail.

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
3. `cub function do --space <space> --unit <slug> vet-schemas`, `vet-placeholders`, `vet-format`, `vet-merge-keys` (or rely on Triggers) — validation passes.

## Evidence

- `cub unit get <slug> --space <space> --web` — opens the Unit's current state.
- `cub revision list <slug> --space <space> --web` — shows the revision history and the `--change-desc` recorded for each.

## References

- `references/functions-catalog.md` — the canonical function index.
- `references/cub-cli.md` — agent-mode help and flag discipline.
- `references/changesets.md` — full ChangeSet lifecycle, rollback, merge / rebase.
- `references/filters-and-queries.md` — named Filters (use these with ChangeSets).
- `references/yaml-patterns.md` — for hand-edit fallback.
- https://docs.confighub.com/guide/change-apply/
- https://docs.confighub.com/guide/functions/
