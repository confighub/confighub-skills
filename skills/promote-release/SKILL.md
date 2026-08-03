---
name: promote-release
description: 'Promote a release to the next environment or across the fleet, and manage variant spaces — cub variant create / promote to reconcile a variant with its upstream, or a ChangeSet-wrapped bulk upgrade for partial / cross-space scopes. Phrases: promote to staging, roll forward to prod, which Units are behind upstream, push the base to every downstream. Not for rollback (use rollback-revision).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub revision list *) Bash(cub revision get *) Bash(cub variant upload *) Bash(cub variant create *) Bash(cub variant promote *) Bash(cub unit update *) Bash(cub unit tag *) Bash(cub tag create *) Bash(cub changeset create *) Bash(cub changeset update *) Bash(cub filter create *) Bash(cub filter update *) Bash(kubectl get *) Bash(kubectl describe *)
---

# promote-release

Promote a release forward. There are two mechanisms; pick by scope:

- **Variant spaces (space-level, preferred for the common case).** `cub variant promote <space>` reconciles a whole variant Space with the upstream Space it was cloned from — in one command. Set up with `cub variant create` (clone a Space into a variant) and, for a brand-new base, `cub variant upload` (ingest rendered manifests into a base Space).
- **ChangeSet-wrapped bulk upgrade (fine-grained / cross-space).** Manual `cub unit update --patch --upgrade --where …` inside a ChangeSet, when you need a partial scope, a cross-Space fleet push, or explicit ChangeSet grouping / approval / atomic rollback.

