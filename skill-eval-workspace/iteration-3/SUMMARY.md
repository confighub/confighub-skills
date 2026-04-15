# Iteration 3 summary — Wave 2 end-to-end deploy/verify/complete chain

Five skills, graded against 8 assertions each. Scenario threaded the live environment:
Worker `eval-worker` (Ready) in `skill-examples` -> Target `k8s-eval-worker` ->
Units `hello-ns` + `hello-app` -> kind cluster `confighub-eval`.

## Headline

| Skill | With-skill | Baseline |
|---|---|---|
| target-bind | 8/8 | 0/8 |
| cub-apply | 8/8 | 1/8 |
| verify-delivery | 8/8 | 0/8 |
| reconciliation-check | 8/8 | 0/8 |
| release-verify | 8/8 | 1/8 |
| **Iteration 3 total** | **40/40 = 100%** | **2/40 = 5%** |

Overall across iterations 1+2+3: **83/88 = 94%** vs **14/88 = 16%**.

## Per-skill findings

### target-bind
- With-skill uses `cub unit set-target`, omits `--change-desc` (binding is not config-data mutation), stops short of apply.
- Baseline invented `--target` + `--change-description` on `cub unit update` and chained into `cub unit apply`, violating hand-off.

### cub-apply
- With-skill composes `cub unit apply --wait --timeout 2m0s`, ApplyGates preflight via `LEN(ApplyGates) > 0`, worker-health preflight, `--dry-run` on the multi-resource unit, no `--change-desc`.
- Baseline invented `--change-desc` on apply (wrong), had no dry-run, no wait, no gate/worker preflight, and the anti-pattern "retry once then check kubectl logs."
- Live chain: `hello-ns` succeeded; `hello-app` Failed (`namespace: confighubplaceholder` left unresolved in unit data).

### verify-delivery
- With-skill leads with ConfigHub (`cub unit get`/`bridgestate`), correctly says "no controller layer" for the direct-K8s Target, names the broken link in plain English, hands off.
- Baseline led with `kubectl`, proposed `cub unit refresh` (mutation) inside a verify skill, planned to re-apply.

### reconciliation-check
- With-skill produces a columnar ConfigHub/Controller/Cluster/Owner table, marks Controller N/A (not fake-agreed), identifies hello-app divergent pair as ConfigHub != Cluster.
- Baseline produced no table, speculated about Argo, proposed `cub unit refresh` (mutation).

### release-verify
- With-skill preflights Head=Applied=Live and zero gates, excludes non-converged hello-app, surfaces `cub revision list` DESCRIPTION column, uses `--web` exclusively, sets read-only stop.
- Baseline invented `cub unit history` (correct verb is `cub revision list`), hand-built a GUI URL, proposed `cub unit apply` inside completion.

## Real bugs / issues found

1. **`confighubplaceholder` namespace unresolved on hello-app** (seeded-data issue in `skill-examples`, not a skill bug). Produced the interesting divergence signal for verify/reconcile evals.
2. **worker-bootstrap**: no fix needed. Current SKILL.md already documents the canonical `--export --include-secret | kubectl apply -f -` path and does not claim `--wait` for install. The iter-2 write-up's `--wait` usage was subagent fabrication, not a shipped skill bug.

## Terminology / flag assertions confirmed

- `cub info` is NOT a valid auth check (does not require auth). Valid: `cub context get` / `cub space list`. Added as an explicit assertion on target-bind (first-in-chain). Every baseline used `cub info`; every with-skill used `cub context get`.
- `cub unit set-target` takes no `--change-desc`.
- `cub target create/update` takes no `--change-desc`.
- `cub unit apply` takes no `--change-desc` (runtime op).
- `cub revision list` is the correct verb; `cub unit history` does not exist.

## Sandbox observations

Iteration 3 ran from inside the repo with `.claude/settings.local.json` loaded. Mutations executed live against the instance:
- `cub unit set-target hello-ns/hello-app k8s-eval-worker` - both "Successfully updated Unit".
- `cub unit apply hello-ns` - Successfully completed; `kubectl get ns hello` -> Active.
- `cub unit apply hello-app` - Failed (placeholder namespace) - real divergence used by verify/reconcile evals.

Baselines composed from general priors (per method), not re-executed.

## Recommendation

Wave 2 complete at 100% with-skill / 5% baseline. Proceed to Wave 3 (import skills) per PLAN.md P1.
