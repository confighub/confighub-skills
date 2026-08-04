---
name: promote-release
description: 'Prepare Variant or ChangeSet promotion. Use for "promote to staging", "roll forward to prod", "which Units are behind?", partial promotion, or push a base across the fleet. Covers variant create/promote and exact later Release scope. Not rollback (rollback-revision).'
phase: act
allowed-tools: []
read-capability-subset: promote-release
---

# promote-release

**Authority boundary:** this companion may run read-only preflight and prepare an exact promotion or approval proposal. It must not execute create, update, approve, promote, or publish operations. The external mutation broker is `NOT_INTEGRATED`, so executable steps end in `ASK` or `BLOCK`.

Promote a release forward. There are two mechanisms; pick by scope:

- **Variant spaces (space-level, preferred for the common case).** `cub variant promote <space>` reconciles a whole variant Space with the upstream Space it was cloned from — in one command. Set up with `cub variant create` (clone a Space into a variant) and, for a brand-new base, `cub variant upload` (ingest rendered manifests into a base Space).
- **ChangeSet-wrapped bulk upgrade (fine-grained / cross-space).** Manual `cub unit update --patch --upgrade --where …` inside a ChangeSet, when you need a partial scope, a cross-Space fleet push, or explicit ChangeSet grouping, review, and set-wise restore.

