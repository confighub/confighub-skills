# confighub-skills

Standalone ConfigHub operating skills for Claude Code / agentskills.io-compatible hosts. The pack teaches, inspects, changes, and verifies Kubernetes configuration managed as data in ConfigHub. A separately installed product may add stricter governance, but is not required. Version 0.4.1 restores the stable standalone execution contract; this checkout remains a source candidate until its release gate and publication complete.

## Install or update

Install from the ConfigHub marketplace:

Run these as two separate commands:

```bash
claude plugin marketplace add https://github.com/confighub/confighub-skills
```

```bash
claude plugin install confighub-skills@confighub
```

Update an existing installation, then restart Claude Code so the new plugin
bytes load into a fresh session:

Run these as two separate commands:

```bash
claude plugin marketplace update confighub
```

```bash
claude plugin update confighub-skills@confighub
```

`cub` must be on `PATH`, and `cub auth status` must succeed before ConfigHub
reads or writes. `kubectl`, `argocd`, and `flux` are optional read-only proof
tools for the workflows that need them. The `cub-helm` plugin is required only
for Helm onboarding.

## How commands run

- Every Skill and compatibility command keeps `allowed-tools: []`: the pack contributes zero preapprovals. It does not make tools unavailable; the host and user settings still decide whether a call is prompted, allowed, or denied.
- Reads use the host's ordinary permission flow.
- For a clear standalone change request, the owning Skill resolves and previews the exact scope, then submits one Bash call containing one mutation command to the host permission system.
- If the host denies the call, Bash is unavailable, or the session is explicitly coached, the Skill says nothing ran and only then hands the exact command to the user.
- A separately installed overlay may inject a stricter stop or approval policy before Bash. That policy is optional and external to this reusable pack.

See [How commands run](references/execution-modes.md). Credentials/secrets, unbounded files, plugin/exec loading, network-refresh side effects, arbitrary functions, and unknown flags are never candidates for silent permission. The typed disposition inventory at [`compatibility/no-loss-inventory.v1.json`](compatibility/no-loss-inventory.v1.json) records every current Skill, ordinary-language trigger family, capability, eval, and historical alias. `release-publish` is the canonical current Skill. Both the deprecated `/confighub-skills:cub-apply` slash command and direct `cub-apply` identity stub remain observable for 0.4.x and route unchanged intent to `release-publish`; `verify-apply` remains a distinct proof Skill.

## Current delivery model

```text
Component
  ├─ source/base Space
  └─ Variant Space
       ├─ Space.ReleaseTargetID -> OCI Target
       ├─ Units whose TargetID matches ReleaseTargetID
       └─ immutable Space Release -> Argo CD / Flux -> Kubernetes
```

`cub release publish <space>` captures the **EffectiveReleaseSet**: Units in that Space whose `TargetID` equals `Space.ReleaseTargetID`. It has no Unit, Filter, ChangeSet, or cross-Space selector. For a narrower “apply this Unit” request, the Skill discloses the whole-Space expansion and asks the user to decide before submission.

`--revision <tag>` is a mutable selector, not an immutable pin. Installed v0.2.15 help says it chooses the highest matching Revision and falls back to a Unit's head where the Tag is absent. Exact v0.2.21 provider source is unavailable here. Preview the mapping and documented fallback, refresh immediately before the host-permitted publish call, inspect the result, and do not claim that the earlier preview was atomically pinned.

The current Release path supports an OCI release Target. Bridge/per-Unit deploy verbs and earlier direct ConfigHub-provider delivery remain machine-recorded historical dispositions, never current executable paths.

Installed v0.2.15 `cub unit approve --help` advertises numeric, live, Tag, and ChangeSet selectors. Exact v0.2.21 server acceptance and atomic preconditions are not source-reviewed here. Confirm current help, inspect the result, and do not claim exact reviewed-artifact binding without provider evidence. Native approval remains separate from host permission for approval, promotion, or publication commands.

An older source-reviewed Unit update path could compare caller-supplied head and content fields transactionally. That finding is not projected onto v0.2.21. Stock restore/function/variant-promotion command surfaces do not prove that values inspected during preview were carried into final execution. The Skills therefore re-read immediately before a standalone call, disclose the race, and avoid stronger exact-state claims. Release publication has a separate target/member/manifest race.

Historical Release proof has two explicit retention boundaries. Membership comes from a retained receipt cross-checked against `Revision.Releases`, not `UnitCount` or today's target members. A digest-matching publication/registry receipt is required for a historical Target claim because the public Release object does not expose it. For permanent deletion, withdraw first, retain exact manifest/member/digest evidence, verify current help, and do not claim that v0.2.21 either enforces or bypasses gates without provider evidence.

## Exact reviewed profile

The current compatibility profile records:

- cub client v0.2.15, commit `3e0cad345fbcc60d4761d928f02fccb8dc5def4f`, reviewed binary SHA-256 `adc0c6cd53e24d91145eacf40947f929d041613393d4afa36e7d009520133051`; the local build is not authenticated as an official release asset because its Go metadata reports a modified development build and no package-manager receipt was found;
- ConfigHub server v0.2.21, commit `770cce6816ad8cbc7169272cbf08277eab0f0eb0`, identified at runtime; exact server source was unavailable for this review; and
- cub helm add-on 0.1.0, commit `ce1b62faa92ec045d96b0e938bf289f83501fd17` — installed as a CLI plugin from [`confighub/cub-helm`](https://github.com/confighub/cub-helm) with `cub plugin install confighub/cub-helm`; it is not part of `cub` itself.

See [`compatibility/current-profile.v1.json`](compatibility/current-profile.v1.json). Standalone commands are host-decided and the pack grants no automatic Bash permission. Static validation does not prove model behavior, provider atomicity, or live delivery. Older tuples remain historical evidence only.

## Validate the checkout

```bash
./tools/validate-current-surface
```

```bash
./tools/check-installed-permission-state --json
```

These commands inspect the checked-out source and current Claude plugin state without changing it. Local validation proves the declared surface and zero-autoallow policy, not publication provenance or live behavior. A release artifact still needs the repository's protected-commit/package/CODEOWNER attestation gate.

`check-installed-permission-state` parses effective user, project, local, known managed, and explicitly supplied managed settings; permission modes/rules; plugin enablement; the installed plugin tree digest; and an optional Claude stream-json JSONL trace. Trace JSON is duplicate-key rejecting and version-bound to the current Claude 2.1.212 modes (`acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`) and known result subtypes; future/unknown values fail closed. Invalid/error traces, unsafe modes, skip-auto, allow rules, an unsafe plugin hook, or a digest mismatch block the trusted installed state. A normal host denial or an unbound digest is reported as a claim limit instead of disabling standalone use. Raw shell text cannot justify plugin-provided automatic permission, but it does not make ordinary host-decided commands unavailable.

Prerequisites depend on the read/evidence path:

- `cub` on PATH with `cub auth status` succeeding;
- `kubectl` for read-only runtime proof;
- `argocd` and/or `flux` for read-only controller proof; and
- cub helm add-on 0.1.0 for the reviewed Helm onboarding surface, installed via `cub plugin install confighub/cub-helm`.

Do not infer compatibility from version strings alone when the installed commits differ from the profile.

## Skills (15 canonical IDs + one compatibility stub)

| Skill | Preserved job |
| --- | --- |
| `confighub-core` | orientation, vocabulary, topology, config-as-data, routing |
| `kubernetes-resources` | author and create reviewed Kubernetes resources |
| `app-config` | AppConfig → ConfigMap via Upsert/render-configmap |
| `cub-query` | ConfigHub fleet and single-workload reads |
| `cub-mutate` | surgical/bulk Unit mutation and ChangeSet grouping |
| `triggers-and-applygates` | policy, gates/warnings, native revision approval |
| `skill-examples-bootstrap` | playground setup and walkthrough |
| `worker-bootstrap` | built-in server-worker setup and external-worker diagnosis |
| `target-bind` | OCI Target + `ReleaseTargetID` + Unit membership |
| `release-publish` | whole-Space Release/read/withdraw/delete with no silent broadening and explicit provider-race disclosure |
| `verify-apply` | immutable Release → controller → runtime proof |
| `import` | Helm/Kustomize Component/Variant onboarding |
| `promote-release` | Variant and ChangeSet promotion preflight/execution |
| `rollback-revision` | head-moving restore plus separate new Release |
| `incident-management` | incident orchestration and scoped mitigation handoffs |

`cub-apply` is the sixteenth directory only because direct historical Skill invocation must remain observable for one release. It grants no tools, has no operational eval surface, and routes to `release-publish`; it is not a second implementation.

## Helm and Kustomize onboarding

The `cub-helm` plugin's `cub helm install <release-name> <chart-ref>` creates `<component>-helm` (HelmSource) and `<component>-base` (untargeted base) Spaces, with one Unit per chart template file. Deployment is `cub variant create <variant> <component>-base --target <space>/<target> --namespace <ns>`, followed by a separately scoped Space Release. The reviewed command has no `--space` or `--update-crds` flag.

Helm/Kustomize rendering is not currently a bounded read capability. The version-bound static checker inventories a canonical local tree, rejects duplicate YAML keys/symlinks/remotes/plugins, traverses the reviewed Kustomize v0.21.1 file-bearing fields, blocks Helm `lookup`/`tpl`, and requires unpacked vendored subcharts rather than opaque archives. Unknown Kustomize source-bearing forms fail closed. A safe render still needs a digest-pinned, network-off, read-only, byte/resource-capped wrapper and receipt. A separately reviewed upload may consume exactly that receipt, normally with per-resource granularity. Publication also needs a verified controller binding; otherwise say that controller delivery remains unproven.

Worker log text is likewise excluded from bounded evidence. `cub worker logs` is slug-only rather than SpaceID/WorkerID-bound and scans the entire file even with `--tail`; it has no byte ceiling or secret redaction. Do not treat external worker logs as trusted evidence until an identity-bound, byte-capped, redacting wrapper exists.

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

The committed fingerprints and artifact manifest are self-renewable local drift sentinels, not trust, review, CODEOWNER, or release authority. Release mode additionally requires an externally supplied protected commit, package digest, and distinct approved CODEOWNER record. Static success does not prove behavioral selection, a particular host permission outcome, provider atomicity, controller convergence, or live runtime state.

## Stronger proof not established locally

- trusted protected-branch/commit/package/CODEOWNER verification outside this repository;
- structured final-argv/effect policy for any future automatic Bash permission;
- protected per-Unit approved-state action/receipt using ConfigHub's existing transactional CAS fields;
- provider-atomic Release execution preconditions for stronger preview-to-publish binding;
- protected render and worker-log wrappers; and
- clean-profile host allow/deny/overlay behavior traces plus live controller/runtime evidence.

These gaps limit stronger provenance, automatic-permission, and live-proof
claims. They do not make ordinary standalone reads or explicitly requested,
host-decided ConfigHub changes unavailable.

The stale historical `PLAN.md` was removed; Git history preserves it without exposing obsolete install/cluster startup instructions as current guidance.
