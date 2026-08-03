# Kubernetes/YAML functions worth knowing

Discover full semantics with:

```bash
CONFIGHUB_AGENT=1 cub function explain --toolchain Kubernetes/YAML <name>
```

Prefer a function over a hand-edit whenever one fits — functions are hermetic, idempotent, and preserve comments.

Get the full built-in function list with:

```bash
CONFIGHUB_AGENT=1 cub function list --toolchain Kubernetes/YAML <name>
```

## Getters

| Function                                                          | Purpose                                                                                        |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `get-container-image`                                             | Current image for a container. There is no get-container-images. Use get-container-image '\*'. |
| `get-container-image-reference`                                   | Just the tag/digest portion.                                                                   |
| `get-container-repository-uri`                                    | Just the registry + repo.                                                                      |
| `get-container-name`                                              | Container name.                                                                                |
| `get-env-var`                                                     | Environment variable value.                                                                    |
| `get-replicas`                                                    | Replicas for workload controllers.                                                             |
| `get-annotation` / `get-label`                                    | Metadata.                                                                                      |
| `get-namespace`                                                   | Namespace attribute.                                                                           |
| `get-placeholders`                                                | Find unfilled `confighubplaceholder` / `999999999` values.                                     |
| `get-path` / `get-string-path` / `get-int-path` / `get-bool-path` | Generic attribute path read.                                                                   |
| `get-cel`                                                         | Extract via CEL expression.                                                                    |
| `get-starlark`                                                    | Extract via Starlark `extract(r)` function.                                                    |
| `get-resources` / `get-resources-of-type`                         | List resources in a unit.                                                                      |
| `get-needed` / `get-provided`                                     | Needs/Provides attributes (see docs).                                                          |

## Setters

| Function                                                          | Purpose                                                      |
| ----------------------------------------------------------------- | ------------------------------------------------------------ |
| `set-container-image`                                             | Set a container's image. Prefer over deprecated `set-image`. |
| `set-container-image-reference`                                   | Update just tag/digest.                                      |
| `set-container-repository-uri`                                    | Update registry/repo.                                        |
| `set-image-registry-by-registry`                                  | Bulk registry prefix replace.                                |
| `set-replicas`                                                    | Replicas for workload controllers.                           |
| `set-env-var` / `set-env`                                         | Environment variables.                                       |
| `set-container-port`                                              | Add/modify a container port.                                 |
| `set-container-resources`                                         | Resource requests/limits.                                    |
| `set-container-volume-mount-path`                                 | Mount path; ensures pod volume.                              |
| `set-container-flag`                                              | POSIX-style `--flag=value` in container args.                |
| `set-annotation` / `set-label`                                    | Metadata.                                                    |
| `set-hostname` / `set-hostname-domain` / `set-hostname-subdomain` | Hostname fields.                                             |
| `set-default-names`                                               | Replace placeholder names.                                   |
| `set-bool-path` / `set-cel`                                       | Generic path / CEL-based set.                                |
| `set-attributes`                                                  | Read-modify-write with an `AttributeValueList`.              |
| `set-hash`                                                        | SHA-256 of values at a path → annotation.                    |

## Defaults (safe, idempotent, opt-in policy)

All of these accept no required parameters and only fill in fields that are missing. Safe to run repeatedly.

| Function                                      | Effect                                                                                                                                                                 |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `set-container-resources-defaults`            | Adds minimum resource requests (128m CPU / 128Mi mem) where none are set.                                                                                              |
| `set-container-probe-defaults`                | Adds liveness, readiness, startup probes using the first containerPort as HTTP GET.                                                                                    |
| `set-pod-container-security-context-defaults` | Sets pod- and container-level security context fields (seccomp, runAsNonRoot, runAsUser/Group, fsGroup, readOnlyRootFilesystem, allowPrivilegeEscalation, privileged). |
| `set-pod-security-defaults`                   | Adds `pod-security.kubernetes.io/*` labels (baseline enforce, restricted warn) on Namespaces.                                                                          |
| `set-automount-service-account-token-false`   | Sets `automountServiceAccountToken: false` on pod specs.                                                                                                               |
| `ensure-namespaces`                           | Adds a `namespace` field (placeholder if unset) to every namespaced resource.                                                                                          |

