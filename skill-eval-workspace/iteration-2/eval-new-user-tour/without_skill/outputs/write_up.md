# New-user tour of ConfigHub for Kubernetes

## (a) Response to the user

Welcome. Here's the shortest useful tour of ConfigHub for someone coming from
Kubernetes + kubectl + (maybe) Helm/Argo.

### The one-sentence version

ConfigHub is a **config-as-data control plane**: your Kubernetes manifests (and
other config) live as versioned, typed **units** inside ConfigHub, organized
into **spaces**, composed with **links**, promoted along **targets**, and
applied to clusters. You interact with it through the `cub` CLI, the web UI,
and (increasingly) AI agents.

Think of it as: Git gives you *files with history*; ConfigHub gives you
*configuration with structure, relationships, policy, and receipts*.

### The core vocabulary (just enough to be dangerous)

- **Unit** — one logical piece of config (a Deployment, a ConfigMap, a Helm
  values block, a Terraform module, etc.). Units are typed and versioned.
  Every change produces a **revision**.
- **Space** — a namespace-like container for units. You typically have spaces
  per environment or per tenant (e.g. `dev`, `staging`, `prod`, or per team).
- **Link** — a typed relationship between units (e.g. "this Deployment uses
  that ConfigMap", "this app targets that cluster"). Links are how ConfigHub
  knows what to promote together and what depends on what.
- **Target** — where a unit gets applied (a cluster/namespace, a cloud
  account, etc.). Applying a unit to a target is the moment config becomes
  live infrastructure.
- **Revision** — an immutable snapshot of a unit. You can diff, promote, and
  roll back revisions. This is the "receipt" layer.
- **Trigger / Worker** — the runtime that actually applies units to targets
  (for Kubernetes, it talks to the API server the way Argo or Flux would,
  but driven by ConfigHub state rather than by a Git directory layout).

### The mental model vs. what you already know

| You know           | ConfigHub analogue                                  |
| ------------------ | --------------------------------------------------- |
| A YAML file        | A **unit** (typed, versioned, queryable)            |
| A folder / repo    | A **space**                                         |
| `kustomize` bases/overlays | Units + **links** + per-space overrides       |
| `helm upgrade`     | Apply a unit revision to a **target**               |
| `git log` / `git diff` | `cub revision list` / `cub unit diff`           |
| Argo Application   | A unit bound to a target, with a worker reconciling |
| `kubectl apply`    | `cub unit apply` (governed, with receipts)          |

### The CLI shape you'll actually use

Almost every command is `cub <noun> <verb>`, and almost every noun has
`list`, `get`, `create`, `update`, `delete`, plus a few specialized verbs.
Useful starting points:

```
cub auth login                      # one-time
cub info                            # who am I, which org, which space
cub space list
cub unit list --space <space>
cub unit get <name> --space <space>
cub unit get <name> --space <space> --web   # open in the GUI
cub revision list <unit> --space <space>
cub target list
cub unit apply <name> --space <space>       # mutating — read first
```

Two habits that pay off immediately:

1. **Start read-only.** `list`, `get`, `get --web`. Get oriented before you
   apply anything.
2. **Use `--web` liberally.** ConfigHub's UI is the trust surface — it's
   where diffs, revisions, links, and apply receipts are reviewable. The
   CLI is for speed; the GUI is for proof.

### A realistic first-week path for Kubernetes

1. **Log in and look around.**
   `cub auth login`, then `cub info`, `cub space list`, `cub unit list`.
2. **Import something real.** Take an existing Deployment + Service +
   ConfigMap and bring it in as units in a `dev` space. ConfigHub has
   importers for raw YAML and for Helm; the `confighub-scan` tooling can
   also ingest live cluster state.
3. **Wire links.** Link the Deployment to its ConfigMap and to a target
   (your dev cluster/namespace). Now ConfigHub knows the shape of the app,
   not just its files.
4. **Apply to dev.** `cub unit apply` against the dev target. Verify with
   `kubectl` that the workload is healthy. Look at the revision + receipt
   in the GUI.
5. **Promote to staging.** Clone or promote the unit(s) to a `staging`
   space/target. Diff before applying. This is the moment where ConfigHub
   earns its keep versus raw kubectl/Helm: the promotion is a typed,
   reviewable event, not a `cp -r` between folders.
6. **Change something, roll back.** Edit a unit, apply, then roll back to
   a prior revision. Feel the receipts.

### What ConfigHub adds over "just Git + Argo"

- **Semantic units instead of file trees.** You query and mutate by meaning
  ("the prod api Deployment"), not by path.
- **Typed links** instead of implicit folder conventions. Promotion,
  diffing, and impact analysis become first-class.
- **Governed mutation.** Every apply produces a revision + receipt you can
  point at. Good for audit, good for AI agents, good for humans under
  pressure.
- **AI-friendly surface.** Because everything is typed and addressable,
  agents (like me) can operate it safely — read first, propose, apply,
  show the receipt.

### When to reach for which tool

- **`kubectl`** — ground truth about what's live in the cluster *right now*.
- **`cub`** — governed state, revisions, promotions, receipts.
- **`cub-scout`** (in this workspace) — diagnosis, ownership, routing clues.
- **GUI (`--web`)** — reviewable trust surface for humans.

### Gotchas worth knowing up front

- If `cub` commands start failing with auth errors, run `cub auth login`
  again — tokens expire.
- `kubectl` context and ConfigHub target are two different things. Don't
  assume a `cub apply` went to the cluster your current kube-context points
  at — check the target.
- Read before you write. `get` and `get --web` before `apply` or `update`.
- The docs at https://docs.confighub.com/ are the canonical reference for
  commands and concepts; `cub <verb> --help` is the quickest local source
  of truth when a flag looks unfamiliar.

### The single next move I'd suggest

Run `cub info` and `cub space list`, pick one space, and do
`cub unit list --space <that space>` followed by
`cub unit get <one unit> --space <that space> --web`. That three-command
loop — identify, enumerate, inspect-in-GUI — is the core motion you'll
repeat hundreds of times.

---

## (b) Commands run + output

I attempted to run grounding commands but Bash access was denied in this
eval sandbox:

```
$ cub --help
-> Bash permission denied by harness

$ cub info
-> Bash permission denied (cancelled as parallel call)
```

No command output was obtained. The answer above is grounded in:

- the repo's `CLAUDE.md` (read via the tool harness), which codifies the
  `cub` / `cub-scout` / `kubectl` division of labor and the `--web` trust
  convention,
- general ConfigHub product knowledge (units, spaces, links, targets,
  revisions, workers).

I did not fabricate command output. Where I reference commands (e.g.
`cub unit list`, `cub unit get --web`), they are shown as *suggested*
commands for the user to run, not as executed output.

## (c) Reasoning notes

- The user self-identified as new to ConfigHub and asked for a *quick tour*
  plus *what to know to start using it for Kubernetes*. That's an
  orientation request, not a deep technical one.
- I prioritized: (1) one-sentence framing, (2) core vocabulary, (3) a
  mental-model mapping from K8s tools they already know, (4) the minimal
  CLI surface, (5) a concrete first-week path, (6) differentiation vs.
  Git+Argo, (7) gotchas, (8) a single next move.
- I deliberately avoided the `CONFIGHUB SAYS` branded framing because the
  user didn't ask for it and the repo's guidance says to default to plain
  concise prose unless the user opts in.
- I avoided demo-specific details (Argo round-trip, promotion/scan packet)
  because the user is new and asked a generic question; routing them into
  a specific demo would be premature.
- Without shell access I could not confirm the user's current org/space or
  tailor the next move to their actual state. I called out `cub info` as
  their first command so they (or a follow-up turn) can ground further
  advice in real state.
