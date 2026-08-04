---
name: verify-apply
description: 'Verify a published ConfigHub Space Release, then prove controller and cluster convergence read-only. Use after release-publish or for "did it deploy?", "is it live?", "did Argo pick it up?", and release close-out.'
phase: verify
allowed-tools: []
read-capability-subset: verify-apply
---

# verify-apply

**Authority boundary:** this skill is read-only. It may identify evidence gaps and route a proposed fix, but it must not mutate ConfigHub, a controller, or a cluster. The external mutation broker is `NOT_INTEGRATED`.

Prove the current delivery chain, read-only: **ConfigHub intent → immutable Space Release → controller source/sync → runtime target**. A successful publish alone is not a live deployment.

## Read the exact release

Start with the Release ID, bundle Digest, and OCI ManifestDigest captured by the externally authorized publish. These are different fields:

- `Digest` identifies the bundle content;
- `ManifestDigest` identifies the OCI manifest the controller consumes; and
- `ReleaseID` identifies the ConfigHub Release record.

Prefer an immutable selector:

```bash
cub release get --space <variant-space> <release-id>
cub release get --space <variant-space> --oci-reference sha256:<manifest-digest>
cub release get --space <variant-space> --bundle-digest sha256:<bundle-digest>
```

If only the Space is known, discover the newest Release with the weaker selector:

```bash
cub release get --space <variant-space> --oci-reference latest
```

Record the SpaceID/slug, ReleaseID/number, UnitCount, TagID if any, bundle Digest, ManifestDigest, repository/reference, and creation time. Do not infer provenance from an invented release-link field. If the user needs a previous immutable release, use its captured ID or digest; never silently substitute `latest`.

The public Release resource exposes no `TargetID` or stored OCI `Manifest`. Exact server v0.2.11 puts `com.confighub.target.id` in the generated manifest and commits that manifest with `ManifestDigest`, so historical Target proof needs the digest-matching manifest/annotation in the governed publication receipt or from a reviewed digest-addressed registry read. Today's `Space.ReleaseTargetID` is current state only. If that attestation is absent, return `HISTORICAL_RELEASE_TARGET_UNPROVEN` rather than guessing the older Target.

## Recover the historical manifest—never substitute today's set

The current EffectiveReleaseSet is current desired membership, not the manifest of an older Release. Heads and TargetIDs can move after publication, and a same-count member swap defeats a `UnitCount` comparison. Start with the governed publication receipt's ordered UnitID/RevisionID/RevisionNum/DataHash set, then cross-check every surviving Revision whose `Revision.Releases` map contains the exact ReleaseID:

```bash
cub revision list --space <variant-space> \
  --where "Releases ? '<release-id>'" \
  --select "RevisionID,RevisionNum,DataHash,Releases" -o json
```

`Releases` is a UUID-keyed map and `?` tests exact key membership. Do not use current head or current target membership as a substitute. If the receipt is absent, a linked Revision is deleted, the reconstructed set differs, or only UnitCount survives, return `HISTORICAL_RELEASE_MANIFEST_UNPROVEN`. Preserve the receipt because Release deletion removes the row/bundle and later Revision deletion can erase server-side reconstruction evidence.

## Prove every layer

| Layer | Read-only proof | Verdict |
| --- | --- | --- |
| Historical intent | governed publication receipt, digest-matching OCI manifest Target annotation, plus exact Revisions whose `Releases` contains ReleaseID | actual historical Target and published UnitID/RevisionID/RevisionNum/DataHash manifest are identified |
| Current intent | `cub space get <variant-space>`, current target membership/heads, and exact Revisions | current desired set is identified separately; drift from historical membership is named |
| Delivery | `cub release get` by ReleaseID, ManifestDigest, or bundle Digest | immutable OCI release and both digests are identified; UnitCount is only a cross-check |
| Controller | `argocd app get <app>` or `flux get …` | controller source/status is bound to the OCI ManifestDigest (or a documented exact equivalent) |
| Runtime | `kubectl get` / `describe` / `logs` plus `confighub.com/origin` | target resources are healthy and trace to SpaceID, UnitID, and RevisionNum |

