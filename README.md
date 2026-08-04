# confighub-skills

ConfigHub knowledge and read-only operating skills for Claude Code / agentskills.io-compatible hosts. The pack teaches, inspects, prepares exact governed proposals, and verifies evidence for Kubernetes configuration managed as data in ConfigHub. Version 0.4.0 is an **evaluation candidate**, not an activation-ready release.

## Authority status

Version **0.4.0** is intentionally **evaluation-only and knowledge/read-only**. Its activation status is `BLOCK_ACTIVATION_STATIC_ONLY`:

- no raw Bash command is auto-allowed by a skill, hook, or settings template;
- eligible metadata help/get/list/query/controller/cluster commands retain their UX through the host's ordinary explicit permission prompt (`ASK`) and the per-skill proposal subsets in [`compatibility/read-capability-subsets.v1.json`](compatibility/read-capability-subsets.v1.json); raw render and worker-log execution are excluded;
- credentials/secrets, unbounded files, plugins/exec, refresh/network flags, arbitrary functions, unknown flags, and mutations are excluded from any future auto-allow until a typed final-argv wrapper exists;
- skills still preserve and teach those operational jobs, but emit exact proposals ending in `ASK`/`BLOCK`; and
- no trusted external mutation-approval broker is integrated (`NOT_INTEGRATED`). A chat confirmation, local flag/file, or ConfigHub revision approval is not execution authorization.

This is a deliberate authority reduction, not feature deletion. The typed disposition inventory at [`compatibility/no-loss-inventory.v1.json`](compatibility/no-loss-inventory.v1.json) records every current skill, ordinary-language trigger family, capability, current eval, and explicit legacy alias, including migrated and versioned-legacy jobs. `release-publish` is the canonical current skill. Both the deprecated `/confighub-skills:cub-apply` slash command and a direct no-tools `cub-apply` Skill identity stub remain observable for 0.4.x and route the unchanged intent to `release-publish`; its apply/deploy and cancel-inflight jobs remain visible, while `verify-apply` remains a distinct proof skill.

## Current delivery model

```text
Component
  ├─ source/base Space
  └─ Variant Space
       ├─ Space.ReleaseTargetID -> OCI Target
       ├─ Units whose TargetID matches ReleaseTargetID
       └─ immutable Space Release -> Argo CD / Flux -> Kubernetes
```

`cub release publish <space>` captures the **EffectiveReleaseSet**: Units in that Space whose `TargetID` equals `Space.ReleaseTargetID`. It has no Unit, Filter, ChangeSet, or cross-Space selector. A narrower “apply this Unit” request is preserved as a job, but the skill must disclose the whole-Space expansion and obtain a new approval subject.

`--revision <tag>` is a mutable selector, not an immutable pin: the server chooses the highest Revision carrying that TagID at execution, without an expected tag-mapping CAS. Omitting `--revision` re-resolves heads and also creates `release-<ReleaseNum>`, attaching that TagID to every bundled Revision. Both effects belong in the proposal subject; neither form is authoritative in this candidate.

The current Release path supports an OCI release Target. ConfigHub v0.2.11 has sunset bridge/per-Unit deploy verbs; that and earlier direct ConfigHub-provider delivery are retained as `VERSIONED_LEGACY/BLOCK`, never as current executable paths.

ConfigHub's native `cub unit approve` operation is preserved with its exact v0.2.11 limitation: only omitted/`HeadRevisionNum` is accepted, it approves the head at execution time, and it has no expected RevisionID/DataHash CAS. It may satisfy `vet-approvedby`, but it is not exact reviewed-artifact approval and is distinct from external authorization to execute approval, promotion, or publication.

That approval limitation is not a claim that Unit mutation lacks CAS. `unit_update.go` can transactionally compare caller-supplied `HeadRevisionNum` plus `DataHash`/`ContentHash`, and raw patch entries can carry them. The missing piece is a protected companion/catalog action that binds the reviewed per-Unit values through final execution and receipt. Stock restore/function/variant-promotion convenience paths do not prove that binding, so authoritative Unit changes return `APPROVED_STATE_CAS_NOT_INTEGRATED`. Release publication has a separate provider-CAS gap.

