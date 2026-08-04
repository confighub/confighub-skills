---
name: release-publish
description: 'Prepare advisory, inspect, withdraw, or delete whole-Space OCI Release subjects. Use for apply/deploy/publish, pending/ChangeSet changes, preview, tagged selection, get/list, cancel legacy, withdraw, or delete. Discloses EffectiveReleaseSet and provider-CAS gaps; stops before writes. Not data edits/rollback.'
phase: act
allowed-tools: []
read-capability-subset: release-publish
---

# release-publish

**Authority boundary:** this companion is knowledge/read-only. It may inspect Releases and produce a fully enumerated but advisory `ReleaseProposal` or `WithdrawalProposal`; it must not publish, withdraw, approve, tag, retarget, or perform any other mutation. The external mutation broker is `NOT_INTEGRATED`, so otherwise valid writes end in `ASK` for exact scope and `BLOCK` for execution.

This skill preserves ordinary-language apply/deploy jobs while using the only current delivery contract: **Component → Variant Space → immutable OCI Release → Argo CD/Flux pull → runtime**. The retired `cub-apply` trigger families route here; they are retained explicitly in `compatibility/no-loss-inventory.v1.json`.

## Current Release contract

`cub release publish <space-slug>`:

- reads `Space.ReleaseTargetID` and requires that Target to use ProviderType `OCI`;
- bundles the **EffectiveReleaseSet**: every Unit in that Space whose `Unit.TargetID == Space.ReleaseTargetID`;
- captures each effective Unit at head unless `--revision <tag-slug>` is supplied, in which case the server selects the highest Revision currently carrying that mutable TagID;
- checks ApplyGates; and
- creates one immutable Release with a ConfigHub `ReleaseID`, bundle `Digest`, OCI `ManifestDigest`, `UnitCount`, and `Published=true`.

It has no Unit, Filter, ChangeSet, cross-Space selector, or dry-run flag. A ChangeSet groups/reviews/restores revisions but does not narrow publication. Current v0.2.11 delivery has no bridge/per-Unit deploy path; that knowledge is `VERSIONED_LEGACY/BLOCK` only.

## Preserve the job without hiding a scope change

| Prior intent | Current disposition |
| --- | --- |
| apply one Unit / Unit list / Filter | compare the requested set with the whole EffectiveReleaseSet; `ASK` for the newly disclosed scope or propose a dedicated Variant Space |
| apply every pending Unit | identify pending heads, then disclose every effective Unit captured, including unchanged heads |
| apply a ChangeSet | verify its closed revisions, then propose the complete destination Space Release |
| dry-run apply | emit the read-only `ReleaseProposal`; never call it a server dry-run |
| apply a specific revision | use a complete revision Tag only after every effective Unit resolves to an exact tagged RevisionID/DataHash |
| cancel an in-flight Unit apply | `VERSIONED_LEGACY`; immutable Release publication has no equivalent cancellation job |
| direct ConfigHub/bridge delivery | `VERSIONED_LEGACY/BLOCK`; the reviewed current Release path accepts OCI only |

Never convert a narrow approval into a broader publish. Say: “Your request selected **N** Units; the supported Release command would capture **M** Units in Space **S**. That is a different approval subject.” If the user accepts, rebuild from fresh reads. Acceptance still does not authorize execution.

## Build a fully enumerated advisory ReleaseProposal (read-only)

### 1. Bind identity and profile

```bash
cub auth status
cub release publish --help
cub space get <variant-space> -o json
```

Record context/organization, `SpaceID`, slug, Component/Variant labels, `ReleaseTargetID`, and the exact profile in `compatibility/current-profile.v1.json`. A different client/server/add-on tuple is `WATCH` or `BLOCK`, never assumed compatible.

### 2. Resolve the Release Target

```bash
cub target get <release-target-id> --space <target-space> -o json
```

Bind TargetID, owning Space, slug, ProviderType, and worker identity. ProviderType must be `OCI`. Missing/ambiguous/non-OCI is `BLOCK`.

### 3. Compute the EffectiveReleaseSet

```bash
cub unit list --space <variant-space> \
  --select "TargetID,HeadRevisionNum,ApplyGates,ToolchainType,DestroyGates" -o json
```

Select only Units whose `TargetID` exactly equals `Space.ReleaseTargetID`. Record excluded Units too. For every effective Unit at head:

```bash
cub revision get --space <variant-space> -o json <unit-slug> <head-revision-num>
```

Bind `UnitID`, slug, TargetID, head/selected RevisionNum, `RevisionID`, `DataHash`, ToolchainType, ApplyGates, and DestroyGates. A non-empty ApplyGate is `BLOCK` until satisfied through a separately governed policy/approval path.

### 4. Optional tagged Release

```bash
cub tag get --space <variant-space> <tag-slug> -o json
cub revision list --space <variant-space> --tag <tag-slug> -o json <unit-slug>
```

