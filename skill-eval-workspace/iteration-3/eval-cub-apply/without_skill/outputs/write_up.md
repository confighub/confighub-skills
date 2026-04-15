# cub-apply eval — without-skill (baseline)

## Scenario

Same: apply hello-ns and hello-app (both bound to k8s-eval-worker) to kind.

## Approach

I'll make sure auth is live and then apply both.

```bash
cub info
cub unit list --space skill-examples
```

Apply:

```bash
cub unit apply hello-ns --space skill-examples \
  --change-desc "Deploy hello-ns namespace to kind-confighub-eval"
cub unit apply hello-app --space skill-examples \
  --change-desc "Deploy hello-app to kind-confighub-eval"
```

If the apply fails, I'll retry once and then look at pod logs with `kubectl get pods -n hello`.

Verify:

```bash
kubectl get ns hello
kubectl get deploy -n hello
```