For Kubernetes/YAML Units, the release stamps `metadata.annotations["confighub.com/origin"]` with JSON fields `spaceId`, `spaceSlug`, `unitId`, `unitSlug`, and `revisionNum`. Release identity is deliberately not in that annotation; it lives on the OCI manifest. Therefore runtime origin alone cannot prove which Release the controller consumed. Require both controller-to-ManifestDigest proof and runtime origin/health proof.

Name each unavailable layer as an explicit proof gap. Do not use successful publication as controller proof, controller sync as workload-health proof, or matching runtime data without provenance as Release proof. Never mutate `kubectl`, Argo, Flux, or ConfigHub from this skill.

## Classify current failures, not retired ones

- No Release exists after an attempted publish: inspect `Space.ReleaseTargetID`, Target ProviderType, the EffectiveReleaseSet, and each selected revision's ApplyGates. Current publication can fail before a Release record is created.
- Release exists but controller is behind: `WATCH` while within the documented sync window; `BLOCK` on source/auth/digest mismatch.
- Controller has the ManifestDigest but runtime is unhealthy: `BLOCK` and report the exact resource/condition (for example ImagePullBackOff, probe failure, or RBAC).
- Runtime origin differs from the proposed Unit/revision set: `BLOCK`; name the specific provenance divergence.

### Versioned-legacy Unit apply/event diagnosis

For historical bridge-era evidence only, preserve the prior diagnostic procedure:

```bash
cub unit get <unit> --space <space> -o jq=.UnitStatus
cub unit get <unit> --space <space> -o jq=.LatestUnitEvent
cub unit-event list <unit> --space <space> -o json
cub unit-action list <unit> --space <space> --where "Action = 'Apply'" -o json
```

`UnitStatus` and `LatestUnitEvent` are top-level siblings in the extended `cub unit get` envelope, not fields of `Unit`; the focused jq views avoid conflating them. Interpret the latest matching event/action with `UnitStatus.Status` (`Progressing`, `Completed`, `Failed`, or `Aborted`) and the event `Message`; bind its UnitID/action/event number and revision counters. This is useful to diagnose an archived per-Unit Apply or explain old audit history. It is `VERSIONED_LEGACY` and must never be used as the primary proof for current OCI Space Release/controller/runtime convergence.

For a whole-Space/bulk closeout, compare Release `UnitCount` with the receipt/reconstructed historical manifest, separately show current EffectiveReleaseSet drift, then evaluate every controller/runtime resource represented by the historical manifest. Do not use the old `apply-not-completed` Unit filter as if it described current Release/controller convergence.

## Close out

Only close out `PASS` when the exact Release, digest-attested historical Target, and historical member manifest are identified and all requested layers agree. State the Component, Variant Space, ReleaseID, bundle Digest, ManifestDigest, historical TargetID, historical member set/UnitCount, current desired-set drift, controller result, runtime result, and any omitted proof. Use `WATCH` for explicitly bounded convergence lag, `BLOCK` for a mismatch/failure, and `ASK` when the user must supply an identity or receipt that cannot be discovered safely.

GUI handoffs retain the review experience with supported commands:

- `cub component open <component> --variant <variant> --print-url`
- `cub space open <variant-space> --print-url`
- `cub unit open <unit> --space <variant-space> --revisions --print-url`

Verify object and organization identity before treating a printed URL as proof.

## Stop conditions

- No exact release identity, wrong cluster context, controller authentication failure, or runtime read failure: return an explicit unknown/proof gap.
- Missing publication receipt, deleted/missing linked Revision, same-count membership swap, or any current/historical member mismatch: do not claim the historical Release manifest is proved.
- Missing digest-matching OCI manifest/`com.confighub.target.id` attestation: do not infer the historical Target from today's Space.
- A fix is needed: route data edits to `cub-mutate`, promotion to `promote-release`, and a head-moving rollback to `rollback-revision`; then prepare a new Space Release through `release-publish` for external authorization.
