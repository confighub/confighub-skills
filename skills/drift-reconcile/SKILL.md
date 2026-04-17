---
name: drift-reconcile
description: 'Use when ConfigHub''s Unit Data and the cluster''s live state for that Unit have diverged — phrases like "reconcile drift", "the cluster changed out of band", "someone kubectl edit''d this", "ConfigHub and the cluster disagree", "accept the live changes", "overwrite the cluster with ConfigHub", "refresh from live", "who owns this drift?", "we have drift on app-a in prod". Runs `cub unit refresh` to pull current live state, `cub unit diff` against Data, walks the decide-who-wins decision (ConfigHub wins → re-apply; cluster wins → absorb; merge → selective reconcile), and executes the chosen path. Do not load for revision history rewind (use `rollback-revision`), for post-apply verification / three-way agreement checks (use `verify-apply`), for the first-time apply of a newly-bound Unit (use `cub-apply`), or for importing wholesale live resources into a brand-new Unit (use `import-from-cluster`).'
phase: verify
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit refresh *) Bash(cub unit update *) Bash(cub unit-action get *) Bash(cub function do *) Bash(kubectl get *) Bash(kubectl describe *)
---

# drift-reconcile

Resolve divergence between a Unit's Data (what ConfigHub thinks is the desired state) and its LiveData/LiveState (what the cluster currently has). The decision isn't mechanical — it's a judgment call about which side should be authoritative for the drift, and the right answer depends on what the drift contains and how it got there.

## The three resolutions

| Resolution          | Meaning                                                                                                                                                           | Commands                                                                                                                                                                                                                         |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **ConfigHub wins**  | Drift is unauthorized / noise (manual `kubectl edit`, controller mutation, drift-by-default fields). ConfigHub's Data is the source of truth.                     | Re-apply via the `cub-apply` skill — `cub unit apply <slug>`. If the drift recurs, address the source (who's running the out-of-band edits, what controller is rewriting the field) rather than treating it as a repeat symptom. |
| **Cluster wins**    | Drift represents an intentional change made in-cluster that should now be absorbed into ConfigHub.                                                                | `cub unit refresh <slug>` (pulls LiveData into Data as a new head revision), then commit the result via `cub unit apply` when ready.                                                                                             |
| **Selective merge** | Some drift accepted, some rejected. Common when a controller adds annotations/fields you want to keep while a hand-edit you want to reject sits in the same Unit. | `cub unit refresh` to pull LiveData into a staging revision, then `cub-mutate` (functions) to keep only the subset you want, then apply.                                                                                         |

The decision goes through the user, not the skill. The skill's job is to _show_ the diff clearly, name the likely sources of drift, and execute the user's chosen resolution.

## When to use

- User says drift, divergence, out-of-band, "someone kubectl edit'd", "ConfigHub and Kubernetes disagree", "is the cluster still in sync?"
- LiveData that suggests the cluster has changed since the last apply.
- A `cub unit refresh` (run manually or by another skill) surfaced changes and the user needs to decide what to do.
- After an incident where manual cluster edits were made to stabilize production, and now the user needs to bring ConfigHub back in line.

## Do not load for

- Revision-history rollback (user wants to revert a change made _in ConfigHub_, not reconcile against the cluster) — use `rollback-revision`.
- Three-way agreement check when everything is supposed to be in sync (ConfigHub ↔ controller ↔ cluster) — use `verify-apply`. That skill assumes the apply has completed; this one handles divergence.
- `cub unit list` shows a Unit with `LiveRevisionNum != LastAppliedRevisionNum`. That indicates an incomplete or stuck apply or destroy.
- First-time apply of a Unit that was just bound to a Target — use the `cub-apply` skill.
- Bringing new, unmanaged resources into ConfigHub for the first time — use `import-from-cluster` (which _creates_ a Unit from live state; drift-reconcile operates on existing Units).

## Preflight gates

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. The affected Unit(s) have a Target bound and a healthy Worker:
   ```bash
   cub unit get <slug> --space <s> -o jq='{TargetID: .Unit.TargetID, BridgeWorker: .BridgeWorker.Slug}'
   cub worker status --space <worker-space> <worker-slug>
   ```
3. User has write permission on the Space (both paths — ConfigHub-wins and cluster-wins — mutate the Unit).
4. Bulk intent is flagged up front: single Unit (surgical) vs. Filter-scoped (bulk refresh + bulk resolution).

## What the Worker already elides

Before the skill decides anything, know that the Worker's Kubernetes bridge already strips fields managed by a long list of controllers during refresh / import — HPA / VPA, Deployment / ReplicaSet / StatefulSet / DaemonSet / Job / CronJob controllers, the scheduler and cluster-autoscaler / descheduler, Istio / Linkerd sidecar injectors, Traefik ingress, cert-manager, plus `status` fields across the board. Full list: `https://github.com/confighub/sdk/blob/main/bridge-impl/kubernetes/kubernetes_lib.go` (search for `ignoredFieldManagers`).

Consequences:

- The HPA-writes-`spec.replicas` case usually doesn't show up as drift — the Worker strips it. If it _does_, the field manager isn't the HPA; dig into what's writing it.
- Linkerd / Istio sidecar annotations and init containers injected by those webhooks are stripped; you won't see them in a refresh.
- What you _will_ see is: user-owned field edits (manual `kubectl edit`, debugging patches), controllers not in the ignored list, and fields the admission chain writes but attributes to the original applier (cleaned-up SecurityContext fields, for example).

Frame the "name the likely source" step around what the Worker leaves in, not around every category of controller activity — most of the noise has already been removed.

## The loop

### 1. Identify the drift

Read the drift as **Data vs LiveData** — both are cleaned of `.status`, controller-managed fields, and the other noise the Worker already elides (`references/cub-cli.md` → "A Unit's four 'what's in it' views"). Apples to apples.

```bash
# Point diagnosis at one Unit first, even for bulk cases — the resolution choice
# should be informed by examples, not a summary.
cub unit diff <slug> --space <s> --from=LastAppliedRevisionNum --to=LiveRevisionNum

# The cluster state corresponding to the unit, cleaned, at the time of the last action (apply, refresh, or import; will be empty after destroy):
cub unit livedata <slug> --space <s>

# For cluster debugging (status, managedFields, full detail), use livestate —
# NOT for drift diffs (too noisy against Data).
# Also current at the time of the last action (apply, refresh, or import; will be empty after destroy).
cub unit livestate <slug> --space <s>
```

For a preview of what a refresh would bring in — without touching the Unit — use `--dry-run`. Refresh queues a unit-action rather than creating a new Unit revision:

```bash
opID=$(cub unit refresh --wait --space <s> <slug> --dry-run -o jq='.QueuedOperationID')
cub unit-action get --space <s> <slug> "$opID" --data    # the refreshed data that would be returned
```

When performing a dry run, the Data / LiveData / LiveState the operation computed stay in the QueuedOperation record; read them via `cub unit-action get` rather than expecting them on the Unit. Useful to answer "what would refresh absorb?" before committing to the refresh.

It's a good idea to use refresh to check for drift before making changes to the configuration data, to ensure you are operating on up-to-date data, rather than waiting until apply time.

`cub unit apply` also supports `--dry-run` similarly, and can be used to test whether updates will work in the cluster, after changes have been made to the configuration data. Resource creates sometimes can't be verified in this way due to dependencies that aren't actually created.

### 2. Name the likely source

After Worker-side elision (above), what's left is usually one of:

- **Manual `kubectl edit` / `kubectl patch`.** Someone debugged in prod and left the edit in place (a "break glass" operational change). Ask the user whether the edit is meant to stick (absorb → cluster wins) or was a stopgap (ConfigHub wins, re-apply to overwrite).
- **Admission mutations the webhook attributed to the original applier.** Some mutating webhooks stamp a field and keep the `manager` field pointing at the client that sent the request, so the Worker's field-manager elision doesn't catch them. These usually represent real workload requirements; absorb into Data.
- **Controllers not in the ignored list.** Operators and custom controllers that write to Unit-managed resources. Check the `manager` field in the diff's `metadata.managedFields` to identify them. Absorb if the field is legitimately controller-owned; restore from Data if the write is wrong.
- **Fields the user expected to own but are being mutated.** e.g., SecurityContext fields written by a PodSecurity admission rewriter. Absorb — the workload needs the rewritten values.
- **External secrets / external controller writes on a resource that shouldn't be in this Unit at all.** Either narrow the Unit's scope (remove the resource) or accept and set Data to match.

### 3. Decide

Walk through the diff with the user and reach one of the three resolutions. For bulk drift, decide per-Unit _or_ group Units that have the same drift shape and decide for the group.

### 4a. Resolution — ConfigHub wins

Re-apply the Unit's Data. The `cub-apply` skill owns this — hand off:

```bash
cub unit apply <slug> --space <s> --wait
```

If drift recurs on the same Unit, identify the source (a teammate still running `kubectl edit`, a mutating admission controller rewriting a field, an HPA writing `spec.replicas`) and address that source. Re-applying on a schedule treats a recurring cause as a repeat symptom; the fix belongs at the source (educate the teammate, adjust the admission policy, remove `spec.replicas` from Data so the HPA owns it).

