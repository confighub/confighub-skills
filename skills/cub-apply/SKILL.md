---
name: cub-apply
description: 'Apply (deploy) a ConfigHub Unit or group of Units to their Target via cub unit apply, respecting ApplyGates. Use for "apply this", "deploy this to staging", "push the change to the cluster", "roll out the fix", "apply everything unapplied", "apply the ChangeSet", "dry-run what would change". Not for rollback (use rollback-revision).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit apply *) Bash(cub unit cancel *) Bash(cub unit tag *) Bash(cub worker logs *) Bash(cub worker status *)
---

# cub-apply

The runtime verb. Takes a Unit's head (or a specific revision) and pushes it through its Target. For an **OCI** Target this publishes the Unit's data to ConfigHub's built-in OCI registry — ArgoCD or Flux then pull it and converge the cluster (outside ConfigHub). For a **ConfigHub** Target it applies ConfigHub-native config directly. The publish/apply itself is what `cub unit apply` does; cluster convergence from an OCI publish is verified separately (`verify-apply`).

## When to use

- User asks to deploy / apply / roll out / push / promote-to-target something that's already committed to ConfigHub.
- User wants to apply every Unit in a set that has pending changes.
- User wants to apply a ChangeSet (bulk release) via `--revision ChangeSet:<slug>`.
- User wants a `--dry-run` of what would change.
- User wants to cancel an in-flight apply.
- After `rollback-revision` has moved head — apply the restored head to push the rollback to the cluster.

## Do not load for

- Changing the Unit's data first (use `cub-mutate` — that produces a new revision, then you apply it).
- Rolling back a change (use `rollback-revision` — moves head via `cub unit update --restore`, then comes here for the apply).
- Creating the Target (use `target-bind`).
- Cutting an **immutable, point-in-time OCI Release bundle** of the Units in a Space and assigned to an OCI ProviderType Target, or withdrawing one (use `release-publish`).
- Verifying the apply landed, troubleshooting a stuck / failed apply, or closing out a release (use `verify-apply`).

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. The Unit(s) have a `TargetID` (use the `has-target`-equivalent check: `cub unit list --space <s> --where "Slug = '<u>' AND TargetID IS NOT NULL"`). If missing, route to `target-bind`.
3. The Target's worker exists. OCI and ConfigHub Targets use **server workers** (hosted in the ConfigHub server) — there's no process to be down, so no health check is needed. If the Target references a missing worker, route to `target-bind` / `worker-bootstrap`.
4. No ApplyGates attached, unless the plan is explicitly to _resolve_ gates before apply: `cub unit list --space <s> --where "Slug = '<u>' AND LEN(ApplyGates) > 0"`. If gates are present, stop and route to `triggers-and-applygates`.
5. If the user framed the request as "rollback" — stop and route to `rollback-revision`. Head must move first; `cub unit apply --revision <N>` on its own is not a rollback.

## The loop

### 1. Scope the apply

| Intent                             | Form                                                                                                                |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| One named Unit                     | `cub unit apply <slug> --space <s>`                                                                                 |
| Several named Units                | `cub unit apply --space <s> --unit slug1,slug2,slug3`                                                               |
| Everything matching metadata       | `cub unit apply --space <s> --where "Labels.Tier = 'backend'"`                                                      |
| Everything with pending changes    | `cub unit apply --space <s> --where "HeadRevisionNum > LiveRevisionNum"` (or `--filter platform/unapplied-changes`) |
| Everything matching a saved Filter | `cub unit apply --space <s> --filter platform/unapplied-changes`                                                    |
| Cross-Space                        | `cub unit apply --space "*" --where "Space.Labels.Environment = 'staging'"`                                         |

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

If `cub unit apply` times out and reports that it did not complete, that does not necessarily mean that it will not complete, but it may be worth investigating what has not completed and why.

### Applying a ChangeSet (bulk release)

When the mutations were grouped into a ChangeSet (via `cub-mutate` → `references/changesets.md`), apply the whole set with `--revision ChangeSet:<home-space>/<slug>` against the same Filter that opened it:

```bash
cub unit apply --space <target-space> \
  --filter <home-space>/<filter-slug> \
  --revision ChangeSet:<home-space>/<slug> \
  --wait --timeout 10m0s
```

Each Unit in the Filter applies its own end-tag revision; Units whose data didn't actually change inside the ChangeSet apply as no-ops (still recorded in the apply history with the ChangeSet reference). This is the canonical bulk-release apply — use it instead of looping per-Unit, and instead of a Filter-only apply that would grab each Unit's current head.

### 4. Apply a specific revision (not for rollback)

