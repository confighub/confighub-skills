---
name: verify-delivery
description: Use right after cub-apply returns, or when the user asks "did it actually deploy?", "is the change live?", "is argo synced?", "did the pod pick up the new image?", or "something says it applied but I'm not sure". Anchors on ConfigHub's own bridge/live state first (the authoritative owner), then cross-checks the controller (Argo / Flux) and the cluster (kubectl) in that order, naming the specific step that failed in plain English if anything breaks. Uses the apply-not-completed filter recipe when triaging many units. Do not load for pure ConfigHub-internal query (use cub-query), for ConfigHub ↔ controller ↔ cluster three-way agreement (use reconciliation-check), or for the final read-only completion step surfacing Revision history (use release-verify).
phase: verify
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit refresh *) Bash(cub worker logs *) Bash(cub worker status *) Bash(kubectl get *) Bash(kubectl describe *) Bash(kubectl logs *) Bash(argocd app get *) Bash(argocd app diff *) Bash(argocd app history *) Bash(flux get *) Bash(flux stats *) Bash(flux logs *)
---

# verify-delivery

Apply returning success is not the same as the change landing. This skill verifies the chain end to end.

## When to use

- Immediately after `cub-apply`.
- User asks "did it deploy?" / "is it live?" / "did argo pick it up?" / "is the pod new?"
- User saw a successful apply but suspects the runtime disagrees.

## Do not load for

- Plain ConfigHub queries (use `cub-query`).
- Three-way agreement across ConfigHub + controller + cluster for a single authoritative picture (use `reconciliation-check`).
- The final read-only completion step surfacing Revision history (use `release-verify`).

## Preflight gates

1. The apply actually happened — there's a `LastActionAt` on the Unit that matches the event the user is asking about. If not, the question is "did the apply run?", not "did delivery succeed?"; route back to `cub-apply` for the actual apply.
2. `cub context get` returns a user.
3. For cluster-level checks: the user's current `kubectl` context matches the cluster the Unit targets. If not, read-only commands still work but the answer may be misleading; flag the mismatch.

## The chain — check in this order

ConfigHub is the authoritative owner. Start there; don't lead with `kubectl get`.

### 1. ConfigHub-side: bridge state and revision numbers

```bash
cub unit get <slug> --space <s>
```

Check:

- `LiveRevisionNum` equals the revision the user intended to apply.
- `LastAppliedRevisionNum` matches.
- `LastActionError` is empty.
- `ApplyGates` is empty (length 0).

```bash
cub unit bridgestate <slug> --space <s>
```

Bridge state shows the worker's most recent reconciliation attempt for this Unit. Success here means the worker finished; failure here is the fast-path for "something broke on the way out of ConfigHub".

### 2. Controller-side (if the Target is Argo or Flux)

For Argo-backed Targets:

```bash
argocd app get <app-name>
argocd app history <app-name>
argocd app diff <app-name>  # should be empty
```

Look for: `Sync Status: Synced`, `Health: Healthy`, no diff. If out of sync, that's where the chain broke.

For Flux-backed Targets:

```bash
flux get kustomizations
flux get helmreleases
flux logs --kind=Kustomization --name=<name>
```

Look for: `Ready: True`, `Status: ...revision matches`, recent reconciliation timestamp.

### 3. Cluster-side (for any K8s-provider Target)

```bash
kubectl get <kind> <name> -n <namespace> -o wide
kubectl describe <kind> <name> -n <namespace>
```

Check:

- Resource exists.
- `status.observedGeneration` matches `metadata.generation` (controller caught up).
- For workloads: `Ready` / `Available` replicas match desired.
- For Pods: no `CrashLoopBackOff`, `ImagePullBackOff`, or pending states.
- For Services/Ingresses: endpoints populated.

Fast path for workload health:

```bash
kubectl get deploy <name> -n <ns> -o jsonpath='{.status.conditions[?(@.type=="Available")]}'
```

### 4. Triage many Units at once

When verifying a bulk apply, the `apply-not-completed` filter surfaces anything that didn't converge:

```bash
cub unit list --space <s> --filter platform/apply-not-completed
```

A Unit showing up here means `LastAppliedRevisionNum != LiveRevisionNum` — i.e., apply was attempted but the live state didn't catch up. That's where to dig.

## Plain-English reporting

Name what you checked and which link broke, in that order. Good:

> ConfigHub's LiveRevisionNum on `checkout` advanced to 12 and bridge state reports success. ArgoCD's `checkout-prod` Application is Synced but Health is Degraded. At the cluster, the new `checkout` pod is in `CrashLoopBackOff`; kubectl logs show an unset env var. Chain broke at the cluster — ConfigHub and Argo agree on what should be there, but the workload can't start.

Bad: "It's applied." / "Apply succeeded." — those don't distinguish the links.

## Tool boundary

Read-only across the board. No mutations in a verify skill, ever — including `kubectl rollout restart`, `argocd app sync --force`, `flux reconcile`, `cub unit refresh` (refresh is a mutation that rewrites Unit state from live).

Exception: if the user's actual intent is "I want to sync again" or "I need to re-apply", hand back and route to `cub-apply`. Don't take the action from here.

## Stop conditions

- Any link in the chain fails. Stop, report where it broke with evidence, and hand back to the user (or route to `cub-apply` / `triggers-and-applygates` / `worker-bootstrap` depending on which link failed).
- The user's intent pivots from verify to fix. Hand off; don't fix from here.

## Verify chain (the skill's own verification)

Not applicable — this skill *is* the verify chain.

## Evidence

- `cub unit get <slug> --space <s> --web` — Unit live state + revision history.
- `cub unit bridgestate <slug> --space <s>` output — the authoritative apply status.
- Argo / Flux UIs — controller-side evidence the user can click on.

## References

- `references/filters-and-queries.md` — `apply-not-completed` and related operational filter recipes.
- `references/cub-cli.md` — read-only diagnosis tool boundary.
- Companion skills: `cub-apply` (the preceding act), `reconciliation-check` (fuller three-way cross-check), `release-verify` (the completion step).
