# New-user ConfigHub tour

## (a) Response to the user

Welcome. Here is the quick tour, grounded in what is actually on your local instance.

### The one-minute mental model

ConfigHub treats configuration as **data**, not templates. Fully materialized YAML lives in a versioned database; you mutate it through server-side **functions**; every change is a new **Revision** with a description attached. Delivery, policy, and audit hang off that model.

### The vocabulary you need on day one

- **Space** — an organizational container. Best practice: one Space per application x environment/region. You already have four: `default`, `test-space`, `platform`, and `skill-examples`.
- **Unit** — a versioned chunk of config. For Kubernetes that means one or more fully rendered K8s resources as YAML, applied as a single atomic operation. Your `skill-examples` Space has two: `hello-ns` (a Namespace with pod-security labels) and `hello-app` (the workload).
- **Revision** — every mutation produces a new Revision, stamped with a `--change-desc` (what the user asked for + any clarifications) and the data diff. Look at the `LAST-CHANGE-DESCRIPTION` column from `cub unit list` — that is a Revision's change-desc showing through.
- **Function** — the server-side operation that mutates data. Getters (`get-container-image`), setters (`set-container-image`, `set-replicas`), defaults, and validators (`vet-schemas`, `vet-cel`). You don't hand-edit YAML; you call a function on a Unit.
- **Target** — a binding that says "this Unit lands here" (a K8s cluster+namespace, an Argo Application, a Flux Kustomization, an OCI registry...).
- **Worker** — the in-cluster process that actually executes apply/refresh/import against the real world. Your instance has no Workers or Targets yet, which is why your Units show `NotLive`.
- **Trigger** + **ApplyGate** — a Trigger fires a validator function on mutations; if it fails, it attaches an ApplyGate that blocks apply until you fix the data or the rule. Never bypass the gate — fix the cause.
- **Filter** — a saved query; powers bulk ops (`cub unit apply --filter ...`) and is how Triggers attach to Spaces via `TriggerFilterID`.
- **Link** — a typed relationship between Units whose resources reference each other (e.g. a Deployment's `serviceAccountName` -> a ServiceAccount Unit), enabling cross-Unit integrity checks.

### Two invariants to internalize

1. **Data is authoritative.** Edits are to the data in ConfigHub, not to upstream templates. Re-rendering from Helm/Kustomize is an *import-time* convenience, not an ongoing workflow.
2. **Mutations go through `cub`.** `kubectl` / `argocd` / `flux` are read-only for diagnosis. Every mutating `cub` command takes `--change-desc "..."` (summary + verbatim prompt + clarifications) and should pass `--display-mutation` to show the diff inline.

### The Space topology pattern

- One Space per application x environment/region, labeled for bulk ops.
- A shared `platform` Space (you have one already, empty) holds Triggers + Filters that application Spaces inherit via `TriggerFilterID`. That is how policy scales without per-app duplication.

### A concrete path to get started on Kubernetes

You already have `skill-examples` with two Units — good playground. From here, typical next moves:

1. **Install a Worker** into a cluster so Units can actually go live (currently all `NotLive`).
2. **Create a Target** pointing at a cluster+namespace and bind the Units to it.
3. **Apply** a Unit and verify delivery (controller status -> workload health -> governed state).
4. **Add a Trigger** in `platform` (e.g. block `:latest` images) and watch it gate a bad mutation.
5. **Mutate** via a setter function with `--change-desc` + `--display-mutation`, then inspect the new Revision.

Tell me which of those you want to do next and I'll route you to the right skill. Rough map:

- bootstrap a playground Space -> `skill-examples-bootstrap` (you've already got one)
- install a worker -> `worker-bootstrap`
- create/bind a Target -> `target-bind`
- apply a Unit -> `cub-apply`
- change data in a Unit -> `cub-mutate`
- find/audit across Units -> `cub-query`
- policy + apply gates -> `triggers-and-applygates`
- verify a change landed -> `verify-delivery` / `reconciliation-check`
- read-only release close -> `release-verify`

If you want to see a Unit in the GUI, `cub unit get hello-app --space skill-examples --web` will open it; `cub revision list --web` does the same for history.

---

## (b) Commands run

```
$ cub space list
NAME              #UNITS  #TRIGGERS  #WORKERS  #TARGETS ...
default           0       1          0         0
test-space        0       0          0         0
platform          0       0          0         0
skill-examples    2       0          0         0
```

```
$ cub unit list --space skill-examples
hello-app    skill-examples   NotLive   (change-desc: ensure-namespaces function run)
hello-ns     skill-examples   NotLive   (change-desc: set-pod-security-defaults function run)
```

(A `cub --help` run was blocked by the sandbox, but the `cub space list` + `cub unit list` output was enough to ground the tour in real state.)

## (c) Reasoning notes

- Read `skills/confighub-core/SKILL.md` in full. It is an orientation skill: explain-and-route, read-only, don't try to do the task here.
- Followed the skill's "loop" for orientation: explained the model in plain terms, covered the primary entities (Space/Unit/Revision/Function/Target/Worker/Trigger/Filter/Link/ApplyGate), hit the two operational invariants (data is authoritative; mutations through `cub` with `--change-desc` + `--display-mutation`), and routed to dedicated skills rather than attempting any task.
- Grounded the tour in live state: four Spaces (including a populated `skill-examples`), and two `NotLive` Units — which gave a natural hook to explain Targets/Workers as the missing piece for going live.
- Kept it Kubernetes-framed per the user's ask; surfaced the shared-`platform`-Space pattern early since it's the thing most new users miss.
- Did not mutate. Offered `--web` as the trust-surface move per the skill's Evidence section.