Before acting, confirm `cub auth status` succeeds (it calls the server's `/me` to verify the token; if it fails, ask the user to run `cub auth login`). Confirm verbs and flags with `cub <verb> --help` before composing — never invent flags. This skill hands off the cluster rollout to `release-publish`.

## When to use

- "Promote to staging / prod", "roll forward", "push the release", "upgrade the downstreams to match upstream".
- The decision question: "is this ready?", "which Units are behind their upstream?".
- Standing up a new environment/region/tenant variant of an existing Space.
- Pushing a shared base out to every downstream across env-Spaces.

## Do not load for

- Rollback of a prior promotion — use `rollback-revision` + `references/changesets.md` (`Before:ChangeSet:<slug>`).
- Verifying a promotion after it applied — use `verify-apply`.
- In-place single-Unit changes — use `cub-mutate`.
- Importing rendered manifests for the first time when you're not setting up a promotable base — `import` (`cub variant upload` here is for seeding a base Space you intend to clone and promote).

## Topology assumptions

Promotion data flows `<source>` → `<destination>` (a parent/base Space → its variant/downstream Spaces). One Space per deployment boundary, **one Target per ToolchainType (e.g. Kubernetes/YAML) per Space** (`confighub-core`). Note the direction gotcha: an `UpgradeUnit` Link points downstream→upstream (dependency edge), the **opposite** of data flow.

---

## The variant lifecycle (space-level)

### 1. Seed a base Space — `cub variant upload`

When a protected renderer has already produced a digest-addressed, byte/resource-bounded manifest plus trusted source-closure receipt, you may prepare an upload proposal for exactly that local artifact. This command does **not** render — it stores what you give it. Do not invoke a renderer or accept remote/unpinned/plugin/exec/unbounded input here; route source inspection to `import` and return `RENDER_SOURCE_POLICY_BLOCK` while its protected render wrapper is absent.

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
- **Auto-customize on clone:** define `PostClone` Triggers and select them via the upstream Space's `WhereTrigger` / `TriggerFilterID` so they're copied down and run during the clone. Trigger args can read Space metadata in Go templates, e.g. `template:{{.SpaceLabels.Region}}` or `template:{{.SpaceAnnotations.host}}` (set the latter with `--space-annotation`). See `triggers-and-applygates`.
- `--unit-delete-gate` / `--unit-destroy-gate` protect a prod variant's Units; `--space-delete-gate` protects the Space. `--wait` (default true) waits for the cloned Units' Triggers.

### 3. Promote a variant — `cub variant promote`

Reconcile a variant Space with its recorded upstream, in one command. Three steps run server-side: (1) **upgrade** every Unit whose upstream advanced (`UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum`), merging upstream changes; (2) **clone** any Units added to the upstream since the variant was created/last promoted; (3) **copy** the new Units' non-`UpgradeUnit` links, retargeting intra-Space endpoints to their downstream copies. It waits for Triggers.

```bash
# Preview first — units that would upgrade (with the diff) and units that would be added.
cub variant promote web-prod --dry-run -o mutations

# Promote, wrapped in a ChangeSet, with a change description.
cub variant promote web-prod \
  --changeset web-home/release-2024-06 \
  --change-desc "Promote web to prod.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>"
```

Then hand off to `release-publish`. A ChangeSet remains grouping/rollback evidence; it is not a selector on `cub release publish`. `release-publish` recomputes the complete destination EffectiveReleaseSet and asks again if the promotion scope was narrower.

**Use the manual ChangeSet flow below instead when** you need to promote only a subset of a Space, push a shared base across *many* Spaces at once, or want explicit ChangeSet open/close/review/set-wise-restore control beyond what `--changeset` on `variant promote` gives.

**Approved-state CAS boundary.** ConfigHub's update provider has a real transactional primitive: caller-supplied `HeadRevisionNum` plus `DataHash`/`ContentHash` can be compared inside the update transaction, and raw patch bodies can carry the values. Stock `cub variant promote` and the current protected companion do not bind the reviewed per-Unit expected state into a digest-pinned final request/receipt. Promotion execution is therefore `APPROVED_STATE_CAS_NOT_INTEGRATED`; this is not evidence that the server lacks Unit CAS.

---

## ChangeSet-wrapped bulk upgrade (fine-grained / cross-space)

For partial scopes or a base→fleet push that spans Spaces. Wrap any multi-Unit promotion in a ChangeSet — it locks the mutation scope, groups revisions for review, and enables set-wise head restore (`--restore Before:ChangeSet:<slug>`). It does not narrow a later Space Release or create an exact native approval selector. One Unit only: skip the ChangeSet and use the `cub-mutate` proposal path.

### Decide — preflight

Produce a concrete go / no-go. `--where` is AND-only (run one query per condition, union in the report); `cub unit list` takes at most one `--filter`.

**A. Source is proved** — promoting an unproved env ships problems forward. Read the newest immutable Release and exact Unit heads, then require `verify-apply` PASS (or an explicitly accepted proof gap) for its ManifestDigest/controller/runtime chain:

```bash
cub release get --space <app>-<source> --oci-reference latest
cub unit list --space <app>-<source> --filter <app>-home/<app>-app \
  --select "HeadRevisionNum,LastAppliedRevisionNum,TargetID,ApplyGates" -o json
```

Recompute the source EffectiveReleaseSet from `Space.ReleaseTargetID` equality. Its size must equal the Release `UnitCount`, and every effective Unit's `HeadRevisionNum` must equal the revision captured by that Release (`LastAppliedRevisionNum`) before source desired state can be called aligned with the newest ConfigHub publication. That still does not prove controller consumption or current runtime state; require the `verify-apply` chain above for that claim. Any mismatch is no-go and must be named. An untargeted base Space has no runtime proof; treat base→Variant promotion as reviewed configuration movement, not as a proved live environment. Never ignore an ApplyGate merely because a Unit is in a base.

**B. Destination needs it** — `cub unit list --space <app>-<dest> --filter platform/needs-upgrade`. Empty = nothing to promote, stop. Narrow with `--where "Slug LIKE '%-api%'"` for a subset.

**C. Diffs are expected** — per in-scope Unit: `cub unit update --patch --upgrade --dry-run -o mutations --space <app>-<dest> --unit <u>`. Flag surprises (image jumps >1 minor, unexpected limit/annotation churn).

**D. Policy + approval** — `cub space get <app>-<dest> -o jq='{AttachedFilter: .TriggerFilter.Slug, TriggerFilterID: .Space.TriggerFilterID}'`; check for lingering gates. If `vet-approvedby` / `is-approved` is set, surface who approves and how.

**E. Upstream linkage matches intent** — `cub unit tree --space <app>-<dest>`; `cub link list --space <app>-<dest> --where "UpdateType = 'UpgradeUnit'"`. If a Unit points at an unexpected upstream, the promotion pulls from there — stop and confirm.

Output: **Scope** (exact `--space`/`--filter`/`--where`), **Count**, **Blockers**, **Diffs** summary, **ChangeSet proposal** (`release-<YYYYMMDD>-<shortref>` in `<app>-home`), **Approval plan**, **Recommendation** (go / go-narrowed / no-go). On no-go, route to remediation (`release-publish`, `triggers-and-applygates`) — don't promote anyway.

### Proposed sequence — open, upgrade, close

```bash
HOME_SPACE=<app>-home ; CHANGESET_REF=$HOME_SPACE/release-$(date +%Y%m%d)-<shortref>

cub changeset create --space $HOME_SPACE release-<YYYYMMDD>-<shortref> --description "<release desc>"

cub unit update --patch --space <SCOPE_SPACE> <SCOPE_SELECTOR> \
  --changeset $CHANGESET_REF --upgrade -o mutations \
  --change-desc "Upgrade to upstream head as part of <changeset>.

User prompt: <verbatim>
Clarifications: <condensed>"

cub unit update --patch --space <SCOPE_SPACE> <SCOPE_SELECTOR> --changeset -   # close
```

**Selectors:**

- **Env-by-env:** `--space <app>-<dest> --filter <app>-home/<app>-app --where "Unit.UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum"`.
- **Base → fleet (cross-space):** `--space "*" --where "Unit.UpstreamUnitID = '<base-uuid>' AND Unit.UpstreamRevisionNum < UpstreamUnit.HeadRevisionNum"`.

> `cub unit push-upgrade` is deprecated — the selector-based `--patch --upgrade` form is its replacement.

### Native gate limitation + publish

If `vet-approvedby` gates the promoted revisions, do not reproduce or propose
the non-head ChangeSet approval selector retained as
`non-head-unit-approval` in `compatibility/no-loss-inventory.v1.json`.

The reviewed server rejects every nonempty selector except `HeadRevisionNum`.
Omitted/`HeadRevisionNum` approval approves each selected Unit's head at
execution time and has no expected RevisionID/DataHash CAS. That cannot bind
the earlier reviewed ChangeSet set across a race. Return
`APPROVAL_HEAD_RACE_BLOCK`; preserve the reviewed UnitID/RevisionID/DataHash
set as evidence, not as proof of what native approval will approve. Exact
ChangeSet approval needs a server-side expected-head precondition.

Next hand off to `release-publish`, which computes all Units whose TargetID equals the destination Space's `ReleaseTargetID`. If that EffectiveReleaseSet contains Units outside the promoted Filter/ChangeSet, return `ASK` with the broadened set and create a new whole-Space review subject. The future provider-CAS-capable execution shape is:

```bash
cub release publish <destination-variant-space>
```

Do not self-approve or execute either command. Exact native approval remains head-racy, the existing Unit update CAS is not integrated into a protected approved-state action, Release provider CAS is absent, and the external broker is unavailable. The companion returns `BLOCK` after producing advisory proposals. Only after protected promotion plus provider-CAS-capable, externally authorized publication may `verify-apply` own immutable Release/controller/runtime proof.

## Rollback

`cub variant promote` and the ChangeSet flow both roll back by moving heads back, followed by a newly reviewed advisory Space Release proposal:

```bash
cub unit update --patch --space <SCOPE_SPACE> <SCOPE_SELECTOR> \
  --restore "Before:ChangeSet:$CHANGESET_REF" \
  --change-desc "Rollback <changeset>. User prompt: <verbatim>. Clarifications: <condensed>"
cub release publish <destination-variant-space>
```

Full detail: `rollback-revision` + `references/changesets.md`.

## Tool boundary

- Host-ASK: read-only preflight/evidence in this skill's declared capability subset; no raw Bash is auto-allowed.
- Proposal-only: `cub variant upload/create/promote`, ChangeSet/Tag/Filter/Unit upgrade operations, and Release publication. Native approval is `APPROVAL_HEAD_RACE_BLOCK`; promotion/update execution is `APPROVED_STATE_CAS_NOT_INTEGRATED` until the existing server CAS fields are bound through a protected action.
- Not allowed: retired per-Unit runtime delivery, `kubectl apply`, controller mutation, or any write without the external broker. Hand publication to `release-publish`; merge-conflict changes go through the `cub-mutate` proposal path.

## Stop conditions

- `cub variant promote` on a Space with no `UpstreamSpaceID` annotation (not made by `cub variant create`) — it errors; set the variant up with `cub variant create` first.
- Preflight `no-go` — route to remediation.
- Another ChangeSet already open against the scope; destination scope empty; upgrade merge leaves conflicts (`cub unit diff` shows `<<<<<<<` / non-empty `MergeConflicts`) — resolve in `cub-mutate` within the ChangeSet, re-diff, close.
- User wants to skip the ChangeSet for a >1-Unit manual promotion (loses lock + grouped set-wise restore), or self-approve without the role, or upstream linkage doesn't match intent — stop and confirm.

## Verify chain

- Variant: `cub variant promote <space> --dry-run` reports zero would-upgrade / would-add after a successful promote; `cub unit list --space <space> --filter platform/needs-upgrade` is empty.
- ChangeSet: scoped Units no longer match `platform/needs-upgrade`; `cub revision list --space <SCOPE_SPACE> --where "ChangeSet.Slug = '<slug>'"` shows the tagged revisions; `cub changeset get --space $HOME_SPACE <slug>` shows start+end tags (closed).

## Evidence

- `cub component open <component> --variant <variant> --print-url` — deployment graph.
- `cub space open <variant-space> --print-url` — destination Variant Space.
- `cub unit open <unit> --space <variant-space> --revisions --print-url` — promoted Unit history.

## References

- `cub variant upload --help`, `cub variant create --help`, `cub variant promote --help` — authoritative flags.
- `references/changesets.md` — lifecycle, rollback, merge/rebase.
- `references/filters-and-queries.md` — `needs-upgrade`, `unapplied-changes`, `has-apply-gates`, `not-approved` recipes.
- `references/cub-cli.md` — `--where` vs `--filter` vs `--changeset`, `-` sentinel for close.
- `references/revisions.md` — `ChangeSet:<name>`, `Before:ChangeSet:<name>`, `Tag:<name>`.
- Companion skills: `confighub-core` (home/env Space layout, one-Target-per-toolchain, config-as-data), `triggers-and-applygates` (PostClone auto-customize, approval gates), `cub-mutate` (conflict resolution), `release-publish` (fully enumerated advisory Release proposal), `rollback-revision`, `verify-apply`.
- `https://docs.confighub.com/markdown/guide/variants.md`, `.../guide/dependencies.md`.
