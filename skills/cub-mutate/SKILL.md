---
name: cub-mutate
description: 'Change data inside an existing ConfigHub Unit, preferring a function over a hand-edit, and write it so it still works in every variant. Use for "update the image", "bump the replicas", "set the annotation", "apply defaults", a bulk edit, or "why did that change miss some variants?". Not for creating a Unit (kubernetes-resources).'
phase: act
allowed-tools: []
read-capability-subset: cub-mutate
---

# cub-mutate

**Authority boundary:** this companion is knowledge/read-only. It may inspect and prepare an exact proposal, but it must not execute create, update, approve, promote, publish, withdraw, install, or delete operations. The external mutation broker is `NOT_INTEGRATED`, so every mutation path ends in `ASK` or `BLOCK`.

The get / modify / write-back loop for ConfigHub Units.

## The rule

**Prefer a function over a hand-edit.** Functions like `set-container-image`, `set-replicas`, `set-env-var`, the defaults family — hermetic, idempotent, comment-preserving, and produce clean revisions. Hand-editing YAML is the fallback when no function fits.

**And write the invocation so it works somewhere else too.** A mutation is rarely a one-off: it runs across whatever selection you give it, it propagates to every downstream variant, and — because an upgrade now *replays* the upstream's recorded invocations against each variant rather than copying the paths they touched — it will be re-run later against data that has changed since. See [Write invocations that generalize](#write-invocations-that-generalize).

## When to use

- Any single-field change: image, replicas, env var, port, annotation, label, resource requests/limits, probe, security context, hostname.
- Applying the defaults functions to one or many Units.
- Bulk changes across multiple Units via `--where` / `--where-data` — usually inside a ChangeSet (see below).
- Making a change hold against the next promotion (`--protect`), or working out why an earlier change missed some variants.
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
             cub function set -- set-yq '<yq expression>'   (catch-all; still via a function)
                          │
                          genuinely needs a whole-unit rewrite
                          ▼
             cub unit data … → edit locally → cub unit update
                          │
                          ▼
Restoring history instead? cub unit update --restore <revision-or-tag>
```

`set-yq` is the escape-hatch mutator: full yq expression power, still invoked via `cub function set`, still records a proper revision with your `--change-desc`. Its non-mutating counterpart `get-yq` is in `cub-query`'s territory (reading a value out). Don't confuse the two.

## Write invocations that generalize

An invocation that only works against the data in front of you fails **silently** in the variants where it does not match: most functions do not error when they find nothing to operate on, deliberately, because that is what lets one invocation run across a bulk selection. So the failure mode is a variant that quietly did not change, not an error message.

### Refer to things by identity, not position

The most common reason an invocation stops working elsewhere is a hardcoded index.

```bash
# Fragile — whichever container happens to be first in this unit.
cub function set --space prod --unit backend \
  -- set-string-path apps/v1/Deployment "spec.template.spec.containers.0.image" ghcr.io/acme/api:v2

# Portable — the container named "api", wherever it appears.
cub function set --space prod --unit backend \
  -- set-container-image api ghcr.io/acme/api:v2
```

`containers.0` selects position 0. A variant that adds a sidecar, or orders its containers differently, has a different container there — and writing to it *succeeds*, because position 0 exists. Nothing fails; the wrong container is modified. Selecting by name is stable under both reordering and insertion, because ConfigHub matches the element rather than counting to it.

Three forms of the same rule:

- **Prefer a purpose-built function** — `set-container-image`, `set-env-var`, `set-container-resources` — over a generic path setter. They already select their target by merge key.
- **When a path is unavoidable, use one that selects.** ConfigHub paths match by merge key: `spec.template.spec.containers.?name=api.image` selects the container named `api`.
- **Keep arguments parameters, not data.** An argument that *names* what to change is portable. An argument carrying a list computed from one Unit's current contents only applies to that Unit.

The same rule applies to expressions written in CEL, yq, and Starlark.

### Merge keys are identity — avoid renaming them

ConfigHub matches array elements by merge key (the container name, the volume name), like Kubernetes strategic merge patch and kustomize. A name identifies the element, so changing it makes it a different element as far as the merge engine and every stored invocation are concerned.

Rename a container from `web` to `frontend` in a downstream variant and every stored invocation naming `web` stops reaching that variant — without failing. Merge-key changes also break patches across variants. If a variant genuinely needs a differently-purposed container, add one and remove the old one: that states it directly. When a rename is unavoidable, treat it as a breaking change for that variant and update the invocations that name the old value.

### Plan for a different number of matches

Variants contain more or fewer resources, containers, ports, and volumes.

- **Search for all relevant occurrences** — the `*` wildcard, or a function that searches by value such as `set-image-reference-by-uri`.
- **Select only the relevant occurrences** — don't assume the path occurs once. Narrow with `--where-resource`, or with an expression in CEL/yq/Starlark, so the invocation doesn't touch paths it shouldn't.

Where a template would express variation with conditional logic or per-environment values files — implicit reasons, buried in a directory layout — make the high-level characteristic **explicit**: put `highly-available`, `pci-compliant`, and the like on the Space or the resource as a label/annotation, then target invocations with a Unit or resource filter over it.

### Dry-run across the variants first

`--dry-run` takes the same selection bulk execution does, so an invocation can be checked against every variant before it becomes history:

```bash
cub function set --space "*" --where "Slug = 'deployment'" --dry-run -o mutations \
  -- set-container-image web ghcr.io/acme/app:v2
