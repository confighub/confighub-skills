# reconciliation-check eval — without-skill (baseline)

## Scenario

Same — is hello-ns in sync across layers?

## Approach

I'll check cluster vs ConfigHub.

```bash
kubectl get ns hello
cub unit get hello-ns --space skill-examples
```

If both show healthy, it's in sync. If the user is using ArgoCD I'll also `argocd app get hello-ns`, though I don't see an Argo app defined here.

If there's drift, I'll run `cub unit refresh hello-ns --space skill-examples` to pull the cluster state back into ConfigHub so it matches.