Historical Release proof has two explicit retention boundaries. Membership comes from a governed receipt cross-checked against `Revision.Releases`, not `UnitCount` or today's target members. The actual Target is committed inside the OCI manifest's `com.confighub.target.id` annotation, but that manifest is not exposed by the public Release object, so a trusted digest-matching manifest receipt is required. Permanent `release delete` bypasses withdrawal and DestroyGates in v0.2.11; Pilot must never treat it as a safe shortcut.

## Exact reviewed profile

The static compatibility baseline is:

- cub client v0.2.11, commit `683dce12c2f26ad151aa9e5763e60b0ac66172a4`, binary SHA-256 `0729618f9a6c22dd646e2ef003cc5103206e9fc2c5abdae1c2b444b1f0534553`; this exact local binary is **not authenticated as an official release asset** because Go metadata says `vcs.modified=true` and module `(devel)`, signing is ad hoc with no team identity, and no package-manager receipt/release checksum was found;
- ConfigHub server v0.2.11, commit `8cb9f6b4925670658850c8c99357f34fb11a51ad`; and
- cub helm add-on 0.1.0, commit `ce1b62faa92ec045d96b0e938bf289f83501fd17`.

See [`compatibility/current-profile.v1.json`](compatibility/current-profile.v1.json). Its status is `BLOCK_ACTIVATION_STATIC_ONLY`: static validation does not prove behavioral no-loss, final-argv policy, provider CAS, mutation authority, or live delivery. The former v0.2.10/v0.2.11 tuple is explicitly unselected/blocked. Tagged publication is not immutable selection: tag-to-Revision mappings can move, and the server resolves the highest matching Revision at execution. Missing-tag behavior also remains fail-closed because installed v0.2.11 client help and reviewed server source disagree.

## Evaluate without activation

```bash
./tools/validate-current-surface
./tools/check-installed-permission-state --json
```

Do **not** install, enable, or activate this candidate as an authoritative companion. The commands above inspect the checked-out source and current Claude plugin state without changing it. Installation/activation instructions return only after the status is no longer `BLOCK_ACTIVATION_STATIC_ONLY`, an external trusted verifier authenticates the protected commit/package/CODEOWNER record, and the behavioral permission/trigger gates pass.

`check-installed-permission-state` parses effective user, project, local, known managed, and explicitly supplied managed settings; permission modes/rules; plugin enablement; the installed plugin tree digest; and an optional Claude stream-json JSONL trace. Trace JSON is duplicate-key rejecting and version-bound to the current Claude 2.1.212 modes (`acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`) and known result subtypes; future/unknown values fail closed. Permission denials, error results, inconsistent `subtype`/`is_error`, unsafe modes, skip-auto, allow rules, or an unbound installed digest are explicit blockers. Even a clean-success trace remains blocked until a deterministic final-argv deny boundary exists.

Prerequisites depend on the read/evidence path:

- `cub` on PATH with `cub auth status` succeeding;
- `kubectl` for read-only runtime proof;
- `argocd` and/or `flux` for read-only controller proof; and
- cub helm add-on 0.1.0 for the reviewed Helm onboarding surface.

Do not infer compatibility from version strings alone when the installed commits differ from the profile.

## Skills (15 canonical IDs + one compatibility stub)

| Skill | Preserved job |
| --- | --- |
| `confighub-core` | orientation, vocabulary, topology, config-as-data, routing |
| `kubernetes-resources` | author a governed Kubernetes resource proposal |
| `app-config` | AppConfig → ConfigMap proposal via Upsert/render-configmap |
| `cub-query` | ConfigHub fleet and single-workload reads |
| `cub-mutate` | surgical/bulk Unit mutation proposal and ChangeSet grouping |
| `triggers-and-applygates` | policy, gates/warnings, native revision approval |
| `skill-examples-bootstrap` | playground proposal and walkthrough |
| `worker-bootstrap` | built-in server-worker proposal and external-worker diagnosis |
| `target-bind` | OCI Target + `ReleaseTargetID` + Unit membership proposal |
| `release-publish` | advisory whole-Space Release/read/withdraw/delete subject with no silent broadening and explicit provider-CAS gap |
| `verify-apply` | immutable Release → controller → runtime proof |
| `import` | Helm/Kustomize Component/Variant onboarding proposal |
| `promote-release` | Variant and ChangeSet promotion preflight/proposal |
| `rollback-revision` | head-moving restore plus new Release proposal |
| `incident-management` | read-only incident orchestration and governed handoffs |