```

Two things in that output are worth reading:

- **Variants that report no mutation.** The invocation matched nothing there — the container is absent, or renamed. This is the case that is hardest to notice later, because it produces no error and no change.
- **Variants that changed something unexpected**, or more paths than intended. The invocation is not selective enough.

Either is cheap to fix while the change is still a proposal.

### Protect only what this variant owns

The other half of a change reaching the right variants is a change not overwriting what a variant set deliberately. ConfigHub records protection per path, and a merge does not overwrite a protected one.

- **A variant's own value is preserved only if someone said so.** Protection is opt-in: pass `--protect` on the change that sets it, or mark the path afterwards with `cub unit set-protection --protect`.
- **Automation applying a value it did not choose passes neither.** A script propagating a release should leave `--protect` off, so the path stays open to the next upgrade.
- **Protecting a path is a standing decision.** Once protected, upstream changes to it are *reported* rather than applied; `cub unit conflicts` lists what was withheld and can apply the ones you want.

See `references/cub-cli.md` → "Protection and merge conflicts".

### Checklist

Before an invocation becomes part of the history:

1. Does it select what it changes by name, rather than by position?
2. Is there a purpose-built function for this change?
3. If it takes a path, does the path select by merge key?
4. Does it select precisely the resources and paths that should be affected?
5. Has it been dry-run across `--space "*"`, and were the variants reporting no mutation accounted for?
6. Does it rename a merge key that other invocations refer to?
7. If it sets a value the variant owns, does it pass `--protect` — and if it is automation applying a value decided elsewhere, does it leave the flag off?

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

### 5. Emit the exact mutation proposal

```bash
cub function set \
  --space <space> \
  --unit <slug> \
  --change-desc "<composed description>" \
  -o mutations \
  -- \
  <function-name> [function args]
```

Add `--protect` **only** when this value is the variant's own decision, to be held against the next upgrade from upstream. Leave it off when the change is propagating a value chosen elsewhere — a release rollout, a replayed change — because a change that protected everything it wrote would turn upstream content into local overrides and block every later merge. Neither choice is reversible by accident: a change never *removes* protection, `cub unit set-protection --unprotect` does.

`-o mutations` makes an externally authorized execution return the resulting diff. Include it in the proposed command, but do not claim anything landed before the broker executes and a fresh revision read verifies it.

**Approved-state CAS boundary.** The v0.2.11 server does have a transactional Unit primitive: `createUpdateFunction` can compare caller-supplied `HeadRevisionNum` plus `DataHash`/`ContentHash` with the current Unit inside `RunInTx`, and raw patch bodies can carry those fields. The current companion does not have a protected, digest-pinned catalog action that carries the reviewed per-Unit values through final requests and receipts; stock restore/function/run/update convenience commands do not prove that binding. Therefore every authoritative Unit mutation returns `APPROVED_STATE_CAS_NOT_INTEGRATED`. This is an integration gap, not a claim that ConfigHub lacks CAS.

`--dry-run` will return what the modified data would look like, but without persisting the change. It can be used with `-o mutations`.

For a multi-Unit proposal, include `--wait` so the external executor can return completion evidence.

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

## Proposing a saved Invocation execution

An [Invocation](https://docs.confighub.com/markdown/background/entities/invocation.md) is a saved function call (function name + arguments). Prepare a **mutating** Invocation proposal with:

```bash
cub invocation invoke set <slug> \
  --space <space> --unit <slug-or-where> \
  --change-desc "<composed description>" \
  -o mutations \
  --param <name>=<value>          # repeat per declared parameter
