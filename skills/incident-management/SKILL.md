---
name: incident-management
description: 'ConfigHub incident orchestration: bind the exact Release/runtime failure, choose rollback vs fix-forward, account for emergency cluster edits, and close with Release/controller/runtime proof. Use for outages, prod crashing, mitigation, and cleanup. Not planned releases.'
phase: cross-cutting
allowed-tools: []
read-capability-subset: incident-management
---

# incident-management

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. Urgency never broadens scope, but in standalone use an explicitly requested mitigation may submit one exact mutation to the host permission system; an external overlay may impose a stricter stop.

Stabilize first, but do not sacrifice attribution. Current delivery evidence is **Space Release → OCI manifest → controller → runtime**, not retired per-Unit apply status.

## First five minutes: establish facts

1. Bind incident scope: service/resource, namespace, cluster/context, Component, Variant Space, symptom, start time, and incident commander.
2. Read the newest relevant Releases, then pin the suspect by immutable identity:

   ```text
   cub release list --space <variant-space> -o json
   cub release get --space <variant-space> <release-id>
   ```

   Record ReleaseID, creation time, bundle Digest, ManifestDigest, UnitCount, and TagID.
3. Read the desired/effective ConfigHub set:

   ```text
   cub space get <variant-space> -o json
   cub unit list --space <variant-space> --select "TargetID,HeadRevisionNum,LastReleasedRevisionNum,ApplyGates" -o json
   ```

   To see the affected workload as a resource rather than as a Unit — the faster read when the
   symptom is phrased in Kubernetes terms — use `cub k8s get deploy <name> --space <variant-space>
   --show detail` or `--show data`. It is configuration, not live state; keep it separate from the
   `kubectl` read in step 5.

   If a promotion preceded the symptom, check what its merge **withheld** as well as what it
   applied. A merge that could not place part of its patch does not fail — it records the withheld
   changes on the Unit:

   ```text
   cub unit conflicts --space <variant-space> <unit>
   cub unit list --space <variant-space> --where "Conflicts.*.Reason = 'ProtectedPath'"
   ```

   A protected path is the common reason, and the common surprise: an environment-specific value
   the variant owns held against the release, so the fix that went everywhere else did not land
   here. `cub unit get <unit> -o mutations` shows which paths this variant owns. See
   `promote-release` for resolving them; resolving is a mutation, not a read.

4. Read controller state and history with `argocd app get/history/diff` or `flux get/logs`. Bind the controller source to the suspect ManifestDigest or mark that link unknown.
5. Read runtime health with `kubectl get/describe/logs`; inspect `confighub.com/origin` for SpaceID, UnitID, and RevisionNum. Never exec, restart, scale, patch, sync, or reconcile from this companion.

Use plain outcomes precisely: report healthy agreement, bounded convergence
lag, a concrete stop/failure, or a focused human decision. Do not expose
internal all-caps status markers in ordinary incident UX.

## Decide: rollback or fix forward

### A. Roll back a recent causal Release

Choose this when symptoms began after a specific immutable Release and a known-good revision set is available. Do not “deploy an old Release” while leaving bad heads current. Route to `rollback-revision` to:

1. identify exact prior RevisionID/DataHash per affected Unit;
2. preview head-moving `cub unit update --restore` operations;
3. compute the resulting destination EffectiveReleaseSet; and
4. prepare a new whole-Space Release proposal through `release-publish`.

If the suspect mutations were grouped in a ChangeSet, `Before:ChangeSet:<space>/<slug>` is useful restore evidence. The ChangeSet does not narrow publication. If only some Units are restored but the Release captures more Units, disclose that scope and ask again.

### B. Fix forward

Choose this when the cause is known and a small, reversible ConfigHub data change is safer/faster than restoring a larger set. Route to `cub-mutate` for an exact function-first change with incident-linked `--change-desc`, then to `release-publish` for the new whole-Space publication.

For a temporary capacity mitigation, state explicitly whether the change is intended to remain desired state after the incident. A runtime-only scale is not durable under Argo/Flux and is outside this companion's authority.

### C. Reconcile emergency out-of-band edits

