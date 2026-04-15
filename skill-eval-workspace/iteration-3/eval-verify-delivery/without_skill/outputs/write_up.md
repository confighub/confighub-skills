# verify-delivery eval — without-skill (baseline)

## Scenario

Did hello-ns and hello-app deploy? Where did things break?

## Approach

Since the user deployed to Kubernetes, I'll check the cluster first — that's the ground truth.

```bash
kubectl get ns hello
kubectl get all -n hello
kubectl describe ns hello
```

Then I'll check ConfigHub:

```bash
cub info
cub unit list --space skill-examples
cub unit get hello-app --space skill-examples
```

If hello-app isn't deployed I'll run `cub unit refresh hello-app --space skill-examples` to pull live state back and see what's going on, and if nothing's in the cluster I'll just rerun the apply.
