# target-bind eval — with-skill

## Scenario

> I have Worker `eval-worker` (Ready) in Space `skill-examples`, an existing Target `k8s-eval-worker` in that Space, and two seeded Units `hello-ns` + `hello-app` which are NotLive and un(re)bound. Attach both Units to `k8s-eval-worker` and verify. Don't apply — that's a later step.

## Preflight

Auth — use `cub context get`, NOT `cub info` (which does not require authentication and is not a valid auth check):

```
$ cub context get
User: brian@confighub.com
```

Worker:

```
$ cub worker get eval-worker --space skill-examples
Condition: Ready
ConfigType[0]: Kubernetes / Kubernetes/YAML / Kubernetes/YAML
```

Target:

```
$ cub target get k8s-eval-worker --space skill-examples
Provider Type: Kubernetes
Toolchain Type: Kubernetes/YAML
Bridge Worker: eval-worker
```

All gates green.

## Plan

1. Attach `hello-ns` and `hello-app` to `k8s-eval-worker` via `cub unit set-target`.
2. Verify with `cub unit get` and `cub unit list --where "TargetID IS NOT NULL"`.
3. Hand off to `cub-apply`.

No `--change-desc` — per the skill, neither `cub target create/update` nor `cub unit set-target` are configuration-data mutations, so `--change-desc` must NOT be passed.

## Commands executed

```bash
cub unit set-target hello-ns  k8s-eval-worker --space skill-examples
cub unit set-target hello-app k8s-eval-worker --space skill-examples
```

Both returned `Successfully updated Unit …`.

## Verification

```bash
cub unit get hello-ns --space skill-examples
# Target: k8s-eval-worker; Bridge Worker: eval-worker.

cub unit list --space skill-examples --where "TargetID IS NOT NULL"
# hello-ns  k8s-eval-worker  NotLive
# hello-app k8s-eval-worker  NotLive
```

Both Units now have the Target attached; they're NotLive because apply hasn't run yet (correct — target-bind stops short of apply).

## Hand-off

Route to `cub-apply` for the actual deployment. Do not apply from here.

## Evidence

```
cub target get k8s-eval-worker --space skill-examples --web
cub unit get hello-app --space skill-examples --web
```
