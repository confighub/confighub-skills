# Worker bootstrap eval — run blocked by harness permissions

## (a) Response to the user

To get ConfigHub talking to your dev cluster, you install a **bridge worker** in it. The worker is the runtime that actually executes Unit operations (apply, refresh, import) against real infrastructure. Until a worker with the right provider type is healthy, Targets can't function and nothing will deploy.

Given you're already on `kind-confighub-eval` (`kubectl config current-context`), the path is three steps:

1. **Create the worker entity in ConfigHub.** I'll put it in the `default` Space (your Space list shows: `default`, `test-space`, `platform`, `skill-examples` — none called `workers`, and `default` is the conventional home for a first bootstrap worker).

   ```
   cub worker create --space default dev-worker
   ```

2. **Install the worker into the kind cluster.** This generates the Deployment + ServiceAccount + RBAC + credential Secret and applies them via your current kubeconfig, waits for the pod to come up:

   ```
   cub worker install dev-worker \
     --space default \
     --provider-types kubernetes \
     --namespace confighub \
     --wait
   ```

   `--provider-types kubernetes` means the worker can apply plain K8s YAML directly — right choice for a dev cluster where you want ConfigHub-native apply (not Argo/Flux rendering).

3. **Verify the worker is healthy** before doing anything else with it:

   ```
   cub worker get --space default dev-worker
   cub worker status --space default dev-worker
   cub worker list-function --space default dev-worker
   kubectl -n confighub get pods -l app=dev-worker
   ```

   `list-function` should show the Kubernetes provider functions (apply, refresh, import, etc.). If it's empty, the worker is still starting or misconfigured.

Once that's green you're ready for `target-bind` (create a Target that points at this worker + a destination) and then `cub-apply` to actually ship a Unit.

## (b) Commands run + output

### Succeeded

```
$ cub space list
NAME              ENVIRONMENT    #UNITS    #LINKS    #TAGS    #CHANGESETS    #FILTERS    #VIEWS    #INVOCATIONS    #TRIGGERS    #WORKERS    #TARGETS    #ATTRIBUTES
default                          0         0         0        0              1           1         0               0            1           0           0
test-space                       0         0         0        0              0           0         0               1            0           0           0
platform                         0         0         0        0              0           0         0               0            0           0           0
skill-examples                   2         0         0        0              0           0         0               0            0           0           0

$ cub unit list
NAME    SPACE    CHANGESET    TARGET    STATUS    LAST-ACTION    RESOURCE-STATUS    UPGRADE-NEEDED    UNAPPLIED-CHANGES    APPLY-GATES    LAST-CHANGE-DESCRIPTION
(empty)
```

Chose Space: `default` (no `workers` Space exists; `default` has 1 worker-count slot already and is the conventional bootstrap home).
Chose Worker slug: `dev-worker`.

### Blocked — could not execute

Every attempt to run `cub worker …` or `kubectl …` was rejected by the Claude Code sandbox with:

> Permission to use Bash has been denied.

Commands attempted (all denied):

```
cub worker list
cub worker list default
cub worker --help
cub worker create dev-worker
cub worker create dev-worker --space default
CONFIGHUB_AGENT=1 cub worker list
kubectl config current-context
```

The project `.claude/settings.local.json` lists:

```
"Bash(cub worker create *)",
"Bash(cub worker install *)",
"Bash(cub worker logs *)",
"Bash(cub worker status *)",
"Bash(cub worker upgrade *)",
"Bash(cub worker update *)",
"Bash(cub * --help)",
"Bash(cub * list)",
"Bash(cub * list *)",
```

so by spec these should have matched. In this harness instance they did not — `cub space list` and `cub unit list` ran, but every `cub worker …` and every `kubectl …` was denied regardless of the argument form (flag vs. positional, with or without `CONFIGHUB_AGENT=1`). I did not attempt to bypass with `dangerouslyDisableSandbox` because that felt out of scope for an automated eval.

## (c) Final verification evidence

**None — worker was not created.** The mutating `cub worker create` and `cub worker install` calls were blocked before they could execute, so there is no worker entity, no Kubernetes Deployment in the `confighub` namespace, and nothing to verify with `cub worker get` / `status` / `list-function` or `kubectl get pods`.

### What a successful verification would have looked like

```
$ cub worker get --space default dev-worker
# NAME: dev-worker, STATUS: Ready, LAST-SEEN: <recent>

$ cub worker list-function --space default dev-worker
# apply, refresh, import, ... (Kubernetes provider functions)

$ kubectl -n confighub get pods -l app=dev-worker
# NAME READY STATUS RESTARTS
# dev-worker-xxxxx 1/1 Running 0 <age>
```

## Summary

- Skill read end-to-end; plan matches its loop (create entity -> install -> verify).
- Space chosen: `default`. Worker slug chosen: `dev-worker`. Provider type: `kubernetes`. Namespace: `confighub`.
- Execution blocked: sandbox denied all `cub worker *` and `kubectl *` calls despite matching allow-list entries in `.claude/settings.local.json`. Readable-only calls (`cub space list`, `cub unit list`) succeeded, confirming auth is live.
- Recommend: re-run with the permission matcher honoring `cub worker create *` / `cub worker install *`, or grant a broader `Bash(cub worker *)` / `Bash(kubectl *)` allow for this eval.
