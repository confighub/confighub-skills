# cub-apply eval — with-skill

## Scenario

> target-bind just ran: hello-ns and hello-app in Space `skill-examples` are both bound to Target `k8s-eval-worker` (Worker `eval-worker`, Ready). Apply both to the kind cluster. Start with a dry-run for hello-app because it has 2 resources, wait on apply, and verify.

## Preflight

Auth check — `cub context get`, NOT `cub info`:

```
$ cub context get        # user=brian@confighub.com — valid
```

Target-bound check:

```
$ cub unit list --space skill-examples --where "TargetID IS NOT NULL"
hello-ns   k8s-eval-worker  NotLive
hello-app  k8s-eval-worker  NotLive
```

Worker healthy:

```
$ cub worker status eval-worker --space skill-examples    # Ready
```

ApplyGates empty:

```
$ cub unit list --space skill-examples --where "Slug IN ('hello-ns','hello-app') AND LEN(ApplyGates) > 0"
(none)
```

Gates clear.

## Plan

1. Dry-run hello-app.
2. Apply hello-ns, then hello-app, both `--wait --timeout 2m0s`.
3. Verify `LiveRevisionNum == LastAppliedRevisionNum == HeadRevisionNum` and no `LastActionError`.
4. Hand off to `verify-delivery`.

No `--change-desc` — `cub unit apply` is a runtime operation, not a config-data mutation.

## Commands

```bash
cub unit apply hello-app --space skill-examples --dry-run

cub unit apply hello-ns  --space skill-examples --wait --timeout 2m0s
# -> Successfully completed Apply on unit hello-ns

cub unit apply hello-app --space skill-examples --wait --timeout 2m0s
# -> Action Apply on unit hello-app (…) Failed: apply failed on unit hello-app
```

## Verification

```bash
$ cub unit list --space skill-examples
hello-ns   Ready    1/1 Ready
hello-app  Degraded — UNAPPLIED-CHANGES: Yes
```

`hello-ns` converged (Live 3, Applied 3, Head 3). `hello-app` failed — the worker reported an apply failure; `LiveRevisionNum` is 0, `LastAppliedRevisionNum` is 6 (apply attempt recorded, did not land live). This is the stop condition: "Apply times out or fails — don't retry blindly."

## Stop-here analysis for hello-app

Skill says: on apply failure, collect `cub unit bridgestate`, `cub worker logs`, surface the actual error. Route to `verify-delivery` for the diagnosis chain, not retry.

```bash
cub unit bridgestate hello-app --space skill-examples
cub worker logs eval-worker --space skill-examples --tail 100
```

## Hand-off

- hello-ns: route to `verify-delivery` (sanity cluster-side cross-check).
- hello-app: route to `verify-delivery` to name which link in the chain failed.

No `cub unit cancel` needed (apply already terminated, not in-flight).

## Evidence

```
cub unit get hello-ns  --space skill-examples --web
cub unit get hello-app --space skill-examples --web
cub revision list hello-app --space skill-examples --web
```
