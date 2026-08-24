# Revisions

**Execution mode:** follow [How commands run](execution-modes.md). Revision reads and diffs are evidence. A command that creates a Revision, restores a head, approves a revision, or publishes data is a separate mutation submitted to the host permission system; native ConfigHub revision approval is policy state, not proof that another command ran.

Every Unit-data mutation produces a `Revision`.

**Revision 1 is empty.** Every Unit now begins with an empty start Revision, and the content it was
created with lands on Revision 2. That gives "before this Unit had anything" a Revision to name, so
a ChangeSet opened as the Unit is created, a clone that replays the upstream's history, and a
restore that rewinds past the first change are all the ordinary path rather than carve-outs. The
consequence to remember: **`--restore 1` restores empty**, not the created content. It cannot be
backfilled, so Units created before this change keep their content on Revision 1 — check
`cub revision list <unit> --space <s>` rather than assuming.
 A Revision's **configuration snapshot** (its configuration data and the `DataHash` over it) is immutable. The row as a whole is not: approvals, gates/warnings, Tags, Release linkage, and timestamps can change or accrue later. Revision reads are therefore useful audit evidence, but a current read alone cannot prove exactly what governance metadata existed at an earlier decision or execution time. Preserve timestamped receipts/events for that.

Authoritative definition: `Revision` struct in the public SDK at `https://github.com/confighub/sdk` (`core/openapi/goclient-new/models.gen.go`).

## Fields, grouped by purpose

### Identity

| Field | Meaning |
|---|---|
| `RevisionNum` | Monotonic integer per Unit. What you see in the `NUM` column of `cub revision list`. |
| `RevisionID` | UUID. Stable identifier across renames/moves. |
| `UnitID` / `SpaceID` / `SpaceSlug` | Which Unit and Space this revision belongs to. |
| `CreatedAt` / `UpdatedAt` | When the revision was created / last updated. |

### Content snapshot

| Field | Meaning |
|---|---|
| `DataHash` | SHA-256 of the revision's configuration data, hex-encoded. Useful for equivalence checks across Units. |
| `DataSize` | Byte size of that data. Answers "is there configuration here, and how much?" without fetching it. |

The data itself is **not a field on `Revision`** — it has its own endpoint, so a revision read never
drags a configuration along. Fetch it with `cub revision data <unit> <revision-num> --space <s>`
(add `-O <path>` to write a file). It comes back as plain text, not base64. Snapshots are immutable —
a revision is never re-rendered.

### Narrative (the "why")

| Field | Meaning |
|---|---|
| `Description` | The short safe `--change-desc` passed at mutation time, copied from `Unit.LastChangeDescription`. Fuller request context remains in the shared transcript or receipt; never interpolate it verbatim into shell source. |

The `Description` field is what makes revision history self-explaining later — it carries the *intent* that produced the data change, not just the diff. Skills must compose it carefully (see `references/cub-cli.md` → "Change descriptions on mutations").

### Provenance (the "who / what / how")

| Field | Meaning |
|---|---|
| `Source` | The cub operation that produced the revision. Common values: `CreateUnit` (initial create), `Update` (`cub unit update`), `Invoke` (`cub function set` / `cub run`), `Resolve` (self-resolve and invoked triggers — automated), `CloneUnit`, `UpgradeUnit`, `MergeUnits`, `MergeExternal` (merge-produced). |
| `UserID` | User who initiated the change. Zero UUID (`00000000-…`) for automated changes like trigger resolution. |
| `UserAgent` | User-Agent string if the change came via API call. Useful for distinguishing CI / custom automation from interactive sessions. |

### Per-path mutation detail

Like the data, `MutationSources` is not a field on `Revision`; it has its own endpoint, which
`cub unit get -o mutations` reads.

| Record | Meaning |
|---|---|
| `MutationSources` | Per-path index of which change last set each configuration value: the mutation type (`Add` / `Update` / `Delete`), a reference to the Mutation (and so the Revision, function, Link, or Trigger) responsible, the value, and a **`Protected`** flag saying whether the path is a local override a merge must not overwrite. It is what powers `compute-mutations` / `patch-mutations`, what the merge engine consults to tell an upstream change from a local one, and what `cub unit get -o mutations` renders. Restore rewinds `MutationSources` along with `Data`, so provenance always matches the state you restored. |

`MutationSources` is what lets you answer "which function set this field?" and "may a merge overwrite this field?" — each entry is keyed by resource identity and path, and names the function + an index into the revision's function-invocation sequence. When you ran `set-container-resources-defaults` on `hello-app` in the skill-examples bootstrap, the resulting revision's `MutationSources` recorded that `resources.requests` was set by that function with a specific value.

