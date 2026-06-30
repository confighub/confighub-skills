# confighub-skills

A set of Claude Code / agentskills.io skills for operating Kubernetes workloads with **ConfigHub** as the source of truth, delivering by publishing Units to ConfigHub's built-in **OCI** registry for **ArgoCD or Flux** to pull (or via a **ConfigHub** Target).

Skills here assume:

- You store Kubernetes configuration as data in ConfigHub Units — fully materialized YAML, literal values, no templates or values-file split, **one resource per Unit** by default. See the "Configuration as Data" doctrine at https://docs.confighub.com/markdown/background/config-as-data.md.
- Mutations go through `cub` (unit update, function do, run). `kubectl` / `argocd` / `flux` are used for read-only diagnosis only.
- You deliver via an **OCI** or **ConfigHub** Target bound to a Space. Both are served by **server workers** hosted in the ConfigHub server — there's no process to run to create or use a Target (`cub worker create --is-server-worker`). An OCI Target publishes Unit data to ConfigHub's OCI registry; ArgoCD or Flux, configured outside ConfigHub, pulls and converges the cluster. You run an external worker only to host custom worker functions. Typically one OCI Target per Space.

## Install

As a Claude Code plugin (recommended):

```
claude plugin marketplace add https://github.com/confighub/confighub-skills
claude plugin install confighub-skills@confighub
```

The plugin manifest is at `.claude-plugin/plugin.json`; Claude Code auto-discovers the `skills/` directory and the `references/` relative paths.

Prerequisites for the skills to actually _do_ anything:

- `cub` CLI on PATH, with a valid session (`cub auth status` succeeds — it calls the server's `/me` to verify the token; `cub context get` only reads local login state and can still show a user when the token is expired).
- `kubectl` on PATH for read-only cluster-convergence checks (`verify-apply`).
- A running ConfigHub server (self-hosted or `https://hub.confighub.com/`).
- `argocd` / `flux` CLI on PATH as read-only diagnostic helpers, to confirm the GitOps tool pulled the OCI artifact and converged the cluster.

## Layout

```
confighub-skills/
├── .claude-plugin/plugin.json  Claude Code plugin manifest
├── SKILL_TEMPLATE.md           shared scaffolding every skill inherits
├── references/                 shared reference material (loaded on demand)
│   ├── cub-cli.md              CLI discipline + extended envelope + AND-only where + four Unit views
│   ├── changesets.md           ChangeSet lifecycle (create/open/mutate/close/approve/apply/rollback)
│   ├── revisions.md            Revision data model (fields, provenance, lifecycle)
│   ├── filters-and-queries.md  filter vocabulary + operational Unit-filter recipes
│   ├── functions-catalog.md    K8s/YAML functions worth knowing
│   ├── triggers-recipes.md     platform-Space + Filter + TriggerFilterID recipe
│   └── yaml-patterns.md        literal-value K8s authoring patterns for all common resource types
└── skills/
    ├── confighub-core/         orientation + routing + config-as-data/topology/one-resource-per-Unit doctrine + Delete/Destroy Gates
    ├── kubernetes-resources/   author common K8s resource types as ConfigHub Units
    ├── app-config/             AppConfig Units → ConfigMap via Upsert link + render-configmap Invocation
    ├── cub-query/              read-only query across Units, Spaces, Revisions
    ├── cub-mutate/             bulk + surgical mutation; ChangeSet-wrapped multi-Unit changes
    ├── triggers-and-applygates/  platform-Space policy + vet-* Triggers + gate diagnosis
    ├── skill-examples-bootstrap/ creates the skill-examples playground Space
    ├── worker-bootstrap/       server worker (no process) for OCI/ConfigHub delivery; external worker for custom functions
    ├── target-bind/            create OCI / ConfigHub Targets, attach Units
    ├── cub-apply/              apply/publish Units to their Targets (incl. ChangeSet bulk release)
    ├── verify-apply/           post-apply verification (publish + Argo/Flux convergence) and release close-out
    ├── import/                 onboard existing Helm charts / Kustomize overlays
    ├── promote-release/        variant spaces (cub variant upload/create/promote) + ChangeSet-wrapped bulk upgrade
    ├── release-publish/        immutable OCI Release bundles (cub release publish/withdraw) pinned per Target
    ├── rollback-revision/      head-moving rollback via cub unit update --restore
    └── incident-management/    orchestrator for the ConfigHub side of a production incident
```

## Conventions every skill follows

- **Phase** — `decide`, `act`, `verify`, `completion`, or `cross-cutting`.
- **Change descriptions** — every `cub unit update`, `cub function do`, `cub run` call (the Unit-mutation verbs) must pass `--change-desc` containing a summary line, the user's original prompt, and a condensed summary of any clarifying-question answers. Space/Trigger/Filter/Target creates don't accept `--change-desc` — those entities aren't versioned data.
- **Preflight gates** — what must be true before acting; if a gate fails, stop.
- **Stop conditions** — what makes the skill hand back control instead of continuing.
- **Verify chain** — how to prove the change actually landed (not just that `cub` returned success).
- **Tool boundary** — which tools this skill may invoke; which are read-only only.

See `SKILL_TEMPLATE.md` for the full scaffolding.

## Permission discipline

Skills split `cub` permissions into a **Read set** and a **Write set** so that read-only skills like `cub-query` physically cannot mutate. Each skill's `allowed-tools` frontmatter declares exactly what it needs — no `Bash(cub *)` wildcards, no `delete` verbs, no mutating `kubectl`/`argocd`/`flux`.

See `references/cub-cli.md` → "Permission sets for `allowed-tools` frontmatter" for the canonical Read and Write sets and the one known ambiguity (`cub function do` / `cub run` live in the Write set only).

The discipline means an end user loading a skill gets seamless, scoped auto-approval for exactly the operations the skill declares — not a blanket grant.

## Running skill evaluations

Subagent-based skill evaluations (`Agent` tool invocations that load a skill and try to complete a user task) don't inherit the parent session's interactive approvals — subagents can't prompt. To let eval subagents actually execute `cub` commands, copy the template:

```bash
cp .claude/settings.local.json.example .claude/settings.local.json
```

The allow-list in that file mirrors the Read + Write cub permission sets declared in `references/cub-cli.md`, scoped to exactly what the skills in this repo need. No bare wildcards, no delete verbs, no kubectl/argocd/flux grants. `.claude/settings.local.json` itself is gitignored; only the `.example` template is checked in.
