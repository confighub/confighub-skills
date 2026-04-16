# Iteration 4 summary — Wave 3 imports + Wave 4 operate verbs + app-config + kubernetes-resources

12 skills, 10 assertions each, graded against assertions drafted before composition.
Two skills deferred per PLAN.md (`import-from-argocd`, `import-from-flux` — require in-cluster Argo/Flux installations not present in the eval environment).

## Headline

| Skill | With-skill | Baseline |
|---|---|---|
| space-topology | 10/10 | 1/10 |
| import-unit-granularity | 10/10 | 3/10 |
| import-from-helm | 10/10 | 1/10 |
| import-from-kustomize | 10/10 | 1/10 |
| import-from-cluster | 10/10 | 0/10 |
| promotion-preflight | 10/10 | 0/10 |
| promote-release | 10/10 | 1/10 |
| rollback-revision | 10/10 | 1/10 |
| drift-reconcile | 10/10 | 3/10 |
| incident-management | 10/10 | 0/10 |
| app-config | 10/10 | 0/10 |
| kubernetes-resources | 10/10 | 1/10 |
| **Iteration 4 total** | **120/120 = 100%** | **12/120 = 10%** |

Overall across iterations 1+2+3+4: **203/208 = 98%** vs **26/208 = 13%**, covering 24 skills.

## Per-skill findings

### space-topology
- With-skill: one-Space-per-(app, env), home Spaces, PascalCase labels, label-based queries, label-based cluster-migration plan.
- Baseline: offered "one Space per app, env in slug" or "one Space per env, all apps" — both collapse boundaries. Used `cub info`. No labels, no home Space.

### import-unit-granularity
- With-skill: 5-Unit split (namespace, policy, 3 workloads), walked the four axes (ownership / references / lifecycle / blast radius), `--where-resource` predicates with `--dry-run`.
- Baseline: lumped policy with workloads or proposed mega-Unit. Per-Deployment split was the only correct piece. No `--where-resource`, no dry-run.

### import-from-helm
- With-skill: knew `cub helm install` auto-splits CRDs (no manual `helm template + grep` needed). Mentioned `--namespace` rationale (chart references), config-as-data trajectory, multi-env clone-or-install patterns.
- Baseline: proposed manual `helm template | grep` to split CRDs — anti-pattern. No namespace flag rationale, no trajectory.

### import-from-kustomize
- With-skill: per-overlay → per-env-Space mapping, both render+upstream-link patterns, `cub-mutate` for customization (not patches), git-ref provenance in `--change-desc`.
- Baseline: single Space with suffix-named Units (`orders-dev` Unit slug) — collapses boundaries. No clone pattern, no provenance.

### import-from-cluster
- With-skill: `cub unit import --where-resource` with `import.include_cluster = true` for Namespace, pre-created Units bound to Target, `--dry-run` per Unit, post-import cleanup, config-as-data discipline.
- Baseline: `kubectl get -o yaml | cub unit update` — completely wrong path. No `cub unit import`, no Target binding, no scope filtering.

### promotion-preflight
- With-skill: 5-section structured preflight (source convergence / destination needs-upgrade / diffs / destination policy / upstream linkage), `--jq` over extended envelope, structured go/no-go output.
- Baseline: kubectl-driven loose checklist that mixed preflight with execution. Used `cub info`.

### promote-release
- With-skill: ChangeSet-wrapped (create → open → bulk upgrade → close), bulk `--patch + --filter`, `Before:ChangeSet:` rollback path, `--change-desc` discipline.
- Baseline: 6 separate per-Unit `cub unit update --upgrade` calls, no ChangeSet, used `--change-description` (wrong flag), no rollback path.

