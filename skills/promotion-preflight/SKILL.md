---
name: promotion-preflight
description: 'Use before running a promotion to decide what''s actually safe to promote — phrases like "what do I need to check before promoting to prod?", "is staging ready to roll forward?", "which Units are behind their upstream?", "preflight before pushing the release to prod", "can I promote this release?". Runs a structured set of read-only checks against the source and destination env-Spaces — which Units are behind upstream, whether the source env is actually converged and healthy, which ApplyGates / approval requirements are outstanding, what the diffs look like — and outputs a go/no-go with a concrete scope (the Filter and any narrowing) for `promote-release` to pick up. Do not load for the promotion itself (use `promote-release`), for rolling back a prior promotion (use `rollback-revision` + `references/changesets.md`), or for drift inside a single env (use `drift-reconcile`).'
phase: decide
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub revision list *) Bash(cub revision get *) Bash(kubectl get *) Bash(kubectl describe *)
---

# promotion-preflight

Read-only decision skill. Confirms that promoting a release from one env-Space to the next won't break on predictable problems, and hands off a concrete promotion scope (Filter + narrowing + proposed ChangeSet name) to `promote-release`.

## When to use

- User says "I'm about to promote to staging/prod", "is this ready?", "what's the status before I roll forward?".
- Before every `cub unit update --upgrade` / `cub unit push-upgrade` that spans more than one Unit.
- Before opening a release ChangeSet — catching misaligned preconditions here is cheap; doing it after ChangeSet open means cleanup revisions on every Unit.

## Do not load for

- Running the promotion — hand off to `promote-release`.
- Rollback or merge/rebase around a past ChangeSet — use `rollback-revision` + `references/changesets.md`.
- Drift between ConfigHub and cluster in the *same* env — use `drift-reconcile`.
- Verifying a promotion *after* it applied — use `verify-delivery` / `reconciliation-check`.

## Preflight gates (for this skill to do its work)

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. The source env-Space and destination env-Space are known (per `space-topology`: `<app>-<from-env>` → `<app>-<to-env>`).
3. The app's home Space is known (`<app>-home`) — the `<app>-app` Filter, release ChangeSets, and Tags live there.
4. User has at least read permission on both env-Spaces and the home Space.

## What to check, and why

### A. Source env is actually ready

Promoting from an env that isn't itself converged just ships the same problems forward. Confirm:

```bash
# `--where` supports AND only (no OR). Run one query per condition and union
# the results in the preflight report. `cub unit list` also takes at most one
# --filter per command — stacking is a no-op or an error depending on cub
# version, so combine a named Filter with --where rather than two --filters.

# Units with unapplied changes (head ahead of live).
cub unit list --space <app>-<from-env> \
  --filter <app>-home/<app>-app \
  --where "HeadRevisionNum > LiveRevisionNum AND TargetID IS NOT NULL"

# Units with open ApplyGates.
cub unit list --space <app>-<from-env> \
  --filter <app>-home/<app>-app \
  --where "LEN(ApplyGates) > 0"

# Units whose last apply hasn't fully completed in the cluster.
cub unit list --space <app>-<from-env> \
  --filter <app>-home/<app>-app \
  --where "LiveRevisionNum != LastAppliedRevisionNum"
```

Any rows from any of the three queries = not ready. Name each problem Unit and which of the three categories it's in (gate / unapplied / lagging LiveRevisionNum) in the preflight report.

Cross-check the delivery side — the Unit's `UnitStatus.Status` reflects whether the last apply landed cleanly:

```bash
cub unit list --space <app>-<from-env> \
  --filter <app>-home/<app>-app \
  --jq '[.[] | {Slug: .Unit.Slug, Status: .UnitStatus.Status, SyncStatus: .UnitStatus.SyncStatus, ActionResult: .UnitStatus.ActionResult}
         | select(.Status != "Ready" or .SyncStatus != "Synced")]'
```

Any non-empty result = broken state in the source env. Promoting forward ships the broken state.

### B. Destination needs what's being promoted

The Units that *would* change are the ones whose `UpstreamRevisionNum` is behind their upstream's `HeadRevisionNum`. Use the standard `needs-upgrade` filter (`references/filters-and-queries.md`):

```bash
# Everything in the destination env that is behind upstream.
cub unit list --space <app>-<to-env> \
  --filter platform/needs-upgrade
```

If empty, there's nothing to promote — tell the user and stop.

Narrow further if the user wants to promote only part of the app:

```bash
# Only the API Units, not the workers.
cub unit list --space <app>-<to-env> \
  --filter platform/needs-upgrade \
  --where "Slug LIKE '%-api%'"
```

The combination of Filter(s) + `--where` is what will be passed to `promote-release`; record it exactly.

### C. Diffs are what the user expects

For each Unit in the scope, show the pre-promotion diff:

```bash
cub unit diff <unit> --space <app>-<to-env> --from Upstream
# or, per-Unit via the scope:
for u in $(cub unit list --space <app>-<to-env> --filter platform/needs-upgrade --quiet --jq '.[].Slug'); do
  echo "=== $u ==="
  cub unit diff "$u" --space <app>-<to-env> --from Upstream
done
```

Read the diffs with the user. Flag anything surprising: images moving by more than one minor version, resource-limit changes not expected, namespace/annotation churn that looks like drift rather than intent, etc.

### D. Destination policy outstanding

Confirm the destination Space has its expected Triggers attached and no lingering ApplyGates from prior runs that would immediately block:

```bash
cub space get <app>-<to-env> --jq '{AttachedFilter: .TriggerFilter.Slug, ResolvedTriggers: (.Triggers // [] | length), TriggerFilterID: .Space.TriggerFilterID}'
cub unit list --space <app>-<to-env> --filter <app>-home/<app>-app --where "LEN(ApplyGates) > 0"
```

If approval is required in the destination (`vet-approvedby` Trigger), surface who needs to approve and how (`cub unit approve --revision ChangeSet:<...>`) so that's part of the promotion plan, not a surprise mid-flight.

### E. Upstream linkage is actually what the user thinks

A Unit gets promoted via its `UpstreamUnitID` — whatever `cub unit update --upgrade` resolves. Confirm the graph:

```bash
cub unit tree --space <app>-<to-env> --filter <app>-home/<app>-app
```

If any destination Unit points upstream at something the user doesn't expect (e.g., it's linked to a shared base rather than to the source env), the "promotion" is going to pull from that base, not from `<app>-<from-env>`. Stop and confirm intent before the mutation.

## Output

Produce a concrete go/no-go with these fields:

- **Scope**: exact Filter + `--where` the `promote-release` call will use.
- **Count**: how many Units are in scope.
- **Blockers** (if any): per-Unit list of outstanding gates / unapproved / not-yet-live / mis-linked.
- **Diffs**: short summary per Unit; full diffs on request.
- **ChangeSet proposal**: slug (`<app>-home/release-<YYYYMMDD>-<shortref>` or whatever the user names it), description draft.
- **Approval plan** (if relevant): who approves, via what revision reference.
- **Recommendation**: `go`, `go with narrowed scope`, or `no-go` with specific remediation.

Hand the scope to `promote-release`.

## Tool boundary

Read-only. No `cub unit update / apply / function do / changeset create`. Those belong to `promote-release` once preflight clears.

## Stop conditions

- Source env has unapplied changes, open gates, or bridgestate issues — promotion would ship broken state forward. Stop and route the user to fix those first (use `cub-apply` or `triggers-and-applygates` for the blockers).
- Destination scope is empty — nothing to promote. Tell the user and stop.
- Destination has lingering ApplyGates that a subsequent `cub unit update --upgrade` won't clear (e.g., `vet-approvedby` requires fresh approval at the new revision). That's informational, not a stop — fold into the approval plan.
- Upstream linkage doesn't match intent. Stop and ask.

## Verify chain

Preflight is itself a verification — its output is the audit trail. Save the composed Filter, diffs, and the proposed ChangeSet description alongside any issue tracker / Slack post the user opens with teammates.

## Evidence

- `cub unit list --space <app>-<to-env> --filter platform/needs-upgrade --web` — the exact set to promote.
- `cub unit tree --space <app>-<to-env> --filter <app>-home/<app>-app --web` — upstream linkage.

## References

- `references/filters-and-queries.md` — `needs-upgrade`, `unapplied-changes`, `has-apply-gates`, `not-approved` recipes.
- `references/changesets.md` — ChangeSet slug convention and lifecycle.
- `references/cub-cli.md` — `--where` vs `--filter` composition rules.
- Companion skills: `space-topology` (home Space + env Spaces), `promote-release` (the execution skill this hands off to), `triggers-and-applygates` (fixing gate blockers in the source), `cub-apply` (fixing unapplied state in the source), `verify-delivery` / `reconciliation-check` (post-promotion checks).