Before acting, confirm `cub auth status` succeeds (it calls the server's `/me` to verify the token; if it fails, ask the user to run `cub auth login`). Confirm verbs and flags with `cub <verb> --help` before composing — never invent flags. This skill hands off the cluster rollout to `release-publish`.

## When to use

- "Promote to staging / prod", "roll forward", "push the release", "upgrade the downstreams to match upstream".
- The decision question: "is this ready?", "which Units are behind their upstream?".
- Standing up a new environment/region/tenant variant of an existing Space.
- Pushing a shared base out to every downstream across env-Spaces.

## Do not load for

- Rollback of a prior promotion — use `rollback-revision` + `references/changesets.md` (`Before:ChangeSet:<slug>`).
- In-place single-Unit changes — use `cub-mutate`.
- Publishing or withdrawing an **immutable OCI Release bundle** (`cub release publish/withdraw`) for a Space and Target — that's a different sense of "release"; use `release-publish`.
- Importing rendered manifests for the first time when you're not setting up a promotable base — `import` (`cub variant upload` here is for seeding a base Space you intend to clone and promote).

## Topology assumptions

Promotion data flows `<source>` → `<destination>` (a parent/base Space → its variant/downstream Spaces). One Space per deployment boundary, **one Target per ToolchainType (e.g. Kubernetes/YAML) per Space** (`confighub-core`). Note the direction gotcha: an `UpgradeUnit` Link points downstream→upstream (dependency edge), the **opposite** of data flow.

---

## The variant lifecycle (space-level)

### 1. Seed a base Space — `cub variant upload`

When you have already-rendered manifests (from the installer, `kustomize build`, `helm template`, or stdin) and want a promotable base Space, ingest them. This command does **not** render — it stores what you give it.

```bash
kustomize build overlays/base | cub variant upload \
  --component web --variant base \
  --granularity per-resource \
  --target web-base/cluster -
```

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
- `--target` retargets the cloned Units and stamps the Space `TargetID`. `--namespace` runs `set-namespace` on the cloned Kubernetes/YAML Units, replacing a `confighubplaceholder` namespace from the base — so each variant lands in its own namespace.
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

Then hand off the cluster rollout to `release-publish` (publish the Space as an OCI bundle Release).

**Use the manual ChangeSet flow below instead when** you need to promote only a subset of a Space, push a shared base across *many* Spaces at once, or want explicit ChangeSet open/close/approve/atomic-rollback control beyond what `--changeset` on `variant promote` gives.

---

## ChangeSet-wrapped bulk upgrade (fine-grained / cross-space)

For partial scopes or a base→fleet push that spans Spaces. Wrap any multi-Unit promotion in a ChangeSet — it locks the scope against interleaving releases, groups revisions for set-wise approval (`--revision ChangeSet:<slug>`), and gives you a named end tag to pin a publish to (`cub release publish --revision <changeset-end-tag>`) rather than the `release-<ReleaseNum>` Tag publish creates by default. It also enables atomic rollback (`--restore Before:ChangeSet:<slug>`). One Unit only: skip the ChangeSet and use `cub-mutate --upgrade`.

### Decide — preflight

Produce a concrete go / no-go. `--where` is AND-only (run one query per condition, union in the report); `cub unit list` takes at most one `--filter`.

**A. Source is converged** — promoting an unconverged env ships problems forward:

```bash
cub unit list --space <app>-<source> --filter <app>-home/<app>-app \
  --where "HeadRevisionNum > LiveRevisionNum AND TargetID IS NOT NULL"   # unpublished changes
cub unit list --space <app>-<source> --filter <app>-home/<app>-app --where "LEN(ApplyGates) > 0"
cub unit list --space <app>-<source> --filter <app>-home/<app>-app \
  -o jq='[.[] | select(.UnitStatus.Status != "Ready" or .UnitStatus.SyncStatus != "Synced")]'
```

Any rows = not ready (name each Unit + category). Base Units legitimately have `TargetID` NULL / `LiveRevisionNum` 0; a `vet-placeholders` gate on a base can be ignored.

**B. Destination needs it** — `cub unit list --space <app>-<dest> --filter platform/needs-upgrade`. Empty = nothing to promote, stop. Narrow with `--where "Slug LIKE '%-api%'"` for a subset.

**C. Diffs are expected** — per in-scope Unit: `cub unit update --patch --upgrade --dry-run -o mutations --space <app>-<dest> --unit <u>`. Flag surprises (image jumps >1 minor, unexpected limit/annotation churn).

**D. Policy + approval** — `cub space get <app>-<dest> -o jq='{AttachedFilter: .TriggerFilter.Slug, TriggerFilterID: .Space.TriggerFilterID}'`; check for lingering gates. If `vet-approvedby` / `is-approved` is set, surface who approves and how.

**E. Upstream linkage matches intent** — `cub unit tree --space <app>-<dest>`; `cub link list --space <app>-<dest> --where "UpdateType = 'UpgradeUnit'"`. If a Unit points at an unexpected upstream, the promotion pulls from there — stop and confirm.

Output: **Scope** (exact `--space`/`--filter`/`--where`), **Count**, **Blockers**, **Diffs** summary, **ChangeSet proposal** (`release-<YYYYMMDD>-<shortref>` in `<app>-home`), **Approval plan**, **Recommendation** (go / go-narrowed / no-go). On no-go, route to remediation (`release-publish`, `triggers-and-applygates`) — don't promote anyway.

### Execute — open, upgrade, close

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

### Approval

```bash
cub unit approve --space <SCOPE_SPACE> <SCOPE_SELECTOR> --revision ChangeSet:$CHANGESET_REF   # if required

# Hand off to release-publish to ship the promoted config.
```

Don't self-approve unless the user holds the role.

## Rollback

`cub variant promote` and the ChangeSet flow both roll back the same way — move head back, then publish:

```bash
cub unit update --patch --space <SCOPE_SPACE> <SCOPE_SELECTOR> \
  --restore "Before:ChangeSet:$CHANGESET_REF" \
  --change-desc "Rollback <changeset>. User prompt: <verbatim>. Clarifications: <condensed>"

# Hand off to release-publish to ship the restored head.
```

Full detail: `rollback-revision` + `references/changesets.md`.

## Tool boundary

- Allowed: `cub variant upload/create/promote`, `cub changeset create/update`, `cub unit update` (patch + upgrade + restore), `cub filter create/update`, `cub tag create`, `cub unit tag`; read-only `cub unit/revision/link list/get/tree/bridgestate/diff`, `kubectl get/describe` for the preflight cross-check.
- Not allowed: `cub unit push-upgrade` (deprecated), `cub release publish` (hand off to `release-publish`), `kubectl apply` / out-of-band cluster mutation. Merge-conflict edits go through `cub-mutate` inside the open ChangeSet.

## Stop conditions

- `cub variant promote` on a Space with no `UpstreamSpaceID` annotation (not made by `cub variant create`) — it errors; set the variant up with `cub variant create` first.
- Preflight `no-go` — route to remediation.
- Another ChangeSet already open against the scope; destination scope empty; upgrade merge leaves conflicts (`cub unit diff` shows `<<<<<<<` / non-empty `MergeConflicts`) — resolve in `cub-mutate` within the ChangeSet, re-diff, close.
- User wants to skip the ChangeSet for a >1-Unit manual promotion (loses lock + atomic rollback), or self-approve without the role, or upstream linkage doesn't match intent — stop and confirm.

## Verify chain

- Variant: `cub variant promote <space> --dry-run` reports zero would-upgrade / would-add after a successful promote; `cub unit list --space <space> --filter platform/needs-upgrade` is empty.
- ChangeSet: scoped Units no longer match `platform/needs-upgrade`; `cub revision list --space <SCOPE_SPACE> --where "ChangeSet.Slug = '<slug>'"` shows the tagged revisions; `cub changeset get --space $HOME_SPACE <slug>` shows start+end tags (closed).

## Evidence

- `cub changeset get --space $HOME_SPACE <slug> --web` — the release entity linking every Unit revision.
- `cub space get <variant-space> --web` — the variant Space, its labels, `UpstreamSpaceID`, and `TargetID`.
- `cub unit tree --space <SCOPE_SPACE> --web` — upstream linkage the promotion followed.

## References

- `cub variant upload --help`, `cub variant create --help`, `cub variant promote --help` — authoritative flags.
- `references/changesets.md` — lifecycle, rollback, merge/rebase.
- `references/filters-and-queries.md` — `needs-upgrade`, `unpublished-changes`, `has-apply-gates`, `not-approved` recipes.
- `references/cub-cli.md` — `--where` vs `--filter` vs `--changeset`, `-` sentinel for close.
- `references/revisions.md` — `ChangeSet:<name>`, `Before:ChangeSet:<name>`, `Tag:<name>`.
- Companion skills: `confighub-core` (home/env Space layout, one-Target-per-toolchain, config-as-data), `triggers-and-applygates` (PostClone auto-customize, approval gates), `cub-mutate` (conflict resolution), `release-publish` (publishes the promoted config), `rollback-revision`.
- `https://docs.confighub.com/markdown/guide/variants.md`, `.../guide/dependencies.md`.
