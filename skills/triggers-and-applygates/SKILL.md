---
name: triggers-and-applygates
description: Use when the user wants validation to be enforced (not just advisory) on ConfigHub Units, is setting up a new Space and wants policy to apply automatically, asks about ApplyGates, says "block bad config from being deployed", "wire up schema validation", "enforce a policy", "require approval", or needs to diagnose why a Unit is blocked from applying. This skill installs the platform-Space + Filter + TriggerFilterID pattern — centralized Triggers that run on every Mutation and attach ApplyGates when validation fails. Do not load for: running validators one-off without installing them (use cub-mutate with vet-* functions instead), or for authoring the YAML itself.
phase: decide
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub space create *) Bash(cub space update *) Bash(cub trigger create *) Bash(cub trigger update *) Bash(cub filter create *) Bash(cub filter update *) Bash(cub unit update *) Bash(cub function do *) Bash(cub run *)
---

# triggers-and-applygates

Make validation enforced, not advisory. Without Triggers, `vet-*` functions are suggestions; with Triggers, they block the apply path.

## When to use

- Setting up a new Space (or retrofitting existing Spaces) and the user wants policy to be enforced.
- User asks "how do I make sure bad config can't be deployed?", "wire up schema validation", "add a policy", "require approval before apply".
- User is diagnosing a Unit that won't apply and the reason might be an ApplyGate.
- Migrating validation from ad-hoc `cub function do vet-*` calls to automatic enforcement.

## Do not load for

- One-off validation runs (use `cub-mutate` or a direct `cub function do vet-schemas …`).
- Authoring YAML (use `config-as-data`).
- Fixing the config itself — this skill diagnoses and sets up gates; fixing is `cub-mutate`.

## Preflight gates

1. `cub context get` returns a user.
2. User has write permission on the `platform` Space (or whichever Space will hold Triggers) and on the target application Spaces.
3. Confirm with the user: should Triggers be centralized in a `platform` Space, or do they already have a different convention? Default recommendation is `platform`.

## The platform-Space pattern

Best practice: one dedicated Space holds Triggers. A Filter selects them. Application Spaces reference that Filter via `TriggerFilterID`. This means you define policy once; every Space that uses the Filter inherits it.

```bash
# 1. Platform Space.
cub space create platform \
  --change-desc "Create platform space to hold org-wide Triggers. User prompt: <verbatim>. Clarifications: <condensed>"

# 2. Baseline vet-* Triggers on Mutation.
for t in vet-schemas vet-placeholders vet-format vet-merge-keys vet-immutable; do
  cub trigger create --space platform --json "$t" Mutation Kubernetes/YAML "$t"
done

# 3. Filter selecting those Triggers.
cub filter create --space platform --json standard-vets Trigger \
  --where-field "Space.Slug = 'platform' AND FunctionName LIKE 'vet-%'"
```

Verify flag spellings with `CONFIGHUB_AGENT=1 cub space create --help`, `cub trigger create --help`, `cub filter create --help` — flag names evolve across cub versions.

## Attaching the filter to Spaces

```bash
# New Space using the filter.
cub space create myapp-prod --trigger-filter platform/standard-vets

# Existing Space — confirm flag spelling first.
cub space update myapp-prod --trigger-filter platform/standard-vets
```

## Adding custom policy

`vet-cel` evaluated once per resource (`r` aliases `object`). Return a `bool` for simple pass/fail; return a map with top-level snake_case keys `passed`, `details`, `failed_attributes` for diagnostics. Prefer `failed_attributes` (path-specific, with PascalCase entry keys `ResourceName`/`ResourceType`/`Path`/`Value`) over `details` when you can point at a specific attribute. Full shape and the Kubernetes CEL libraries (`quantity()`, `url()`, `ip()`, `cidr()`, `regex()`, `format()`) are documented in `references/functions-catalog.md` → "`vet-cel` — CEL validator with structured failures".

```bash
# Simple bool form.
cub trigger create --space platform --json require-ha Mutation Kubernetes/YAML \
  vet-cel 'r.kind != "Deployment" || r.spec.replicas >= 2'

# Path-specific failure — preferred over freeform details when you can name the attribute.
cub trigger create --space platform --json require-ha Mutation Kubernetes/YAML \
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
cub trigger create --space platform --json no-latest Mutation Kubernetes/YAML \
  vet-cel 'r.kind != "Deployment" || !r.spec.template.spec.containers.exists(c, c.image.endsWith(":latest"))'
```

See `references/triggers-recipes.md` for parameterized rules (`--param=key=value` → `params.key`) and `quantity()`-based numeric policy examples. If the Filter already matches (`FunctionName LIKE 'vet-%'` + platform scope), new Triggers propagate automatically.

## Approval gate

```bash
cub trigger create --space platform --json require-approval Mutation Kubernetes/YAML \
  vet-approvedby 1
```

## Diagnosing a blocked apply

1. `cub unit get <slug> --space <space>` — shows attached ApplyGates and which Trigger produced them.
2. `cub revision list <slug> --space <space>` — find the revision that failed validation; the `--change-desc` should indicate what the user was trying to do.
3. `cub trigger get --space platform <trigger-slug>` — see what the Trigger is checking.
4. Fix the data via `cub function do` or `cub unit update` — the Mutation Triggers re-run automatically and release the gate if it passes.

**Never** bypass a gate by dropping the Trigger, deleting the Filter, or editing gate state directly. If a rule is genuinely wrong, fix the Trigger in `platform` (with `--change-desc` recording why) so the whole fleet benefits.

## Tool boundary

- Allowed: `cub space / trigger / filter / unit / revision` — all with `--change-desc` when mutating.
- Not allowed: bypassing gates, disabling Triggers to unblock a single Unit, editing ApplyGates by hand.

## Change description

Every `cub space create/update`, `cub trigger create/update/delete`, `cub filter create/update/delete` call passes `--change-desc`:

```
<summary: "Add require-ha trigger to platform space">

User prompt: <verbatim>
Clarifications: <condensed — e.g., "user confirmed min replicas = 2, not 3">
```

## Stop conditions

- User asks to bypass or remove an ApplyGate to force apply. Stop — fix the data instead, or update the policy upstream.
- Flag spellings don't match what `--help` reports. Stop and re-check before guessing.

## Verify chain

1. `cub trigger list --space platform` — Triggers present.
2. `cub filter get --space platform standard-vets` — Filter selects the expected Triggers.
3. `cub space get <app-space>` — `TriggerFilterID` references the Filter.
4. Deliberately make a violating edit (e.g., introduce a placeholder) in a test Unit → confirm an ApplyGate attaches → fix → confirm it releases.

## Evidence

- `cub space get <space> --web` — Space page shows attached Triggers/Filter.
- `cub unit get <slug> --space <space> --web` — shows gates on a Unit.
- `cub trigger get --space platform <slug> --web` — Trigger details.

## References

- `references/triggers-recipes.md`
- `references/functions-catalog.md` — which `vet-*` does what.
- `references/cub-cli.md`