**To undo out-of-band cluster edits explicitly** (not just a re-apply — capture what's there, then reset to the prior Data): refresh to absorb live state into a new head, then restore back to the pre-refresh head and apply. This records both the observation and the revert as distinct revisions:

```bash
cub unit refresh <slug> --space <s>          # new head = live state (N)
cub unit update <slug> --space <s> --restore -1 \
  --change-desc "Revert out-of-band cluster changes to <slug>. Restored to pre-refresh head (N-1).

User prompt: <verbatim>
Clarifications: <condensed — what was changed in-cluster and why it's rejected>"
cub unit apply <slug> --space <s> --wait
```

Use this when it's important for the audit trail to show _what was in the cluster_, not just that ConfigHub's Data was re-applied.

Note that due to asynchronous triggers and changes made due to links (aka "resolve"), refresh and other mutations sometimes generate two revisions rather than just one. Either create a tag and set it with `cub unit tag` prior to refresh, or simply look at the revisions with `cub revision list` after performing `cub unit refresh`.

### 4b. Resolution — cluster wins

Absorb live state into Data:

```bash
cub unit refresh <slug> --space <s>
```

`cub unit refresh` creates a new head revision whose Data matches current LiveData. Review the revision:

```bash
cub unit diff <slug> --space <s> --from=-1    # new head vs prior head
```

Refresh updates LiveRevisionNum and LastAppliedRevisionNum to match the new HeadRevisionNum, so an apply is not necessary - the changes were already in the cluster.

If you had unapplied changes before doing the reset, you may want to merge them into the updated configuration data so that they can be applied.

```bash
cub unit update --patch --space <s> <slug> --merge-source Self --merge-base PreviousLiveRevisionNum --merge-end Before:HeadRevisionNum --change-desc "Merge unapplied changes from before refresh"
```

### 4c. Resolution — selective merge

Refresh into a new head, then use `cub-mutate` to reject the parts you don't want:

```bash
cub unit refresh <slug> --space <s>
# New head contains everything — the accepted sidecar annotations AND the stopgap kubectl edit.
# Reject the kubectl edit with a function (example: strip a specific label back to the prior value).
cub function do --space <s> --unit <slug> \
  --change-desc "Keep sidecar annotations; reject debug label left by manual kubectl edit.

User prompt: <verbatim>
Clarifications: <condensed>" \
  -o mutations \
  -- set-label app.kubernetes.io/debug "-"   # example; use the function that matches
cub unit apply <slug> --space <s> --wait
```

For more complex merges (many fields to keep / reject), a whole-unit rewrite fallback (via `cub-mutate` Shape 6) may be cleaner than a chain of functions. Use the function path when the merge is three or fewer fields.

### 5. Close the loop — stop recurrence at the source

Reconciliation handles the drift that's present. If the same drift is likely to recur, the fix is at the source, not in the reconciliation cadence:

- **Recurring manual edits** — talk to the operator; tighten `kubectl` RBAC on the namespace; route them through `cub-mutate` next time.
- **Controller / admission-webhook rewrites** — either accept the rewritten fields into Data (so the next apply matches what the webhook would set) or remove those fields from Data (so the controller is unambiguously authoritative).
- **HPA / VPA / Descheduler owning a field** — remove the ConfigHub-side value for that field (e.g., drop `spec.replicas` from a Deployment that's under an HPA). If it isn't in Data, it can't drift.

Scheduling a drift-reconcile run for regular recurrence is a workaround, not a fix — use it only when you can't change the source.

## Bulk drift across many Units

Apply the same loop per-Unit, or for same-shape drift use bulk commands:

```bash
# Bulk drift detection check.
cub unit refresh --space "*" --filter <app>-home/<app>-app --wait --dry-run -o mutations

# Bulk refresh.
cub unit refresh --space "*" --filter <app>-home/<app>-app --wait

# Bulk re-apply (ConfigHub wins resolution).
cub unit apply --space "*" --filter <app>-home/<app>-app --wait
```

Always `--dry-run` first on bulk refresh — you're creating new head revisions on every matching Unit.

## Tool boundary

- Allowed: `cub unit refresh / diff / livestate / livedata / update / tag`, `cub unit-action get`, `cub function do`, read-only `kubectl get/describe` for diagnosis.
- Not allowed: `kubectl edit / apply / patch / delete` to "fix" drift — that creates more drift. If a cluster-side fix is genuinely needed (e.g., a broken resource that won't accept a re-apply), do it through `cub-mutate` + `cub-apply`.

## Stop conditions

- The "drift" is the ConfigHub Unit being one revision behind a very recent apply that hasn't fully converged — wait for `verify-apply` to clear first, then re-check.
- The Unit has an open ChangeSet — close it first; drift-reconcile against an open ChangeSet would layer more mutations into the release.
- User wants to keep both the ConfigHub state and the cluster state as "sources of truth" indefinitely. Push back: that's permanent drift and defeats ConfigHub's premise. Either accept the drift into Data, or remove the diverging field from Data so a controller owns it unambiguously.

## Verify chain

1. `cub unit refresh --wait --dry-run -o mutations` shows no additional changes.
2. Whatever source-level change step 5 called for has landed (operator trained, admission policy adjusted, field removed from Data).

## Evidence

- `cub unit get <slug> --space <s> --web` — current state including LiveRevisionNum and drift indicators.
- `cub revision list <slug> --space <s> --web` — the refresh + apply revisions with their `--change-desc`.

## References

- `references/cub-cli.md` — `--change-desc` scope; `-o mutations` on mutating calls.
- `references/functions-catalog.md` — functions for selective merge (strip-metadata-\*, set-label, set-annotation, set-cel).
- Companion skills: `cub-apply` (runtime for ConfigHub-wins), `cub-mutate` (surgical edits during selective merge), `verify-apply` (post-apply verification; this skill is the divergence counterpart when an apply converged but the cluster has since diverged, or when a "drift" report is actually a stuck/failed apply), `rollback-revision` (ConfigHub-history rewind, different problem).
- https://docs.confighub.com/guide/drift/
