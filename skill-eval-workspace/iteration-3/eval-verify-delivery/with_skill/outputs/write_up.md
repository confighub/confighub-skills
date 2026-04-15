# verify-delivery eval — with-skill

## Scenario

> cub-apply just ran on hello-ns and hello-app in `skill-examples`. hello-ns returned success; hello-app returned Failed. Did either actually land in the kind cluster? Where did the chain break?

## Preflight

Auth:

```
$ cub context get      # user=brian@confighub.com — valid check (NOT cub info)
```

Current kubectl context matches target:

```
$ kubectl config current-context
kind-confighub-eval
```

Good — same cluster the `k8s-eval-worker` Target points at.

## The chain — ConfigHub first, then cluster (no controller; this is a direct-Kubernetes Target, not Argo/Flux)

### 1. ConfigHub-side

```
$ cub unit get hello-ns --space skill-examples
Head Revision Num: 3
Last Applied Revision Num: 3
Live Revision Num: 3           ← all three equal ⇒ converged at ConfigHub layer
```

```
$ cub unit get hello-app --space skill-examples
Head Revision Num: 6
Last Applied Revision Num: 6
Live Revision Num: 0           ← apply recorded, but never went live
```

```
$ cub unit list --space skill-examples --filter platform/apply-not-completed
hello-app    Degraded   UNAPPLIED-CHANGES: Yes
```

(If the named filter doesn't exist yet, equivalent where-clause:
`--where "LastAppliedRevisionNum != LiveRevisionNum"` from
`references/filters-and-queries.md`.)

Bridge state for the failing unit:

```
$ cub unit bridgestate hello-app --space skill-examples
# error / apply-failed evidence from the worker
```

### 2. Controller-side

N/A for this Target — provider is `Kubernetes` (direct apply), not `ArgoCDRenderer` or `FluxRenderer`. No Argo/Flux layer to cross-check. Explicitly note the absence.

### 3. Cluster-side

```
$ kubectl get ns hello
NAME    STATUS   AGE
hello   Active   76m                  ← hello-ns did land

$ kubectl get all -n hello
No resources found in hello namespace.  ← hello-app did NOT land
```

## Plain-English report

- **hello-ns**: ConfigHub shows Live=3=Applied=Head and `kubectl get ns hello` returns Active. Chain is whole; the namespace is deployed.
- **hello-app**: ConfigHub's worker recorded `LastAppliedRevisionNum=6` but `LiveRevisionNum=0`, and the bridge-state entry for the Unit is not present / apply failed. The cluster has no resources in namespace `hello`. **The chain broke at the worker's apply step before the cluster was mutated.** Next step is to read `cub worker logs eval-worker --space skill-examples` and the Unit's `bridgestate` / `LastActionError` for the specific error — likely admission rejection (the security defaults + probe defaults may not match a valid image), not a cluster connectivity issue.

## Tool boundary respected

All read-only. Did not call `cub unit refresh` (mutation), `kubectl apply` (mutation), `argocd app sync` (mutation), or `cub-apply` from here. Handed back.

## Evidence

```
cub unit get hello-app --space skill-examples --web
cub unit bridgestate hello-app --space skill-examples
```

## Hand-off

Broken link is "cub → worker → cluster" for hello-app. Route the user back to `cub-apply` (after they fix the underlying data — likely via `cub-mutate`) or to the `triggers-and-applygates` skill if a gate is causing refusal. Do not re-apply from here.
