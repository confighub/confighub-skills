# Eval summary — Iterations 1 + 2 + 3 + 4

24 evals across 24 of 26 shipped skills (`import-from-argocd` + `import-from-flux` deferred — need in-cluster Argo/Flux). Graded against assertions drafted before composition.

## Headline

| | With-skill | Baseline |
|---|---|---|
| Iteration 1 | 17/22 = **77%** | 6/22 = **27%** |
| Iteration 2 | 26/26 = **100%** | 6/26 = **23%** |
| Iteration 3 | 40/40 = **100%** | 2/40 = **5%** |
| Iteration 4 | 120/120 = **100%** | 12/120 = **10%** |
| **Overall** | **203/208 = 98%** | **26/208 = 13%** |

Iteration 3 exercised the Wave 2 deploy/verify/complete chain end-to-end against a live kind cluster with a real Worker. Mutating skills executed against the live instance; baselines composed from general priors.

## Skills tested so far

| Skill | Eval | With/Total | Baseline/Total |
|---|---|---|---|
| config-as-data | user-wants-helm-values | 6/6 | 3/6 |
| triggers-and-applygates | bootstrap-platform-space | 4/8 | 1/8 |
| cub-mutate | single-image-bump | 7/8 | 2/8 |
| confighub-core | new-user-tour | 7/7 | 1/7 |
| cub-query | find-release-deployments | 5/5 | 3/5 |
| skill-examples-bootstrap | idempotent-rerun | 6/6 | 1/6 |
| worker-bootstrap | first-worker-direct-install | 8/8 | 1/8 |
| target-bind | bind-hello-units | 8/8 | 0/8 |
| cub-apply | apply-hello-both | 8/8 | 1/8 |
| verify-delivery | diagnose-hello-app-failure | 8/8 | 0/8 |
| reconciliation-check | three-way-hello-ns | 8/8 | 0/8 |
| release-verify | close-out-hello-ns | 8/8 | 1/8 |
| space-topology | first-real-layout | 10/10 | 1/10 |
| import-unit-granularity | cluster-namespace-inventory | 10/10 | 3/10 |
| import-from-helm | cert-manager-first-install | 10/10 | 1/10 |
| import-from-kustomize | base-plus-overlays-onboarding | 10/10 | 1/10 |
| import-from-cluster | kubectl-apply-onboarding | 10/10 | 0/10 |
| promotion-preflight | ready-to-promote-staging-to-prod | 10/10 | 0/10 |
| promote-release | staging-to-prod-bulk | 10/10 | 1/10 |
| rollback-revision | apply-revision-is-not-rollback | 10/10 | 1/10 |
| drift-reconcile | kubectl-edit-stopgap | 10/10 | 3/10 |
| incident-management | recent-release-crashing-prod | 10/10 | 0/10 |
| app-config | properties-for-java-app | 10/10 | 0/10 |
| kubernetes-resources | statefulset-for-redis | 10/10 | 1/10 |

24 of 26 shipped skills now covered. `import-from-argocd` and `import-from-flux` deferred (need in-cluster installations).

## What the deltas reveal

### Where with-skill clearly wins

- **Function choice.** `cub-mutate` evals: with-skill chose `set-container-image`; baseline chose deprecated `set-image-reference`.
- **Flag correctness.** With-skill used `--change-desc` + `--display-mutation` per the skill's convention; baselines invented `--change-description` / `-m` or didn't include inline-diff at all.
- **Doctrinal refusals.** `config-as-data` eval: with-skill cleanly refused a Helm values.yaml; baseline refused but offered a problematic "Option 2: keep the Helm chart" fallback that contradicts config-as-data.
- **Current terminology.** With-skill consistently uses Revision / `--change-desc` / `--display-mutation` / review links. Baselines regress to "receipts" / "trust surface".
- **Routing.** `confighub-core` with-skill produces a concrete routing table mapping intent → specific skill; baseline offers general prose without named skills.
- **Operational grounding.** With-skill runs consistently ran read-only queries to ground their answers in the actual state of Brian's instance (Space count, Unit count, existing Units); baselines often didn't.

### Where the gap is smaller

- **Read-only query tasks** (`cub-query / find-release-deployments`): baseline scored 3/5 vs with-skill 5/5. Both correctly reported "not found" and avoided fabrication. The skill added systematic query coverage (metadata + content + `image#reference` decomposition), not correctness.

### Real skill bug caught (and fixed)

`triggers-and-applygates / bootstrap-platform-space` surfaced that the skill told agents to pass `--change-desc` on `cub space create/update` and `cub trigger/filter create/update/delete`. None of those accept the flag. Fixed in this iteration; covered in commit `f56c4e8`.

### False positive dismissed

Same eval reported `vet-cel` as wrong because `cub trigger create --help` examples use `vet-celexpr`. Direct test: `vet-cel` works fine as a Trigger function. The help examples are stale; the skill is right.

## Sandbox limitation

Subagent Bash permissions behave asymmetrically:

- Read-only cub (`list`, `get`, `--help`) goes through for both with-skill and baseline.
- Mutating cub (`function do`, `unit update`, `trigger create`, `worker install`) goes through inconsistently — sometimes pre-approved via the skill's `allowed-tools`, sometimes denied. `kubectl` is consistently denied (not in the allow-list — we scoped `settings.local.json.example` to cub-only per direction).

Implication: subagent evals primarily measure **reasoning, function choice, flag correctness, and doctrinal adherence**. End-to-end execution requires running from inside `confighub-skills/` so `settings.local.json` is loaded at session start, or broadening the permission model.

The signal has been strong enough at the reasoning level that execution-blocked evals still produce actionable grades.

## Timing + tokens (averages across 7 runs per variant)

| | With-skill | Baseline |
|---|---|---|
| Tokens | 32,193 | 22,726 |
| Duration | 103.8s | 54.4s |

With-skill runs cost ~40% more tokens and ~90% more time (skill body + references load, plus more thorough execution). Consistent with expected overhead; no outliers.

## Recommended next moves

1. **Commit iteration 2 + benchmark** and the eval workspace (currently gitignored; fine to keep that way).
2. **Five remaining skills** (`target-bind`, `cub-apply`, `verify-delivery`, `reconciliation-check`, `release-verify`) need evals. They're also the ones that depend on a running Worker + Target; worth completing a Worker install first (from a session started inside `confighub-skills/`) so those evals can exercise the real chain.
3. **Iteration 2 has no user-visible skill bugs to fix.** Could push into **description optimization** (`skill-creator`'s `run_loop.py`) on the top-scoring skills to tighten triggering.
4. **Viewer.** The skill-creator methodology suggests launching `eval-viewer/generate_review.py` with this workspace so you can click through per-eval output. Want me to run it?
