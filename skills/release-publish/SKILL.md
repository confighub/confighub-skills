---
name: release-publish
description: 'Preview, publish, inspect, withdraw, or delete whole-Space OCI Releases. Use for apply/deploy/publish, pending/ChangeSet changes, preview, tagged selection, get/list, historical cancel questions, withdraw, or delete. Discloses EffectiveReleaseSet and provider races. Not data edits/rollback.'
phase: act
allowed-tools: []
read-capability-subset: release-publish
---

# release-publish

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. After a fresh whole-Space scope preview, standalone use submits one requested publish or lifecycle mutation to the host permission system. Scope expansion, incomplete Target membership, failed gates, or missing destructive preconditions still require a stop; an external overlay may impose a stricter stop before Bash.

This skill preserves ordinary-language apply/deploy jobs while using the only current delivery contract: **Component → Variant Space → immutable OCI Release → Argo CD/Flux pull → runtime**. The retired `cub-apply` trigger families route here; they are retained explicitly in `compatibility/no-loss-inventory.v1.json`.

## Current Release contract

`cub release publish <space-slug>`:

- reads `Space.ReleaseTargetID` and requires that Target to use ProviderType `OCI`;
- bundles the **EffectiveReleaseSet**: every Unit in that Space whose `Unit.TargetID == Space.ReleaseTargetID`;
- captures each effective Unit at head unless `--revision <tag-slug>` is supplied, in which case the server selects the highest Revision currently carrying that mutable TagID;
- checks ApplyGates; and
- creates one immutable Release with a ConfigHub `ReleaseID`, bundle `Digest`, OCI `ManifestDigest`, `UnitCount`, and `Published=true`.

It has no Unit, Filter, ChangeSet, cross-Space selector, or dry-run flag. A ChangeSet groups/reviews/restores revisions but does not narrow publication. The current profile uses OCI Space Releases; older bridge/per-Unit delivery is historical context only and must not be offered as executable fallback.

## Preserve the job without hiding a scope change

| Prior intent | Current disposition |
| --- | --- |
| apply one Unit / Unit list / Filter | compare the requested set with the whole EffectiveReleaseSet; ask the user to accept the newly disclosed scope or use a dedicated Variant Space |
| apply every pending Unit | identify pending heads, then disclose every effective Unit captured, including unchanged heads |
| apply a ChangeSet | verify its closed revisions, then preview the complete destination Space Release |
| dry-run apply | emit a read-only publication preview; never call it a server dry-run |
| apply a specific revision | use a complete revision Tag only after every effective Unit resolves to an exact tagged RevisionID/DataHash |
| cancel an in-flight Unit apply | historical per-Unit behavior; immutable Release publication has no equivalent cancellation job |
| direct ConfigHub/bridge delivery | unsupported by the reviewed current Release path, which accepts OCI only |

Never convert a narrow request into a broader publish silently. Say: “Your request selected **N** Units; the supported Release command would capture **M** Units in Space **S**. That is a different scope.” Ask the user to accept that changed scope, then rebuild from fresh reads and submit one publish call to the host permission system.

## Build a fully enumerated publication preview (read-only)

### 1. Bind identity and profile

```text
cub auth status
cub release publish --help
cub space get <variant-space> -o json
```

Record context/organization, `SpaceID`, slug, Component/Variant labels,
`ReleaseTargetID`, and the installed profile. The current reviewed identity is
cub v0.2.15 with server v0.2.21. If a different version is installed, check
its help instead of assuming flag compatibility; the mismatch limits stronger
semantic claims but does not by itself block an ordinary requested publish.

### 2. Resolve the Release Target

```bash
cub target get <release-target-id> --space <target-space> -o json
```

Bind TargetID, owning Space, slug, ProviderType, and worker identity. ProviderType must be `OCI`. Stop on a missing, ambiguous, or non-OCI Target.

### 3. Compute the EffectiveReleaseSet

```bash
cub unit list --space <variant-space> \
  --select "TargetID,HeadRevisionNum,ApplyGates,ToolchainType,DestroyGates" -o json
```

Select only Units whose `TargetID` exactly equals `Space.ReleaseTargetID`. Record excluded Units too. For every effective Unit at head:

