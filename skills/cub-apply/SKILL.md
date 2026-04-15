---
name: cub-apply
description: Use when the user wants to apply (deploy) a ConfigHub Unit or group of Units to their Target — phrases like "apply this", "deploy this to staging", "push the change to the cluster", "roll out the fix", "apply everything that's unapplied", "roll back to the last applied revision", "dry-run what would change". Runs `cub unit apply` with the right scoping (single / list / --where / --filter), handles revision-pinned apply for rollback, respects ApplyGates (never bypasses), waits for completion, and hands off to verify-delivery. Do not load for authoring changes (use cub-mutate), binding a destination (use target-bind), or pure verification (use verify-delivery / reconciliation-check).
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit apply *) Bash(cub unit cancel *) Bash(cub unit tag *) Bash(cub worker logs *) Bash(cub worker status *)
---

# cub-apply

The runtime verb. Takes a Unit's head (or a specific revision) and pushes it through its Target.

## When to use

- User asks to deploy / apply / roll out / push / promote-to-target something that's already committed to ConfigHub.
- User wants to apply every Unit in a set that has pending changes.
- User wants to roll back by applying a prior revision.
- User wants a `--dry-run` of what would change.
- User wants to cancel an in-flight apply.

## Do not load for

- Changing the Unit's data first (use `cub-mutate` — that produces a new revision, then you apply it).
- Creating the Target (use `target-bind`).
- Verifying the apply landed (use `verify-delivery` / `reconciliation-check`).

## Preflight gates

1. `cub context get` returns a user.
2. The Unit(s) have a `TargetID` (use the `has-target`-equivalent check: `cub unit list --space <s> --where "Slug = '<u>' AND TargetID IS NOT NULL"`). If missing, route to `target-bind`.
3. The Worker backing the Target is healthy: `cub worker status --space <worker-space> <worker-slug>`. If down, route to `worker-bootstrap`.
4. No ApplyGates attached, unless the plan is explicitly to *resolve* gates before apply: `cub unit list --space <s> --where "Slug = '<u>' AND LEN(ApplyGates) > 0"`. If gates are present, stop and route to `triggers-and-applygates`.
5. For rollback intent, confirm the target revision: `cub revision list <unit> --space <s>`.

## The loop

### 1. Scope the apply

| Intent | Form |
|---|---|
| One named Unit | `cub unit apply <slug> --space <s>` |
| Several named Units | `cub unit apply --space <s> --unit slug1,slug2,slug3` |
| Everything matching metadata | `cub unit apply --space <s> --where "Labels.Tier = 'backend'"` |
| Everything with pending changes | `cub unit apply --space <s> --where "HeadRevisionNum > LiveRevisionNum"` (or `--filter platform/unapplied-changes`) |
| Everything matching a saved Filter | `cub unit apply --space <s> --filter platform/unapplied-changes` |
| Cross-Space | `cub unit apply --space "*" --where "Space.Labels.Environment = 'staging'"` |

For bulk scope, always confirm blast radius with the user before running — especially `--space "*"`.

### 2. Dry-run first (for anything non-trivial)

```bash
cub unit apply --space <s> --unit <slug> --dry-run
```

`--dry-run` shows what would happen without mutating the Target. Use it whenever the apply scope is broad, the user is unsure, or the change is consequential. Cheap insurance.

### 3. Apply

```bash
cub unit apply --space <s> --unit <slug> \
  --wait \
  --timeout 2m0s
```

`--wait` blocks until the apply completes; `--timeout` caps the wait. For bulk:

```bash
cub unit apply --space <s> --filter platform/unapplied-changes \
  --wait --timeout 5m0s
```

### 4. Rollback via revision-pinned apply

Apply a specific prior revision instead of the current head:

