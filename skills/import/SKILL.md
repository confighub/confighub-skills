---
name: import
description: 'Onboard Helm charts or local Kustomize bases/overlays into Component/Variant/Release. Use for the cub-helm plugin (install/upgrade/template), multi-env variants, CRDs/hooks, preserving downstream edits, or rendered manifests + cub variant upload. Not for live-cluster or GitOps-CR adoption.'
phase: act
allowed-tools: []
read-capability-subset: import
---

# import

**Authority boundary:** this companion is knowledge/read-only. It may inspect local source metadata and prepare an exact onboarding proposal, but it must not execute a renderer, install, upload, create, promote, publish, or other mutation. The protected render wrapper and external mutation broker are `NOT_INTEGRATED`, so rendering returns `RENDER_SOURCE_POLICY_BLOCK` and onboarding mutations end in `ASK` or `BLOCK`.

This skill preserves two onboarding jobs while aligning them to the installed model:

- **Helm:** `HelmSource Space → base Variant Space → deployment Variant Space → OCI Release`.
- **Kustomize:** rendered stream → base or explicit Variant Space → OCI Release.

After onboarding, prefer literal configuration-as-data plus ConfigHub functions and upstream/downstream promotion. A chart or overlay remains auditable source material, not hidden runtime state.

## Shared preflight

```bash
cub auth status
cub plugin list                 # is the helm plugin installed?
cub helm version                # only resolves once it is
cub helm install --help
cub helm upgrade --help
cub variant upload --help
cub variant create --help
cub release publish --help
```

