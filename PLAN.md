# confighub-skills — plan for remaining work

Status as of 2026-04-15 (PR [#1](https://github.com/confighubai/confighub-skills/pull/1) on `brian-skill-pack-initial`):

- 12 skills shipped (Waves 1 + 2).
- Shared scaffolding, references, and conventions in place.
- Eval results from 7 of 12 skills: with-skill 90% pass rate vs baseline 25%.
- 1 real skill bug caught (`--change-desc` scope) and fixed.
- 5 skills still need evals; 8 more skills planned across Waves 3–5.

This doc is the handoff to whatever session picks up next.

## Reference to the originating session

The skill pack and eval results were authored in a Claude Code session running from `~/ConfigHub/confighub-ai-demo` on 2026-04-15. The session transcript is at:

```
~/.claude/projects/-Users-briangrant-ConfigHub-confighub-ai-demo/e6832d25-73a5-44d0-8df8-6e7c61e7f07d.jsonl
```

That's a local-only artifact — not pushed anywhere — but useful for tracing how decisions were made (terminology choices, function discovery, eval scoping, sandbox limitations encountered).

Durable design context that survives across sessions lives in the repo itself:

- `README.md` — installation, conventions, permission discipline, eval guide.
- `SKILL_TEMPLATE.md` — the scaffolding every new skill inherits.
- `references/` — CLI discipline, function catalog, query/filter recipes, trigger patterns, YAML authoring, Revision data model.
- `skill-eval-workspace/SUMMARY.md` — what the existing skills do well + where they need improvement.

When starting a new session in this repo, **read those four first** before adding a skill.

## Operating context for the next session

- Run Claude Code from inside `confighub-skills/` so `.claude/settings.local.json` is loaded at session start. That gives subagents the cub allow-list (Read + Write sets, scoped per `references/cub-cli.md`).
- `.claude/settings.local.json.example` is the committed template; copy to `.claude/settings.local.json` (gitignored).
- Brian's local ConfigHub test instance is the eval target. `cub auth login` should already be active; verify via `cub context get`.
- A kind cluster `confighub-eval` was created on 2026-04-15 for cluster-dependent evals. Verify it's still up: `kind get clusters`. If not, recreate: `kind create cluster --name confighub-eval`.
- The `skill-examples` Space on the local instance has two seeded Units (`hello-ns`, `hello-app`) used by the bootstrap and image-bump evals. Don't delete them.
- The `platform` Space exists (created during eval iteration 1) but is empty — no Triggers or Filters were created because the subagent sandbox blocked them. Future eval runs on `triggers-and-applygates` should populate it.

## Priority queue

### P0 — Eval the five remaining Wave 2 skills

These skills depend on each other (Worker → Target → apply → verify → reconcile → completion), so the eval makes the most sense as an end-to-end chain. Expected to be the highest-signal eval batch in the repo.

Skills to cover: `target-bind`, `cub-apply`, `verify-delivery`, `reconciliation-check`, `release-verify`.

Prerequisites:
1. Session rooted in this repo so `settings.local.json` applies to subagents.
2. `kubectl config current-context` set to `kind-confighub-eval`.
3. Optionally: a Worker installed via `worker-bootstrap` first (manual, from the parent session, since that's the seed step), then subagent-evaluate the rest of the chain against the live Worker.

Plan:
1. Manually install a Worker in the kind cluster following `skills/worker-bootstrap/SKILL.md`.
2. Spawn one with-skill + baseline subagent per remaining skill, each eval prompt referencing the live Worker by slug.
3. Grade per `skill-eval-workspace/iteration-1/assertions-draft.md` patterns.
4. Aggregate into `skill-eval-workspace/iteration-3/SUMMARY.md` and update `benchmark.json`.

### P1 — Wave 3: import skills

Biggest user-facing gap. Most new ConfigHub adopters arrive with existing Helm charts, Kustomize overlays, ArgoCD Applications, or Flux Kustomizations and need a path in.

Skills to draft:
- `import-from-helm` — render once via `helm template`, store as Unit, never re-render.
- `import-from-kustomize` — same shape with `kustomize build`.
- `import-from-argocd` — `cub unit import` against an ArgoCD Application.
- `import-from-flux` — `cub unit import` against a Flux Kustomization / HelmRelease.
- `import-unit-granularity` — decision helper for one-Unit-per-what (per chart, per workload, per namespace, per release).

All five use `cub unit import` (verified to exist via `cub unit --help`). Authoring-side discipline (no re-rendering after import) is already enforced by `config-as-data`.

### P2 — Wave 4: operate verbs

Most are refactors/ports of demo skills from `~/ConfigHub/confighub-ai-demo/skills/`. Strip demo-specific vocabulary; align with the new conventions.

Skills:
- `promote-release` + `promotion-preflight` — uses `needs-upgrade` filter recipe and `cub unit update --upgrade`.
- `rollback-revision` — head restore via `cub unit update --restore`, distinct from `cub-apply --revision <n>` (which doesn't move head).
- `drift-reconcile` — `cub unit refresh` + diff + decide-who-wins.
- `rotate-secrets` — bounded sensitive change.
- `incident-management` — stabilize / mitigate-vs-rollback / hand-off orchestrator.

### P3 — Wave 5: governance

- `space-topology` — app × env/region naming, label strategy, platform-Space pattern. Mostly teaching; no unique commands.
- `approval-flow` — `cub unit approve` + the `vet-approvedby` Trigger pattern. Currently a gap.

### P4 — Description optimization

Once skill bodies are stable across all waves, run `skill-creator/scripts/run_loop.py` per skill with a 20-query trigger eval set (mix should-trigger / should-not-trigger). Goal: push trigger accuracy on each skill > 90% on a held-out test set. Defer until WaveS 3–5 are landed; reasoning gaps would compound.

### P5 — Packaging + distribution

- `.skill` artifacts via `skill-creator/scripts/package_skill.py` for downloadable installs.
- Installation instructions specific to Claude Code, agentskills.io.
- Lightweight CI for SKILL.md schema (frontmatter required fields, `allowed-tools` syntax, no `Bash(cub *)` wildcards, no deprecated function names).

## Decisions to preserve

These were settled in the originating session and are load-bearing for everything that follows. Don't relitigate without strong reason.

1. **End-user audience, not demo.** Skills target end users operating their own K8s via ConfigHub.
2. **Plugin-only delivery.** Claude Code plugin + agentskills.io-style harnesses. Not Claude.ai / API.
3. **Argo and Flux are peers.** Not Argo-primary.
4. **Configuration as data.** Units contain literal YAML, no parameterization at rest. `set-pod-container-security-context-defaults` and the rest of the defaults functions are how you apply policy, not Helm values.
5. **`--change-desc` is Unit-data-mutation-only.** It does NOT exist on `cub space / trigger / filter / target / worker create/update`.
6. **`--display-mutations` on every mutating call.** Inline diffs make changes visible without chasing them via `cub unit diff` afterward. Flag spelling is plural — `--display-mutation` (singular) is rejected as unknown.
7. **Triggers are opt-in but recommended.** Best practice is the platform-Space + Filter + `TriggerFilterID` recipe documented in `references/triggers-recipes.md`.
8. **Permission discipline.** Read set + Write set, both verb-scoped, no `Bash(cub *)`, no delete verbs in normal skills.
9. **Standard terminology.** Revision (not receipt / change record), Evidence (not Trust surface), completion (not close / closeout), ConfigHub-managed (not governed), review links (not trust URLs). Memory rule: don't invent synonyms for product entity names.
10. **No local paths in shipped artifacts.** Use `https://github.com/confighub/sdk` and `https://docs.confighub.com/`.

## Known unknowns

- **Subagent permission model.** The asymmetry observed in eval iterations (with-skill subagents got cub access via skill `allowed-tools`; baselines didn't) is worth understanding more deeply. May affect how iteration 3 evals are designed.
- **`vet-cel` vs `vet-celexpr`.** Both work as Trigger functions; help examples on `cub trigger create` are stale (still show `vet-celexpr`). Worth a CLI-side fix; the skill is already correct.
- **`cub unit set-target` change-desc behavior.** Likely doesn't take `--change-desc` (target binding isn't config-data mutation), but verify before drafting Wave 4 promote/rollback skills that touch target reassignment.
- **Whether the `confighub-ai-demo` repo's CLAUDE.md should be updated** to reflect the new skills repo as the canonical end-user surface (currently CLAUDE.md is demo-specific and predates this repo). Not blocking; flag for whoever owns that repo.
- **Server bug: `cub space update --trigger-filter <slug>` does not clear the default `WhereTrigger`.** A Space is created with `WhereTrigger = SpaceID = '<this-space>'`, which shadows the attached filter so `# Triggers = 0` even though `cub trigger list --filter <slug>` resolves correctly. Workaround documented in `triggers-and-applygates`: pass `--where-trigger "-"` alongside `--trigger-filter`. Worth a server-side fix.
- **Server bug: `Space.WhereTrigger` evaluator rejects attributes that Filter WHERE accepts** (e.g., `FunctionName` → `HTTP 400 unrecognized attribute name`). Filter→Space attribute vocabularies diverge; should be unified.

## Smaller gaps

- **`cub unit push-upgrade`** — downstream bulk upgrade. Fold into `promote-release` rather than a standalone skill.
- **Links authoring** — currently not covered. Fold into `config-as-data` as a section rather than a standalone skill.
- **`cub unit tag`** — covered in `cub-mutate` + `release-verify`. Leave as-is unless users need a dedicated skill.

## How to start

```bash
cd ~/ConfigHub/confighub-skills
cp .claude/settings.local.json.example .claude/settings.local.json
# verify cluster
kubectl config current-context   # expect kind-confighub-eval
kind get clusters                # expect confighub-eval
# verify cub
cub context get
# launch claude
claude
```

First prompt to Claude: read `README.md`, `SKILL_TEMPLATE.md`, `references/cub-cli.md`, and `skill-eval-workspace/SUMMARY.md`. Then pick a P0 task.
