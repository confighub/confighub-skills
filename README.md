# confighub-skills

A set of Claude Code / agentskills.io skills for operating Kubernetes workloads with **ConfigHub** as the source of truth, and **ArgoCD or Flux** for delivery.

Skills here assume:

- You store Kubernetes configuration as data in ConfigHub Units — fully materialized YAML, literal values, no templates or values-file split. See the "Configuration as Data" doctrine on https://docs.confighub.com/.
- Mutations go through `cub` (unit update, function do, run). `kubectl` / `argocd` / `flux` are used for read-only diagnosis only.
- You deploy via ArgoCD or Flux Targets bound to Spaces.

## Layout

```
confighub-skills/
├── SKILL_TEMPLATE.md           shared scaffolding every skill inherits
├── references/                 shared reference material (loaded on demand)
│   ├── cub-cli.md              CLI discipline + agent help mode + permission sets
│   ├── revisions.md            Revision data model (fields, provenance, lifecycle)
│   ├── filters-and-queries.md  filter vocabulary + operational Unit-filter recipes
│   ├── functions-catalog.md    K8s/YAML functions worth knowing
│   ├── triggers-recipes.md     platform-Space + Filter + TriggerFilterID recipe
│   └── yaml-patterns.md        literal-value K8s authoring patterns
└── skills/
    ├── config-as-data/         authoring doctrine (Wave 1)
    ├── triggers-and-applygates/
    ├── cub-mutate/
    ├── cub-query/
    ├── skill-examples-bootstrap/  creates the skill-examples playground Space
    ├── confighub-core/         orientation + routing (Wave 2)
    ├── worker-bootstrap/       install bridge workers in clusters
    ├── target-bind/            create Targets, attach Units to destinations
    ├── cub-apply/              apply Units to their Targets
    ├── verify-delivery/        cub → controller → cluster link verification
    ├── reconciliation-check/   three-way ConfigHub/controller/cluster agreement
    └── release-verify/         final read-only completion with Revision history + GUI review links
```

More skills arrive in subsequent waves (CRUD + delivery, import paths, operate verbs, governance).

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