**Helm is a plugin, not part of `cub`.** The `cub helm` command group is contributed by
[`confighub/cub-helm`](https://github.com/confighub/cub-helm) and has to be installed before any
of it resolves:

```bash
cub plugin install confighub/cub-helm       # latest release for this platform
cub plugin install confighub/cub-helm@v1.2.0   # or pin the release tag
cub plugin upgrade helm                     # later, to pick up a new version
```

Pin the tag when the profile has to be reproducible; an unpinned install takes whatever the latest
release is. `cub plugin list` reports the installed plugins and their status. The plugin
authenticates using the current `cub` session (`cub` passes `CUB_SERVER` / `CUB_TOKEN` when it
invokes a plugin), so `cub auth login` must have run first. If `cub helm` is absent, say so and
propose the install rather than reaching for stock `helm`.

The reviewed profile is exactly cub client v0.2.11, server v0.2.11, and cub helm add-on 0.1.0 (commits and client binary hash in `compatibility/current-profile.v1.json`). A different profile is `WATCH` or `BLOCK` until its help and semantics are reviewed; v0.2.10/v0.2.11 is explicitly unselected.

Before proposing any write, bind the organization/context, component, release name, chart or overlay source, pinned source revision/version, Variant Space slug, namespace, target, expected Unit set, and proof plan.

### Render-source preflight (before any renderer)

Run only the static `tools/check-render-source` preflight over one approved local source root. It canonicalizes the root, inventories regular-file count/bytes, rejects every symlink rather than following it, rejects duplicate YAML keys, and parses the reviewed Helm/Kustomize source fields without executing either renderer. For Helm it scans template actions throughout the tree (including unpacked vendored subcharts), blocks `lookup` and dynamic `tpl`, and refuses opaque dependency archives. For Kustomize it is version-bound to kustomize v5.8.1 / API module v0.21.1: it resolves `openapi.path`, resources/bases/components, CRDs/configurations, patch/replacement paths, and ConfigMap generator files/envs; it rejects unknown top-level or file-bearing nested fields, ambiguous `patchesStrategicMerge`, Secret generators, plugins, validators, and Helm inflators. Stop on any remote, absolute, escaping, missing, wrong-type, or unsupported reference.

A static pass is only `SOURCE_PREFLIGHT_PASS_RENDER_STILL_BLOCKED`. It does not create a trusted source digest or dependency-lock receipt, prove renderer egress is off, inspect a packaged archive, or bound rendered output/resources.

Raw `cub helm template`, `helm template`, `kustomize build`, and `kubectl kustomize` do not enforce that source closure or a rendered-byte/resource ceiling. The future wrapper specified by `compatibility/render-source-policy.v1.json` must run with network off, a read-only source closure, digest-pinned renderer, explicit source/output/document/resource bounds, secret scanning, and a truncation/input receipt. No such wrapper exists in this candidate, so passing static source inspection does not authorize a render.

---

## A. Helm onboarding

### What the plugin's `cub helm install` actually creates

```text
cub helm install <release-name> <chart-ref>
  ├─ <component>-helm   HelmSource Space (one HelmSource Unit per release)
  └─ <component>-base   untargeted base Variant Space
       └─ one Unit per chart template file
```

`templates/backend.yaml` becomes Unit `backend`; nested paths are flattened; `crds/foo.yaml` becomes a separate file-derived Unit such as `crds-foo`; subchart files are prefixed. It does **not** create a single `<release>` Unit plus a special `<release>-crds` Unit. The chart reference, values, and options are recorded as a `HelmSource` Unit in `<component>-helm`, which is the source of truth for upgrades.

Rendering is entirely client-side and never contacts a cluster: Helm hooks are dropped unless `--include-hooks` (which retains them only as ordinary resources), `lookup` returns nothing, and capabilities are Helm's defaults. Charts depending on any of that are out of scope; charts that render cleanly client-side work fully.

`cub helm install` and `cub helm upgrade` only ever touch `<component>-helm` and `<component>-base`. Deployments are created with `cub variant create` and updated with `cub variant promote` — the helm commands never touch them.

### Render remains blocked

After source preflight, record the exact local chart digest, vendored dependency digests, values-file digests, and intended renderer digest. Do not invoke `cub helm template` (the plugin's offline preview of the Units `install` would create) or another Helm renderer from this skill. A remote chart reference or version string alone is not a content pin and may trigger repository/network refresh. Return `RENDER_SOURCE_POLICY_BLOCK` until the protected wrapper exists. A separately supplied render artifact may be inspected as untrusted input, but it is not attributed to these sources without a trusted render receipt.

### Install proposal

```bash
cub helm install <release-name> <chart-ref> \
  --component <component> \
  --version <pinned-version> \
  --namespace <namespace> \
  --values <values-file>
```

Use only needed flags, and confirm them against the **installed plugin's** `--help` — the plugin versions independently of `cub`, so its flag set is not fixed by the server profile. In the reviewed 0.1.0 add-on the valid options include `--component`, `--create-namespace`, `--include-hooks`, `--namespace`, `--prefix`, `--repo`, `--set`, `--skip-crds`, `--values/-f`, `--version`, and `--wait`; there is no `--space` or `--update-crds`.

The base is untargeted. Do not claim the install deployed anything.

### Create deployment variants

```bash
cub variant create <variant> <component>-base \
  --target <target-space>/<target> \
  --namespace <namespace>
```

The destination slug defaults to `<component>-<variant>`. With an OCI target, the command sets Unit TargetIDs and the new Space's `ReleaseTargetID`. For a target created by `cub cluster up`, current `cub variant create --target` also creates the Argo CD Application unless `--no-argo-app` is explicitly chosen; that is a material side effect and must be in the proposal scope.

For dev, staging, and prod, propose one Variant per environment with its exact namespace/target/gates. Do not re-run Helm install into arbitrary env Spaces.

### Compatibility lane: materially different per-environment values

The shared-base route is correct only when environment differences can be expressed after rendering through namespace substitution and governed ConfigHub mutations. If the user's existing `values-dev.yaml`, `values-staging.yaml`, and `values-prod.yaml` materially change rendered resources and migration is not part of this change, preserve that job through **independent environment components**:

```bash
cub helm install <release>-<environment> <chart-ref> \
  --component <component>-<environment> \
  --version <pinned-version> \
  --namespace <namespace> \
  --values values-<environment>.yaml

cub variant create <environment> <component>-<environment>-base \
  --space-pattern 'template:{{.Labels.Component}}' \
  --target <target-space>/<target> --namespace <namespace>
```

The explicit space pattern keeps the deployment Space at `<component>-<environment>`; without it, the independent Component label plus Variant label would default to the duplicate `<component>-<environment>-<environment>`. This is intentionally different from the recommended shared component. Each environment gets its own HelmSource/base and upgrade stream; `cub variant promote` cannot flow one shared base across them. Bind and retain the exact values-file digest, chart digest/version, renderer/add-on version, rendered Unit identities, and environment target in each proposal. Never pretend a values file was absorbed into the ordinary shared Variant when it actually changed the rendered base.

Label this `HELM_VALUES_COMPATIBILITY`, explain the lost shared-promotion benefit, and offer a later migration: establish one common HelmSource/base, express durable environment differences on Variants with ConfigHub functions, diff every resource, then retire the independent components only after equivalence proof.

### Publish proposal

```bash
cub release publish <component>-<variant>
```

Hand off to `release-publish` first: it must compute the exact EffectiveReleaseSet and obtain new whole-Space approval. This skill never executes publication.

### Upgrade without losing downstream edits

```bash
cub helm upgrade <release-name> \
  --component <component> \
  --version <new-version>
```

Upgrade patches the HelmSource, re-renders from it, and reconciles `<component>-base`: changed file Units update, new files create Units, and disappeared files delete Units. That delete behavior is part of the approval subject.

The base is where the chart is authoritative, so an edit made in ConfigHub on top of a rendered Unit survives the next upgrade **only if its path is protected** — otherwise the re-render puts the chart's value back. Protect deliberately and sparingly; if the same path needs protecting after every upgrade, the value belongs in the chart values instead.

```bash
cub function set --space <component>-base --unit <unit> --protect set-replicas 5
```

Then preview each downstream Variant:

```bash
cub variant promote <component>-<variant> --dry-run -o mutations
```

If the merge is expected, prepare a governed `cub variant promote <component>-<variant> --changeset <component>-home/<slug>` proposal — the promotion walks the range and records one revision per upstream revision, so the ChangeSet is what makes it undoable. Downstream ConfigHub edits are merge inputs, and what the merge withheld shows up in `cub unit conflicts` rather than as a failure: check it explicitly before calling the promotion clean. Conflicts are `BLOCK` here, not permission to overwrite. After promotion, build a fresh `release-publish` ReleaseProposal. See `promote-release`.

### Helm stop conditions

- the `cub-helm` plugin is not installed, or its version is not the reviewed one;
- chart version/source is unpinned;
- chart/source/dependency is remote, not vendored, or can refresh over the network;
- renderer binary digest, source/output/resource ceilings, or trusted render receipt is missing;
- chart needs live cluster `lookup` or unsupported Helm hook lifecycle;
- materially different environment values are silently folded into one shared base instead of selecting and naming the compatibility lane;
- proposed flags are not present in installed help;
- upgrade would delete or unexpectedly rename file-derived Units;
- variant promotion conflicts or expands scope;
- external mutation broker is absent.

---

## B. Kustomize onboarding

This skill covers a local `kustomization.yaml`, not a Flux `Kustomization` CRD or an Argo CD `Application` adoption flow.

### Kustomize source preflight; render blocked

Inspect `kustomization.yaml` and the enumerated v0.21.1 file-bearing fields as data. The checker resolves every admitted path relative to its Kustomization and inside the canonical root, while unknown fields and unsupported executable/ambiguous forms fail closed. This is conservative static source closure, not a general proof for future Kustomize schemas. `kustomize build` and `kubectl kustomize` remain `RENDER_SOURCE_POLICY_BLOCK` because this companion has no network-off, read-only, byte/resource-capped renderer or trusted render receipt. Rendered Secrets remain out of scope for ConfigHub Units.

### Recommended migration: one base plus ConfigHub Variants

The future governed shape is: a trusted renderer produces a digest-addressed, bounded manifest receipt from the approved local source closure; a separate mutation proposal uploads exactly that artifact with `--granularity per-resource`. Never emit a raw `kustomize build | cub variant upload` pipeline from this skill.

Then prepare `cub variant create` proposals per environment, as in the Helm path, and express durable differences through ConfigHub functions/metadata. `--granularity per-resource` preserves the one-resource-per-Unit doctrine; use `per-file` only when the source file boundary is intentionally the ownership boundary.

Before handing any Kustomize Variant to `release-publish`, prove an existing controller binding for that exact Variant/Target (for example, the Argo Application auto-created by a reviewed `cub variant create --target` flow, or an explicitly governed Flux binding) and bind its source/target identity. A Target and Release alone do not prove that a controller watches the artifact. If the binding is absent or cannot be read, return `CONTROLLER_BINDING_UNPROVEN`; do not describe the upload path as deployable or promise runtime verification.

### Compatibility path: preserve existing overlays first

When each overlay already contains essential differences that cannot be migrated in this change, propose one explicit Variant upload per overlay:

For each overlay, require a separate trusted render receipt and prepare a separate upload proposal bound to its artifact digest, Component/Variant/Space, granularity, TargetID, and expected resource identities. Never combine render and upload in a shell pipeline.

Label this `MIGRATED_WITH_PARITY`, not the preferred steady state. Record the source repository, commit, overlay path, renderer version, and rendered content digest in the proposal.

If `kustomization.yaml` uses a Helm chart inflator, choose deliberately:

- use the Helm Component path when the chart/source lifecycle should remain first-class; or
- render the complete overlay once and upload the resulting stream when Kustomize composition is the authoritative input.

Do not run both and create duplicate resources.

### Kustomize stop conditions

- renderer fails or requires an unreviewed exec plugin;
- source closure includes a remote base/resource, symlink escape, unpinned dependency, Helm inflator fetch, or executable generator;
- protected renderer digest, network-off enforcement, output/resource ceilings, or render receipt is missing (`RENDER_SOURCE_POLICY_BLOCK`);
- rendered stream contains Secrets or live-cluster status;
- base/overlay identity collisions are unresolved;
- upload would replace an existing Variant without an exact diff;
- the target Variant lacks a verified Argo CD/Flux controller binding (`CONTROLLER_BINDING_UNPROVEN`);
- external mutation broker is absent.

## Read-only verification after external execution

```bash
cub space get <component>-helm -o json
cub space get <component>-base -o json
cub unit list --space <component>-base --select "HeadRevisionNum,ToolchainType,TargetID" -o json
cub space get <component>-<variant> -o json
cub unit tree --space <component>-<variant>
```

Verify expected file/resource-derived Unit identities, upstream links, namespace transforms, Unit TargetIDs, Space `ReleaseTargetID`, and gates. Then use `release-publish` and `verify-apply` for immutable Release, controller, and runtime proof.

## GUI handoff

- `cub component open <component> --variant <variant> --print-url`
- `cub space open <component>-base --print-url`
- `cub unit open <unit> --space <component>-<variant> --revisions --print-url`

## References

- `compatibility/current-profile.v1.json`
- `compatibility/no-loss-inventory.v1.json`
- `confighub-core` — configuration-as-data and Unit granularity.
- `promote-release` — Variant reconciliation, protection, and merge conflicts.
- [`confighub/cub-helm`](https://github.com/confighub/cub-helm) — the plugin contributing `cub helm`; its [guide](https://github.com/confighub/cub-helm/blob/main/docs/guide.md) covers values, namespaces, CRDs, hooks, and upgrades end to end.
- `target-bind`, `release-publish`, `verify-apply` — exact delivery chain.