```bash
cub revision get --space <variant-space> -o json <unit-slug> <head-revision-num>
```

Bind `UnitID`, slug, TargetID, head/selected RevisionNum, `RevisionID`, `DataHash`, ToolchainType, ApplyGates, and DestroyGates. A non-empty ApplyGate is a concrete stop until the owning policy is satisfied.

### 4. Optional tagged Release

```text
cub tag get --space <variant-space> <tag-slug> -o json
cub revision list --space <variant-space> --tag <tag-slug> -o json <unit-slug>
```

For each effective Unit choose the highest matching Revision, then read and bind
the expected `TagID → UnitID/RevisionID/RevisionNum/DataHash` mapping. A Tag is
mutable metadata on Revision rows: it can be removed from one Revision and
added to another. Publication resolves it at execution, so even a complete
pre-read is not an immutable content pin. Installed v0.2.15 help says a Unit
without the Tag falls back to its head; exact v0.2.21 server source is not
available here. Disclose missing coverage and the documented fallback. Stop
only if the user's intent requires a tag-only set with no head fallback; an
ordinary explicitly accepted tagged publish can proceed and its result must be
inspected.

### 5. Emit the scope preview

The preview contains:

- context/organization and exact compatibility profile;
- SpaceID/slug/Component/Variant;
- ReleaseTargetID, Target identity, ProviderType, and worker identity;
- ordered EffectiveReleaseSet with every UnitID/slug/TargetID/head/selected RevisionNum/RevisionID/DataHash/toolchain/gate;
- excluded Units and the user's originally requested subset;
- optional TagID/slug, complete-coverage proof, and expected per-Unit TagID-to-RevisionID/RevisionNum/DataHash mapping;
- any side effect documented by current help or observed from the current server; the older auto-tag behavior is historical evidence, not a current assertion without observation;
- exact command and controller/runtime proof plan.

Any material change to identity, target, membership, head/revision/hash, TagID mapping, gate, command, side effect, or proof plan requires a focused new decision before submission.

### 6. Name the execution-CAS gap

A fresh pre-read does not bind the eventual server operation. Installed help
exposes no expected Space version, TargetID, tag mapping, ordered
UnitID/RevisionID/DataHash manifest, or preview digest. `--revision <tag>` is
therefore a mutable selector, not a content pin.

Therefore the preview is not atomically bound to execution. In standalone mode, refresh it immediately before the one publish call, disclose the race, and submit it to the host permission system; do not claim that the preview itself was an authoritative or immutable execution subject. Stronger governance needs server-side expected-target/expected-manifest preconditions or another operation that the provider verifies atomically.

## Native head approval is separate—and not exact

Installed v0.2.15 help advertises numeric, `LiveRevisionNum`, Tag, and
ChangeSet approval selectors; as of v0.4.0 `LiveRevisionNum` is removed and
`LastAppliedRevisionNum` is renamed `LastReleasedRevisionNum`. Exact server
acceptance and atomic preconditions are not source-reviewed here. Confirm the selector with current
help, submit an explicitly requested approval as its own command, inspect the
result, and do not claim exact reviewed-artifact binding without provider
evidence. Approval and publication remain separate host-permission calls.

## Publication command shape

```text
cub release publish <variant-space>

cub release publish --revision <tag-slug> <variant-space>
```

Neither form removes the execution race. The untagged form selects current
heads; the tagged form uses a mutable Tag mapping and, per installed help,
falls back to head where the Tag is absent. Refresh immediately before
execution, then make exactly one selected publish call through the host
permission system. Do not claim the earlier preview was atomically pinned.

## Read existing Releases

Prefer immutable selectors:

```text
cub release get --space <variant-space> <release-id>
cub release get --space <variant-space> --oci-reference sha256:<manifest-digest>
cub release get --space <variant-space> --bundle-digest sha256:<bundle-digest>
cub release list --space '*' --where "Digest = 'sha256:<bundle-digest>'" -o json
```

