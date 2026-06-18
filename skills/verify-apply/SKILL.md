---
name: verify-apply
description: 'Post-apply verification and close-out. Confirm ConfigHub published/applied the Unit (Completed vs Failed), then confirm ArgoCD/Flux pulled the OCI artifact and the cluster converged (read-only argocd/flux/kubectl). Use right after cub-apply, or for: did it actually deploy, is it live, did argo pick it up, close this release out. Not for authoring (use cub-mutate).'
phase: verify
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(kubectl get *) Bash(kubectl describe *) Bash(kubectl logs *) Bash(argocd app get *) Bash(argocd app diff *) Bash(argocd app history *) Bash(flux get *) Bash(flux stats *) Bash(flux logs *)
---

# verify-apply

Post-apply verification, troubleshooting, and close-out — one skill for the whole arc from "did it land?" to "we're done."

Confirm verbs and flags with `cub <verb> --help` before composing.

## The two questions

`cub unit apply` returning is not the same as the change being live. With OCI delivery there are **two distinct stages**, and ConfigHub only owns the first:

1. **Did ConfigHub publish/apply succeed?** For an **OCI** Target, apply *publishes* the Unit's data to ConfigHub's OCI registry and completes immediately (`ApplyCompleted` = "Published successfully") — there's no "waiting for the cluster" on the ConfigHub side. For a **ConfigHub** Target, apply writes ConfigHub-native config directly. This stage is answered from ConfigHub (`UnitStatus` / `unit-event`).
2. **Did ArgoCD/Flux converge the cluster?** The GitOps tool pulls the published OCI artifact and rolls it out. ConfigHub does **not** observe this — verify it **out-of-band**, read-only, with `argocd` / `flux` / `kubectl`. Runtime failures (`ImagePullBackOff`, `CrashLoopBackOff`, probe failures) live entirely here.

`cub-apply` hands off here immediately after returning.

## When to use

- Right after `cub-apply` returns, always.
- "Did it deploy?" / "is it live?" / "did argo pick it up?" / "prove it converged."
- A publish/apply reported failure, or the user thinks the rollout is stuck.
- "Close this out" / "show me the revision history to file."

## Do not load for

- The apply has not run yet — use `cub-apply`.
- Plain ConfigHub-internal query with no runtime cross-check — use `cub-query`.
- Rolling back a change — use `rollback-revision`.

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. An apply has been attempted — at least one `Apply` entry in `cub unit-action list <slug> --space <s>`. If not, route to `cub-apply`.
3. For cluster-convergence checks: `kubectl config current-context` matches the cluster ArgoCD/Flux deploys to, and `argocd` / `flux` are authenticated against the right instance. If a layer is unreachable, say so explicitly — don't fake agreement.

## Stage 1 — did ConfigHub publish/apply?

ConfigHub exposes apply status in overlapping views. Pick the smallest that answers the question.

| Source | Command | What it shows |
| --- | --- | --- |
| Unit rollup | `cub unit get <slug> --space <s> -o jq=.UnitStatus` | `Action`, `ActionResult`, `Status`, `SyncStatus`, `Drift`. First look. |
| Latest event | `cub unit get <slug> --space <s> -o jq=.LatestUnitEvent` | Last Worker progress record — `Action`, `Result`, `Status`, `Message`, `UnitEventNum`. |
| Full event log | `cub unit-event list <slug> --space <s>` | Every event for the unit. |
| Per-event detail | `cub unit-event get <slug> <num> --space <s>` | `Message` (the actual error) + a `ResourceStatuses` table per resource. |
| Action rollup | `cub unit-action list <slug> --space <s>` | One final status per action: `Completed` / `Failed` / `Aborted`. |

Terminal results worth recognizing:

- **`Completed` / `ApplyCompleted`** — for OCI, the data was **published** to the registry ("Published successfully (oci)"). The Unit is now available for Argo/Flux to pull — go to Stage 2 to confirm the cluster. For a ConfigHub Target, the config was applied directly.
- **`Failed` / `ApplyFailed`** — the publish/apply itself failed. `Message` carries the error. Go to "Failed" below.
- **`Aborted`** — cancelled via `cub unit cancel` or superseded by a later apply.

`LastActionError` is not a real field — read errors from `unit-event`'s `Message`. For bulk scope, pivot to `cub unit list --space <s> --filter platform/apply-not-completed` to surface anything whose publish didn't complete.

### Failed — read the error

```bash
cub unit-event get <slug> <latest-event-num> --space <s>
```

`Message` carries it; `ResourceStatuses` names the resource. Common shapes: schema violation (would be caught by `vet-schemas` — route to `triggers-and-applygates` to gate it next time), RBAC on the OCI registry, malformed data. Surface it; route to the right fix skill (`cub-mutate` for data, `cub-apply` to re-publish).

## Stage 2 — did Argo/Flux converge the cluster?

ConfigHub reports `Completed` once the artifact is published; whether the cluster actually rolled it out is the GitOps tool's job. Verify it directly, **read-only**:

For ArgoCD-pulled deployments:

```bash
argocd app get <app-name>          # Sync + Health, and the synced revision
argocd app diff <app-name>         # live vs desired
argocd app history <app-name>
```

For Flux-pulled deployments:

```bash
flux get kustomizations
flux get helmreleases
flux logs --kind=Kustomization --name=<name>
```

Then the cluster itself (where runtime failures surface):

```bash
kubectl get <kind> <name> -n <namespace>
kubectl describe <kind> <name> -n <namespace>
kubectl get pods -n <namespace> -l <selector>
kubectl logs <pod> -n <namespace> --previous   # crashlooped pods
```

Report the broken link in plain English — "ConfigHub published rev 12; Argo synced it; but the `checkout` pod is in `ImagePullBackOff`: image `ghcr.io/acme/checkout:v1.2.4` not found." Do **not** mutate — no `kubectl rollout restart`, no `argocd app sync --force`, no `flux reconcile`. If the fix is a data change, hand back to `cub-mutate`; if a re-publish, `cub-apply`.

## Three-way agreement (optional)

When asked "is everything in sync?", build a three-column table — note ConfigHub's column means **published**, not "applied to cluster":

| Row | ConfigHub (published) | Controller (Argo/Flux) | Cluster |
| --- | --- | --- | --- |
| Revision | `cub unit get -o jq='.Unit \| {head: .HeadRevisionNum, live: .LiveRevisionNum, applied: .LastAppliedRevisionNum}'` | `argocd app get` → Sync revision / `flux get` → Applied revision | `metadata.annotations.confighub.com/RevisionNum` |
| Image | `cub function get --space <s> --unit <slug> get-container-image <container>` | Argo live manifest | `kubectl get <kind> -o jsonpath='{.spec.template.spec.containers[*].image}'` |
| Health | `UnitStatus.Status == "Completed"` (published) | Argo `Healthy` / Flux `Ready: True` | `.status.conditions[?(@.type=="Available")].status` |

Name what disagrees:

- **ConfigHub published, controller behind** — Argo/Flux hasn't pulled the new OCI artifact yet (sync interval, manual sync, or a broken source). Check the controller.
- **Controller synced, cluster not converged** — probe failure, image-pull, or RBAC in the cluster.
- **Cluster diverges from the published artifact** — something mutated the cluster out of band; that's Argo/Flux's reconciliation domain (self-heal / drift detection), not ConfigHub's. Point the user at the controller.

If a column is unreachable (`argocd` not authenticated, `kubectl` context mismatch), report it "unknown" — don't assume agreement.

## Close the release out

Only when Stage 1 is `Completed` for the whole scope and (if asked) Stage 2 converged:

1. Surface the revision + `--change-desc`: `cub revision list <slug> --space <s>` (the `DESCRIPTION` column is the audit trail).
2. Show what changed: `cub unit diff <slug> --space <s> --from <pre-release-revision> --to LiveRevisionNum`.
3. Open review links: `cub unit get <slug> --space <s> --web`, `cub revision list <slug> --space <s> --web`.
4. Explicitly stop. Tell the user what landed and which links to file. A further change starts fresh via `cub-mutate` / `cub-apply`.

## Tool boundary

Read-only end to end. No mutations — including `kubectl apply/edit/delete/rollout restart`, `argocd app sync`, `flux reconcile`, and any non-dry `cub unit refresh`. The `argocd` / `flux` / `kubectl` reads here are how you verify Stage 2; they never mutate.

If the fix is data → `cub-mutate`. Another publish → `cub-apply`. Rollback → `rollback-revision`.

## Stop conditions

- User's intent pivots from verify to fix — hand off, don't mutate.
- A controller or cluster layer is unreachable — report "unknown."
- Scope too broad for a useful table — narrow via `--where` / `--filter` / `platform/apply-not-completed`.
- Close-out preflight fails (any Unit still publishing / Failed / gated / `LiveRevisionNum` behind `HeadRevisionNum`) — route back.

## Evidence

- `cub unit get <slug> --space <s> --web` — Unit page (data, published state, revisions, gates, events).
- `cub unit-event list <slug> --space <s>` — per-apply event stream.
- `cub revision list <slug> --space <s> --web` — revision history with `--change-desc`.
- ArgoCD / Flux UIs and `kubectl get <kind> <name> -o yaml` — cluster-side evidence.

## References

- `references/cub-cli.md` — unit/event/action query patterns, read-only discipline.
- `references/filters-and-queries.md` — `apply-not-completed`, `unapplied-changes`, `has-apply-gates`.
- `references/revisions.md` — revision data model for close-out.
- Companion skills: `cub-apply` (publishes; hands off here), `cub-mutate` (composed the `--change-desc` you cite), `rollback-revision` (restore a prior revision), `target-bind`/`worker-bootstrap` (when the broken link is the Target), `triggers-and-applygates` (when a vet should have caught it pre-apply).