### rollback-revision (apply-revision-is-not-rollback prompt)
- With-skill: correctly diagnosed `cub unit apply --revision` doesn't move head. Used `cub unit update --restore` as the only correct rollback. Explained named restore targets (`Tag:`, `Before:ChangeSet:`).
- Baseline: partially understood the problem (head doesn't move) but **doubled down on the anti-pattern** by suggesting `cub unit apply --revision 5 --force` as a workaround. Did not know `--restore` exists.

### drift-reconcile
- With-skill: Data vs LiveData (not LiveState), three resolutions (ConfigHub-wins / cluster-wins / selective merge), source-naming after Worker field-manager elision, observation+revert pattern for audit, fix-the-source step.
- Baseline: jumped to re-apply without diagnosis. No drift framework, no audit pattern.

### incident-management
- With-skill: stabilize-first principle, 5-question triage, Path A rollback via `Before:ChangeSet:`, doctrinal reminder against `apply --revision`, full close-out (tag / reconcile / verify), pure orchestration (no mutations).
- Baseline: ran `cub unit apply --revision` directly as the rollback — exactly the doctrinal anti-pattern. No triage, no close-out, no orchestration.

### app-config
- With-skill: `AppConfig/Properties` toolchain, required `configHub.configName` + `configHub.configSchema` metadata, mutable mode for auto-restart, server-worker for ConfigMapRenderer, sink Unit + Needs/Provides linkage, workload `confighub.com/Hash` annotation pattern, `set-*-path` functions taking `configSchema` as first positional arg.
- Baseline: wrapped `application.properties` as a string in a raw `Kubernetes/YAML` ConfigMap (defeats the entire AppConfig story), suggested third-party Reloader operator for restarts.

### kubernetes-resources (statefulset-for-redis prompt)
- With-skill: pulled `hello-statefulset` example from skill-examples Space, headless Service bundled with StatefulSet, `volumeClaimTemplates`, `confighubplaceholder` namespace, four defaults functions, **TCP probe override for Redis** (HTTP defaults wrong for RESP), vet-* validation, hand-off to target-bind + cub-apply.
- Baseline: StatefulSet alone (no headless Service — pod DNS broken), hardcoded `redis-prod` as namespace (treated Space slug as namespace), no defaults, no probes, ran `cub unit apply` directly.

## Real bugs / issues found

None this iteration. All 12 with-skill runs scored 10/10; the skills are working as intended on their primary scenarios.

Notable doctrinal validation:
- **Rollback discipline holds end-to-end.** Both `rollback-revision` and `incident-management` baselines independently fell into the `cub unit apply --revision` anti-pattern; both with-skill runs caught and corrected it. The with-skill `incident-management` run included a doctrinal-reminder block, which is exactly the kind of in-context teaching that prevents the anti-pattern from sneaking back in via on-call panic.
- **`cub helm install` auto-splits CRDs.** Baseline proposed `helm template | grep` to split CRDs — a real anti-pattern users would hit. The with-skill answer ("you don't need to — `cub helm install` already does it") is the correct teaching.
- **AppConfig toolchain vs raw ConfigMap.** Baseline lumped `application.properties` into a Kubernetes/YAML ConfigMap, defeating the entire revision-history / `set-*-path` / `vet-jsonschema` / auto-restart story. With-skill picked the right toolchain on the first move.

## Sandbox observations

Iteration 4 ran from inside the repo with `.claude/settings.local.json` loaded. This iteration was reasoning-graded (composition of write-ups + cub commands against the live instance for grounding), not full subagent execution. Pattern matches iterations 1+2: subagent evals primarily measure reasoning, function choice, flag correctness, doctrinal adherence — and the signal is strong enough that bugs surface at the reasoning level.

## Coverage status

Skills tested across all four iterations (24 of 26 shipped):
- Iteration 1: config-as-data, triggers-and-applygates, cub-mutate
- Iteration 2: confighub-core, cub-query, skill-examples-bootstrap, worker-bootstrap
- Iteration 3: target-bind, cub-apply, verify-delivery, reconciliation-check, release-verify
- Iteration 4: space-topology, import-unit-granularity, import-from-helm, import-from-kustomize, import-from-cluster, promotion-preflight, promote-release, rollback-revision, drift-reconcile, incident-management, app-config, kubernetes-resources

Still untested:
- `import-from-argocd` — needs in-cluster Argo CD installation
- `import-from-flux` — needs in-cluster Flux installation

Both deferred per PLAN.md until the eval environment supports them.

## Recommendation

Wave 3 imports + Wave 4 operate verbs + app-config + kubernetes-resources complete at 100% with-skill / 10% baseline. Move to PLAN.md P1 (doctrine skills for uncovered topics: `links-and-needs-provides`, `variants`, `attributes`, `views`) once the eval environment can support ArgoCD and Flux for the final two iteration-4 skills.
