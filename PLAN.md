# confighub-skills — plan for remaining work

Status as of 2026-04-15, `main` at `c9fcbd8` after PRs [#1](https://github.com/confighubai/confighub-skills/pull/1) + [#3](https://github.com/confighubai/confighub-skills/pull/3) + [#4](https://github.com/confighubai/confighub-skills/pull/4) + [#5](https://github.com/confighubai/confighub-skills/pull/5) merged:

- **25 skills shipped** across Waves 1–4 + Wave 5's `space-topology` + `app-config`.
- **Plugin manifest** (`.claude-plugin/plugin.json`) in place — installs via `/plugin install https://github.com/confighubai/confighub-skills`.
- **Iteration 3 evals**: 5 Wave 2 skills run live against a kind cluster; overall benchmark 83/88 = 94% with-skill vs 14/88 = 16% baseline across 12 skills.
- **4 real skill bugs fixed** during iteration 3 / Wave 4 drafting (worker-bootstrap direct install, `--display-mutations` plural, `triggers-and-applygates` `--where-trigger "-"` gotcha, `skill-examples-bootstrap` `egrep`-status leak).
- **Reference docs expanded**: `changesets.md`; `cub-cli.md` gains extended-envelope, four Unit views (Data / LiveData / LiveState / BridgeState), `--where` AND-only, `ConfigHub.ResourceType` pseudo-attributes, `--filter` one-per-command.
- **Memory captured** for load-bearing session feedback (cub-auth-check, PascalCase labels, rollback means `--restore`, `--jq` on extended envelope, branch-creation convention, etc.).

This doc tracks what's left.

## Operating context for the next session

- Repo: `~/ConfigHub/confighub-skills`. Launch `claude` from inside it so `.claude/settings.local.json` loads.
- `.claude/settings.local.json.example` is the committed template; copy to `.claude/settings.local.json` (gitignored).
- Brian's local ConfigHub instance is the eval target. `cub context get` should show the user; `cub space list` is the canonical auth check.
- A kind cluster `confighub-eval` is used for live exercises; recreate if missing: `kind create cluster --name confighub-eval`.
- The `skill-examples` Space has seeded `hello-ns` + `hello-app` (now resolved + applied, hello-app ImagePullBackOff because the image tag is fake). Don't delete them.
- `platform` Space holds the 5 baseline `vet-*` Triggers + the `standard-vets` Filter, attached to `skill-examples` with `WhereTrigger` cleared via `-`.
- Worker `eval-worker` runs in the kind cluster (patched to `CONFIGHUB_URL=http://host.docker.internal:9090` to escape kind loopback).

## Priority queue

### P0 — Evals for Wave 3 / 4 skills + `app-config`

Twelve skills shipped since iteration 3 have `evals/evals.json` prompts but no actual run:

- Wave 3: `import-from-helm`, `import-from-kustomize`, `import-from-argocd`, `import-from-flux`, `import-from-cluster`, `import-unit-granularity`.
- Wave 4: `promotion-preflight`, `promote-release`, `rollback-revision`, `drift-reconcile`, `incident-management`.
- Wave 5 (partial): `space-topology`.
- New: `app-config`.

Iteration 3 caught 4 real bugs in its 5 target skills; iteration 4 is the same kind of bet for twelve more. Eval infrastructure (`skill-eval-workspace/iteration-N/<eval-name>/{with_skill,without_skill}/{grading.json,timing.json,outputs/}`) is already the convention — follow it.

Prerequisites for live execution:

1. Live kind cluster with `eval-worker` Ready (above).
2. For `import-from-helm`: `helm` on PATH, a chart repo added (e.g., `helm repo add jetstack https://charts.jetstack.io`).
3. For `import-from-argocd` / `import-from-flux`: Argo CD and/or Flux installed in-cluster; Worker installed with `-t kubernetes,argocdrenderer,argocdoci` or `-t kubernetes,fluxrenderer,fluxoci` respectively. Non-trivial setup; consider deferring these two until the eval environment supports them.
4. For `app-config`: a server-worker (`cub worker create --is-server-worker --allow-exists server-worker`).

Reasoning-only evals (sandbox-blocked mutations) are still valuable — iterations 1–2 graded primarily on reasoning and caught multiple bugs. If live execution isn't available, run reasoning-only and annotate.

Aggregate into `skill-eval-workspace/iteration-4/SUMMARY.md` and append to `benchmark.json`.

### P1 — Doctrine skills for uncovered doc topics

Topics from the published docs that aren't yet a skill, ranked by operational value:

- **`links-and-needs-provides`** — `dependencies.md`. Links + Needs/Provides is referenced by `app-config`, `rendered-manifests`, `space-topology`, and every import skill, but has no doctrine home. Highest value.
- **`variants`** — `variants.md`. The clone / upstream-downstream mental model that `promote-release` operationalizes. A decide-phase doctrine skill.
- **`attributes`** — Space-level Attributes used for per-env substitution on promotion (referenced in `skill-examples-bootstrap` change-desc). Currently no home; pairs well with `promote-release` and `variants`.
- **`views`** — saved-query entity; `cub-query` covers Filters but not Views. Thin skill or a section inside `cub-query`.

### P2 — Optional / specialist

- `admission-webhook-functions` — writing custom Worker-side validator functions.
- `custom-workers` — building Worker bridges for non-K8s providers.
- `secrets-handling` — doctrine skill for ConfigHub + external SecretStore. Replaces the `rotate-secrets` skill that Brian explicitly skipped; scope is "how do we think about secrets," not "how do we rotate them."
- `approval-flow` — explicitly skipped by Brian. `cub unit approve` + `vet-approvedby` Trigger pattern.
- `rotate-secrets` — explicitly skipped.

### P3 — Description optimization

Once every skill has at least one eval iteration, run `skill-creator/scripts/run_loop.py` per skill with a 20-query trigger eval set (mix should-trigger / should-not-trigger). Goal: >90% trigger accuracy on a held-out test set. Defer until P0 evals are in; reasoning gaps would compound.

### P4 — Packaging + distribution

- `.skill` artifacts via `skill-creator/scripts/package_skill.py` for downloadable installs (alongside the git-URL `/plugin install` path).
- Optional marketplace manifest (`.claude-plugin/marketplace.json`) if distributing through the Claude Code marketplace.
- Lightweight CI for SKILL.md schema: frontmatter required fields, `allowed-tools` syntax sanity, no `Bash(cub *)` wildcards, no deprecated function names, no `--display-mutation` (singular), no `cub-apply --revision` framed as rollback.

### P5 — Smaller gaps

- **`cub unit push-upgrade`** — folded into `promote-release` as Shape B. No further action unless user demand surfaces.
- **Links authoring** — partially covered in `app-config` / `import-from-helm`. Full home is P1's `links-and-needs-provides` skill.
- **`cub unit tag`** — covered in `cub-mutate`, `release-verify`, `rollback-revision`, `promote-release`. Leave as-is.

## Decisions to preserve

These are settled and load-bearing. Don't relitigate without strong reason.

1. **End-user audience, not demo.** Skills target end users operating their own Kubernetes via ConfigHub.
2. **Plugin-only delivery.** Claude Code plugin + agentskills.io-style harnesses. Not Claude.ai / API.
3. **Argo and Flux are peers.** Not Argo-primary.
4. **Configuration as data.** Units contain literal YAML, no parameterization at rest. Helm / Kustomize are onboarding ramps, not ongoing workflows.
5. **`--change-desc` is Unit-data-mutation-only.** Not on `cub space / trigger / filter / target / worker create/update`.
6. **`--display-mutations` (plural)** on every mutating call. The singular `--display-mutation` is rejected.
7. **Triggers are opt-in but recommended.** Platform-Space + Filter + `TriggerFilterID` recipe, attached with `--where-trigger "-"` to clear the default.
8. **Permission discipline.** Read set + Write set, both verb-scoped, no `Bash(cub *)`, no delete verbs in normal skills.
9. **Standard terminology.** Revision / Evidence / completion / ConfigHub-managed / review links. Don't invent synonyms.
10. **No local paths in shipped artifacts.** `https://github.com/confighub/sdk` / `https://docs.confighub.com/`.
11. **Environments are Spaces, not slug suffixes.** One Space per `(app, env[, region])`; app team's home Space `<app>-home` for ChangeSets / Tags / Filters / Views / Invocations.
12. **Rollback = `cub unit update --restore` then apply.** `cub unit apply --revision <N>` is NOT a rollback (head unchanged).
13. **Drift diff = Data vs LiveData.** Not LiveState (noisy); not BridgeState (bridge-dependent blob).
14. **Labels are PascalCase, non-abbreviated** (`Environment`, `Application`, `Region`, `Cluster`, `Tier`).
15. **`cub --jq` over piping to `jq`.** `cub get` / `list` return an extended envelope with the entity under `.Unit` / `.Space` / etc. and related entities at top level (`.BridgeWorker`, `.TriggerFilter`, `.Triggers`).
16. **`--where` / `--where-field` / `--where-data` / `--where-resource` are AND only.** No OR. Disjunctions split into separate commands, `IN (...)`, or separate Units.
17. **`--filter` takes one argument per command.** Combine with `--where`, or create a third Filter expressing the intersection.

## Known unknowns

- **Subagent permission model.** Iteration 1–2 observed asymmetric grants. May affect how future iteration-N evals are designed if the harness still blocks mutations for baselines.
- **`vet-cel` vs `vet-celexpr` in `cub trigger create --help` examples.** Stale; skill is correct. CLI fix deferred upstream.
- **Whether the `confighub-ai-demo` repo's CLAUDE.md should be updated** to reflect this repo as the canonical end-user skill pack. Not blocking; flag for whoever owns that repo.

## How to start

```bash
cd ~/ConfigHub/confighub-skills
cp .claude/settings.local.json.example .claude/settings.local.json
kubectl config current-context   # expect kind-confighub-eval
kind get clusters                # expect confighub-eval
cub space list                    # auth check
claude
```

First prompt to Claude: read `README.md`, `SKILL_TEMPLATE.md`, `references/cub-cli.md`, and `skill-eval-workspace/SUMMARY.md`. Then pick a P0 task.
