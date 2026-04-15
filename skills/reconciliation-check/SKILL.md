---
name: reconciliation-check
description: Use when the user wants to prove ConfigHub, the controller (Argo / Flux), and the cluster all agree on the same state for one or more Units — phrases like "is everything in sync?", "are ConfigHub and Argo telling the same story?", "three-way check", "prove the change converged", "is there drift anywhere?", "which source of truth should I believe?". Builds a four-column table (image, revision, health, owner) using cub, the controller CLI, and kubectl so divergence is visible at a glance. Load after verify-delivery passes individual checks; stops short of the final read-only close (that's release-verify). Do not load for plain cluster debugging (use kubectl directly), for ConfigHub-internal query (use cub-query), or before an apply has finished (use verify-delivery first).
phase: verify
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(kubectl get *) Bash(kubectl describe *) Bash(argocd app get *) Bash(argocd app diff *) Bash(flux get *) Bash(flux stats *)
---

# reconciliation-check

Three-way agreement: ConfigHub ↔ controller ↔ cluster.

## Why this matters

"Apply succeeded" tells you *one* layer succeeded. Convergence is when **all three** layers — ConfigHub (the managed source of record), the controller (Argo / Flux), and the cluster — tell the same story. Drift between any two means one of them is wrong; knowing *which two disagree* is the fastest path to the cause.

## When to use

- After `verify-delivery` passes, the user wants explicit three-way confirmation.
- User suspects drift: cluster looks right but ConfigHub says pending, or vice versa.
- Pre-incident or pre-change: "is everything in agreement before I touch it?"
- Auditing a release: "prove this actually converged."

## Do not load for

- Debugging a pod that's crashing (that's cluster-level only — use `kubectl` / `verify-delivery`).
- ConfigHub-only queries without a live-state cross-check (`cub-query`).
- The final read-only completion step surfacing Revision history (`release-verify`).

## Preflight gates

1. `cub context get` returns a user.
2. `kubectl config current-context` matches the cluster the Unit targets. If not, the cluster column will be wrong; stop and fix context before reporting.
3. For controller columns: `argocd login` / Flux kubectl context is usable; otherwise skip that column and say so explicitly.

## The four-column table

For each Unit in scope, populate:

| Column | Source | What it says |
|---|---|---|
| Image | **ConfigHub:** `cub function do get-container-image` <br> **Controller:** `argocd app get` → target spec / `flux get` → last applied <br> **Cluster:** `kubectl get <workload> -o jsonpath='{.spec.template.spec.containers[*].image}'` | The container image each layer *thinks* should run. |
| Revision | **ConfigHub:** `cub unit get` → `LiveRevisionNum` / `LastAppliedRevisionNum` <br> **Controller:** `argocd app get` → Sync revision / `flux get` → Applied revision <br> **Cluster:** `metadata.annotations.confighub.com/revision` (if the worker sets it) or `.status.observedGeneration` | What revision each layer thinks is live. |
| Health | **ConfigHub:** `cub unit get` → `LastActionError` empty <br> **Controller:** `argocd app get` → `Health: Healthy` / `flux get` → `Ready: True` <br> **Cluster:** `.status.conditions[?(@.type=="Available")].status == "True"` (or equivalent per kind) | Whether each layer thinks the state is OK. |
| Owner | **ConfigHub:** `Space.Slug` / `Unit.Slug` <br> **Controller:** `argocd app get` → `Project` / `flux get` → `Source` <br> **Cluster:** `metadata.annotations.confighub.com/*` and `metadata.ownerReferences` | Who each layer thinks owns this resource. This column catches resources owned by the wrong Unit or by no ConfigHub-managed source at all. |

Surface the table as-is; don't collapse divergences. A passing three-way shows the same value across all three columns. A divergence is the finding.

## The loop

### 1. Resolve the scope

Single Unit, list, or filter — typically the same scope `verify-delivery` just ran against.

### 2. Extract each column from each source

Prefer getter functions for the ConfigHub-side content columns (they're structured and preserve comments):

```bash
# Image per Deployment, across the scope.
cub function do --space <s> --where "Slug IN ('<u1>','<u2>')" --resource-type apps/v1/Deployment \
  get-container-image <container> \
  --quiet --output-jq '.[] | {unit: .UnitSlug, image: .Value}'

# Revision numbers.
cub unit list --space <s> --where "Slug IN ('<u1>','<u2>')" \
  --jq '.[].Unit | {slug: .Slug, head: .HeadRevisionNum, live: .LiveRevisionNum, applied: .LastAppliedRevisionNum}'
```

Controller and cluster columns come from the read-only controller CLI and `kubectl get`, respectively. Batch where practical to reduce chatter.

### 3. Report the table, then the divergences

Lay out the table (markdown or plain text). For each row where the three columns disagree, name the specific pair that disagrees and what that implies:

- **ConfigHub ≠ controller:** the apply hasn't propagated. Often means the worker is stuck or the controller hasn't synced yet — check `cub unit bridgestate` and `cub worker status`.
- **Controller ≠ cluster:** the controller thinks it finished but the cluster didn't actually converge. Often a probe failure, image-pull, or RBAC denial — check `kubectl describe`.
- **Cluster ≠ ConfigHub, controller agrees with cluster:** someone mutated the cluster out-of-band. Drift. Route to `cub unit refresh` + drift handling (not this skill).

### 4. Hand off

- Three-way agreement → hand off to `release-verify` for the final completion step.
- Divergence → hand off to the skill that addresses the broken link (`cub-apply`, `triggers-and-applygates`, `worker-bootstrap`, or a drift-reconcile flow).

## Tool boundary

Read-only across ConfigHub, controller, and cluster. **Never** mutate from here, including `cub unit refresh` (it rewrites Unit state from live), `argocd app sync`, or `kubectl rollout restart`. If the answer is "we should fix it", hand off.

## Stop conditions

- Any column is unreachable (e.g., `argocd` CLI not authenticated). Report that column as "unknown" rather than faking agreement.
- User's intent pivots to remediation. Hand off.
- Scope is too broad to produce a useful table (hundreds of Units). Ask the user to narrow the scope via `--where` / `--filter`.

## Verify chain

N/A — this skill produces the three-way verification directly.

## Evidence

- `cub unit get <slug> --space <s> --web` — the Unit page, one row's worth of ConfigHub data.
- Argo UI / Flux UI — controller column evidence.
- `kubectl get <kind> <name> -o yaml` — cluster column evidence.

## References

- `references/filters-and-queries.md` — scoping recipes, especially `apply-not-completed` and `has-upstream`.
- `references/cub-cli.md` — read-only diagnosis tool boundary.
- Companion skills: `verify-delivery` (runs before this for pure link-by-link verification), `release-verify` (the completion step after this passes).
