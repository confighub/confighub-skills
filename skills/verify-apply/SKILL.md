---
name: verify-apply
description: 'Use right after cub-apply returns, or any time the user asks "did it actually deploy?", "is it live?", "is it still applying?", "did argo pick it up?", "are ConfigHub and the cluster in sync?", "prove this converged", "close this release out", "show me what changed". Single skill covering the whole post-apply arc: read Unit status + latest event to classify the apply (Progressing / Completed / Failed / Aborted), drill into `cub unit-event get` for per-resource sync/ready status and the Message field when something broke, cross-check the controller (Argo/Flux) and cluster (kubectl) for runtime failures (ImagePullBackOff, CrashLoopBackOff, schema errors), optionally produce a three-way ConfigHub ↔ controller ↔ cluster agreement table, and on success surface the Revision history with its --change-desc + GUI review links. Do not load for pure ConfigHub-internal query (use cub-query), for reconciling known drift (use drift-reconcile), or when the apply has not actually run yet (use cub-apply).'
phase: verify
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit refresh --dry-run *) Bash(cub worker logs *) Bash(cub worker status *) Bash(kubectl get *) Bash(kubectl describe *) Bash(kubectl logs *) Bash(argocd app get *) Bash(argocd app diff *) Bash(argocd app history *) Bash(flux get *) Bash(flux stats *) Bash(flux logs *)
---

# verify-apply

Post-apply verification, troubleshooting, and close-out — one skill for the whole arc from "did it land?" to "we're done."

## What this answers

`cub unit apply` returning is not the same as the change being live. Verification is three questions in sequence:

1. **Did the apply reach a terminal outcome?** Progressing, Completed, Failed, or Aborted.
2. **If not Completed: where did it break?** ConfigHub → controller (Argo/Flux) → cluster (kubectl) — name the first broken link.
3. **If Completed: are all layers in agreement?** And can we document the release?

`cub-apply` hands off to this skill immediately after returning. Even a successful return value can hide an in-progress, failed, or stuck apply.

## When to use

- Right after `cub-apply` returns, always.
- "Did it deploy?" / "is it live?" / "is the pod new?" / "did argo pick it up?"
- `cub unit apply --wait` timed out, or the user thinks it's stuck.
- "Is ConfigHub, Argo, and the cluster in agreement?" / "prove it converged."
- "Close this out" / "show me the revision history to file."
- Post-incident: "we applied the fix; confirm we're stable and document it."

## Do not load for

- The apply has not actually run yet — use `cub-apply`.
- Plain ConfigHub-internal query with no runtime cross-check — use `cub-query`.
- Known drift where the decision is accept vs. overwrite — use `drift-reconcile`.
- Rolling back a change — use `rollback-revision`.

## Preflight gates

