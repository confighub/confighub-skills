# reconciliation-check eval — with-skill

## Scenario

> hello-ns passed verify-delivery. Do ConfigHub and the cluster actually agree on what's live? Produce the three-way table. (Note: no Argo/Flux in play — this Target is direct Kubernetes, so the controller column is N/A by design; surface that explicitly rather than faking an Argo row.)

## Preflight

```
$ cub context get                       # auth OK (NOT cub info)
$ kubectl config current-context        # kind-confighub-eval — matches Target's KubeContext
```

Scope: `hello-ns` (single Unit, one Namespace resource).

## Three-way table

Since there's no Argo/Flux controller layer, the **controller** column is `N/A (direct Kubernetes Target)`. Per the skill: "Any column is unreachable — report that column as 'unknown' rather than faking agreement." Here the absence is by design, not unreachable, so report it as N/A.

| Column | ConfigHub | Controller | Cluster | Agreement |
|---|---|---|---|---|
| Resource | `Namespace/hello` (`cub unit livedata hello-ns`) | N/A | `kubectl get ns hello` → Active | ✓ |
| Revision | `LiveRevisionNum=3`, `LastAppliedRevisionNum=3`, `HeadRevisionNum=3` | N/A | `metadata.annotations[cli-utils.sigs.k8s.io/inventory-id]` present, namespace owned by worker | ✓ |
| Health | `LastActionError` empty; list shows STATUS=Ready | N/A | `status.phase=Active` | ✓ |
| Owner | Space `skill-examples`, Unit `hello-ns` | N/A | `labels[app.kubernetes.io/managed-by]=confighub` + inventory ConfigMap `confighub.com/SpaceID`, `confighub.com/UnitSlug=hello-ns` | ✓ |

Commands used:

```bash
cub unit get hello-ns --space skill-examples
cub unit livedata hello-ns --space skill-examples
cub unit bridgestate hello-ns --space skill-examples

kubectl get ns hello -o yaml
```

## Findings

All three rows agree. No divergences. For reference, if any pair had disagreed:

- **ConfigHub ≠ controller**: apply not yet propagated — check `cub worker status` + `cub unit bridgestate`.
- **Controller ≠ cluster**: controller thinks it finished but cluster didn't — `kubectl describe`.
- **Cluster ≠ ConfigHub, controller agrees with cluster**: out-of-band drift — route to `cub unit refresh` (drift skill), NOT this skill.

## For hello-app (the failed unit) — separate row to make the divergence visible

| Column | ConfigHub | Controller | Cluster | Agreement |
|---|---|---|---|---|
| Resource | `Deployment/hello-app`, `Service/hello-app` (data has `namespace: confighubplaceholder`) | N/A | No resources in namespace `hello` (and no `confighubplaceholder` namespace exists) | ✗ |
| Revision | `LastApplied=6`, `Live=0` | N/A | n/a | ✗ ConfigHub ≠ Cluster |
| Health | `STATUS=Degraded` | N/A | n/a | ✗ |

Divergence → ConfigHub side attempted apply (Applied=6) but the cluster doesn't have the resources → the worker's apply failed at the `cub → cluster` link before anything landed. Route back to `cub-apply` after fixing the underlying data (the namespace placeholder). Not this skill's job to fix.

## Tool boundary

All read-only. No `cub unit refresh`, no `kubectl apply`, no `argocd app sync`.

## Hand-off

- hello-ns converged three-way (two-way here, since no controller) → route to `release-verify` for completion.
- hello-app diverged → route to `cub-mutate` (fix placeholder) then `cub-apply`.

## Evidence

```
cub unit get hello-ns --space skill-examples --web
cub unit get hello-app --space skill-examples --web
```
