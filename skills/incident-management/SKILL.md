---
name: incident-management
description: Use when the user is in the middle of a production incident and needs an orchestrated plan — phrases like "we have an outage", "prod is crashing", "page me through this", "what do I do first?", "mitigate or roll back?", "production is down since the last release", "something's broken in staging — help me triage", "we're on an incident call, walk me through the ConfigHub side", "post-incident cleanup". Triage the situation, decide between stabilize-and-mitigate vs head-moving rollback vs drift reconciliation, route to the right mutation skill with the scope and `--change-desc` composed, and drive the post-incident verification + close-out. Do not load for planned releases (use `promotion-preflight` + `promote-release`), for routine change management, or for single-Unit edits the user is confidently making on their own (use `cub-mutate`).
phase: cross-cutting
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub revision list *) Bash(cub revision get *) Bash(cub worker logs *) Bash(cub worker status *) Bash(kubectl get *) Bash(kubectl describe *) Bash(kubectl logs *)
---

# incident-management

Orchestrator for the ConfigHub-side of a production incident. Triages, decides stabilize vs. rollback vs. reconcile, and hands off to the mutating skill that will do the actual work. Does not mutate itself.

## Principle: stabilize first, diagnose later

An incident is an ongoing loss of service. The first move is to return to a known-good state; root-cause analysis comes after the bleeding stops. This skill is biased toward the fastest path back to green, not the most elegant fix.

## When to use

- Production is actively broken or degraded.
- User asks "roll back or fix forward?" about a live incident.
- SRE / on-call is driving and wants a structured ConfigHub-side plan.
- Post-incident cleanup: absorb manual fixes, tag the incident's revisions, reconcile drift.

## Do not load for

- Planned releases — `promotion-preflight` + `promote-release`.
- Routine single-Unit change — `cub-mutate`.
- Debugging an apply that's just slow — `verify-delivery`.
- General "how does ConfigHub work" orientation — `confighub-core`.

## Triage — the first five questions

Ask (or derive from context) in order. Stop at the first one that routes clearly:

1. **What was applied to the cluster most recently, and is that the suspected cause?**
   Only applies change live state — ChangeSet opens, mutations, upgrades, and `--restore` operations don't hit the cluster until the corresponding `cub unit apply`. Ignore the head-revision / ChangeSet noise; look at what the Worker actually deployed in the incident window.

   ```bash
   # Apply actions across the org that started after <incident-window-start>.
   # Returns at most one row per Unit (the latest Apply), with Unit + Space
   # slug columns so a repeated slug across Spaces is disambiguated.
   cub unit-action list --space '*' \
     --where "Action = 'Apply' AND CreatedAt > '<ISO-timestamp>'"

   # To scope by app, first get the Unit IDs from the app filter, then use
   # UnitID IN (...) in the where clause:
   cub unit list --space '*' --filter <app>-home/<app>-app \
     --jq '[.[] | .Unit.UnitID] | join("'"'"','"'"'")' \
     --no-header
   # => paste the IDs into:
   cub unit-action list --space '*' \
     --where "Action = 'Apply' AND CreatedAt > '<ISO-timestamp>' AND UnitID IN ('<id1>','<id2>',...)"
   ```

   If this returns rows plausibly linked to symptoms → **rollback path** (Path A). If it returns rows but symptoms don't match, or returns empty → **mitigate path** (Path B).

   Inspect a specific action with `cub unit-action get <unit-slug> <num>` (the Num column from list), adding `--data`, `--livedata`, `--livestate`, or `--bridgestate` when the payload matters for triage.

2. **Did anyone make out-of-band cluster changes (kubectl, argocd sync, flux reconcile) to stabilize?**
   - Yes → after incident is contained, `drift-reconcile` to decide who wins per change.
   - No → note, continue.

3. **Is the breakage widespread (many Units) or narrow (one Unit)?**
   - Wide + recent applied release → the release ChangeSet is a natural scope if the applies in question correspond to a single ChangeSet's end-tag apply. (Confirm by spot-checking that the Units returned in question 1 share a `ChangeSet.Slug` on their end-tag revisions.)
   - Narrow → single-Unit path.

4. **Is ConfigHub itself healthy?**
   - Worker alive: `cub worker status --space <workers-space> <worker>`. If Worker is down, mutations can't apply anyway — route to `worker-bootstrap` fix first, hold the ConfigHub-side mitigation until the Worker is back.
   - Server reachable: `cub space list` succeeds.