`cub-apply` is the sixteenth directory only because direct historical Skill invocation must remain observable for one release. It grants no tools, has no operational eval surface, and routes to `release-publish`; it is not a second implementation.

## Helm and Kustomize onboarding

Current `cub helm install <release-name> <chart-ref>` creates `<component>-helm` (HelmSource) and `<component>-base` (untargeted base) Spaces, with one Unit per chart template file. Deployment is `cub variant create <variant> <component>-base --target <space>/<target> --namespace <ns>`, followed by an exact Space Release proposal. The reviewed command has no `--space` or `--update-crds` flag.

Helm/Kustomize rendering is not currently a read capability. The version-bound static checker inventories a canonical local tree, rejects duplicate YAML keys/symlinks/remotes/plugins, traverses the reviewed Kustomize v0.21.1 file-bearing fields, blocks Helm `lookup`/`tpl`, and requires unpacked vendored subcharts rather than opaque archives. Unknown Kustomize source-bearing forms fail closed. Its success status explicitly says render is still blocked: it neither creates a trusted digest receipt nor enforces renderer network/output/resource bounds. The required digest-pinned, network-off, read-only, byte/resource-capped wrapper and receipt are not integrated. A separately governed upload may later consume exactly that receipt, normally with per-resource granularity. Publication still requires a verified controller binding; otherwise return `CONTROLLER_BINDING_UNPROVEN`.

Worker log text is likewise excluded from bounded evidence. `cub worker logs` is slug-only rather than SpaceID/WorkerID-bound and scans the entire file even with `--tail`; it has no byte ceiling or secret redaction. External worker logs remain `WORKER_LOG_EVIDENCE_BLOCK` until a protected identity-bound, byte-capped, redacting wrapper exists.

## Repository layout

```text
.claude-plugin/                 plugin/marketplace manifests
.claude/settings...example     read-only evaluation permissions only
commands/                      one-release deprecated cub-apply slash-command shim
compatibility/                 exact profile + typed no-loss/semantic/artifact inventories
hooks/                         routing reminder only; no Bash permission hook
references/                    shared operating knowledge
skills/                        15 canonical skills/eval fixtures + no-tools cub-apply identity stub
tools/                         drift, policy, installed-state, stream/frontmatter, and compatibility validators
```

## Validation

```bash
./tools/validate-current-surface
```

The validator checks the exact 15 canonical skills plus the no-tools compatibility identity, typed trigger/eval/capability dispositions, full YAML frontmatter, local semantic drift sentinels, independent adversarial policy tests, effective Claude settings/plugin state, explicit stream-json JSONL traces, exact compatibility commits, zero raw Bash autoallow, read subsets, Release/approval/CAS boundaries, historical Release proof, dirty cub provenance, worker-log exclusion, and render-source preflight blocks.

The committed fingerprints and artifact manifest are explicitly **self-renewable local drift sentinels**, not trust, review, CODEOWNER, or release authority. Local success is labeled `LOCAL_DRIFT_MATCH`. Release mode additionally requires an externally supplied protected commit, package digest, and distinct approved CODEOWNER record; the local verifier can bind their structure but still returns `BLOCK_EXTERNAL_REVIEW_AUTHENTICITY_UNVERIFIED` until a trusted GitHub verifier exists. No repository-local regeneration can emit a releasable PASS. Static success does not claim activation readiness, behavior/no-loss, mutation authority, controller convergence, or live runtime proof.

## Remaining blockers

- trusted protected-branch/commit/package/CODEOWNER verification outside this repository;
- deterministic final-argv/effect policy and exact installed-artifact binding for Claude;
- protected per-Unit approved-state action/receipt using ConfigHub's existing transactional CAS fields;
- provider-atomic Release execution preconditions and external approval broker;
- protected render and worker-log wrappers; and
- clean-profile trigger/tool-denial traces plus live controller/runtime evidence.

The stale historical `PLAN.md` was removed; Git history preserves it without exposing obsolete install/cluster startup instructions as current guidance.