If an operator changed Kubernetes or a controller during the hot window:

- inventory the exact live changes read-only;
- decide which are durable vs temporary;
- recreate durable intent as a governed ConfigHub mutation proposal;
- let temporary changes disappear under normal controller reconciliation; and
- never claim ConfigHub `LiveData` proves cluster state for OCI Release delivery.

This preserves the prior drift-reconciliation job without pretending the OCI server worker performs remote cluster reads.

## Delivery and worker failures

The OCI Target's server-worker entity is not an external process to restart. Diagnose separately:

- ConfigHub Release missing/rejected: `ReleaseTargetID`, OCI provider, Unit membership, tag coverage, ApplyGates.
- controller cannot pull/sync: OCI reference/auth/source/digest and controller logs.
- runtime unhealthy after sync: image, probes, RBAC, dependencies, quotas, scheduling.
- external custom-function worker failing: route read-only diagnosis to `worker-bootstrap`.

Direct ConfigHub-provider Release delivery is historical and unsupported in the reviewed current profile.

## Approval, execution, and incident provenance

Installed help advertises several native approval selectors, but exact current server acceptance and atomic preconditions are not source-reviewed; do not call it exact reviewed-artifact approval without provider evidence. Incident urgency does not merge distinct operations or erase their races. Produce the smallest exact command, blast radius, rollback plan, proof plan, and resume condition, then submit one requested mitigation to the host permission system. Stop before Bash if an external governance overlay says to block it.

Do not conflate native approval with mutation preconditions. Unit update execution has transactional expected `HeadRevisionNum` and hash checks when the caller supplies them, but stock restore and function convenience paths do not prove that inspected values reached the final request. Re-read immediately before the call, state the race, and never let urgency justify a stronger claim than the command supports.

Every incident mutation uses a short safe summary from
`references/execution-modes.md`. Include only a validated ticket slug and a
model-authored summary, never verbatim user text:

```text
Incident: INC-512 rollback checkout to prior image
```

Retain fuller context in the shared transcript and result receipt. For
concurrent incidents, name the owning incident and check whether another open
ChangeSet already holds any affected Unit. Shared Units must be sequenced or
the scope split; never interleave two incident ChangeSets on one Unit.

## Closeout

Use `verify-apply` after stabilization. Close only when it records:

- exact new ReleaseID, bundle Digest, and ManifestDigest;
- controller bound to that immutable source;
- runtime health and ConfigHub origin provenance;
- EffectiveReleaseSet/UnitCount coverage;
- any omitted evidence as an explicit gap; and
- emergency out-of-band changes either encoded as desired state or intentionally removed.

Then capture the incident timeline, suspect and recovery Releases, restored/mutated RevisionIDs, permissions/receipts, remaining warnings, and follow-up owners. The durable resolution marker used by the baseline workflow is a separate mutation; submit it once to the host permission system when the user requests incident closeout:

```bash
cub tag create --space <app>-home incident-<YYYYMMDD>-<ticket> \
  --annotation 'description=Record reviewed incident resolution'
```

After verifying the Tag, attach it as a separate command:

```bash
cub unit tag <app>-home/incident-<YYYYMMDD>-<ticket> \
  --space <env-space> --filter <app>-home/<app>-app
```

Bind the exact revisions before the tag call; tagging is a mutation with its own host-permission call. GUI open commands are navigation only until org/object identity is verified.

## Stop conditions

- no immutable suspect Release or wrong cluster context;
- rollback target, blast radius, or durable-vs-temporary intent is ambiguous;
- a narrow restore/fix would be published as a broader Space Release without new approval;
- user asks to bypass an ApplyGate, controller policy, host permission, or external governance overlay;
- another incident ChangeSet already owns any Unit in scope and no sequencing decision exists;
- mutation provenance would omit the validated incident slug and safe summary;
- evidence requires a mutation to discover.

## References

- `compatibility/current-profile.v1.json`
- `rollback-revision`, `cub-mutate`, `release-publish`, `verify-apply`
- `worker-bootstrap` for external custom-function worker diagnosis
- `references/changesets.md` for grouped revision restore/approval semantics