5. **Is the user paging, post-mortem, or blast-radius bounding?**
   - Actively paging → minimize steps, defer tagging / close-out work until green.
   - Post-mortem / after → move into the close-out section below; no new mutations.

Use this triage to pick one of the three paths.

## Path A — rollback (recent apply, causal)

Use when the incident started after a specific recent `cub unit apply` / promotion apply and reverting is the fastest path back. "Recent change" alone isn't the trigger — it's "recent change that was _applied_ into the cluster."

### Identify the target

The triage query in question 1 already identified the Units with applies in the incident window. If those applies came from a single release ChangeSet, restore scope = that ChangeSet. Otherwise, restore per-Unit.

```bash
# Which ChangeSet's end-tag apply produced the suspect applies? Read the
# LastChangeDescription from the triage output, or look at the applied revision:
cub revision list --space <env-space> <unit-slug> \
  --where "RevisionNum = <LastAppliedRevisionNum from triage>" \
  --jq '.[] | {ChangeSet: .Revision.ChangeSet.Slug, Description: .Revision.Description}'

# Recent ChangeSets in the home Space (useful when the apply query above
# returned multiple Units in the same ChangeSet).
cub changeset list --space <app>-home --where "CreatedAt >= '<incident start ISO timestamp>'"
```

Pick the restore target — `Before:ChangeSet:<home-space>/<slug>` if the suspect is a ChangeSet, or `LastAppliedRevisionNum` (before the incident-window apply — i.e., `PreviousLiveRevisionNum` or a specific prior number) for single-Unit cases.

### Hand off

Route to `rollback-revision` with the scope + target, and with a `--change-desc` draft that makes the incident context explicit:

```
Incident rollback — <one-line symptom>. Reverting <slug-or-changeset> per on-call decision.

User prompt: <verbatim>
Clarifications: <condensed — link to incident ticket / Slack thread, symptom evidence, who approved>
```

`rollback-revision` owns the `cub unit update --restore` + `cub-apply` hand-off. `incident-management` returns after apply completes, then moves to the verify + close-out block below.

Remember: rollback means `cub unit update --restore`. `cub unit apply --revision <N>` is **not** a rollback — it leaves head unchanged and the bad state returns on the next forward change.

## Path B — mitigate (cause is not a recent ConfigHub change, or can be faster-fixed)

Use when the incident root cause is not a recent mutation (infra flake, load spike, external dependency down, bad external image on registry side) and a targeted forward fix gets to green faster than a rollback.

Typical mitigations:

| Symptom                                   | Mitigation                                                                 | Skill        |
| ----------------------------------------- | -------------------------------------------------------------------------- | ------------ |
| Saturation / traffic spike                | Scale up (`set-replicas`), raise resources (`set-container-resources`).    | `cub-mutate` |
| Bad image tag just pushed by CI           | Pin to the last known-good image via `set-container-image`.                | `cub-mutate` |
| Feature flag / env var causing crash      | Flip it off via `set-env-var`.                                             | `cub-mutate` |
| Broken probe taking pods down             | Relax or disable via `set-int-path` / `yq-i` / `set-starlark` / `set-cel`. | `cub-mutate` |
| Pod spec wedged on a new admission policy | Adjust the security-context / label the pod sets to satisfy policy.        | `cub-mutate` |

For any mitigation that touches more than one Unit, open a ChangeSet (named `incident-<YYYYMMDD>-<ticket>`) so the fix can be tagged and rolled back as a set if it doesn't hold. Single-Unit: skip the ChangeSet.

Remember: opening a ChangeSet and running mutations inside it does **not** touch the cluster. Live state changes only when `cub unit apply` runs (explicitly, or via `--revision ChangeSet:<slug>` against the filter once the ChangeSet is closed). Compose the mutations, close the ChangeSet, then hand off to `cub-apply` to put the fix in front of traffic.

### Hand off

Compose the `--change-desc` the same way — make the incident context explicit — and hand off to `cub-mutate` for the data change, then `cub-apply` to push it.

```
Incident mitigation — <symptom>. <What we changed and why>.

User prompt: <verbatim>
Clarifications: <condensed — ticket / channel, decision, expected-to-hold-through >
```

## Path C — reconcile (post-mitigation, or manual cluster edits were made)

Use after an incident where someone applied hotfixes directly in-cluster (`kubectl edit`, `argocd app sync` with an override, etc.) and ConfigHub now diverges from what's live.

Hand off to `drift-reconcile` with the scope of affected Units. The decisions there (ConfigHub wins / cluster wins / selective merge) should usually lean cluster-wins for incident-time edits that _stuck_ — absorb the stabilization into Data so the next apply doesn't undo it — and ConfigHub-wins for edits that were temporary and the user wants gone.

