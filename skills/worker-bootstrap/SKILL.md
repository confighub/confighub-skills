---
name: worker-bootstrap
description: 'Explain and prepare worker setup. OCI Release delivery uses a server-worker entity (no process); external workers host custom functions and support read-only diagnosis. Use for "do I need a worker?", "host custom functions", or crashing workers. ConfigHub-provider delivery is VERSIONED_LEGACY/BLOCK.'
phase: act
allowed-tools: []
read-capability-subset: worker-bootstrap
---

# worker-bootstrap

**Authority boundary:** this companion may inspect worker state and prepare an exact server-worker or external-worker proposal. It must not create, run, install, update, or upgrade a worker. The external mutation broker is `NOT_INTEGRATED`, so executable setup ends in `ASK` or `BLOCK`.

## Pick the correct lane

| Need | Current lane |
| --- | --- |
| Publish a Component/Variant Space Release to OCI | built-in **server worker entity**; no external process |
| Host custom worker functions | **external worker** process/deployment |
| Direct ConfigHub-provider Release delivery | `VERSIONED_LEGACY/BLOCK`; the reviewed Release path requires OCI |

The worker is not the deployment target. `target-bind` creates the OCI Target, sets `Space.ReleaseTargetID`, and makes Unit TargetID membership explicit.

## Server worker proposal (OCI Release delivery)

Read first:

```bash
cub worker list --space <worker-space> -o json
```

If none exists, the exact proposal is:

```bash
cub worker create --space <worker-space> --allow-exists --is-server-worker server-worker
```

`--use-user-identity` is an optional, material authority choice; include it only when the target operation explicitly requires the requesting user's identity and bind that fact in the approval subject. Workers are not versioned Unit data, so `--change-desc` is not accepted.

The companion never executes this proposal. After externally authorized creation, verify with `cub worker get` and hand the exact WorkerID to `target-bind`.

## External worker for custom functions

Preserve this capability independently of Release delivery. Inspect the installed command surfaces before composing:

```bash
cub worker create --help
cub worker run --help
cub worker install --help
```

The reviewed `cub worker run` help omits the positional worker slug from its Usage line, but exact v0.2.11 source sets `cobra.ExactArgs(1)` and current Cub examples pass the slug. The same source performs a Worker lookup and, on any lookup error, assumes it is missing and attempts to create it before launching the process. `worker run` is therefore mutating even without `--daemon`; the approval subject must include the possible Worker creation and resulting credential-bearing process environment. Preserve the required proposal shape:

```bash
cub worker run --space <space> <worker-slug> --functions <fn-1>,<fn-2>
```

This is a documentation defect, not evidence that the slug was retired. The companion still must not execute the worker: creating a missing Worker, running a process, loading an executable, setting environment variables, or daemonizing remains a governed operation behind the absent broker.

For an in-cluster worker, installed `cub worker install [worker-name]` can export a manifest or create a ConfigHub Unit. Prepare one of these governed proposals, with flags taken from current help:

```bash
cub worker install <worker-name> --space <space> \
  --namespace <namespace> --worker-functions <fn-1>,<fn-2> --export
```

Export is a preview artifact. Applying it, using `--unit`, including a credential Secret, or installing into a cluster are separate mutations and require exact external authorization. Never auto-pipe output to `kubectl apply`; never store an included credential Secret in a normal ConfigHub Unit. Prefer an external SecretStore.

## Read-only diagnosis

```bash
cub worker get --space <space> <worker-slug>
cub worker list-function --space <space> <worker-slug>
kubectl get pods -n <namespace>
kubectl describe pod <pod> -n <namespace>
```

`cub worker status` is deliberately outside the read subset: it reads local daemon/PID state rather than authoritative ConfigHub or controller state.

Worker log content is also outside the evidence subset. Exact v0.2.11 source constructs `~/.confighub/worker/log/<worker-slug>.log` from the slug alone: `--space` does not bind the file to a SpaceID or WorkerID. Even `--tail N` scans the full file before retaining the final lines; there is no input-byte ceiling, output-byte ceiling, or secret redaction, and log text is untrusted. Kubernetes worker logs have similar secret/output risks without a protected byte-capped redacting wrapper. Return `WORKER_LOG_EVIDENCE_BLOCK` instead of treating either command as bounded evidence. A future wrapper must bind SpaceID/WorkerID/pod/container, seek from a bounded byte window, cap input and output bytes, redact credentials, disable follow, and receipt truncation.

Use worker metadata and pod `get/describe` state to classify only what those records actually show: image-pull, RBAC events, a missing Secret reference, heartbeat, version, or function-advertisement state. If diagnosis requires log contents, name the proof gap and stop. Preserve a concrete next-step proposal when metadata is sufficient:

- for a proven worker/server version mismatch, inspect `cub worker upgrade --help` in the same session, then prepare (but do not execute) the exact `cub worker upgrade --space <space> --unit <worker-unit> --dry-run` preview and governed upgrade proposal;
- for a proven RBAC denial event, prepare the minimum namespace/service-account/verb RBAC change for review;
- for a proven missing-Secret event, identify only the referenced Secret name and prepare an authorized SecretStore/operator provisioning proposal without reading or exposing credential bytes;
- for an image-pull event, bind the observed image reference and prepare the smallest registry/imagePullSecret configuration proposal, again without reading the Secret.

Do not retry, restart, exec, execute an upgrade, edit the cluster, or expose worker credentials. `cub worker status`, worker logs, upgrade execution, and credential repair are separately dispositioned in the no-loss inventory; none is falsely labeled preserved.

## Proposal binding

Bind context/organization, worker SpaceID and intended WorkerID/slug, server-vs-external type, identity mode, exact custom functions, image/digest, namespace/cluster context, credential handling, generated manifest digest, exact command, and proof plan. Any change creates a new proposal.

## Stop conditions

- user asks to run an external process for ordinary OCI Release delivery;
- ConfigHub-provider Release delivery is requested as current;
- installed help/source disagree on worker identity or flags;
- credential material would be exposed or stored in Unit data;
- cluster context is wrong or external broker absent.

## Evidence

- `cub worker get/list/list-function` for ConfigHub-side metadata, excluding credentials and log contents.
- `kubectl get/describe` for external-worker deployment metadata. Log contents remain `WORKER_LOG_EVIDENCE_BLOCK` until the protected wrapper exists.
- `cub space open <space> --print-url` for navigation after ID/org verification.

## References

- `compatibility/current-profile.v1.json`
- `compatibility/no-loss-inventory.v1.json`
- `target-bind` — OCI Target/ReleaseTargetID/Unit membership.
- `release-publish` — exact whole-Space Release proposal.