For each effective Unit choose the highest matching Revision, then read and bind the full expected `TagID → UnitID/RevisionID/RevisionNum/DataHash` mapping. A Tag is mutable metadata on Revision rows: it can be removed from one Revision and added to another. Publication resolves the highest matching Revision **at execution**, so even a complete pre-read is not an immutable content pin. Installed v0.2.11 client help says a missing tag falls back to head; reviewed server source errors. Until exact installed-server behavior is live-tested, require **complete tag coverage**. Any missing/ambiguous tag is `BLOCK`, and any inability to atomically compare the expected tag mapping is `RELEASE_TAG_MAPPING_CAS_BLOCK`.

### 5. Emit the approval subject

The advisory proposal contains:

- context/organization and exact compatibility profile;
- SpaceID/slug/Component/Variant;
- ReleaseTargetID, Target identity, ProviderType, and worker identity;
- ordered EffectiveReleaseSet with every UnitID/slug/TargetID/head/selected RevisionNum/RevisionID/DataHash/toolchain/gate;
- excluded Units and the user's originally requested subset;
- optional TagID/slug, complete-coverage proof, and expected per-Unit TagID-to-RevisionID/RevisionNum/DataHash mapping;
- when no `--revision` is proposed, the material side effect that the server creates `release-<ReleaseNum>` and adds its TagID to every bundled Revision;
- exact proposed command, controller/runtime proof plan, and proposal digest.

Any change to identity, target, membership, head/revision/hash, TagID mapping, gate, profile, command, auto-tag side effect, or proof plan invalidates review and requires a new proposal.

### 6. Name the execution-CAS gap

A fresh pre-read does not bind the eventual server operation. `cub release publish <space>` re-resolves `Space.ReleaseTargetID`, matching Unit membership, heads or the current TagID-to-RevisionID/DataHash mapping, and gates during publication; the API accepts no expected Space version, TargetID, expected tag mapping, ordered UnitID/RevisionID/DataHash manifest, or proposal digest. `--revision <tag>` is therefore a mutable selector, not a content pin. An external approval broker by itself cannot repair this provider-atomic gap.

Therefore the ReleaseProposal is advisory, not an executable authoritative subject. Classify current execution `RELEASE_EXECUTION_CAS_BLOCK`. A future path must either add server-side expected-target/expected-manifest preconditions or execute a digest-pinned catalog artifact that the provider verifies atomically. Until then, even a human-approved proposal may have changed effect by execution time.

## Native head approval is separate—and not exact

Server v0.2.11 rejects numeric, Tag, ChangeSet, RevisionID, `LiveRevisionNum`, and `LastAppliedRevisionNum` approval selectors even though CLI help advertises them. Only omitted `--revision` and `--revision HeadRevisionNum` are accepted; both approve whichever head is current inside the execution transaction. There is no expected RevisionID/DataHash CAS. Native approval may satisfy `vet-approvedby`, but a pre-read cannot prove that the reviewed head was the head approved. Return `APPROVAL_HEAD_RACE_BLOCK` for an authoritative exact-revision claim. Native approval is also not authorization for this companion to approve or publish.

## Publication command shape (never execute here)

```bash
cub release publish <variant-space>

cub release publish --revision <tag-slug> <variant-space>
```

Neither form removes the execution race. The untagged form re-resolves heads and also creates a `release-<ReleaseNum>` Tag attached to every bundled Revision. The tagged form re-resolves a mutable Tag mapping and chooses the highest Revision currently carrying the Tag. Bind the applicable side effects and expected mapping, then return `BLOCK` because neither provider CAS nor an external broker is integrated. Do not turn chat confirmation, a local file/flag, or native Unit approval into permission.

## Read existing Releases

Prefer immutable selectors:

```bash
cub release get --space <variant-space> <release-id>
cub release get --space <variant-space> --oci-reference sha256:<manifest-digest>
cub release get --space <variant-space> --bundle-digest sha256:<bundle-digest>
cub release list --space '*' --where "Digest = 'sha256:<bundle-digest>'" -o json
```

`--oci-reference latest` is weaker discovery only. Keep `Digest` (bundle) and `ManifestDigest` (OCI manifest) distinct. The public Release resource has no `TargetID`, and `cub release get/list` do not expose the server's stored OCI `Manifest`. The server-generated manifest committed by `ManifestDigest` does contain `annotations["com.confighub.target.id"]`, but proving the historical Target therefore requires a trusted publication receipt that captures that manifest/annotation or a digest-addressed registry read through a reviewed catalog action. `Space.ReleaseTargetID` shows only the Space's **current** binding and must not be misreported as proof of the Target used by an older Release. Without the manifest attestation, return `HISTORICAL_RELEASE_TARGET_UNPROVEN`.