```

`cub invocation invoke` is verb-scoped like `cub function get/set/vet`: `set` runs only mutating Invocations, `get` only non-mutating, `vet` only validating — so the verb both picks the right Invocation kind and scopes agent permissions to the operation class. For mutations, always use `set`. It reuses the same flags as `cub function set` (`--space`, `--where`/`--unit`/`--filter`, `--changeset`, `--dry-run`, `-o mutations`, `--change-desc`).

- **Fully-bound Invocation** (no parameters): propose `cub invocation invoke set <slug>` with no `--param`, or `cub function set --invocation <slug>`.
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
- **Grouped review, not exact native approval.** The CLI-advertised non-head
  ChangeSet approval selector is retained as `non-head-unit-approval` in the
  no-loss inventory, not reproduced as selectable guidance here. Server
  v0.2.11 rejects non-head selectors. Omitted/`HeadRevisionNum` approval has
  no expected RevisionID/DataHash CAS, so it cannot prove the reviewed
  ChangeSet heads were the heads approved at execution time. A ChangeSet also
  does not select or narrow a Space Release.
- **Audit.** The ChangeSet's start / end Tags are recorded on every affected Unit's revision history — one name to search by, across Units and Spaces. The start tag marks each Unit's head as it was *before* the ChangeSet opened, so attaching creates no revision and a Unit that joined but never changed still rewinds with the rest.
- **The only practical undo for a promotion.** An upgrade walks its range and records one revision per upstream revision that had an effect, so there is no single "before" number to restore to. `--restore Before:ChangeSet:<slug>` is it. See `promote-release`.

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

# 3. Mutate: every function set / unit update / run must pass --changeset.
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

# 5. Hand fresh state to release-publish. It computes the complete EffectiveReleaseSet,
# separates native revision approval from execution authorization, and emits the
# whole-Space Release proposal. This companion executes none of these writes.
```

**Don't** use a ChangeSet for single-Unit edits (overhead without payoff) or for rolling per-Unit releases that need different approvals per Unit. See `references/changesets.md` for rollback via `Before:ChangeSet:<...>`, the merge / rebase pattern around a restored ChangeSet, and listing revisions by ChangeSet membership.

Use a **named Filter** (`cub filter create --space <home-space> <slug> Unit --where-field "…"`) over inlined `--where` so the same selection flows through open / mutate / close and the reviewed release proposal. See `references/filters-and-queries.md`.

The `release-publish` skill maps apply/deploy intent to the exact current Space Release contract.

## Tool boundary

- Host-ASK: read-only Unit/function/revision inspection in this skill's declared capability subset; no raw Bash is auto-allowed.
- Proposal-only: Unit/function/run/ChangeSet writes; include `--change-desc` on configuration-data mutations. Exact native revision approval remains `APPROVAL_HEAD_RACE_BLOCK`; mutation execution remains `APPROVED_STATE_CAS_NOT_INTEGRATED` until a protected action binds the server's existing per-Unit CAS fields to the reviewed artifact and receipt.
- Not allowed: executing writes without the external broker, `kubectl apply/edit/patch/delete`, controller mutation, or wholesale out-of-band replacement when a function-composed path exists.

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

- `cub space open <space> --print-url` — Space review.
- `cub unit open <slug> --space <space> --revisions --print-url` — Unit history and `--change-desc`.

## References

- `references/functions-catalog.md` — the canonical function index.
- `references/cub-cli.md` — agent-mode help and flag discipline.
- `references/changesets.md` — full ChangeSet lifecycle, rollback, merge / rebase.
- `references/cub-cli.md` → "Protection and merge conflicts" — `--protect`, `cub unit set-protection`, `cub unit conflicts`.
- `references/filters-and-queries.md` — named Filters (use these with ChangeSets).
- `references/yaml-patterns.md` — for hand-edit fallback.
- https://docs.confighub.com/markdown/guide/change-apply.md
- https://docs.confighub.com/markdown/guide/functions.md
- https://docs.confighub.com/markdown/guide/invocations-that-generalize.md
