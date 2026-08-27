---
name: promote-release
description: 'Prepare Variant or ChangeSet promotion and reconcile what a merge withheld. Use for "promote to staging", "roll forward to prod", "which Units are behind?", partial promotion, "why was my override overwritten?", or outstanding merge conflicts. Covers variant upload/create/promote and protection. Not rollback (rollback-revision).'
phase: act
allowed-tools: []
read-capability-subset: promote-release
---

# promote-release

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. After fresh preflight and an exact source/destination/scope preview, standalone use submits one requested promotion to the host permission system; publication is a later, separate host-permission call. An external overlay may stop either step before Bash.

Promote a release forward. There are two mechanisms; pick by scope:

- **Variant spaces (space-level, preferred for the common case).** `cub variant promote <space>` reconciles a whole variant Space with the upstream Space it was cloned from — in one command. Set up with `cub variant create` (clone a Space into a variant) and, for a brand-new base, `cub variant upload` (ingest rendered manifests into a base Space).
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

`--path` and `--resource` narrow further. Applying writes the withheld value **and records the path as content that came from elsewhere**, so a later upstream change to it lands normally instead of reporting the same conflict release after release. Dismissing changes no data and leaves the protection in place. Applying is a configuration-data mutation: the Unit goes through the same Trigger pass as any other change and may pick up an ApplyGate.

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

## ChangeSet-wrapped bulk upgrade (fine-grained / cross-space)

For partial scopes or a base→fleet push that spans Spaces. Wrap any multi-Unit promotion in a ChangeSet — it locks the mutation scope, groups revisions for review, and enables set-wise head restore (`--restore Before:ChangeSet:<slug>`). It does not narrow a later Space Release or create an exact native approval selector. One Unit only: skip the ChangeSet and use the `cub-mutate` proposal path.

### Decide — preflight

Produce a concrete go / no-go. `--where` is AND-only (run one query per condition, union in the report); `cub unit list` takes at most one `--filter`.

**A. Source is proved** — promoting an unproved env ships problems forward. Read the newest immutable Release and exact Unit heads, then require a successful `verify-apply` result (or an explicitly accepted proof gap) for its ManifestDigest/controller/runtime chain:

```text
cub release get --space <app>-<source> --oci-reference latest
cub unit list --space <app>-<source> --filter <app>-home/<app>-app \
  --select "HeadRevisionNum,LastReleasedRevisionNum,TargetID,ApplyGates" -o json
```

Recompute the source EffectiveReleaseSet from `Space.ReleaseTargetID` equality. Its size must equal the Release `UnitCount`, and every effective Unit's `HeadRevisionNum` must equal the revision captured by that Release (`LastReleasedRevisionNum`) before source desired state can be called aligned with the newest ConfigHub publication. That still does not prove controller consumption or current runtime state; require the `verify-apply` chain above for that claim. Any mismatch is no-go and must be named. An untargeted base Space has no runtime proof; treat base→Variant promotion as reviewed configuration movement, not as a proved live environment. Never ignore an ApplyGate merely because a Unit is in a base.

**B. Destination needs it** — `cub unit list --space <app>-<dest> --filter platform/needs-upgrade`. Empty = nothing to promote, stop. Narrow with `--where "Slug LIKE '%-api%'"` for a subset.

**C. Diffs are expected** — per in-scope Unit: `cub unit update --patch --upgrade --dry-run -o mutations --space <app>-<dest> --unit <u>`. Flag surprises (image jumps >1 minor, unexpected limit/annotation churn).

**D. Policy + approval** — `cub space get <app>-<dest> -o jq='{AttachedFilter: .TriggerFilter.Slug, TriggerFilterID: .Space.TriggerFilterID}'`; check for lingering gates. If `vet-approvedby` / `is-approved` is set, surface who approves and how.

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

### Native gate limitation + publish

If `vet-approvedby` gates the promoted revisions, do not reproduce or propose
the non-head ChangeSet approval selector retained as
`non-head-unit-approval` in `compatibility/no-loss-inventory.v1.json`.

Installed v0.2.15 help advertises numeric, `LiveRevisionNum`, Tag, and
ChangeSet selectors; as of v0.4.0 `LiveRevisionNum` is removed and
`LastAppliedRevisionNum` is renamed `LastReleasedRevisionNum`. The exact
v0.2.21 server implementation is not available
in this checkout, so confirm the current selector with installed help and
inspect the result. Do not claim that native approval atomically bound the
earlier reviewed UnitID/RevisionID/DataHash set unless the provider operation
actually accepts and verifies those expected values.

Next hand off to `release-publish`, which computes all Units whose TargetID equals the destination Space's `ReleaseTargetID`. If that EffectiveReleaseSet contains Units outside the promoted Filter/ChangeSet, show the broadened set and ask the user to decide before submission. The current publication command shape is:

```bash
cub release publish <destination-variant-space>
```

Do not silently combine approval, promotion, and publication. Native approval is head-racy, stock promotion does not bind the pre-read Unit state, and Release publication has no expected-manifest/target precondition. In standalone mode each explicitly requested step is one separate host-permission call after a fresh preview. Only after successful promotion and publication may `verify-apply` gather immutable Release/controller/runtime proof.

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
- Standalone mutation steps: `cub variant upload/create/promote`, ChangeSet/Tag/Filter/Unit upgrade operations, and Release publication each use one exact host-permission call. Native approval is head-at-execution and stock promotion has the pre-read race above, so do not make stronger exact-artifact claims.
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
- `references/filters-and-queries.md` — `needs-upgrade`, `unapplied-changes`, `has-apply-gates`, `not-approved` recipes.
- `references/cub-cli.md` — `--where` vs `--filter` vs `--changeset`, `-` sentinel for close, and "Protection and merge conflicts".
- `references/revisions.md` — `ChangeSet:<name>`, `Before:ChangeSet:<name>`, `Tag:<name>`.
- Companion skills: `confighub-core` (home/env Space layout, one-Target-per-toolchain, config-as-data), `triggers-and-applygates` (PostClone auto-customize, approval gates), `cub-mutate` (conflict resolution), `release-publish` (fully enumerated whole-Space publication), `rollback-revision`, `verify-apply`.
- `https://docs.confighub.com/markdown/guide/variants.md`, `.../guide/advanced-merging.md`, `.../background/concepts/mutation-sources.md`, `.../background/concepts/component.md`, `.../guide/dependencies.md`.
