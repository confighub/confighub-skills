# confighub-skills — plan for remaining work

Status as of 2026-04-16, `main` at `6956d39` after PRs [#1](https://github.com/confighub/confighub-skills/pull/1) + [#3](https://github.com/confighub/confighub-skills/pull/3) + [#4](https://github.com/confighub/confighub-skills/pull/4) + [#5](https://github.com/confighub/confighub-skills/pull/5) + [#9](https://github.com/confighub/confighub-skills/pull/9) + [#10](https://github.com/confighub/confighub-skills/pull/10) + [#11](https://github.com/confighub/confighub-skills/pull/11) + [#13](https://github.com/confighub/confighub-skills/pull/13) + [#14](https://github.com/confighub/confighub-skills/pull/14) + [#15](https://github.com/confighub/confighub-skills/pull/15) + [#16](https://github.com/confighub/confighub-skills/pull/16) + [#17](https://github.com/confighub/confighub-skills/pull/17) + [#18](https://github.com/confighub/confighub-skills/pull/18) + [#19](https://github.com/confighub/confighub-skills/pull/19) merged:

- **23 skills shipped** across Waves 1–4 + Wave 5's `space-topology` + `app-config`. Count dropped from 25→23 via two post-iteration-4 consolidations: `verify-delivery` + `reconciliation-check` + `release-verify` merged into `verify-apply` (PR #19); `promotion-preflight` merged into `promote-release` (on this branch). `cub unit push-upgrade` is deprecated — `promote-release` now uses a unified selector-based `cub unit update --patch --upgrade` for both env-by-env and base-to-fleet cases.
- **Plugin manifest** (`.claude-plugin/plugin.json`) in place — installs via `/plugin install https://github.com/confighub/confighub-skills`.
- **All four eval iterations complete**: overall benchmark **203/208 = 98%** with-skill vs **26/208 = 13%** baseline across 24 of 26 pre-consolidation skills (`skill-eval-workspace/SUMMARY.md`). Iteration 4 shipped in PR #9 (120/120 with-skill, 12/120 baseline, 0 real bugs found). The only two skills without an eval are `import-from-argocd` and `import-from-flux` (require in-cluster Argo/Flux installations not present in the eval environment).
- **4 real skill bugs fixed** during iteration 3 / Wave 4 drafting (worker-bootstrap direct install, `--display-mutations` plural, `triggers-and-applygates` `--where-trigger "-"` gotcha, `skill-examples-bootstrap` `egrep`-status leak). Iteration 4 found zero new bugs.
- **Post-iteration-4 review fixes** (PRs #15–#19): `cub organization list` is the canonical auth preflight (not `cub context get` / `cub info` / `cub version`); `--unit <slug>` replaces `--where "Slug = '<slug>'"` for bulk-only commands (`cub function do`, `cub run`); `LastActionError` field removed (hallucinated — error text lives on `cub unit-event`'s `Message`); `cub unit get --jq .UnitStatus` + `.LatestUnitEvent` documented as the first-look status views.
- **Reference docs expanded**: `changesets.md`; `cub-cli.md` gains extended-envelope, four Unit views (Data / LiveData / LiveState / BridgeState), `--where` AND-only, `ConfigHub.ResourceType` pseudo-attributes, `--filter` one-per-command, `--unit` vs `--where "Slug = ..."` for bulk-only commands.
- **Memory captured** for load-bearing session feedback (cub-auth-check, PascalCase labels, rollback means `--restore`, `--jq` on extended envelope, branch-creation convention, etc.).

This doc tracks what's left.

## Operating context for the next session

- Repo: `~/ConfigHub/confighub-skills`. Launch `claude` from inside it so `.claude/settings.local.json` loads.
- `.claude/settings.local.json.example` is the committed template; copy to `.claude/settings.local.json` (gitignored).
- Brian's local ConfigHub instance is the eval target. `cub organization list` is the canonical auth check (`cub context get` / `cub info` / `cub version` don't require a valid token).
- A kind cluster `confighub-eval` is used for live exercises; recreate if missing: `kind create cluster --name confighub-eval`.
- The `skill-examples` Space has seeded `hello-ns` + `hello-app` (now resolved + applied, hello-app ImagePullBackOff because the image tag is fake). Don't delete them.
- `platform` Space holds the 5 baseline `vet-*` Triggers + the `standard-vets` Filter, attached to `skill-examples` with `WhereTrigger` cleared via `-`.
- Worker `eval-worker` runs in the kind cluster (patched to `CONFIGHUB_URL=http://host.docker.internal:9090` to escape kind loopback).

## Priority queue

### P0 — Iteration 4 complete. Only remaining coverage gap: ArgoCD + Flux imports

Iteration 4 shipped in PR #9 — 12 skills, 120/120 with-skill, 12/120 baseline, 0 real bugs (`skill-eval-workspace/iteration-4/SUMMARY.md`). The consolidations since iteration 4 (`verify-apply` ← 3 skills; `promote-release` ← `promotion-preflight`) do not invalidate those results — iteration-4 graded the individual skills' content, which is preserved inside the merged skills.

Outstanding:

- **`import-from-argocd` eval** — needs in-cluster Argo CD and a Worker installed with `-t kubernetes,argocdrenderer,argocdoci`.
- **`import-from-flux` eval** — needs in-cluster Flux and a Worker installed with `-t kubernetes,fluxrenderer,fluxoci`.

Both deferred from every prior iteration. Not worth standing up a new eval environment for two skills; pick these up opportunistically when an Argo/Flux cluster is already available, or when either skill changes in a way that warrants fresh grading.

A post-consolidation smoke eval for `verify-apply` and the new `promote-release` would also be prudent — their merged structure differs enough from the pre-merge evals that a targeted run is useful even if iteration-4's content coverage is already recorded.

### P1 — Doctrine skills for uncovered doc topics (active queue)

With P0 complete, this is the active work. Topics from the published docs that aren't yet a skill, ranked by operational value:

- **`links-and-needs-provides`** — `dependencies.md`. Links + Needs/Provides is referenced by `app-config`, `rendered-manifests`, `space-topology`, and every import skill, but has no doctrine home. Highest value. The Link-direction vs data-flow-direction terminology gotcha (Link points downstream→upstream, data flows upstream→downstream) that surfaced during the `promote-release` merge is load-bearing material for this skill.
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

- **`cub unit push-upgrade`** — deprecated. `promote-release` now uses a unified `cub unit update --patch --upgrade --where "Unit.UpstreamUnitID = '<base-uuid>' AND Unit.UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum" --space "*"` for the base-to-fleet case, which composes with `--dry-run`, `--display-mutations`, and `--changeset`.
- **`LastActionError`** — hallucinated Unit field, removed during the `verify-apply` merge. Not a real field; error text lives on `cub unit-event`'s `Message`. Flag and remove if it appears in any new draft.
- **Links authoring** — partially covered in `app-config` / `import-from-helm`. Full home is P1's `links-and-needs-provides` skill.
- **`cub unit tag`** — covered in `cub-mutate`, `verify-apply`, `rollback-revision`, `promote-release`. Leave as-is.

## Decisions to preserve

These are settled and load-bearing. Don't relitigate without strong reason.

1. **End-user audience, not demo.** Skills target end users operating their own Kubernetes via ConfigHub. Don't overfit the skills for specific demos or examples.
2. **Plugin-only delivery.** Claude Code plugin + agentskills.io-style harnesses. Not Claude.ai / API.
3. **ArgoCD and Flux are peers.** Not ArgoCD-primary.
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
18. **Auth preflight is `cub organization list`** (or any other authenticated read). Never `cub context get` / `cub info` / `cub version` — the first reads local login state and the others don't require a token at all.
19. **`--unit <slug|uuid>[,…]` replaces `--where "Slug = '<slug>'"` for bulk-only commands** (`cub function do`, `cub run`). Composes with `--where` for additional filtering.
20. **Apply status lives on `cub unit-event`, not on a Unit field.** `cub unit get --jq .UnitStatus` + `.LatestUnitEvent` are the first-look envelopes; `cub unit-event list/get` is the authoritative event stream (including `ResourceStatuses` per resource). `LastActionError` is not a real field.
21. **Promotion direction ≠ Link direction.** Data flows `<source-env>` → `<destination-env>`; a `UpgradeUnit` Link points _from_ a downstream Unit _to_ its upstream (dependency edge, opposite of data flow). Skills use `<source-env>` / `<destination-env>` for promotion and "upstream / downstream" for Link structure — never "from/to" for both.

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

First prompt to Claude: read `README.md`, `SKILL_TEMPLATE.md`, `references/cub-cli.md`, and `skill-eval-workspace/SUMMARY.md`. P0 is complete; pick a P1 task (doctrine skills: `links-and-needs-provides`, `variants`, `attributes`, `views`).
