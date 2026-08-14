---
name: target-bind
description: 'Prepare OCI Target, Space.ReleaseTargetID, and matching Unit.TargetID membership. Use for "set up a target", "publish this Space to OCI", "attach Units", or "do I need a worker?". Direct ConfigHub-provider delivery is historical and unsupported in the reviewed current profile.'
phase: act
allowed-tools: []
read-capability-subset: target-bind
---

# target-bind

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. Standalone use previews the before/after EffectiveReleaseSet, then submits one requested worker, Target, Space, or Unit binding change at a time to the host permission system; an external overlay may stop it before Bash.

## The current binding has two required layers

A Unit `TargetID` by itself is not enough for Space Releases.

1. `Space.ReleaseTargetID` identifies the one Target consumed by `cub release publish <space>`.
2. The **EffectiveReleaseSet** contains only Units in that Space whose `Unit.TargetID` exactly equals the `ReleaseTargetID`.

The current Release path requires an **OCI** Target. Argo CD or Flux consumes the resulting OCI manifest outside ConfigHub. A server worker entity backs the OCI Target; no external worker process is needed for this built-in delivery path.

`cub variant create ... --target ...` and `cub variant upload ... --target ...` can establish these relationships for new variants. This skill is the explicit repair/setup route for existing Spaces and for auditing ambiguous bindings.

## Historical ConfigHub-provider delivery

Earlier surfaces taught a ProviderType `ConfigHub` Target for direct ConfigHub/YAML delivery. Preserve that fact only as historical context; do not present it as current Release delivery. The reviewed Release implementation rejects a non-OCI `ReleaseTargetID`, and the former per-Unit runtime apply path is retired. Explain that no current supported command provides that route.

## Read-only preflight

```text
cub auth status
cub worker list --space <worker-space> -o json
cub target list --space <target-space> -o json
cub space get <app-space> -o json
cub unit list --space <app-space> --select "TargetID,HeadRevisionNum,ApplyGates,ToolchainType" -o json
```

Bind the organization/context, SpaceID, existing `ReleaseTargetID`, every UnitID/TargetID, and the intended target owner/slug. If changing a current target would add or remove Units from the EffectiveReleaseSet, disclose the before/after set and require a fresh release proposal after binding.

## Ordered mutation steps

Confirm every form with installed help immediately before submission. For a
clear standalone setup request, submit the first missing step through the host
permission system, verify it, then continue one requested step at a time.

### 1. Ensure the built-in server worker entity

```bash
cub worker create --space <worker-space> --allow-exists --is-server-worker server-worker
```

After the scope preview remains unchanged, submit this one command to the host
permission system. Do not combine it with Target creation.

### 2. Create an OCI Target

```bash
cub target create <target-slug> '' <worker-space>/server-worker \
  --space <target-space> --provider OCI
```

The empty string is the Target parameters argument. Do not invent cluster/namespace parameters for the OCI Target; cluster/controller configuration is a separate integration.

### 3. Set the Space release Target

```bash
cub space update <app-space> --release-target <target-space>/<target-slug>
```

This `--release-target` step is load-bearing. It sets `Space.ReleaseTargetID`; a proposal that only calls `cub unit set-target` is incomplete.

### 4. Make Unit membership explicit

For one intended Unit:

```bash
cub unit set-target <unit-slug> <target-space>/<target-slug> --space <app-space>
```

For an exact reviewed set:

```bash
cub unit set-target <target-space>/<target-slug> --space <app-space> --unit <unit-1>,<unit-2>
```

A metadata selector is supported, but resolve it to UnitIDs and show the exact count before submitting it:

```bash
cub unit set-target <target-space>/<target-slug> --space <app-space> --where "Labels.Tier = 'backend'"
```

Do not claim “single-Unit delivery” after setting one Unit: a later `release publish` captures every Unit whose TargetID matches the Space's ReleaseTargetID. If other Units already match, show them. If the user's intent is truly isolated, propose a dedicated Variant Space rather than relying on a filter the Release command cannot accept.

## Scope binding and changed-scope decisions

The scope preview must bind:

- context/organization and compatibility profile;
- worker ID/type;
- target SpaceID, TargetID, slug, and ProviderType `OCI`;
- app SpaceID and old/new `ReleaseTargetID`;
- old/new EffectiveReleaseSet as UnitIDs;
- exact commands and expected postconditions.

Changing the Target, Space, Unit selector, resolved Unit membership, provider, or command creates a new scope. After a binding completes, rebuild the `release-publish` preview from fresh reads; permission for target binding is not permission for release publication.

## Read-only verification

```text
cub target get <target-slug> --space <target-space> -o json
cub space get <app-space> -o json
cub unit list --space <app-space> --select "TargetID,HeadRevisionNum,ApplyGates" -o json
```

A successful binding requires:

- Target ProviderType is exactly `OCI`;
- `Space.ReleaseTargetID` equals that TargetID;
- each intended Unit has the same TargetID;
- every unintended matching Unit is surfaced, not hidden; and
- publication remains a separate user request and host-permission call.

## Stop conditions

- ConfigHub or any non-OCI provider requested for current Release delivery;
- target owner Space is unknown;
- selector resolves differently from the reviewed UnitID set;
- setting/changing `ReleaseTargetID` broadens release scope without explicit re-approval;
- the host denies the command or an external governance overlay blocks it.

## Evidence

- `cub space open <target-space> --print-url`
- `cub space open <app-space> --print-url`
- `cub unit open <unit> --space <app-space> --print-url`

Navigation URLs do not replace ID/org verification.

## References

- `compatibility/current-profile.v1.json`
- `compatibility/no-loss-inventory.v1.json`
- `release-publish` — computes the exact EffectiveReleaseSet and release approval subject.
- `worker-bootstrap` — external workers remain available for custom functions, not built-in OCI Release delivery.
