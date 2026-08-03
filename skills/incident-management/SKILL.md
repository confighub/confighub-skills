---
name: incident-management
description: 'Orchestrate the ConfigHub side of a live production incident — triage, decide stabilize-and-mitigate vs rollback vs drift reconciliation, route to the right mutation skill. Use for "we have an outage", "prod is crashing", "mitigate or roll back?", "post-incident cleanup". Not for planned releases (use promote-release).'
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

- Planned releases — `promote-release`.
- Routine single-Unit change — `cub-mutate`.
- General "how does ConfigHub work" orientation — `confighub-core`.

## Triage — the first five questions

Ask (or derive from context) in order. Stop at the first one that routes clearly:

1. **What reached the cluster most recently, and is that the suspected cause?**
   Only a published Release changes live state — ChangeSet opens, mutations, upgrades, and `--restore` operations don't hit the cluster until the Space is published and Argo/Flux pulls it. Ignore the head-revision / ChangeSet noise; look at what Argo/Flux actually deployed in the incident window.

   ```bash
   # Release actions across the org that started after <incident-window-start>.
   cub release list --space '*' --where 'CreateAt >= <timestamp>'

   # To scope to a single App, identify the Space in question, and fetch the 
   # latest OCI bundle
   cub release get --space '<space slug>' --oci-reference latest

   # To then find the revisions contained in the bundle
   cub revision list --where 'release ~ (<ReleaseID>)'
   ```

   If the revisions in the bundle are plausibly linked to symptoms → **rollback path** (Path A). If there are Releases in the window but the revisions don't match symptoms, or nothing lands in the window → **mitigate path** (Path B).

   Inspect a specific action with `cub unit-action get <unit-slug> <num>`, adding `--data`, `--livedata`, `--livestate`, or `--bridgestate` when the payload matters for triage.

2. **Did anyone make out-of-band cluster changes (kubectl, argocd sync, flux reconcile) to stabilize?**
   - Yes → those edits will be reverted by ArgoCD/Flux on the next sync unless captured in ConfigHub. After the incident is contained, re-create the intended change as a ConfigHub mutation (Path C) so the published desired state matches.
   - No → note, continue.

3. **Is the breakage widespread (many Units) or narrow (one Unit)?**
   - Wide + recent Release → the Release is a natural scope; its Tag names every Revision it bundled. (Confirm by spot-checking that the Revisions from question 1 belong to the same Release.)
   - Narrow → single-Unit path.