Don't start Path C until the incident is contained (symptoms resolved, no ongoing paging). Reconciling drift while pods are still crashing just adds confusion.

## During the incident — logging discipline

Every mutation during the incident, regardless of path, carries a `--change-desc` with:

- `Incident: <ticket-id or short slug>`
- The verbatim user / on-call prompt.
- One-line condensed clarifications.

This costs nothing in the moment and saves hours in the postmortem. Skip anything else that doesn't get you back to green — naming Tags, cleaning up slugs, renaming ChangeSets — until the incident is closed.

## After green — close-out

Once symptoms are gone and the user confirms stable:

1. **Tag the resolution.** Tag the rollback / mitigation revisions so they're a first-class reference for the postmortem:

   ```bash
   cub tag create --space <app>-home incident-<YYYYMMDD>-<ticket> \
     --annotation "description=<short incident description> — resolution type: rollback|mitigate|reconcile"

   cub unit tag <app>-home/incident-<YYYYMMDD>-<ticket> \
     --space <env-space> --filter <app>-home/<app>-app
   ```

2. **Run `reconciliation-check`** on the affected scope. ConfigHub, controller, and cluster must agree. If they don't, you're not actually done — investigate.

3. **Run `release-verify`** on the resolved state so there's a clickable record with the Revision history and review links.

4. **If Path B with a ChangeSet was used, consider whether the ChangeSet should be rolled back.** A mitigation is often temporary — the root-cause fix comes later. Keep the ChangeSet open as a marker, or close it and rely on Tag:incident-\* for retrieval.

5. **If Path C absorbed manual cluster fixes into ConfigHub**, confirm the absorbed data has passed the Space's `platform/standard-vets` Triggers. Incident-time edits often produce vet failures; fix them in a follow-up change once you're out of the hot window.

## Tool boundary

Read-only and decision-only. **This skill does not mutate.** Every mutation during an incident goes through the skill it hands off to:

- Rollback → `rollback-revision`.
- Forward fix → `cub-mutate`.
- Apply / deploy → `cub-apply`.
- Drift reconciliation → `drift-reconcile`.
- Verification → `verify-delivery`, `reconciliation-check`, `release-verify`.

If you find yourself about to run `cub unit update` / `cub function do` / `cub unit apply` from here, stop and hand off.

## Stop conditions

- User asks to "just skip the `--change-desc`" to save time. Push back — it's one line, costs nothing, saves hours in postmortem. If they insist and the situation is truly dire, log the mutations and the reasoning yourself in the session; a follow-up commit can annotate.
- User asks to `cub unit apply --revision <N>` as a rollback. Stop and route to `rollback-revision` — that approach leaves head unchanged and the bad state returns on the next change.
- Worker is down and user wants to mutate — stop; fix Worker (`worker-bootstrap`) first.
- Multiple overlapping incidents affecting shared Units. Don't try to thread multiple ChangeSets through the same Units simultaneously. Sequence them: one incident's fix closes before the next opens.
- User wants root-cause-first instead of stabilize-first. Offer the trade-off honestly (longer outage, better understanding) and let them choose; don't push back hard unless the outage is actively expensive.

## Verify chain (of the orchestration, not the mutations)

1. After every hand-off, confirm the targeted skill returned success before the next step.
2. After green: `verify-delivery` / `reconciliation-check` / `release-verify` chain passes for the affected scope.
3. `cub revision list --space <env-space> --filter <app>-home/<app>-app --tag <app>-home/incident-<...>` surfaces every incident-related revision under one query.

## Evidence

- The incident ticket / Slack thread — referenced verbatim in every `--change-desc`.
- `cub tag get --space <app>-home incident-<...> --web` — the incident marker in the GUI.
- `cub changeset get --space <app>-home <slug> --web` — if a ChangeSet was opened.
- `cub unit get <unit> --space <env-space> --web` per affected Unit.

## References

- `references/changesets.md` — ChangeSet lifecycle + rollback via `Before:ChangeSet:<slug>`.
- `references/revisions.md` — restore-target syntax.
- `references/cub-cli.md` — `--change-desc` discipline.
- Companion skills: `rollback-revision` (Path A), `cub-mutate` (Path B data change), `cub-apply` (Path B runtime), `drift-reconcile` (Path C), `verify-delivery` / `reconciliation-check` / `release-verify` (close-out), `worker-bootstrap` (Worker-down blocker), `promotion-preflight` (the opposite-direction skill — don't use during an incident).