`--oci-reference latest` is weaker discovery only. Keep `Digest` (bundle) and `ManifestDigest` (OCI manifest) distinct. The public Release resource has no `TargetID`, and `cub release get/list` do not expose the server's stored OCI `Manifest`. The server-generated manifest committed by `ManifestDigest` does contain `annotations["com.confighub.target.id"]`, but proving the historical Target therefore requires a trusted publication receipt that captures that manifest/annotation or a digest-addressed registry read through a reviewed catalog action. `Space.ReleaseTargetID` shows only the Space's **current** binding and must not be misreported as proof of the Target used by an older Release. Without the manifest attestation, say that the historical Target is unproven.

After separately operated publication, immediately capture a governed receipt containing the actual ReleaseID/Digest/ManifestDigest, the digest-matching OCI manifest and its `com.confighub.target.id` annotation, and exact UnitID/RevisionID/RevisionNum/DataHash membership recovered from `Revision.Releases`. A pre-publish Target read is not a substitute for the post-publish manifest target because publish lacks expected-target CAS. Route that receipt to `verify-apply`. A successful publish is not controller or runtime convergence, and Release `UnitCount` is not a manifest.

## Withdrawal (destroy-class)

Withdrawal takes an immutable-content Release out of service but retains its record with `Published=false`; deletion permanently removes the Release row and stored bundle. Locate and bind the exact global ReleaseID first, including SpaceID, Digest, ManifestDigest, `Published`, UnitCount, the attested historical Target, the historical member manifest, and current DestroyGates:

```text
cub release list --space '*' --where "ReleaseID = '<release-id>'" -o json
cub release get --space <actual-space> <release-id> -o json
cub revision list --space <actual-space> \
  --where "Releases ? '<release-id>'" \
  --select "RevisionID,RevisionNum,DataHash,Releases" -o json
```

`Releases` is a UUID-keyed map; the `?` predicate tests exact key membership. Reconstruct the original members by selecting only Revisions whose `Releases` map contains the ReleaseID. Compare their exact UnitID/RevisionID/RevisionNum/DataHash set with the governed publication receipt. A same `UnitCount` is insufficient: a retargeted member can be replaced by another Unit without changing the count. Missing/deleted Revision rows or a missing receipt are an explicit historical-manifest proof gap.

Before submitting any withdrawal, verify the destructive verb and flags from the installed client in the same session:

```bash
cub release withdraw --help
```

Only after that check and the dependency inventory, the separately submitted command is:

```bash
cub release withdraw <release-id>
```

The CLI resolves the Release's actual Space by globally unique ID. Current
help says withdrawal checks DestroyGates for Units in the Release bundle.
Exact v0.2.21 implementation is not source-reviewed here, so inventory the
historical members and current gate state, submit only the exact ReleaseID,
and inspect the result. Older current-target-membership behavior remains
historical evidence, not a current claim. Never clear a gate as an implicit
sub-step. Bind identity, availability impact, consumers, rollback/republish
plan, command, and proof plan before the host-permission call.

After execution, verify the retained record has the same immutable IDs/digests
and `Published=false`; do not expect not-found. For permanent deletion, verify
`cub release delete --help` in the same session before offering the separate
destroy-class command `cub release delete <release-id>`. Require a verified
withdrawal first, retained manifest/member/digest evidence, explicit retention
authorization, consumer proof, and a not-found/blob-unavailable postcondition.
The exact v0.2.21 delete implementation is not source-reviewed, so do not claim
that gates are either enforced or bypassed. Never describe deletion as
withdrawal or rely on surviving Revision linkage as the only audit record.

## Stop conditions

- narrower intent differs from the EffectiveReleaseSet;
- missing/changed ReleaseTargetID, Unit membership, head/revision/hash, TagID mapping, auto-tag side effect, or gate state;
- non-OCI Target or any bridge/per-Unit deploy request presented as current;
- incomplete tag coverage when the user requires tag-only selection without the documented head fallback;
- historical Release receipt/member reconstruction is missing for a historical-membership claim or destructive lifecycle action;
- historical Target is inferred from current Space state rather than attested by the digest-matching OCI manifest;
- withdrawal consumer impact is unknown or a DestroyGate is present;
- deletion is still published or lacks a prior withdrawal receipt and retained manifest evidence;
- the host denies the command or an external governance overlay blocks it; or
- a requested controller/runtime claim cannot bind to the immutable Release (publication itself may still succeed; name the proof gap).

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