`--revision` applies a specific revision instead of the Unit's current head:

```bash
cub unit apply <slug> --space <s> --revision LastAppliedRevisionNum   # last successful apply
cub unit apply <slug> --space <s> --revision 7                         # absolute revision
cub unit apply <slug> --space <s> --revision -1                        # relative to head
cub unit apply <slug> --space <s> --revision Tag:release-v1.0          # tagged revision
cub unit apply <slug> --space <s> --revision ChangeSet:hotfix-42       # changeset
```

**Do not use `--revision` to roll back.** It applies the older revision to the cluster _without_ moving the Unit's head — the "bad" revision stays head, and the next `cub-mutate` run, promotion, or merge will re-introduce it, silently. Rollback = move head, then apply. Run `cub unit update --restore <target>` via the `rollback-revision` skill, which will hand off to this skill with head already restored. The legitimate uses of `--revision` here are applying the end-tag of a ChangeSet (bulk release, above) or applying a specific tag for a forward deploy that doesn't match head (e.g., pinning a release in a lane where head has already moved).

If the user asks to "roll back" by naming an older revision, stop and route to `rollback-revision`.

### 5. Cancel if needed

```bash
cub unit cancel <slug> --space <s>
```

Cancels an in-flight apply. Use when an apply is stuck or the user changed their mind mid-operation.

### 6. Tag the release (optional)

For intentional releases the user wants to mark:

```bash
cub unit tag release-v1.2.3 --space <s> --unit <slug>
```

Tagged revisions become first-class `--revision` targets (`Tag:release-v1.2.3`) for future apply; rollback uses them via `cub unit update --restore Tag:...` in `rollback-revision`, not via `--revision` here.

### 7. Hand off to verify-apply

Apply returned. That does **not** mean it landed — the apply may still be `Progressing` (waiting for resources to become ready), or `Failed` with the error in the latest `cub unit-event`, or `Completed` but diverged from the controller or cluster. Always route to `verify-apply` immediately, even on a clean `--wait` return. That skill classifies the outcome (`Progressing` / `Completed` / `Failed` / `Aborted`), drills into the event stream or the cluster if something's off, and closes out the release on success.

## Tool boundary

- Mutations: `cub unit apply / cancel / tag`.
- Read-only: Read set + `cub unit diff/tree/bridgestate/livedata/livestate`, `cub worker logs/status`.
- Not allowed: `kubectl apply` / `edit` / `delete`, `argocd app sync/create/delete`, `flux reconcile/suspend`. Apply flows through cub → Worker → Target. If the user wants to bypass that, they're in the wrong skill.

## Change description

`cub unit apply` is a runtime operation, not a configuration-data mutation. It does **not** accept `--change-desc`. The Unit's revision history already reflects _what_ changed (via earlier `cub-mutate` calls); apply just records _when_ the runtime acted. If the user wants to record rationale for an apply, do it in the preceding mutation's `--change-desc`.

## Stop conditions

- ApplyGates present on any Unit in scope. Stop; fix the data (route to `triggers-and-applygates` for diagnosis) and retry.
- Unit has no Target. Stop; route to `target-bind`.
- `--space "*"` scope without explicit user confirmation of blast radius. Stop and ask.
- Apply times out (`--timeout` exceeded). Don't retry blindly — collect the latest `cub unit-event` and surface the actual error.
- User asks to bypass a gate via Trigger removal. Refuse; fix the data instead.

## Verify chain

Right after apply, hand off to `verify-apply` — it owns the full post-apply arc (classify outcome, drill into events or the cluster on failure, three-way agreement, release close-out). Don't open-code the checks here.

## Evidence

- `cub unit get <slug> --space <s> --web` — Unit page shows the applied revision, live state, action history.
- `cub revision list <slug> --space <s> --web` — revision history including which was last applied.

## References

- `references/cub-cli.md` — `--change-desc` scope (not on apply), `-o mutations` (not applicable on apply).
- `references/filters-and-queries.md` — operational filter recipes (`unapplied-changes`, `apply-not-completed`, `has-apply-gates`, `needs-upgrade`).
- `references/changesets.md` — ChangeSet lifecycle (apply with `--revision ChangeSet:<slug>`; rollback with `--restore Before:ChangeSet:<slug>` done via `rollback-revision`).
- Companion skills: `triggers-and-applygates` (gate diagnosis), `verify-apply` (post-apply verification, troubleshooting, close-out), `rollback-revision` (head-moving rollback — always goes there first, then hands back here to apply).
- https://docs.confighub.com/markdown/guide/unit-sets.md
