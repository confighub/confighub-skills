# Triggers + ApplyGates — the platform-Space recipe

Triggers run functions automatically on lifecycle events (`Mutation`, `PostClone`). A validating function that returns false attaches an ApplyGate, which blocks apply until the failure is resolved.

## The recommended pattern

Rather than repeating trigger definitions per Space, centralize them:

1. Create a **platform** Space to hold Triggers.
2. Create a Filter that selects those Triggers.
3. On each application Space, set the `TriggerFilterID` to point at that Filter.

When anything mutates a Unit in an application Space, every Trigger selected by the Filter runs. No per-Space trigger maintenance.

## Recipe

```bash
# 1. Platform Space to hold triggers.
cub space create platform

# 2. Validating triggers on Mutation events in the platform space.
cub trigger create --space platform -o json vet-schemas        Mutation Kubernetes/YAML vet-schemas
cub trigger create --space platform -o json vet-placeholders   Mutation Kubernetes/YAML vet-placeholders
cub trigger create --space platform -o json vet-format         Mutation Kubernetes/YAML vet-format
cub trigger create --space platform -o json vet-merge-keys     Mutation Kubernetes/YAML vet-merge-keys
cub trigger create --space platform -o json vet-immutable      Mutation Kubernetes/YAML vet-immutable

# 3. Filter selecting those triggers.
cub filter create --space platform -o json standard-vets Trigger \
  --where-field "Space.Slug = 'platform' AND FunctionName LIKE 'vet-%'"

# 4. New application Space uses the filter.
cub space create myapp-prod --trigger-filter platform/standard-vets

# Existing Space: set trigger filter in-place.
cub space update myapp-prod --trigger-filter platform/standard-vets
```

(Confirm `cub space update --trigger-filter` via `--help` on your current cub version before using — flag may be renamed across versions.)

## When a gate attaches

If any `vet-*` trigger returns false, an ApplyGate is attached to the Unit. The Unit will not apply until either:

- The data is fixed (another mutation causes the triggers to re-run and pass).
- The gate is explicitly resolved (see `cub gate` / ApplyGate docs on your cub version).

Skills should **never bypass a gate**. Instead, fix the data and let the trigger re-validate.

## Adding custom policy

Use `vet-cel` for org-specific rules. Expression is evaluated once per resource; access the resource as `r` (alias for `object`). Return a `bool`, or a map with `passed` / `details` / `failed_attributes` for richer diagnostics. See `references/functions-catalog.md` → "`vet-cel` — CEL validator with structured failures" for the full return-value shape (including the PascalCase `failed_attributes` entry keys) and the Kubernetes CEL libraries.

```bash
# Require replicas >= 2 for Deployments (simple bool form).
cub trigger create --space platform -o json require-ha Mutation Kubernetes/YAML \
  vet-cel 'r.kind != "Deployment" || r.spec.replicas >= 2'

# Path-specific failure pointing at spec.replicas — preferred over a bare details message.
cub trigger create --space platform -o json require-ha Mutation Kubernetes/YAML \
  vet-cel '
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

# Disallow :latest.
cub trigger create --space platform -o json no-latest Mutation Kubernetes/YAML \
  vet-cel 'r.kind != "Deployment" || !r.spec.template.spec.containers.exists(c, c.image.endsWith(":latest"))'

# Enforce a memory-limit floor using the quantity() library.
cub trigger create --space platform -o json min-memory Mutation Kubernetes/YAML \
  vet-cel 'r.kind != "Deployment" || r.spec.template.spec.containers.all(c, quantity(c.resources.limits["memory"]).isGreaterThan(quantity("64Mi")))'

# Parameterized rule — minimum replicas supplied per Trigger instantiation.
cub trigger create --space platform -o json require-min-replicas Mutation Kubernetes/YAML \
  vet-cel --param=min=2 'r.kind != "Deployment" || r.spec.replicas >= int(params.min)'
```

Add `require-ha`, `no-latest`, etc. to your Filter (or broaden it) and every downstream Space inherits the rule.

## Approval gate (optional)

```bash
cub trigger create --space platform -o json require-approval Mutation Kubernetes/YAML \
  vet-approvedby 1
```

Approval policy is recorded as a gate until sufficient approvers sign off.

## Diagnosing a blocked apply

1. `cub unit get <slug> --space <app-space>` — shows attached gates.
2. `cub revision list <slug> --space <app-space>` — history of validating failures.
3. Inspect the trigger: `cub trigger get --space platform <trigger-slug>`.
4. Fix the data (e.g., `cub function do set-container-image …`) — the Mutation triggers re-run.

Never drop the trigger or delete the gate to "make it apply."