```bash
cub unit apply <slug> --space <s> --revision LastAppliedRevisionNum   # last successful apply
cub unit apply <slug> --space <s> --revision 7                         # absolute revision
cub unit apply <slug> --space <s> --revision -1                        # relative to head
cub unit apply <slug> --space <s> --revision Tag:release-v1.0          # tagged revision
cub unit apply <slug> --space <s> --revision ChangeSet:hotfix-42       # changeset
```

This does **not** mutate the Unit's head — it just applies an older revision. To also move the Unit's head back to that revision, use `cub unit update --restore <revision>` separately (that one does take `--change-desc` — see `cub-mutate`).

### 5. Drift mode

`--drift-mode` sets how the Target reconciles drift going forward:

- `OnDemand` — reconcile only when the user asks (`cub unit refresh`, the next `cub unit apply`).
- `ContinuousApply` — worker continuously re-applies ConfigHub state, overwriting drift.
- `ContinuousRefresh` — worker continuously pulls live state back into ConfigHub's view.

Default behavior depends on the Target. Be explicit when the user's intent about drift handling is non-default; default to `OnDemand` if you must choose without guidance.

### 6. Cancel if needed

```bash
cub unit cancel <slug> --space <s>
```

Cancels an in-flight apply. Use when an apply is stuck or the user changed their mind mid-operation.

### 7. Tag the release (optional)

For intentional releases the user wants to mark:

```bash
cub unit tag <slug> --space <s> --add Tag:release-v1.2.3
```

Tagged revisions become first-class `--revision` targets (`Tag:release-v1.2.3`) for future apply / rollback.

### 8. Hand off to verify

Apply returned. That does **not** mean it landed — controllers and clusters can still disagree, or resources can still be settling. Route to `verify-delivery` immediately.

## Tool boundary

- Mutations: `cub unit apply / cancel / tag`.
- Read-only: Read set + `cub unit diff/tree/bridgestate/livedata/livestate`, `cub worker logs/status`.
- Not allowed: `kubectl apply` / `edit` / `delete`, `argocd app sync/create/delete`, `flux reconcile/suspend`. Apply flows through cub → Worker → Target. If the user wants to bypass that, they're in the wrong skill.

## Change description

`cub unit apply` is a runtime operation, not a configuration-data mutation. It does **not** accept `--change-desc`. The Unit's revision history already reflects *what* changed (via earlier `cub-mutate` calls); apply just records *when* the runtime acted. If the user wants to record rationale for an apply, do it in the preceding mutation's `--change-desc`.

## Stop conditions

- ApplyGates present on any Unit in scope. Stop; fix the data (route to `triggers-and-applygates` for diagnosis) and retry.
- No Worker healthy for the Target's provider. Stop; route to `worker-bootstrap`.
- `--space "*"` scope without explicit user confirmation of blast radius. Stop and ask.
- Apply times out (`--timeout` exceeded). Don't retry blindly — collect `cub unit bridgestate`, `cub worker logs`, surface the actual error.
- User asks to bypass a gate via Trigger removal. Refuse; fix the data instead.

## Verify chain

Right after apply:

1. `cub unit get <slug> --space <s>` — `LiveRevisionNum` advanced to match the applied revision; `LastAppliedRevisionNum` matches; `LastActionError` is empty.
2. `cub unit bridgestate <slug> --space <s>` — status reflects success.
3. Hand off to `verify-delivery` for controller + cluster agreement.

## Evidence

- `cub unit get <slug> --space <s> --web` — Unit page shows the applied revision, live state, action history.
- `cub revision list <slug> --space <s> --web` — revision history including which was last applied.

## References

- `references/cub-cli.md` — `--change-desc` scope (not on apply), `--display-mutations` (not applicable on apply).
- `references/filters-and-queries.md` — operational filter recipes (`unapplied-changes`, `apply-not-completed`, `has-apply-gates`, `needs-upgrade`).
- Companion skills: `triggers-and-applygates` (gate diagnosis), `verify-delivery` (post-apply verification), `cub-mutate` (mutation via `--restore` for head rollback).
