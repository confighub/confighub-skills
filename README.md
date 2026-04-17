# confighub-skills

A set of Claude Code / agentskills.io skills for operating Kubernetes workloads with **ConfigHub** as the source of truth, and **ArgoCD or Flux** for delivery.

Skills here assume:

- You store Kubernetes configuration as data in ConfigHub Units — fully materialized YAML, literal values, no templates or values-file split. See the "Configuration as Data" doctrine on https://docs.confighub.com/.
- Mutations go through `cub` (unit update, function do, run). `kubectl` / `argocd` / `flux` are used for read-only diagnosis only.
- You deploy via ArgoCD or Flux Targets bound to Spaces.

## Install

As a Claude Code plugin (recommended):

```
/plugin install https://github.com/confighubai/confighub-skills
```

The plugin manifest is at `.claude-plugin/plugin.json`; Claude Code auto-discovers the `skills/` directory and the `references/` relative paths.

Prerequisites for the skills to actually *do* anything:

- `cub` CLI on PATH, with a valid session (`cub organization list` succeeds — `cub context get` only reads local login state and can still show a user when the token is expired).
- `kubectl` on PATH for skills that touch clusters.
- A running ConfigHub server (self-hosted or `https://hub.confighub.com/`).
- For GitOps imports: `argocd` / `flux` CLI on PATH as read-only diagnostic helpers.

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
    ├── confighub-core/         orientation + routing + Delete/Destroy Gates
    ├── config-as-data/         authoring doctrine
    ├── kubernetes-resources/   author common K8s resource types as ConfigHub Units
    ├── app-config/             AppConfig Units + ConfigMapRenderer for .properties/.env/.yaml/etc.
    ├── space-topology/         one Space per (app, env[, region]); <app>-home for ChangeSets/Tags/Filters
    ├── cub-query/              read-only query across Units, Spaces, Revisions
    ├── cub-mutate/             bulk + surgical mutation; ChangeSet-wrapped multi-Unit changes
    ├── triggers-and-applygates/  platform-Space policy + vet-* Triggers + gate diagnosis
    ├── skill-examples-bootstrap/ creates the skill-examples playground Space
    ├── worker-bootstrap/       install bridge workers in clusters
    ├── target-bind/            create Targets, attach Units to destinations
    ├── cub-apply/              apply Units to their Targets (incl. ChangeSet bulk release)
    ├── verify-apply/           post-apply verification, troubleshooting, and release close-out
    ├── import-from-helm/       cub helm install/upgrade onboarding for existing charts
    ├── import-from-kustomize/  kustomize build → cub unit create
    ├── import-from-argocd/     cub gitops discover/import against ArgoCD Applications
    ├── import-from-flux/       cub gitops discover/import against Flux HelmReleases + Kustomizations
    ├── import-from-cluster/    cub unit import for plain live-resource adoption
    ├── import-unit-granularity/ decision helper — one Unit or many?
    ├── promotion-preflight/    five-axis readiness check before a promotion
    ├── promote-release/        ChangeSet-wrapped bulk upgrade (env-by-env or push-upgrade)
    ├── rollback-revision/      head-moving rollback via cub unit update --restore
    ├── drift-reconcile/        ConfigHub ↔ cluster divergence; decide who wins
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