After separately operated publication, immediately capture a governed receipt containing the actual ReleaseID/Digest/ManifestDigest, the digest-matching OCI manifest and its `com.confighub.target.id` annotation, and exact UnitID/RevisionID/RevisionNum/DataHash membership recovered from `Revision.Releases`. A pre-publish Target read is not a substitute for the post-publish manifest target because publish lacks expected-target CAS. Route that receipt to `verify-apply`. A successful publish is not controller or runtime convergence, and Release `UnitCount` is not a manifest.

## WithdrawalProposal (destroy-class, never execute here)

Withdrawal takes an immutable-content Release out of service but retains its record with `Published=false`; deletion permanently removes the Release row and stored bundle. Locate and bind the exact global ReleaseID first, including SpaceID, Digest, ManifestDigest, `Published`, UnitCount, the attested historical Target, the historical member manifest, and current DestroyGates:

```bash
cub release list --space '*' --where "ReleaseID = '<release-id>'" -o json
cub release get --space <actual-space> <release-id> -o json
cub revision list --space <actual-space> \
  --where "Releases ? '<release-id>'" \
  --select "RevisionID,RevisionNum,DataHash,Releases" -o json
```

`Releases` is a UUID-keyed map; the `?` predicate tests exact key membership. Reconstruct the original members by selecting only Revisions whose `Releases` map contains the ReleaseID. Compare their exact UnitID/RevisionID/RevisionNum/DataHash set with the governed publication receipt. A same `UnitCount` is insufficient: a retargeted member can be replaced by another Unit without changing the count. Missing/deleted Revision rows or a missing receipt are an explicit historical-manifest proof gap.

Before emitting any withdrawal proposal, verify the destructive verb and flags from the installed client in the same session:

```bash
cub release withdraw --help
```

Only after that check, the governed proposal is:

```bash
cub release withdraw <release-id>
```

The CLI resolves the Release's actual Space by globally unique ID. The v0.2.11 server checks DestroyGates on the **current** set of Units whose TargetID matches the Space's current ReleaseTargetID, not necessarily the original Release members. Compare the original receipt/`Revision.Releases` manifest with that current gate set. If an original member was retargeted away, a new member was retargeted in, the Target changed, or either set is incomplete, return `WITHDRAWAL_MEMBERSHIP_DRIFT_BLOCK`; do not claim the server checked the original Release. Never clear a gate as an implicit sub-step. Bind exact identity, availability impact, consumers, rollback/republish plan, command, and proof plan. With the broker absent, return `BLOCK`.

After external execution, verify the retained record has the same immutable IDs/digests and `Published=false`; do not expect not-found. For permanent deletion, verify `cub release delete --help` in the same session before emitting the separately reviewed destroy-class shape `cub release delete <release-id>`. Exact v0.2.11 source hard-deletes directly: it does **not** call withdrawal first and does **not** run withdrawal's DestroyGate check. Therefore require a verified `Published=false` withdrawal receipt, a prior export of the digest-matching OCI manifest/Target annotation plus exact historical member manifest and digests, explicit retention authorization, consumer proof, and a not-found/blob-unavailable postcondition. A still-published Release is `RELEASE_DELETE_STILL_PUBLISHED_BLOCK`; a gate pre-read is not provider-enforced delete CAS. Never describe deletion as withdrawal or rely on surviving Revision linkage as the only audit record.

## Stop conditions

- narrower intent differs from the EffectiveReleaseSet;
- missing/changed ReleaseTargetID, Unit membership, head/revision/hash, TagID mapping, auto-tag side effect, or gate state;
- non-OCI Target or any bridge/per-Unit deploy request presented as current;
- incomplete tag coverage or unresolved client/server tag semantics;
- absent provider-atomic target/membership/revision/tag-mapping CAS;
- historical Release receipt/member reconstruction is missing, deleted, or disagrees with current UnitCount;
- historical Target is inferred from current Space state rather than attested by the digest-matching OCI manifest;
- withdrawal original/current membership differs, consumer impact is unknown, or a DestroyGate is present;
- deletion is still published, lacks a prior withdrawal receipt/retained manifest evidence, or relies on a DestroyGate check the delete provider does not perform;
- missing external broker authorization; or
- controller/runtime evidence cannot bind to the immutable Release.

## GUI handoff

- `cub component open <component> --variant <variant> --print-url`
- `cub space open <variant-space> --print-url`
- `cub unit open <unit> --space <variant-space> --revisions --print-url`

Navigation URLs do not replace organization/object-ID verification.

## References

- `compatibility/current-profile.v1.json` — exact static profile and known gaps.
- `compatibility/no-loss-inventory.v1.json` — current and replaced triggers/capabilities/evals.
- `references/changesets.md` — grouping/restore and native approval separation.
- `target-bind` — ReleaseTargetID and exact Unit membership.
- `verify-apply` — Release/controller/runtime proof.
