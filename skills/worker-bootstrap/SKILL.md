---
name: worker-bootstrap
description: 'Explain and prepare worker setup. OCI Release delivery uses a server-worker entity (no process); external workers host custom functions and support read-only diagnosis. Use for "do I need a worker?", "host custom functions", or crashing workers. Direct ConfigHub-provider delivery is historical and unsupported in the reviewed current profile.'
phase: act
allowed-tools: []
read-capability-subset: worker-bootstrap
---

# worker-bootstrap

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. A requested server-worker entity create can use one host-permission call after exact scoping. Local process launch, install/export, and upgrade flows are explicitly coached because they are long-running, executable-loading, file-producing, or credential-bearing; the user runs each such command in their terminal. An external overlay may impose a stricter stop.

## Pick the correct lane

| Need | Current lane |
| --- | --- |
| Publish a Component/Variant Space Release to OCI | built-in **server worker entity**; no external process |
| Host custom worker functions | **external worker** process/deployment |
| Direct ConfigHub-provider Release delivery | historical and unsupported; the reviewed Release path requires OCI |

The worker is not the deployment target. `target-bind` creates the OCI Target, sets `Space.ReleaseTargetID`, and makes Unit TargetID membership explicit.

## Server worker setup (OCI Release delivery)

Read first:

```bash
cub worker list --space <worker-space> -o json
```

If none exists, the exact create is:

```bash
cub worker create --space <worker-space> --allow-exists --is-server-worker server-worker
```

`--use-user-identity` is an optional, material authority choice; include it only when the target operation explicitly requires the requesting user's identity and bind that fact in the approval subject. Workers are not versioned Unit data, so `--change-desc` is not accepted.

In standalone mode, submit this exact create once to the host permission system. After success, verify with `cub worker get` and hand the exact WorkerID to `target-bind`.

## External worker for custom functions

Preserve this capability independently of Release delivery. Inspect the installed command surfaces before composing:

```text
cub worker create --help
cub worker run --help
cub worker install --help
```

Installed v0.2.15 `cub worker run --help` omits the positional worker slug from
its Usage line, but the exact installed client source commit
`3e0cad345fbcc60d4761d928f02fccb8dc5def4f` sets
`cobra.ExactArgs(1)` and reads `args[0]`. The same source looks up that Worker
and attempts to create it on lookup error before launching the process.
`worker run` is therefore mutating even without `--daemon`; the coached scope
must include possible Worker creation and the credential-bearing process
environment. Preserve the required command shape:

```bash
cub worker run --space <space> <worker-slug> --functions <fn-1>,<fn-2>
```

This is a help/source documentation mismatch, not evidence that the slug was
retired. Creating a missing Worker, running a process, loading an executable,
setting environment variables, or daemonizing are material effects. Resolve
and disclose them, then use explicit coached mode; never hide an implicit
create inside a “run” description.

For an in-cluster worker, installed `cub worker install [worker-name]` can
export a manifest or create a ConfigHub Unit. In coached mode, use one exact
command with flags taken from current help:

```bash
cub worker install <worker-name> --space <space> \
  --namespace <namespace> --worker-functions <fn-1>,<fn-2> --export
```

Export is a preview artifact. Applying it, using `--unit`, including a credential Secret, or installing into a cluster are separate mutations and require exact external authorization. Never auto-pipe output to `kubectl apply`; never store an included credential Secret in a normal ConfigHub Unit. Prefer an external SecretStore.

## Read-only diagnosis

```text
cub worker get --space <space> <worker-slug>
cub worker list-function --space <space> <worker-slug>
kubectl get pods -n <namespace>
kubectl describe pod <pod> -n <namespace>
```

`cub worker status` is deliberately outside the read subset: it reads local daemon/PID state rather than authoritative ConfigHub or controller state.

Worker log content is also outside the evidence subset. Exact v0.2.15 client
source at the commit above constructs a slug-named local log file: `--space`
does not bind the file to a SpaceID or WorkerID. Even `--tail N` scans the full
file before retaining the final lines; there is no byte ceiling or secret
redaction, and log text is untrusted. Kubernetes worker logs have similar
risks. Ask for a bounded redacted excerpt or use a reviewed identity-bound
reader when one exists.

Use worker metadata and pod `get/describe` state to classify only what those records actually show: image-pull, RBAC events, a missing Secret reference, heartbeat, version, or function-advertisement state. If diagnosis requires log contents, name the proof gap and stop. Preserve a concrete coached next step when metadata is sufficient:

- for a proven worker/server version mismatch, inspect `cub worker upgrade --help` in the same session, show the exact dry-run, then coach the separately requested upgrade in the user's terminal;
- for a proven RBAC denial event, identify the minimum namespace/service-account/verb RBAC change;
- for a proven missing-Secret event, identify only the referenced Secret name and coach SecretStore/operator provisioning without reading or exposing credential bytes;
- for an image-pull event, bind the observed image reference and identify the smallest registry/imagePullSecret configuration change, again without reading the Secret.

Do not retry, restart, exec, edit the cluster, or expose worker credentials from
this assistant session. Long-running worker execution, upgrade, and credential
repair stay coached in the user's terminal.

## Scope binding

Bind context/organization, worker SpaceID and intended WorkerID/slug,
server-vs-external type, identity mode, exact custom functions, image/digest,
namespace/cluster context, credential handling, generated manifest digest,
exact command, and proof plan. A material change requires a focused new user
decision.

## Stop conditions

- user asks to run an external process for ordinary OCI Release delivery;
- ConfigHub-provider Release delivery is requested as current;
- installed help/source disagree on worker identity or flags;
- credential material would be exposed or stored in Unit data;
- cluster context is wrong, the host denies the command, or an external governance overlay blocks it.

## Evidence

- `cub worker get/list/list-function` for ConfigHub-side metadata, excluding credentials and log contents.
- `kubectl get/describe` for external-worker deployment metadata. Log contents remain untrusted and unbounded until the protected wrapper exists.
- `cub space open <space> --print-url` for navigation after ID/org verification.

## References

- `compatibility/current-profile.v1.json`
- `compatibility/no-loss-inventory.v1.json`
- `target-bind` — OCI Target/ReleaseTargetID/Unit membership.
- `release-publish` — exact whole-Space publication preview and command.
