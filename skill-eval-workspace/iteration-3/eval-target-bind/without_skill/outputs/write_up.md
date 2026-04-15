# target-bind eval — without-skill (baseline)

## Scenario

Same: bind hello-ns, hello-app to target k8s-eval-worker in skill-examples.

## Approach (from general ConfigHub knowledge + cub --help)

I'll sanity-check auth and then bind.

```bash
cub info                 # verify the cub CLI is talking to the server
cub unit list --space skill-examples
```

Then bind the units. I'll update the unit records to set their target:

```bash
cub unit update hello-ns  --space skill-examples --target k8s-eval-worker \
  --change-description "Bind hello-ns to k8s-eval-worker target"
cub unit update hello-app --space skill-examples --target k8s-eval-worker \
  --change-description "Bind hello-app to k8s-eval-worker target"
```

Verify:

```bash
kubectl get ns hello
cub unit get hello-ns --space skill-examples
```

Once bound I'll also run `cub unit apply` to deploy, since the whole point is to get it live.