## Validators (`vet-*`)

All return pass/fail; none mutate. Wire them as Mutation triggers so they fail the publish path when they fail. See `references/triggers-recipes.md`.

| Function           | Checks                                                                                                                                                                         |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `vet-schemas`      | OpenAPI schema validation. Optional `--kubernetes-version=1.30.0`.                                                                                                             |
| `vet-placeholders` | No `confighubplaceholder` strings or `999999999` numbers remain.                                                                                                               |
| `vet-format`       | No YAML anchors/aliases, empty values, duplicate keys, truthy words (`yes/no/on/off/y/n`), old-style octals (`0755`).                                                          |
| `vet-merge-keys`   | No duplicate strategic-merge-patch keys (e.g., duplicate container or env-var names).                                                                                          |
| `vet-immutable`    | Immutable fields unchanged vs last applied revision. Optional `--attribute-name`. Passes if never applied.                                                                     |
| `vet-cel`          | CEL expression validates each resource. Replaces `vet-celexpr` / deprecated `cel-validate`. See the dedicated `vet-cel` section below for the return-value shape and examples. |
| `vet-approvedby`   | Sufficient approvers present. Replaces deprecated `is-approved`.                                                                                                               |

## `vet-cel` — CEL validator with structured failures

The preferred custom-policy validator. Expression is evaluated once per resource. Access the resource as `r` (alias for `object`). Parameters passed as `--param=key=value` are available via `params.key`. Kubernetes CEL libraries are available: `quantity()`, `url()`, `ip()`, `cidr()`, `regex()`, `format()`.

### Return value shape

The CEL expression must return **either** a `bool` **or** a `map` with these top-level keys (snake_case):

| Key                 | Type            | Purpose                                                                                      |
| ------------------- | --------------- | -------------------------------------------------------------------------------------------- |
| `passed`            | bool            | Pass/fail.                                                                                   |
| `details`           | list of strings | Freeform failure messages not tied to specific paths.                                        |
| `failed_attributes` | list of maps    | Path-specific findings. Preferred over `details` when you can point at a specific attribute. |

Other fields on the underlying Go `ValidationResult` API — `Issues`, `MaxScore`, `Score` on individual findings — exist but are **not currently extractable from a CEL return value** (the CEL parser wires up only the three keys above). If you need severity/identifier granularity, write a Go function instead of a CEL trigger.

### `failed_attributes` entry shape

Each entry is a map with **PascalCase** keys (matches the Go `AttributeValue` JSON encoding):

| Key             | Type   | Required | Description                                                                                      |
| --------------- | ------ | -------- | ------------------------------------------------------------------------------------------------ |
| `ResourceName`  | string | yes      | `<namespace>/<name>` for Kubernetes resources, or a provider-appropriate identifier.             |
| `ResourceType`  | string | yes      | `<apiVersion>/<kind>`, e.g. `apps/v1/Deployment`.                                                |
| `Path`          | string | yes      | The attribute path that failed, e.g. `spec.replicas` or `spec.template.spec.containers.0.image`. |
| `Value`         | any    | yes      | The offending value at that path.                                                                |
| `AttributeName` | string | no       | Registered attribute name if the path corresponds to one.                                        |
| `DataType`      | string | no       | Data type of the value.                                                                          |

If an entry sets just the minimum (`ResourceName`, `ResourceType`, `Path`, `Value`), the diagnostic still points cleanly at the right place.

### Examples

