---
name: incident-management
description: 'Read-only ConfigHub incident orchestration: bind the exact Release/runtime failure, choose rollback vs fix-forward, account for emergency cluster edits, and close with Release/controller/runtime proof. Use for outages, prod crashing, mitigation, and cleanup. Not planned releases.'
phase: cross-cutting
allowed-tools: []
read-capability-subset: incident-management
---

# incident-management

**Authority boundary:** this skill triages read-only and may prepare a stabilization proposal. It must not execute a mutation, even during an incident. The external mutation broker is `NOT_INTEGRATED`, so mutation paths end in `ASK` or `BLOCK` with exact risk and proof requirements.

Stabilize first, but do not sacrifice attribution. Current delivery evidence is **Space Release → OCI manifest → controller → runtime**, not retired per-Unit apply status.

## First five minutes: establish facts

1. Bind incident scope: service/resource, namespace, cluster/context, Component, Variant Space, symptom, start time, and incident commander.
2. Read the newest relevant Releases, then pin the suspect by immutable identity:

   ```bash
   cub release list --space <variant-space> -o json
   cub release get --space <variant-space> <release-id>
   ```

   Record ReleaseID, creation time, bundle Digest, ManifestDigest, UnitCount, and TagID.
3. Read the desired/effective ConfigHub set:

   ```bash
   cub space get <variant-space> -o json
   cub unit list --space <variant-space> --select "TargetID,HeadRevisionNum,LastAppliedRevisionNum,ApplyGates" -o json
   ```

4. Read controller state and history with `argocd app get/history/diff` or `flux get/logs`. Bind the controller source to the suspect ManifestDigest or mark that link unknown.
5. Read runtime health with `kubectl get/describe/logs`; inspect `confighub.com/origin` for SpaceID, UnitID, and RevisionNum. Never exec, restart, scale, patch, sync, or reconcile from this companion.

Use outcomes precisely:

- `PASS`: exact Release, controller, and runtime agree and are healthy (the reported symptom needs a different owner).
- `WATCH`: bounded, evidenced convergence lag with no failure/mismatch yet.
- `BLOCK`: unhealthy runtime, digest/provenance mismatch, gates, unknown target, or a proposed mutation without broker authority.
- `ASK`: a human must choose between materially different stabilization scopes.

## Decide: rollback or fix forward

### A. Roll back a recent causal Release

Choose this when symptoms began after a specific immutable Release and a known-good revision set is available. Do not “deploy an old Release” while leaving bad heads current. Route to `rollback-revision` to:

1. identify exact prior RevisionID/DataHash per affected Unit;
2. propose head-moving `cub unit update --restore` operations;
3. compute the resulting destination EffectiveReleaseSet; and
4. prepare a new whole-Space Release proposal through `release-publish`.

If the suspect mutations were grouped in a ChangeSet, `Before:ChangeSet:<space>/<slug>` is useful restore evidence. The ChangeSet does not narrow publication. If only some Units are restored but the Release captures more Units, disclose that scope and ask again.

### B. Fix forward

Choose this when the cause is known and a small, reversible ConfigHub data change is safer/faster than restoring a larger set. Route to `cub-mutate` for an exact function-first proposal with incident-linked `--change-desc`, then to `release-publish` for the new whole-Space Release subject.

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

Direct ConfigHub-provider Release delivery is `VERSIONED_LEGACY/BLOCK` in the reviewed profile.

## Approval, execution, and incident provenance

Current native approval is head-at-execution only and has no expected RevisionID/DataHash CAS; do not call it exact revision approval. It also does not authorize this companion to execute the approval, restore, mutation, promotion, or Release. Incident urgency does not create broker authority. Produce the smallest exact proposal, blast radius, rollback plan, proof plan, and resume condition; then return `BLOCK` while the broker is absent.

Do not conflate native approval with mutation CAS. Unit update execution has transactional expected `HeadRevisionNum` and hash checks when the caller supplies them, but the protected incident path does not bind those approved values through final request and receipt. Restores/fixes therefore also return `APPROVED_STATE_CAS_NOT_INTEGRATED`; urgency is not a reason to use the unbound convenience path.

Every incident mutation proposal must retain the baseline provenance contract in its `--change-desc`:

```text
Incident: <ticket-id or short slug>
User prompt: <verbatim>
Clarifications: <condensed decision, evidence, approver/commander, and expected duration>
```

Do not paraphrase away the original prompt. For concurrent incidents, name the owning incident and check whether another open ChangeSet already holds any affected Unit. Shared Units must be sequenced or the scope split; never interleave two incident ChangeSets on one Unit.

## Closeout

Use `verify-apply` after externally authorized stabilization. Close only when it records:

- exact new ReleaseID, bundle Digest, and ManifestDigest;
- controller bound to that immutable source;
- runtime health and ConfigHub origin provenance;
- EffectiveReleaseSet/UnitCount coverage;
- any omitted evidence as an explicit gap; and
- emergency out-of-band changes either encoded as desired state or intentionally removed.

Then capture the incident timeline, suspect and recovery Releases, restored/mutated RevisionIDs, approvals/receipts, remaining warnings, and follow-up owners. Prepare (but do not execute) the durable resolution marker used by the baseline workflow:

```bash
cub tag create --space <app>-home incident-<YYYYMMDD>-<ticket> \
  --annotation "description=<short incident description> — resolution type: rollback|mitigate|reconcile"
cub unit tag <app>-home/incident-<YYYYMMDD>-<ticket> \
  --space <env-space> --filter <app>-home/<app>-app
```

Bind the exact revisions before proposing the tag; tagging is a mutation and remains `BLOCK` without the broker. GUI open commands are navigation only until org/object identity is verified.

## Stop conditions

- no immutable suspect Release or wrong cluster context;
- rollback target, blast radius, or durable-vs-temporary intent is ambiguous;
- a narrow restore/fix would be published as a broader Space Release without new approval;
- user asks to bypass an ApplyGate, controller policy, or broker;
- another incident ChangeSet already owns any Unit in scope and no sequencing decision exists;
- mutation provenance would omit `Incident:`, the verbatim prompt, or clarifications;
- evidence requires a mutation to discover.

## References

- `compatibility/current-profile.v1.json`
- `rollback-revision`, `cub-mutate`, `release-publish`, `verify-apply`
- `worker-bootstrap` for external custom-function worker diagnosis
- `references/changesets.md` for grouped revision restore/approval semantics
