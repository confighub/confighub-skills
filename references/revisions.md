# Revisions

Every Unit-data mutation produces a `Revision`. Revisions are the durable, immutable record of each change to a Unit, and the primary audit artifact in ConfigHub. Understanding what's in a Revision lets skills answer "what changed, why, by whom, when, and with what gates/approvals" from a single query surface.

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
| `Data` | The **full** configuration data at this revision. Snapshots are immutable — a revision is never re-rendered. |
| `DataHash` | SHA-256 of `Data`, hex-encoded. Useful for equivalence checks across Units. |
| `ContentHash` | Deprecated — CRC32 of the same data. Use `DataHash`. |

### Narrative (the "why")

| Field | Meaning |
|---|---|
| `Description` | The `--change-desc` passed at mutation time, copied from `Unit.LastChangeDescription`. Per the skill convention, this includes a one-line summary, the verbatim user prompt, and a condensed summary of clarifying-question answers. |

The `Description` field is what makes revision history self-explaining later — it carries the *intent* that produced the data change, not just the diff. Skills must compose it carefully (see `references/cub-cli.md` → "Change descriptions on mutations").

### Provenance (the "who / what / how")

| Field | Meaning |
|---|---|
| `Source` | The cub operation that produced the revision. Common values: `CreateUnit` (initial create), `Update` (`cub unit update`), `Invoke` (`cub function do` / `cub run`), `Resolve` (self-resolve and invoked triggers — automated). |
| `UserID` | User who initiated the change. Zero UUID (`00000000-…`) for automated changes like trigger resolution. |
| `UserAgent` | User-Agent string if the change came via API call. Useful for distinguishing CI / custom automation from interactive sessions. |

### Per-path mutation detail

| Field | Meaning |
|---|---|
| `MutationSources` | For each attribute path that changed in this revision, records which function produced the change, the mutation type (`Add` / `Update`), and the new value. This is what you see in `cub unit get --yaml` under `MutationSources` and what powers `compute-mutations` / `patch-mutations`. |

`MutationSources` is what lets you answer "which function set this field?" — each entry is keyed by resource identity and path, and names the function + an index into the revision's function-invocation sequence. When you ran `set-container-resources-defaults` on `hello-app` in the skill-examples bootstrap, the resulting revision's `MutationSources` recorded that `resources.requests` was set by that function with a specific value.

### Validation state (frozen at this revision)

| Field | Meaning |
|---|---|
| `ApplyGates` | `map[string]bool` keyed by `<space-slug>/<trigger-slug>/<function-name>`. Any entry set to `true` means a validating Trigger failed on this revision's data — **Apply is blocked** until the data passes or the gate is resolved upstream (e.g., fixing the Trigger's policy, not bypassing the gate). |
| `ApplyWarnings` | Same shape but for Triggers with `Warn=true` — they surface concerns without blocking apply. |

Gates and warnings are snapshotted per revision. If you fix the data in a later revision, the new revision's `ApplyGates` will reflect the new state; the old revision still shows what was blocked at the time.

### Governance state (frozen at this revision)

| Field | Meaning |
|---|---|
| `ApprovedBy` | List of User UUIDs who approved this revision (via `cub unit approve` or the corresponding API). Used by `vet-approvedby` to gate apply on approver count. |

### Lifecycle

| Field | Meaning |
|---|---|
| `LiveAt` | Timestamp when this revision was applied to its Target. Zero-time (`0001-01-01T00:00:00Z`) if the revision was never applied. Combined with `LastAppliedRevisionNum` on the Unit, lets you reconstruct the apply history. |

### Grouping

| Field | Meaning |
|---|---|
| `ChangeSetID` | Optional UUID that groups multiple revisions across multiple Units into a single logical change set — e.g., "release v1.4.0 touched these 12 Units". Apply by `ChangeSet:<slug>` references this. |
| `Tags` | `map[string]string` of TagID → label. Set via `cub unit tag … --add Tag:<slug>`. Tagged revisions are first-class `--revision` / `--restore` targets. |

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

For the full structure, use `cub revision get <unit> --space <s> --revision <n> --yaml` or `--json`.

## Common audit queries

```bash
# Recent revisions across a space, with their descriptions.
cub revision list --space <s> --where "UpdatedAt > '2026-04-01'"

# Revisions that were ever blocked by gates.
cub revision list --space <s> --where "LEN(ApplyGates) > 0"

# Revisions by a specific user.
cub revision list --space <s> --where "UserID = '<uuid>'"

# All revisions belonging to a ChangeSet.
cub revision list --space <s> --where "ChangeSetID = '<uuid>'"

# Unit's revision history as structured data.
cub revision list <unit> --space <s> --json

# Full detail for one revision, including MutationSources and Data.
cub revision get <unit> --space <s> --revision <n> --yaml
```

## Related

- `references/cub-cli.md` — `--change-desc` composition rule and `--display-mutations` for inline diffs at mutation time.
- `references/filters-and-queries.md` — filter vocabulary including revision-state fields (`HeadRevisionNum`, `LiveRevisionNum`, `LastAppliedRevisionNum`, `UpstreamRevisionNum`) on the Unit side.
- Skills: `cub-mutate` (composes `--change-desc`), `cub-query` (audit queries), `cub-apply` (sets `LiveAt` on the applied revision), `release-verify` (surfaces the revision history at completion).