1. `cub organization list` succeeds (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. An apply has been attempted on the Unit(s) in scope — there's at least one `Apply` entry in `cub unit-action list <slug> --space <s>`. If not, the question is "should we apply?" — route to `cub-apply`.
3. For cluster-level checks: `kubectl config current-context` matches the cluster the Unit's Target points at. If not, flag the mismatch — read-only commands still work but the answer may be wrong.
4. For controller-level checks: `argocd` / `flux` CLI is authenticated against the right instance. If not, skip that layer and say so explicitly — don't fake agreement.

## Apply-status taxonomy

ConfigHub exposes apply status in three overlapping views. Pick the smallest one that answers the question.

| Source           | Command                                                                        | What it shows                                                                                                                                                                                |
| ---------------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unit rollup      | `cub unit get <slug> --space <s> -o jq=.UnitStatus`                            | Compact status envelope: `Action`, `ActionResult`, `ActionStartedAt`, `ActionTerminatedAt`, `Drift`, `Status`, `SyncStatus`. First place to look.                                            |
| Latest event     | `cub unit get <slug> --space <s> -o jq=.LatestUnitEvent`                       | Last progress record from the Worker — `Action`, `Result`, `Status`, `Message`, `UnitEventNum`. Gives you the unit-event number to drill into.                                               |
| Full event log   | `cub unit-event list <slug> --space <s>`                                       | Every progress + terminal event for the unit. Walk back when debugging "how did we get here?".                                                                                               |
| Per-event detail | `cub unit-event get <slug> <num> --space <s>`                                  | Includes `Message` (the actual error when things broke) and a `ResourceStatuses` table with `SyncStatus` + `Readiness` per resource in the Unit. Use this to pinpoint which resource failed. |
| Action rollup    | `cub unit-action list <slug> --space <s>` / `cub unit-action get <slug> <num>` | One final status per action: `Completed`, `Failed`, `Aborted`. Less detailed than `unit-event`, but the right grain for "what happened to the last N applies?" across many Units.            |

`Status` values worth recognising in event / action output:

- **`Progressing`** + `Result: None` — Worker is still acting. The apply may be stuck. See the Progressing branch below.
- **`Progressing`** + `Result: ApplySynced` — resources were applied to the cluster successfully; the Worker is now waiting for them to become ready. A healthy intermediate state, but a workload in `ImagePullBackOff` will sit here forever.
- **`Completed`** + `Result: ApplyCompleted` — terminal success. All resources synced + ready.
- **`Failed`** + `Result: ApplyFailed` — terminal failure. The `Message` field carries the error (schema violation, RBAC denial, missing namespace, etc.).
- **`Aborted`** — the user cancelled via `cub unit cancel` or a subsequent apply superseded this one.

A Unit's `Data`, `LiveData`, `LiveState`, and `BridgeState` views only update on successful apply. Do not use them to debug a failed or stuck apply — they reflect the last success, not current reality. Use `cub unit refresh <slug> --dry-run` (read-only) to pull what the cluster currently has without updating the Unit; the `drift-reconcile` skill covers that path in detail.

`LastActionError` is not a real field. Read error text from `unit-event`'s `Message` field.

## The loop

### 1. Classify the apply

```bash
cub unit get <slug> --space <s> -o jq='{status: .UnitStatus, event: .LatestUnitEvent}'
```

Branch on `UnitStatus.Status`:

- **`Completed` / `Ready`** → the apply reached a terminal success. Go to step 4 (three-way agreement) if the user asked for confirmation, or step 5 (close-out) if they just want the release documented.
- **`Progressing`** → the apply is still in flight _or_ stuck. Go to step 2.
- **`Failed`** → read the error. Go to step 3.
- **`Aborted`** → the user (or a superseding apply) cancelled. Surface that and ask what they want next.

For bulk scope (many Units), pivot to the `apply-not-completed` filter to surface anything that didn't converge:

```bash
cub unit list --space <s> --filter platform/apply-not-completed
```

Units that show up have `LastAppliedRevisionNum != LiveRevisionNum` — apply attempted, live state did not catch up.

### 2. Progressing — is it moving, or stuck?

```bash
cub unit-event list <slug> --space <s>
```

Look at the event stream. Healthy apply progression is roughly:

1. `Apply` / `Status: Progressing` / `Message: Starting to apply resources...`
2. `Apply` / `Status: Progressing` / `Message: Applying resources...`
3. `Apply` / `Status: Progressing` / `Result: ApplySynced` / `Message: Resources applied successfully, waiting for ready state`
4. `Apply` / `Status: Completed` / `Result: ApplyCompleted`

If the latest event is step 3 and hasn't moved, the resources are applied but at least one isn't becoming ready. This is the common runtime-error case — `ImagePullBackOff`, `CrashLoopBackOff`, unsatisfiable probe, unscheduled pod. The Worker won't tell you which pod; go to the cluster directly:

```bash
kubectl get <kind> <name> -n <namespace>
kubectl describe <kind> <name> -n <namespace>
kubectl get pods -n <namespace> -l <selector>
kubectl logs <pod> -n <namespace> --previous   # for crashlooped pods
```

For Argo-backed Targets, also:

```bash
argocd app get <app-name>
argocd app diff <app-name>
```

For Flux-backed Targets:

```bash
flux get kustomizations
flux get helmreleases
flux logs --kind=Kustomization --name=<name>
```

Report the broken link in plain English — "resources applied, but the `checkout` pod is in `ImagePullBackOff`: image `ghcr.io/acme/checkout:v1.2.4` not found." Do not mutate — no `kubectl rollout restart`, no `argocd app sync --force`, no `cub unit refresh`. If the fix is a data change, hand back to `cub-mutate`; if it's a new apply, hand back to `cub-apply`.

### 3. Failed — read the error

```bash
cub unit-event get <slug> <latest-event-num> --space <s>
```

The `Message` field carries the error. Common shapes:

- **Schema violation** — e.g. `field not declared in schema`. Would have been caught by `vet-schemas`; route to `triggers-and-applygates` to wire the vet function as a gate so this class of failure blocks apply next time.
- **Missing namespace** — `namespaces "foo" not found`. Ensure the Namespace Unit is applied first.
- **RBAC** — the Worker's ServiceAccount can't create the resource. Check the worker's role bindings.
- **Conflict** — another controller or apply is rewriting the same field.

`ResourceStatuses` in the same event output names the specific resource that failed, so you can pinpoint which one to fix. Surface that to the user; route to the right skill for the fix.

### 4. Completed — three-way agreement (optional)

When the user explicitly asks "is everything in sync across ConfigHub, the controller, and the cluster?", build a three-column table:

| Column                        | ConfigHub                                                                                                          | Controller                                                       | Cluster                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Revision                      | `cub unit get -o jq='.Unit \| {head: .HeadRevisionNum, live: .LiveRevisionNum, applied: .LastAppliedRevisionNum}'` | `argocd app get` → Sync revision / `flux get` → Applied revision | `metadata.annotations.confighub.com/RevisionNum`                                       |
| Image (example content field) | `cub function get --space <s> --unit <slug> get-container-image <container>`                                       | `argocd app get` → live manifest                                 | `kubectl get <kind> -o jsonpath='{.spec.template.spec.containers[*].image}'`           |
| Health                        | `UnitStatus.Status == "Ready"`, `SyncStatus == "InSync"`                                                           | Argo `Health: Healthy` / Flux `Ready: True`                      | `.status.conditions[?(@.type=="Available")].status == "True"` (or equivalent per kind) |
| Owner                         | `Space.Slug` / `Unit.Slug`                                                                                         | Argo `Project` / Flux `Source`                                   | `metadata.annotations.confighub.com/*` and `metadata.ownerReferences`                  |

Surface the table as-is; don't collapse divergences. Name what disagrees:

- **ConfigHub ≠ controller** — apply hasn't propagated or the worker thinks it hasn't. Check `cub unit livestate` and `cub worker status`.
- **Controller ≠ cluster** — controller thinks it finished but the cluster didn't converge. Usually probe failure, image-pull, or RBAC.
- **Cluster ≠ ConfigHub, controller agrees with cluster** — someone mutated the cluster out of band. Route to `drift-reconcile`.

If a column is unreachable (`argocd` not authenticated, `kubectl` context mismatch), report it as "unknown" rather than assume agreement.

### 5. Close the release out

Only when the scope is fully Completed and (if three-way was asked for) converged:

1. Surface the revision + `--change-desc`:

   ```bash
   cub revision list <slug> --space <s>
   ```

   The `DESCRIPTION` column carries each revision's `--change-desc` — the verbatim user prompt + condensed clarifications from the moment the mutation happened. That is the audit trail.

2. Show what actually changed end-to-end:

   ```bash
   cub unit diff <slug> --space <s> --from <pre-release-revision> --to LiveRevisionNum
   ```

3. Open the canonical review links (prefer `--web` over hand-built URLs):

   ```bash
   cub unit get <slug> --space <s> --web
   cub revision list <slug> --space <s> --web
   cub space get <s> --web
   ```

4. Explicitly stop. Tell the user: what landed, which links to file/share, "no further changes in this session unless you start a new one." If the user then asks for another change, route to `cub-mutate` / `cub-apply` with fresh preflight gates — don't thread it through the close-out.

## Tool boundary

Read-only end to end. No mutations — including `kubectl apply/edit/delete/rollout restart`, `argocd app sync --force`, `flux reconcile`, and `cub unit refresh` _without_ `--dry-run` (a bare `cub unit refresh` rewrites Unit state from live and is a mutation). `cub unit refresh --dry-run` is fine for looking at current cluster content.

If the fix is data: hand back to `cub-mutate`. If the fix is another apply: hand back to `cub-apply`. If the fix is rollback: hand back to `rollback-revision`. If it's drift: hand back to `drift-reconcile`.

## Stop conditions

- User's intent pivots from verify to fix — hand off, don't mutate from here.
- A column (controller or cluster) is unreachable — report "unknown" rather than assume agreement.
- Scope is too broad to produce a useful table (hundreds of Units) — ask the user to narrow via `--where` / `--filter` / the `apply-not-completed` filter.
- Close-out preflight fails (any Unit still Progressing / Failed / with `ApplyGates` / with `LiveRevisionNum` behind `HeadRevisionNum`) — stop and route back to step 1–3.

## Evidence

- `cub unit get <slug> --space <s> --web` — authoritative Unit page (data, live state, revisions, gates, events).
- `cub unit-event list <slug> --space <s>` — per-apply event stream with messages.
- `cub revision list <slug> --space <s> --web` — revision history with `--change-desc`.
- Argo / Flux UIs — controller-side evidence the user can click on.
- `kubectl get <kind> <name> -o yaml` — cluster-side evidence.

## References

- `references/cub-cli.md` — unit/event/action query patterns, read-only discipline.
- `references/filters-and-queries.md` — `apply-not-completed`, `unapplied-changes`, `has-apply-gates`, related operational filter recipes.
- `references/revisions.md` — revision data model for close-out explanations.
- Companion skills: `cub-apply` (upstream act; hands off here), `cub-mutate` (what composed the `--change-desc` you see in close-out), `drift-reconcile` (when the failure mode is drift rather than a broken apply), `rollback-revision` (when the fix is to restore a prior revision), `worker-bootstrap` (when the broken link is the Worker itself), `triggers-and-applygates` (when a vet function should have caught the failure pre-apply).