### Validation state (revision-scoped, but mutable)

| Field | Meaning |
|---|---|
| `ApplyGates` | `map[string]bool` keyed by `<space-slug>/<trigger-slug>/<function-name>`. Any entry set to `true` means a validating Trigger failed on this revision's data — **Publish is blocked** until the data passes or the gate is resolved upstream (e.g., fixing the Trigger's policy, not bypassing the gate). |
| `ApplyWarnings` | Same shape but for Triggers with `Warn=true` — they surface concerns without blocking publish. |

Gates and warnings are scoped to a Revision's data, but resolution can update them after the Revision is created. A later read shows current recorded gate state, not necessarily the state at an earlier approval or publish attempt. A later data fix normally produces a new Revision with its own state.

### Governance state (accruing)

| Field | Meaning |
|---|---|
| `ApprovedBy` | List of User UUIDs currently recorded as approving this revision. It can accrue after creation. Installed v0.2.15 help advertises several selectors; exact v0.2.21 acceptance and atomic preconditions are not source-reviewed, so inspect the result and do not claim exact reviewed-artifact binding. |

### Lifecycle

| Field | Meaning |
|---|---|
| `LiveAt` | Bridge-era runtime timestamp. Do not use it to establish current OCI Release membership or publication time; use the Release record, `Revision.Releases`, and the publication receipt. |

### Grouping

| Field | Meaning |
|---|---|
| `ChangeSetID` | Optional UUID that groups multiple revisions across multiple Units into a single logical change set — e.g., "release v1.4.0 touched these 12 Units". Apply by `ChangeSet:<slug>` references this. |
| `Tags` | `map[string]string` of TagID → label. Tags can be added after Revision creation. Tagged revisions are first-class restore targets and may be used by Release publication. |
| `Releases` | Set/map of ReleaseIDs that have bundled this Revision. Publication adds linkage after Revision creation. It is the server-side reconstruction source for historical membership while the Revision survives; a durable publication receipt must preserve the same UnitID/RevisionID/RevisionNum/DataHash manifest because later deletion can make reconstruction incomplete. |

## What appears in `cub revision list`

The CLI surfaces a subset of the above as columns:

```
NUM  UNIT  CHANGESET  TIME  USER  SOURCE  DESCRIPTION  APPLY-GATES  TAGS
```

- `NUM` = `RevisionNum`
- `CHANGESET` = the slug of the ChangeSet if `ChangeSetID` is set, else blank
- `TIME` = `CreatedAt`
- `USER` = resolved from `UserID`
- `SOURCE` = `Source`
- `DESCRIPTION` = `Description` (the composed `--change-desc`)
- `APPLY-GATES` = `None` if the map is empty, else the list of blocking gate keys
- `TAGS` = `None` if empty, else tag labels

For the full structure, use `cub revision get <unit> --space <s> --revision <n> -o yaml` or `-o json`.

## Common audit queries

```text
# Recent revisions across a space, with their descriptions.
cub revision list --space <s> --where "UpdatedAt > '2026-04-01'"

# Revisions that were ever blocked by gates.
cub revision list --space <s> --where "LEN(ApplyGates) > 0"

# Revisions by a specific user.
cub revision list --space <s> --where "UserID = '<uuid>'"

# All revisions belonging to a ChangeSet.
cub revision list --space <s> --where "ChangeSetID = '<uuid>'"

# Unit's revision history as structured data.
cub revision list <unit> --space <s> -o json

# Full metadata for one revision (not its configuration — see below).
cub revision get <unit> --space <s> --revision <n> -o yaml

# The revision's configuration, and its per-path provenance.
cub revision data <unit> <n> --space <s>
cub unit get <unit> --space <s> -o mutations
```

## Related

- `references/cub-cli.md` — `--change-desc` composition rule and `-o mutations` for inline diffs at mutation time.
- `references/filters-and-queries.md` — filter vocabulary including revision-state fields (`HeadRevisionNum`, `LiveRevisionNum`, `LastAppliedRevisionNum`, `UpstreamRevisionNum`) on the Unit side.
- `references/cub-cli.md` → "Protection and merge conflicts" — the `Protected` flag, `cub unit set-protection`, and `cub unit conflicts`.
- Skills: `cub-mutate` (composes `--change-desc`), `cub-query` (audit queries), `promote-release` (walked merges record one revision per upstream revision), `rollback-revision` (restore targets), `release-publish` (publishes from a tagged revision via `cub release publish --revision <tag>`).