4. **Is ConfigHub itself healthy?**
   - Auth + server reachable: `cub auth status` succeeds (calls the server's `/me`). If it fails, the session is unauthenticated — ask the user to run `cub auth login` before any ConfigHub-side action.
   - Delivery worker: OCI/ConfigHub Targets use server workers (always available — no process to be down). Only an external worker hosting custom functions can be down; if one is and it's in the path, route to `worker-bootstrap`.

5. **Is the user paging, post-mortem, or blast-radius bounding?**
   - Actively paging → minimize steps, defer tagging / close-out work until green.
   - Post-mortem / after → move into the close-out section below; no new mutations.

Use this triage to pick one of the three paths.

## Path A — rollback (recent Release, causal)

Use when the incident started after a specific recent Release / promotion and reverting is the fastest path back. "Recent change" alone isn't the trigger — it's "recent change that actually _reached the cluster_."

### Identify the target

The triage queries in question 1 identified the Releases in the incident window and the revisions they bundled. If those revisions came from a single release Tag, restore scope = that Tag. Otherwise, restore per-Unit.

```bash
# Releases published into the incident window.
cub release list --space <env-space> --where "CreatedAt >= '<incident start ISO timestamp>'"

# The suspect Release — Tag, UnitCount, digests.
cub release get --space <env-space> <release-id>

# The Revisions it bundled.
cub revision list --space '*' --tag <release-tag>
```

Pick the restore target:

- `Tag:<env-space>/<release-tag>` — the last known-good Release's Tag, the usual choice.
- `Before:ChangeSet:<home-space>/<slug>` — when the suspect Revisions all came from one ChangeSet.
- `PreviousLiveRevisionNum` or a specific prior number — single-Unit cases.

### Hand off

Route to `rollback-revision` with the scope + target, and with a `--change-desc` draft that makes the incident context explicit:

```
Incident rollback — <one-line symptom>. Reverting <slug-or-changeset> per on-call decision.

User prompt: <verbatim>
Clarifications: <condensed — link to incident ticket / Slack thread, symptom evidence, who approved>
```

`rollback-revision` owns the `cub unit update --restore` + `release-publish` hand-off. `incident-management` returns after the rollback is published and converged, then moves to the verify + close-out block below.

Remember: rollback means `cub unit update --restore` — a new head whose data equals the prior revision.

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

Remember: opening a ChangeSet and running mutations inside it does **not** touch the cluster. Live state changes only once the Space is published and Argo/Flux pulls it. Compose the mutations, close the ChangeSet, then hand off to `release-publish` to put the fix in front of traffic.

### Hand off

Compose the `--change-desc` the same way — make the incident context explicit — and hand off to `cub-mutate` for the data change, then `release-publish` to push it.

```
Incident mitigation — <symptom>. <What we changed and why>.

User prompt: <verbatim>
Clarifications: <condensed — ticket / channel, decision, expected-to-hold-through >
```

## Path C — capture out-of-band cluster edits into ConfigHub

Use after an incident where someone applied hotfixes directly in-cluster (`kubectl edit`, `argocd app sync` with an override, etc.). ConfigHub doesn't read live cluster state, and ArgoCD/Flux will revert those manual edits on their next sync of the published desired state — so a manual edit that *should* persist must be re-created in ConfigHub.

Re-express each stabilizing edit as a ConfigHub data mutation (Path B: `cub-mutate`) and re-publish (`release-publish`), so the OCI-published desired state carries the fix and Argo/Flux converges to it. For edits that were only temporary and should disappear, do nothing — the next sync removes them.

Don't start Path C until the incident is contained (symptoms resolved, no ongoing paging). Re-publishing while pods are still crashing just adds confusion.

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

2. **Confirm the affected scope converged.** Check `cub release get` for the published Release, then Argo/Flux and `kubectl` read-only to confirm the cluster caught up before closing out.

3. **If Path B with a ChangeSet was used, consider whether the ChangeSet should be rolled back.** A mitigation is often temporary — the root-cause fix comes later. Keep the ChangeSet open as a marker, or close it and rely on Tag:incident-\* for retrieval.

4. **If Path C re-created manual cluster fixes as ConfigHub mutations**, confirm the new data has passed the Space's `platform/standard-vets` Triggers. Incident-time edits often produce vet failures; fix them in a follow-up change once you're out of the hot window.

## Tool boundary

Read-only and decision-only. **This skill does not mutate.** Every mutation during an incident goes through the skill it hands off to:

- Rollback → `rollback-revision`.
- Forward fix / capture cluster edits (Path C) → `cub-mutate`.
- Publish → `release-publish`.

If you find yourself about to run `cub unit update` / `cub function do` / `cub function set` / `cub release publish` from here, stop and hand off.

## Stop conditions

- User asks to "just skip the `--change-desc`" to save time. Push back — it's one line, costs nothing, saves hours in postmortem. If they insist and the situation is truly dire, log the mutations and the reasoning yourself in the session; a follow-up commit can annotate.
- User asks to roll back by re-publishing an older Release or Tag. That ships older data but leaves head unchanged, so the bad state returns on the next forward change — confirm that's what they want, or route to `rollback-revision` for a head-moving rollback.
- Worker is down and user wants to mutate — stop; fix Worker (`worker-bootstrap`) first.
- Multiple overlapping incidents affecting shared Units. Don't try to thread multiple ChangeSets through the same Units simultaneously. Sequence them: one incident's fix closes before the next opens.
- User wants root-cause-first instead of stabilize-first. Offer the trade-off honestly (longer outage, better understanding) and let them choose; don't push back hard unless the outage is actively expensive.

## Verify chain (of the orchestration, not the mutations)

1. After every hand-off, confirm the targeted skill returned success before the next step.
2. After green: confirm the Release is published (`cub release get --space <env-space> --oci-reference latest`) and that Argo/Flux converged the affected scope.
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
- Companion skills: `rollback-revision` (Path A), `cub-mutate` (Path B / Path C data change), `release-publish` (publishes the Path B/C fix), `worker-bootstrap` (external-worker blocker), `promote-release` (the opposite-direction skill — don't use during an incident).