```bash
# Simple bool.
cub function vet --space "$s" --where "Slug = '$u'" \
  -- vet-cel 'r.kind != "Deployment" || r.spec.replicas >= 2'

# Structured with a freeform message.
cub function vet --space "$s" --where "Slug = '$u'" \
  -- vet-cel 'r.kind != "Deployment" || r.spec.replicas >= 2 ? {"passed": true} : {"passed": false, "details": [r.metadata.name + " has fewer than 2 replicas"]}'

# Structured with a path-specific finding — preferred when you can name the attribute.
cub function vet --space "$s" --where "Slug = '$u'" \
  -- vet-cel '
    r.kind != "Deployment" || r.spec.replicas >= 2 ?
      {"passed": true} :
      {
        "passed": false,
        "failed_attributes": [{
          "ResourceName": r.metadata.?namespace.orValue("") + "/" + r.metadata.name,
          "ResourceType": r.apiVersion + "/" + r.kind,
          "Path": "spec.replicas",
          "Value": r.spec.replicas
        }]
      }'

# Using the quantity() Kubernetes CEL library.
cub function vet --space "$s" --where "Slug = '$u'" \
  -- vet-cel 'r.kind != "Deployment" || r.spec.template.spec.containers.all(c, quantity(c.resources.limits["memory"]).isGreaterThan(quantity("64Mi")))'

# Parameterized.
cub function vet --space "$s" --where "Slug = '$u'" \
  --param=min=2 \
  -- vet-cel 'r.kind != "Deployment" || r.spec.replicas >= int(params.min)'
```

### Related

- `get-cel` — the non-validating counterpart. Returns a list of `AttributeValue` maps (same PascalCase shape) for arbitrary extraction. See the getters table above.
- Source of truth for return types in the public SDK (https://github.com/confighub/sdk): `core/function/api/validation_result.go` and `core/function/api/attribute_value.go`. CEL extractor: `function-impl/generic/cel.go`.

## yq escape hatches

Two variants — **watch the `-i` suffix**, it's the only thing separating read from write:

| Function | Mutating | Purpose                                                                                                |
| -------- | -------- | ------------------------------------------------------------------------------------------------------ |
| `get-yq` | **no**   | Run a yq expression and return the result. Read-only.                                                  |
| `set-yq` | **yes**  | Run a yq `-i` (in-place) expression and store the result back as the Unit's configuration data. Write. |

Prefer a purpose-built function when one exists (`set-container-image`, `set-replicas`, the defaults family, etc.). Reach for `get-yq` / `set-yq` only for the long tail where no dedicated function fits.

Examples:

```bash
# Read — get-yq, non-mutating.
cub function get --space "$space" --where "Slug = '$unit'" \
  --show output -- get-yq '.spec.template.spec.containers[0].image'

# Write — set-yq, mutating. Always pass --change-desc.
cub function set --space "$space" --where "Slug = '$unit'" \
  --change-desc "Bump replicas to 7. User prompt: … Clarifications: …" \
  -- set-yq '.spec.replicas = 7'

# Subset of documents.
cub function get --space "$space" --where "Slug = '$unit'" \
  --show output -- get-yq 'select(.kind == "Deployment") | .spec.replicas'

cub function set --space "$space" --where "Slug = '$unit'" \
  --change-desc "… " \
  -- set-yq 'with(select(.kind == "Deployment"); .spec.replicas = 3)'
```

## Mutation-graph helpers

| Function            | Purpose                                                      |
| ------------------- | ------------------------------------------------------------ |
| `compute-mutations` | Diff prior vs current config data; produces a mutation list. |
| `patch-mutations`   | Apply a mutation list selectively (patchable attrs).         |
| `reset`             | Revert attributes to placeholders where matching predicates. |
| `replicate`         | Produce N-1 additional replicas of a resource/element.       |
| `search-replace`    | Literal string replace across all resources.                 |
| `normalize`         | Assign unique ResourceIDs.                                   |
| `ensure-context`    | Add/remove context annotations (e.g., for `cub k8s source`). |

## Deprecated — don't use in new skills

- `set-image` → use `set-container-image`.
- `set-image-reference` → `set-container-image-reference`.
- `get-image` / `get-image-reference` / `get-image-uri` → container-prefixed equivalents.
- `cel-validate` → `vet-cel`.
- `vet-celexpr` → `vet-cel` (richer structured failures: `passed`, `details`, `failed_attributes`).
- `no-placeholders` → `vet-placeholders`.
- `is-approved` → `vet-approvedby`.
