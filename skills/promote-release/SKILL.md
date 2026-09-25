---
name: promote-release
description: 'Prepare Variant, ChangeOrder, or ChangeSet promotion, record and require approvals, and reconcile what a merge withheld. Use for "promote to staging", "roll forward to prod", "advance this change", "approve this change", "require approval", "which Units are behind?", partial promotion, or merge conflicts. Covers variant promote/approve, ChangeWorkflow, ChangeOrder, protection. Not rollback (rollback-revision).'
phase: act
allowed-tools: []
read-capability-subset: promote-release
---

# promote-release

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. After fresh preflight and an exact source/destination/scope preview, standalone use submits one requested promotion to the host permission system; publication is a later, separate host-permission call. An external overlay may stop either step before Bash.

Promote a release forward. There are two mechanisms; pick by scope:

- **Variant spaces (space-level, preferred for the common case).** `cub variant promote <space>` reconciles a whole variant Space with the upstream Space it was cloned from — in one command. Set up with `cub variant create` (clone a Space into a variant) and, for a brand-new base, `cub variant upload` (ingest rendered manifests into a base Space).
- **ChangeOrder through a ChangeWorkflow (named change, staged rollout).** `cub changeorder create --change-workflow` names one change, and `cub variant promote --change-order` moves it stage by stage through server-enforced gates, including required approvals. See [below](#changeorder-through-a-changeworkflow-named-change-staged-rollout).
- **ChangeSet-wrapped bulk upgrade (fine-grained / cross-space).** Manual `cub unit update --patch --upgrade --where …` inside a ChangeSet, when you need a partial scope, a cross-Space fleet push, or explicit ChangeSet grouping, review, and set-wise restore.

Before acting, confirm `cub auth status` succeeds (it calls the server's `/me` to verify the token; if it fails, ask the user to run `cub auth login`). Confirm verbs and flags with `cub <verb> --help` before composing — never invent flags. This skill hands off the cluster rollout to `release-publish`.

## When to use

- "Promote to staging / prod", "roll forward", "push the release", "upgrade the downstreams to match upstream".
- The decision question: "is this ready?", "which Units are behind their upstream?".
- "The promotion overwrote a value this environment had set" / "this environment didn't pick up the change" — the [protection](#what-a-merge-may-overwrite-protection) and [conflicts](#conflicts-what-the-merge-withheld) sections.
- Standing up a new environment/region/tenant variant of an existing Space.
- Pushing a shared base out to every downstream across env-Spaces.

## Do not load for

- Rollback of a prior promotion — use `rollback-revision` + `references/changesets.md` (`Before:ChangeSet:<slug>`).
- Verifying a promotion after it applied — use `verify-apply`.
- In-place single-Unit changes — use `cub-mutate`.
- Importing rendered manifests for the first time when you're not setting up a promotable base — `import` (`cub variant upload` here is for seeding a base Space you intend to clone and promote).

## Topology assumptions

The [component model](../confighub-core/SKILL.md) is the frame: a **Component** is a group of Spaces sharing a `Component` label, each Space a **variant** — a **base** (no Target, exists to be cloned) or a **deployment** (has a Target, can be released). Promotion data flows upstream → downstream along that tree, and the relationships form a tree: a variant has at most one upstream. **One Target per ToolchainType per Space.** Note the direction gotcha: an `UpgradeUnit` Link points downstream→upstream (a dependency edge), the **opposite** of data flow.

---

## What a promotion actually does

Read this before proposing one. `cub variant promote` and `cub unit update --upgrade` run the same merge engine, and two of its behaviors decide what a promotion produces and what it leaves behind.

### It walks the range, replaying functions

A merge takes the source's revisions **in order** and, where a revision was produced by a function, **re-runs that function against the target Unit** rather than copying the paths the function happened to touch upstream. Each source revision that has an effect downstream becomes a downstream revision of its own, carrying that upstream revision's change description. The variant's history then reads as the upstream's does, rather than as a series of opaque promotions.

Replay is what makes an upstream policy change reach what a variant added. If the upstream ran `set-container-probe-defaults` with one container and this variant has two because it added a metrics sidecar, replay re-runs the function here and reaches **both** containers. A rebased patch could only have carried probes for the container upstream knew about.

Not everything can be re-run. A revision that was a hand edit, an import, or another merge records no invocation; some functions are excluded (a path with a hardcoded index, a removed function, one that ran on a worker). Those steps are merged as a patch, as before, and the outcome is recorded per mutation — `Replayed`, `ReplayedNoEffect` (re-ran, matched nothing here), `NotReplayable`, `ReplayUnavailable`, `ReplayFailed`, or `Patched`:

```bash
cub mutation list --space <variant-space> <unit> --select "*" \
  -o jq='[.[] | .Mutation | {num: .MutationNum, outcome: .ReplayOutcome, why: .ReplayReason}]'
```

`ReplayedNoEffect` on a Unit you expected to change is the signal that the upstream invocation didn't generalize — see `cub-mutate` → "Write invocations that generalize".

**Two consequences for the proposal.** One promotion produces *many* revisions per Unit, so there is no single "the revision before the promotion" to restore to — always wrap a promotion in a ChangeSet (below). And an invocation replayed across several variants must select what it changes by name rather than position.

Use the installed v0.2.15 walked-range behavior and inspect conflicts after
promotion. Do not add flags that are absent from current help.

### What a merge may overwrite: protection

**Protection is opt-in, and it is the behavior most likely to surprise a user.** An ordinary downstream change — a hand edit, a function invocation, a Trigger, a needs/provides binding — leaves each path it writes as protected as it found it, and content arriving from a clone, an upgrade, or a merge is recorded unprotected. So **by default an upstream change reaches the variant even if someone here had set that path to something else.**

That is the right default for a value the variant is only carrying: a replica count copied down from the base should follow the base when the base changes its mind. It is the wrong default for a value the variant *chose*, and the variant has to say so:

```text
# As the change is made — every path it writes becomes a protected local override.
cub function set --space <variant-space> --unit <unit> --protect set-replicas 5

# Afterwards, per path, as RESOURCE_TYPE:RESOURCE_NAME:PATH.
cub unit set-protection --space <variant-space> <unit> \
  --protect "apps/v1/Deployment:<ns>/<name>:spec.replicas"

# Changed our mind — let the upstream drive it again.
cub unit set-protection --space <variant-space> <unit> \
  --unprotect "apps/v1/Deployment:<ns>/<name>:spec.replicas"
```

**Leave `--protect` off for the promotion itself.** A promotion that protected everything it wrote would turn upstream content into local overrides and block every merge after it. `--protect` belongs on the change that *decides* a value — including a `PostClone` Trigger that customizes a variant, which takes `--protect` on `cub trigger create` for exactly this reason.

Read what a Unit currently protects before proposing a promotion; the two lists are precisely the question the promotion is about to ask:

```bash
cub unit get --space <variant-space> <unit> -o mutations
```

```
Locally overridden (preserved during merges):
Resource: apps/v1/Deployment prod/backend
  ~ [Update] spec.replicas  (#2)

Eligible for upstream merges:
Resource: apps/v1/Deployment prod/backend
  + [Add] (#1)
```

Protection is stored per path, survives a restore, and is remembered across merges. Two alternatives decide the same question by rule instead — a `WhereMutation` filter over mutation history on the Link, and the merge's subtraction step (`--merge-enable-subtraction`). Each **replaces** the stored flags for the merges it applies to rather than adding to them, so don't describe them as stacking. Both are off/empty by default.

### Conflicts: what the merge withheld

A merge that cannot apply part of what it brought **does not fail, and does not apply it anyway.** It applies the rest and records what it withheld on the Unit, where it stays until dealt with. A merge replaces the outstanding set rather than adding to it, and a merge that lands cleanly clears it — so the set describes where the Unit stands now, not everything that ever happened. Within one walked range, conflicts accumulate across the hops, so nothing is erased before it has been seen.

```bash
cub unit conflicts --space <variant-space> <unit>
```

Each conflict names the resource, the path, the withheld value, and a reason:

| Reason | Meaning |
| --- | --- |
| `ProtectedPath` | The path is a protected local override, so the upstream's change to it was withheld. The common one — protection reporting itself rather than working silently. |
| `ExclusiveWithheld` / `ExclusiveCleared` | The two sides set mutually exclusive fields (a volume with one source; a deployment strategy and its options). `Withheld` = the downstream's choice stands; `Cleared` = the source's change applied and a conflicting downstream value was removed to make room, and the conflict carries it. |
| `Subtracted` / `DeleteShadowed` | The subtraction step dropped a change, or a deletion could not be applied because the target had changed underneath it. |
| `UnresolvedPath` | The path the source changed could not be located in this Unit. |
| `ReplayFailed` | A replayed function errored here. The step was patched instead; the conflict carries the function name and the error. |

Resolve by taking the upstream's value after all, or by dropping the report:

```text
# What would taking the upstream's value do here? --dry-run writes nothing.
cub unit conflicts --space <variant-space> <unit> --apply --dry-run -o mutations

# Apply everything withheld for a given reason (or all of it, with no selector).
cub unit conflicts --space <variant-space> <unit> --apply --reason ProtectedPath

# Or drop the report without changing any data.
cub unit conflicts --space <variant-space> <unit> --dismiss --reason ProtectedPath
```

`--path` and `--resource` narrow further. Applying writes the withheld value **and records the path as content that came from elsewhere**, so a later upstream change to it lands normally instead of reporting the same conflict release after release. Dismissing changes no data and leaves the protection in place. Applying is a configuration-data mutation: the Unit goes through the same Trigger pass as any other change and may pick up a ValidationError.

Conflicts are queryable, so "which variants have something outstanding?" is one command:

```bash
cub unit list --space "*" --where "Conflicts.*.Reason = 'ProtectedPath'"
```

To make outstanding conflicts **block** a publish rather than sit there, attach `vet-no-merge-conflicts` as a Trigger (see `triggers-and-applygates`).

---

## The variant lifecycle (space-level)

### 1. Seed a base Space — `cub variant upload`

When a protected renderer has already produced a digest-addressed, byte/resource-bounded manifest plus trusted source-closure receipt, you may prepare an upload for exactly that local artifact. This command does **not** render — it stores what you give it. Do not invoke a renderer or accept remote/unpinned/plugin/exec/unbounded input here; route source inspection to `import` and stop while its bounded render wrapper is absent.

```bash
cub variant upload \
  --component web --variant base \
  --granularity per-resource \
  --target web-base/cluster <receipt-bound-local-manifest>
```

Never combine rendering and mutation in a shell pipeline. Bind the exact local artifact digest and trusted render receipt into the upload proposal; changing either requires new review.

- `--component` and `--variant` are **required** and become the well-known `Component` / `Variant` Space labels; `--environment` / `--region` / `--layer` / `--owner` set the rest. The Space slug comes from `--space-pattern` (default `template:{{.Labels.Component}}-{{.Labels.Variant}}`) or explicit `--space`. The Space is created if missing.
- `--granularity per-resource` = one Unit per resource (matches the one-resource-per-unit doctrine). The default `minimal` packs everything into one Unit with CRDs and each AppConfig file split out — fine for a quick start, but prefer `per-resource` for ongoing management.
- `--target` binds the created Units and stamps the Space's `TargetID` annotation (the one-Target-per-Space convention).
- `--namespace` synthesizes a Namespace if absent. Links between Units are inferred from references/selectors/CRD relationships; reported cycles are broken at the weakest edge.
- **Rendered Secrets are never uploaded** — apply them out-of-band via a SecretStore.
- **Re-uploading is a merge, not a replace.** Running the same command again against a Space it already populated 3-way merges each Unit against the last upload: unchanged Units are left alone, changed ones merged, new resources become new Units, and the whole re-upload is recorded in a ChangeSet so it can be rolled back with the `--restore Before:ChangeSet:<slug>` command printed at the end. A change made in ConfigHub after the first upload survives that merge **only if the path is protected** — the rendered source is otherwise authoritative and the next upload puts its own value back:

  ```bash
  cub function set --space <base-space> --unit <unit> --protect set-replicas 5
  ```

  That is usually what you want for a Space whose content is generated elsewhere. If the same path needs protecting after every render, the value belongs in the source instead.
- `--granularity` and `--namespace` are recorded on the Space and must be repeated on a re-upload; an upload with different values is refused rather than silently replacing the Space's Units. `--prune` empties Units the input no longer produces (nothing is ever deleted); Units guarded by a DestroyGate refuse.
- `--dry-run` reports what would be created, updated, or emptied, including the per-field merge as the server would resolve it.

### 2. Clone a variant — `cub variant create`

Clone the base (or any upstream) Space and all its Units into a new downstream Space, linked upstream so it can be promoted later.

```bash
cub variant create prod web-base \
  --space-pattern "template:{{.Labels.Component}}-{{.Labels.Variant}}" \
  --environment Prod --region us-east2 \
  --target web-prod/cluster \
  --namespace web-prod \
  --unit-delete-gate prod-critical --unit-destroy-gate prod-critical
```

- First arg is the **variant name** (becomes the `Variant` label); second is the **upstream Space**. New Space labels inherit from upstream with `Variant` overridden; `--environment` / `--region` / `--variant-labels` adjust the rest.
- Copies the upstream Space's `WhereTrigger`, `TriggerFilterID`, Permissions, and DeleteGates, and stamps an `UpstreamSpaceID` annotation (this is what `cub variant promote` reads later — only Spaces made by `cub variant create` are promotable).
- `--target` retargets cloned Units and records the target annotation; for an OCI Target it also sets the new Space's `ReleaseTargetID`, which `cub release publish` requires. `--namespace` runs `set-namespace` on cloned Kubernetes/YAML Units, replacing a `confighubplaceholder` namespace from the base.
- **Auto-customize on clone:** define `PostClone` Triggers and select them via the upstream Space's `WhereTrigger` / `TriggerFilterID` so they're copied down and run during the clone. Trigger args can read Space metadata in Go templates, e.g. `template:{{.SpaceLabels.Region}}` or `template:{{.SpaceAnnotations.host}}` (set the latter with `--space-annotation`). See `triggers-and-applygates`. A PostClone Trigger *decides* a value the variant then owns, so it is the one Trigger that usually wants `cub trigger create --protect` — otherwise the next promotion overwrites what it set.
- `--unit-delete-gate` / `--unit-destroy-gate` protect a prod variant's Units; `--space-delete-gate` protects the Space. `--wait` (default true) waits for the cloned Units' Triggers.

### 3. Promote a variant — `cub variant promote`

Reconcile a variant Space with its recorded upstream, in one command. Three steps run server-side: (1) **upgrade** every Unit whose upstream advanced (`UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum`), merging upstream changes; (2) **clone** any Units added to the upstream since the variant was created/last promoted; (3) **copy** the new Units' non-`UpgradeUnit` links, retargeting intra-Space endpoints to their downstream copies. It waits for Triggers.

```bash
# Preview first — units that would upgrade (with the diff) and units that would be added.
cub variant promote web-prod --dry-run -o mutations
```

After the user requests the previewed scope, submit the promotion separately:

```bash
cub variant promote web-prod \
  --changeset web-home/release-2024-06 \
  --change-desc 'Promote web to prod'
```

**Always pass `--changeset`.** The promotion walks the range and records one
revision per upstream revision that had an effect, so `--restore <n>` has
nothing meaningful to name; `--restore Before:ChangeSet:<slug>` across the
Space is the set-wise undo. Installed v0.2.15 help supports `--changeset`,
`--change-desc`, and `--dry-run`; use only flags present in that help.

After promoting, check what the merge withheld before calling it done:

```text
cub unit list --space <variant-space> --where "Conflicts.*.Reason = 'ProtectedPath'"
cub unit conflicts --space <variant-space> <unit>
```

Then hand off to `release-publish`. A ChangeSet remains grouping/rollback evidence; it is not a selector on `cub release publish`. `release-publish` recomputes the complete destination EffectiveReleaseSet and asks again if the promotion scope was narrower.

**Use the manual ChangeSet flow below instead when** you need to promote only a subset of a Space, push a shared base across *many* Spaces at once, or want explicit ChangeSet open/close/review/set-wise-restore control beyond what `--changeset` on `variant promote` gives.

**Pre-read race.** ConfigHub's update provider has a real transactional primitive: caller-supplied `HeadRevisionNum` plus `DataHash` can be compared inside the update transaction, and raw patch bodies can carry the values. Stock `cub variant promote` does not prove that the reviewed per-Unit expected state was bound into its final request. Revalidate immediately before the one standalone promotion call, disclose the race, and do not claim exact reviewed-state binding. This is not evidence that the server lacks Unit CAS.

---

## ChangeOrder through a ChangeWorkflow (named change, staged rollout)

Use this when one named change has to move base → dev → staging → prod in order, with gates between stages, or when the same operation (an image tag bump) has to run in every variant. Confirm flags with `cub changeworkflow --help`, `cub changeorder create --help`, and `cub variant promote --help`.

- **ChangeWorkflow** is an entity in its own Space (never a base Space, or `cub variant create` clones it). `Stages` each select Spaces with `WhereSpace`; the server appends the ChangeOrder's `Component`, so a `WhereSpace` naming `Labels.Component` is refused. A Stage's `Prerequisites` are entry gates evaluated over **every Space of the Stage ahead**, so the first Stage's never run. Built-in: `Validated` (no ValidationErrors on the revision the change arrived at), `Released`, `Healthy`. `CustomPrerequisites` are named `cel:` expressions over `Space`, `ChangeOrder`, and `Release`. `AttestationPrerequisites` require approvals ([below](#approvals-are-attestations)). `ReleasePrerequisites` gate a publish for the ChangeOrder in the Stage's own Spaces and may name only attestation prerequisites. `Final.Prerequisites` decide when the rollout reads as `Completed`.
- **ChangeOrder** names the change and lives in the base Space. `--change-workflow` copies the workflow's definition onto it at creation; editing the workflow later does not change a rollout already under way. Where it is headed is recorded as `InScopeSpaceIDs`: the component's Spaces (with a workflow), an explicit `--in-scope-space` list, or a server-evaluated `--where-space-field` / `--space-filter` selection that `cub changeorder update --refresh-spaces` re-evaluates. For a link-following ChangeOrder, every Space between the base and a Space in scope must be in scope, or creation is refused.
- **`--update-type Invoke`** makes the change one Invocation run in each Space (`--invocation`, `--param`, `--where-unit`), fixed at creation, so every variant gets the same change. Use it for routine rollouts such as tag bumps; nothing is merged or cloned, and a Unit added to a Space later reads as not having the change.

```text
cub changeworkflow create --space <app>-workflows <workflow> --filename <workflow.yaml>
cub changeorder create --space <app>-base <change> --description '<summary>' \
  --change-workflow <app>-workflows/<workflow>
cub variant promote --change-order <app>-base/<change> --target-stage <stage> --dry-run
cub variant promote --change-order <app>-base/<change> --target-stage <stage>
cub release publish --revision ChangeOrder:<app>-base/<change> <stage-space>
cub changeorder get --space <app>-base <change>
```

Each line is its own host-permission call; the `get` and `--dry-run` are reads. Without `--target-stage`, `--change-order` advances to the next stage it has not reached. The server enforces the gates for every client, and a dry run into a gated Stage is refused with the same message as the real promotion, naming each failing prerequisite and the Space that fails it — use that as the preflight. `--force --force-reason '<reason>'` promotes past failing gates and is recorded in the ChangeOrder's `PromotionOverrides`; propose it only when the user explicitly asks to override, and name the gates it skips. `cub unit update --upgrade --change-order` is an ungated single-Unit repair path, not a promotion; do not use it to get around a gate.

Read progress from `cub changeorder get`: `State` (`New`, `InProgress`, `Resolved`, `Released`, `Aborted`, `Restored`, `RestoreReleased`) is derived on read; `Stage` is recorded by the server and becomes `Completed` once `Final` holds. Undo is `cub changeorder update --aborted-reason '<why>'` followed by `cub variant demote <space> --change-order <app>-base/<change>` per Space, then a separate publish.

## Approvals are Attestations

An approval is an **Attestation** of type `Approval`: an immutable record, in one Space, that a user approved (`Pass`) or rejected (`Fail`) specific Revisions. It is not a Trigger and never appears in ValidationErrors. A ChangeWorkflow requires approvals through `AttestationPrerequisites` (`Count`, `FromUserIDs`, `MaxAge`, `AllowAuthors`, `IgnoreFail`); they are evaluated when a promotion or a publish for the ChangeOrder is attempted.

```text
cub variant approve --change-order <app>-base/<change> --stage <stage> --dry-run
cub variant approve --change-order <app>-base/<change> --stage <stage> --note '<reason>'
cub variant approve <space> --change-order <app>-base/<change> --reject --note '<reason>'
cub attestation list --space <space>
cub attestation revoke <attestation-id> --note '<reason>'
```

What an approval binds, and what it does not:

- **Exact subjects.** The response names each covered Unit and RevisionNum, and skips Units with no matching revision rather than covering some other one. Report those subjects back; they are the approval.
- **Selection is resolved at execution.** With `--change-order`, the revisions are the ones the ChangeOrder's server-owned end Tag marks, which `cub unit tag` cannot move. Without it, the default is each Unit's head at execution time, so a head that moves between review and the call is what gets approved: prefer `--change-order`, or a `--revision` Tag/ChangeSet selector, and compare the covered revisions with what was reviewed.
- **Content, per Unit.** A later revision of the same Unit with the same `DataHash` stays covered; any content change is unapproved. Coverage never crosses Units or variants.
- **Entry gates read the Stage ahead.** "prod requires two approvals" is evaluated over the revisions the change arrived at in staging, so approve with `--stage staging`. `ReleasePrerequisites` read the revisions a publish bundles, inside the publish transaction, so they bind to exactly what ships.
- **Authors do not count** by default: anyone who wrote a revision of the change in that Space, including whoever promoted it there. Host permission to run `cub variant approve` records a claim; it does not satisfy a requirement that excludes the caller or names other users. Never suggest self-approval or `AllowAuthors` to get past a gate.

Revoking records a new Attestation; nothing is edited or deleted. `cub attestation create --type <Type>` records other claims, such as a `ChangeRecord` with `--claim servicenow.com/change=<id>`, which a workflow can require the same way.

---

## ChangeSet-wrapped bulk upgrade (fine-grained / cross-space)

For partial scopes or a base→fleet push that spans Spaces. Wrap any multi-Unit promotion in a ChangeSet — it locks the mutation scope, groups revisions for review, and enables set-wise head restore (`--restore Before:ChangeSet:<slug>`). It does not narrow a later Space Release or create an exact native approval selector. One Unit only: skip the ChangeSet and use the `cub-mutate` proposal path.

### Decide — preflight

Produce a concrete go / no-go. `--where` is AND-only (run one query per condition, union in the report); `cub unit list` takes at most one `--filter`.

**A. Source is proved** — promoting an unproved env ships problems forward. Read the newest immutable Release and exact Unit heads, then require a successful `verify-apply` result (or an explicitly accepted proof gap) for its ManifestDigest/controller/runtime chain:

```text
cub release get --space <app>-<source> --oci-reference latest
cub unit list --space <app>-<source> --filter <app>-home/<app>-app \
  --select "HeadRevisionNum,LastReleasedRevisionNum,TargetID,ValidationErrors" -o json
```

Recompute the source EffectiveReleaseSet from `Space.ReleaseTargetID` equality. Its size must equal the Release `UnitCount`, and every effective Unit's `HeadRevisionNum` must equal the revision captured by that Release (`LastReleasedRevisionNum`) before source desired state can be called aligned with the newest ConfigHub publication. That still does not prove controller consumption or current runtime state; require the `verify-apply` chain above for that claim. Any mismatch is no-go and must be named. An untargeted base Space has no runtime proof; treat base→Variant promotion as reviewed configuration movement, not as a proved live environment. Never ignore a ValidationError merely because a Unit is in a base.

**B. Destination needs it** — `cub unit list --space <app>-<dest> --filter platform/needs-upgrade`. Empty = nothing to promote, stop. Narrow with `--where "Slug LIKE '%-api%'"` for a subset.

**C. Diffs are expected** — per in-scope Unit: `cub unit update --patch --upgrade --dry-run -o mutations --space <app>-<dest> --unit <u>`. Flag surprises (image jumps >1 minor, unexpected limit/annotation churn).

**D. Policy + approval** — `cub space get <app>-<dest> -o jq='{AttachedFilter: .TriggerFilter.Slug, TriggerFilterID: .Space.TriggerFilterID}'`; check for lingering gates. If the change is a ChangeOrder under a ChangeWorkflow, a `cub variant promote --change-order ... --dry-run` names any approval the next Stage still needs; surface who may approve and how ([Approvals are Attestations](#approvals-are-attestations)).

**E. Upstream linkage matches intent** — `cub unit tree --space <app>-<dest>`; `cub link list --space <app>-<dest> --where "UpdateType = 'UpgradeUnit'"`. If a Unit points at an unexpected upstream, the promotion pulls from there — stop and confirm.

Output: **Scope** (exact `--space`/`--filter`/`--where`), **Count**, **Blockers**, **Diffs** summary, **ChangeSet proposal** (`release-<YYYYMMDD>-<shortref>` in `<app>-home`), **Approval plan**, **Recommendation** (go / go-narrowed / no-go). On no-go, route to remediation (`release-publish`, `triggers-and-applygates`) — don't promote anyway.

### Proposed sequence — open, upgrade, close

Resolve every placeholder to a literal value before submission. Submit and
verify each of these as a separate host-permission call; never send the whole
sequence as one Bash call.

```bash
cub changeset create --space <app>-home release-<YYYYMMDD>-<shortref> --description 'Prepare reviewed promotion'
```

```bash
cub unit update --patch --space <scope-space> <scope-selector> \
  --changeset <app>-home/release-<YYYYMMDD>-<shortref> --upgrade -o mutations \
  --change-desc 'Upgrade reviewed scope to upstream head'
```

```bash
cub unit update --patch --space <scope-space> <scope-selector> --changeset -
```

**Selectors:**

- **Env-by-env:** `--space <app>-<dest> --filter <app>-home/<app>-app --where "Unit.UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum"`.
- **Base → fleet (cross-space):** `--space "*" --where "Unit.UpstreamUnitID = '<base-uuid>' AND Unit.UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum"`.

> `cub unit push-upgrade` is deprecated — the selector-based `--patch --upgrade` form is its replacement.

### Approval + publish

If the destination's release needs approval, record it with `cub variant approve` as described in [Approvals are Attestations](#approvals-are-attestations), naming the revisions the ChangeSet ended on (`--revision ChangeSet:<app>-home/<slug>`) rather than each head, and report the covered revisions from its response.

Next hand off to `release-publish`, which computes all Units whose TargetID equals the destination Space's `ReleaseTargetID`. If that EffectiveReleaseSet contains Units outside the promoted Filter/ChangeSet, show the broadened set and ask the user to decide before submission. The current publication command shape is:

```bash
cub release publish <destination-variant-space>
```

Do not silently combine approval, promotion, and publication. An approval by head resolves at execution, stock promotion does not bind the pre-read Unit state, and Release publication has no expected-manifest/target precondition. In standalone mode each explicitly requested step is one separate host-permission call after a fresh preview. Only after successful promotion and publication may `verify-apply` gather immutable Release/controller/runtime proof.

## Rollback

`cub variant promote` and the ChangeSet flow both roll back by moving heads back, followed by a separately reviewed Space publication:

```bash
cub unit update --patch --space <SCOPE_SPACE> <SCOPE_SELECTOR> \
  --restore 'Before:ChangeSet:<app>-home/<changeset-slug>' \
  --change-desc 'Rollback reviewed ChangeSet'
```

After verifying the restore, the user may separately request publication:

```bash
cub release publish <destination-variant-space>
```

Full detail: `rollback-revision` + `references/changesets.md`.

## Tool boundary

- Host permission: read-only preflight/evidence in this skill's declared capability subset; the pack preapproves no Bash call.
- Standalone mutation steps: `cub variant upload/create/promote/approve/demote`, ChangeWorkflow/ChangeOrder/ChangeSet/Tag/Filter/Unit upgrade operations, Attestation writes, and Release publication each use one exact host-permission call. Stock promotion has the pre-read race above, and an approval without `--change-order` or a `--revision` selector resolves each head at execution, so do not make stronger exact-artifact claims.
- Not allowed: retired per-Unit runtime delivery, `kubectl apply`, or controller mutation. Hand publication to `release-publish`; merge-conflict changes go through `cub-mutate`. An external governance overlay may impose additional restrictions.

## Stop conditions

- `cub variant promote` on a Space with no `UpstreamSpaceID` annotation (not made by `cub variant create`) — it errors; set the variant up with `cub variant create` first.
- Preflight `no-go` — route to remediation.
- Another ChangeSet already open against the scope, or the destination scope is empty.
- The upgrade left outstanding conflicts (`cub unit conflicts <unit>` is non-empty). A merge does not fail on these — it applies the rest and reports what it withheld — so check explicitly rather than reading a successful exit as a clean merge. Resolve with `cub unit conflicts --apply|--dismiss` inside the ChangeSet, re-check, then close.
- A `ReplayedNoEffect` or `ReplayFailed` outcome on a Unit the promotion was supposed to change — the upstream invocation did not generalize to this variant. Fix the invocation upstream rather than patching the variant by hand.
- User wants to skip the ChangeSet for a >1-Unit manual promotion (loses lock + grouped set-wise restore), or self-approve without the role, or upstream linkage doesn't match intent — stop and confirm.

## Verify chain

- Variant: `cub variant promote <space> --dry-run` reports zero would-upgrade / would-add after a successful promote; `cub unit list --space <space> --filter platform/needs-upgrade` is empty.
- Conflicts: `cub unit list --space <space> --where "Conflicts.*.Reason = 'ProtectedPath'"` returns nothing outstanding, or every entry is a deliberate protection the user has seen.
- Protection held: `cub unit get --space <space> <unit> -o mutations` still lists the variant's own values under **Locally overridden**.
- ChangeSet: scoped Units no longer match `platform/needs-upgrade`; `cub revision list --space <scope-space> --where "ChangeSet.Slug = '<slug>'"` shows the tagged revisions; `cub changeset get --space <app>-home <slug>` shows start+end tags (closed).

## Evidence

- `cub component open <component> --variant <variant> --print-url` — deployment graph.
- `cub space open <variant-space> --print-url` — destination Variant Space.
- `cub unit open <unit> --space <variant-space> --revisions --print-url` — promoted Unit history.

## References

- `cub variant upload --help`, `cub variant create --help`, `cub variant promote --help` — authoritative flags.
- `references/changesets.md` — lifecycle, rollback, merge/rebase.
- `references/filters-and-queries.md` — `needs-upgrade`, `unapplied-changes`, `has-validation-errors`, `approved-revisions` recipes.
- `cub changeworkflow --help`, `cub changeorder create --help`, `cub variant approve --help`, `cub attestation --help` — authoritative flags for staged rollouts and approvals.
- `references/cub-cli.md` — `--where` vs `--filter` vs `--changeset`, `-` sentinel for close, and "Protection and merge conflicts".
- `references/revisions.md` — `ChangeSet:<name>`, `Before:ChangeSet:<name>`, `Tag:<name>`.
- Companion skills: `confighub-core` (home/env Space layout, one-Target-per-toolchain, config-as-data), `triggers-and-applygates` (PostClone auto-customize, validation gates), `cub-mutate` (conflict resolution), `release-publish` (fully enumerated whole-Space publication), `rollback-revision`, `verify-apply`.
- `https://docs.confighub.com/markdown/guide/promotion.md` (ChangeWorkflows, ChangeOrders, review and approval), `.../background/entities/attestation.md`.
- `https://docs.confighub.com/markdown/guide/variants.md`, `.../guide/advanced-merging.md`, `.../background/concepts/mutation-sources.md`, `.../background/concepts/component.md`, `.../guide/dependencies.md`.
