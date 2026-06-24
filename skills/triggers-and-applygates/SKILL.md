---
name: triggers-and-applygates
description: 'Make validation enforced or advisory, via the platform-Space + Filter + TriggerFilterID pattern — Triggers that attach a blocking ApplyGate, or a non-blocking ApplyWarning (--warn), when validation fails. Use for "block bad config from being deployed", "wire up schema validation", "enforce a policy", "warn but don''t block", "why is this Unit blocked?", "what warnings does this Unit have?". Not for one-off validator runs (use cub-mutate).'
phase: decide
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub space create *) Bash(cub space update *) Bash(cub trigger create *) Bash(cub trigger update *) Bash(cub filter create *) Bash(cub filter update *) Bash(cub unit update *) Bash(cub function *) Bash(cub run *)
---

# triggers-and-applygates

Make validation enforced, not advisory. Without Triggers, `vet-*` functions are suggestions; with Triggers, they either **block** the apply path (an ApplyGate) or **flag** it without blocking (an ApplyWarning) — see [Blocking vs warning](#blocking-vs-warning-applygates-and-applywarnings).

## When to use

- Setting up a new Space (or retrofitting existing Spaces) and the user wants policy to be enforced.
- User asks "how do I make sure bad config can't be deployed?", "wire up schema validation", "add a policy", "require approval before apply".
- User is diagnosing a Unit that won't apply and the reason might be an ApplyGate, or wants to see what non-blocking ApplyWarnings a Unit carries.
- User wants a check to advise rather than block (a `--warn` Trigger producing ApplyWarnings), or to flip an existing check between blocking and advisory.
- Migrating validation from ad-hoc `cub function vet vet-*` calls to automatic enforcement.

## Do not load for

- One-off validation runs (use `cub-mutate` or a direct `cub function vet vet-schemas …`).
- Authoring YAML (use `confighub-core`).
- Fixing the config itself — this skill diagnoses and sets up gates; fixing is `cub-mutate`.

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
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
  cub trigger create --space platform -o json "$t" Mutation Kubernetes/YAML "$t"
done

# 3. Filter selecting those Triggers.
cub filter create --space platform -o json standard-vets Trigger \
  --where-field "Space.Slug = 'platform' AND FunctionName LIKE 'vet-%'"
```

Verify flag spellings with `CONFIGHUB_AGENT=1 cub space create --help`, `cub trigger create --help`, `cub filter create --help` — flag names evolve across cub versions.

## Attaching the filter to Spaces

```bash
# New Space using the filter.
cub space create myapp-prod --trigger-filter platform/standard-vets --where-trigger "-"

# Existing Space — confirm flag spelling first.
cub space update myapp-prod --trigger-filter platform/standard-vets --where-trigger "-"
```

**Why `--where-trigger "-"`**: `WhereTrigger` and `TriggerFilterID` combine — both must match for a Trigger to apply to the Space. Every Space is created with a default `WhereTrigger = SpaceID = '<this-space>'` so Triggers defined in the Space itself apply by default. When you attach a cross-Space `--trigger-filter` (e.g., Triggers living in `platform`), that default still applies and nothing matches both predicates, so `# Triggers = 0` in `cub space get` even though `cub trigger list --filter <slug>` resolves the filter correctly. To use the filter alone, clear the default with `--where-trigger "-"` (the sentinel; plain `""` is indistinguishable from "flag not set"). Keep both predicates when you actually want the union's intersection — e.g., Space-local Triggers plus the platform baseline. Verify with `cub space get -o json <space>` — `Triggers` should be populated.

## Adding custom policy

`vet-cel` evaluated once per resource (`r` aliases `object`). Return a `bool` for simple pass/fail; return a map with top-level snake_case keys `passed`, `details`, `failed_attributes` for diagnostics. Prefer `failed_attributes` (path-specific, with PascalCase entry keys `ResourceName`/`ResourceType`/`Path`/`Value`) over `details` when you can point at a specific attribute. Full shape and the Kubernetes CEL libraries (`quantity()`, `url()`, `ip()`, `cidr()`, `regex()`, `format()`) are documented in `references/functions-catalog.md` → "`vet-cel` — CEL validator with structured failures".

```bash
# Simple bool form.
cub trigger create --space platform -o json require-ha Mutation Kubernetes/YAML \
  vet-cel 'r.kind != "Deployment" || r.spec.replicas >= 2'

# Path-specific failure — preferred over freeform details when you can name the attribute.
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
```

See `references/triggers-recipes.md` for parameterized rules (`--param=key=value` → `params.key`) and `quantity()`-based numeric policy examples. If the Filter already matches (`FunctionName LIKE 'vet-%'` + platform scope), new Triggers propagate automatically.

## Approval gate

```bash
cub trigger create --space platform -o json require-approval Mutation Kubernetes/YAML \
  vet-approvedby 1
```

## Blocking vs warning: ApplyGates and ApplyWarnings

A failing Trigger produces one of two outcomes, tracked in two **separate** Unit fields with the same `<space>/<trigger>/<function>` key shape:

| Trigger | Failure records | Effect on apply |
| --- | --- | --- |
| default (`--warn` omitted) | `ApplyGates` | **Blocks** — apply is refused until the gate clears |
| `--warn` | `ApplyWarnings` | **Advisory** — recorded on the Unit, apply still proceeds |

Pass `--warn` on `cub trigger create` to make a check advisory: *"Set trigger to produce ApplyWarnings instead of ApplyGates."* The same validator (`vet-cel`, `vet-kyverno`, `vet-schemas`, …) can be a gate in prod and a warning in dev — the `--warn` flag is what differs, not the function. Add `--description` so the recorded failure explains how to fix it.

```bash
# Advisory check — surfaces an ApplyWarning, never blocks.
cub trigger create --space platform -o json --warn \
  --description "Probes recommended; warning only outside prod" \
  liveness-readiness-check Mutation Kubernetes/YAML \
  vet-cel 'r.kind != "Deployment" || r.spec.template.spec.containers.all(c, has(c.livenessProbe))'
```

`cub trigger list` shows a `WARN` column distinguishing the two. To flip an existing Trigger between tiers: `cub trigger update <slug> --warn` makes it advisory, `--unwarn` makes it blocking again (the default). Both take `--patch` for bulk flips, e.g. `cub trigger update --patch --where "Event = 'Mutation'" --warn`.

### Querying both tiers

```bash
# Blocked Units (gates).
cub unit list --space <space> --where "LEN(ApplyGates) > 0" --columns Unit.Slug,Unit.ApplyGates

# Units carrying warnings (still appliable).
cub unit list --space <space> --where "LEN(ApplyWarnings) > 0" --columns Unit.Slug,Unit.ApplyWarnings

# Raw map per Unit (which warnings, keyed by trigger).
cub unit list --space <space> -o "jq=.[].Unit.ApplyWarnings" --select ApplyWarnings
```

A Unit can carry warnings and apply cleanly; only a non-empty `ApplyGates` blocks. When triaging a Space, check **both** — warnings are the "tech debt" tier you fix on your own schedule, gates are the hard stop.

## Diagnosing a blocked apply

1. `cub unit get <slug> --space <space>` — shows attached ApplyGates/ApplyWarnings as `<space>/<trigger>/<function>` keys. The default text view stops at the keys — it does **not** print the failure message.
1a. **For the actual failure message, read `Unit.ValidationResults`** — a map under the same keys, each entry carrying human-readable `Details[]` and structured `FailedAttributes[]` (e.g. the kyverno policy/rule `Identifier` + `Message`, plus `ResourceType` and `ResourceName`). This is what turns "gated by X" into "here's exactly what X objected to", and it covers warnings too:
   ```bash
   cub unit get <slug> --space <space> -o "jq=.Unit.ValidationResults"
   # just one trigger:
   cub unit get <slug> --space <space> \
     -o 'jq=.Unit.ValidationResults["<space>/<trigger>/vet-kyverno"]'
   ```
   (`-o jq=<expr>` applies the jq expression to the output directly — no piping to a separate `jq`.)
2. `cub revision list <slug> --space <space>` — find the revision that failed validation; the `--change-desc` should indicate what the user was trying to do.
3. `cub trigger get --space platform <trigger-slug>` — see what the Trigger is checking.
4. Fix the data via `cub function set` or `cub unit update` — the Mutation Triggers re-run automatically and release the gate if it passes.

If the Unit applies but you want to know what's flagged on it, inspect `ApplyWarnings` instead (`cub unit get` shows it, or query with `--where "LEN(ApplyWarnings) > 0"`). Same fix loop — correcting the data re-runs the Trigger and clears the warning — but there's no apply block forcing the issue, so warnings persist until someone chooses to address them.

**Never** bypass a gate by dropping the Trigger, deleting the Filter, demoting it to `--warn`, or editing gate state directly. If a rule is genuinely wrong, fix the Trigger in `platform` (with `--change-desc` recording why) so the whole fleet benefits.

## Tool boundary

- Allowed: `cub space / trigger / filter / unit / revision` — Unit-data mutations (`cub unit update`, `cub function set`, `cub run`) must pass `--change-desc`.
- Not allowed: bypassing gates, disabling Triggers to unblock a single Unit, editing ApplyGates by hand.

## Change description

`--change-desc` is a Unit-data-mutation flag only. It applies to `cub unit update`, `cub function set`, `cub run`, and `cub unit update --patch`. **It does not apply** to `cub space create/update`, `cub trigger create/update/delete`, `cub filter create/update/delete`, `cub target create/update`, or `cub worker create/update` — those entities aren't versioned configuration data and will reject the flag with `unknown flag: --change-desc`. The audit trail for Space/Trigger/Filter/Target/Worker operations is the entity's own history, not a per-call description.

When this skill's flow does cause a Unit-data mutation (e.g., `cub unit update` while resolving a blocked apply), compose the description as:

```
<summary: "Fix placeholder that was blocking vet-placeholders gate">

User prompt: <verbatim>
Clarifications: <condensed — e.g., "user confirmed the namespace value should be 'prod'">
```

## Stop conditions

- User asks to bypass or remove an ApplyGate to force apply. Stop — fix the data instead, or update the policy upstream.
- Flag spellings don't match what `--help` reports. Stop and re-check before guessing.

## Verify chain

1. `cub trigger list --space platform` — Triggers present.
2. `cub filter get --space platform standard-vets` — Filter selects the expected Triggers.
3. `cub space get <app-space>` — `TriggerFilterID` references the Filter.
4. Deliberately make a violating edit (e.g., introduce a placeholder) in a test Unit → confirm an ApplyGate attaches → fix → confirm it releases.
5. For a `--warn` Trigger, confirm the violation lands in `ApplyWarnings` (not `ApplyGates`) and that apply still succeeds: `cub unit list --space <space> --where "LEN(ApplyWarnings) > 0"`.

## Evidence

- `cub space get <space> --web` — Space page shows attached Triggers/Filter.
- `cub unit get <slug> --space <space> --web` — shows gates/warnings on a Unit.
- `cub unit get <slug> --space <space> -o "jq=.Unit.ValidationResults"` — the failure messages behind each gate/warning (`Details[]` + `FailedAttributes[]`).
- `cub trigger get --space platform <slug> --web` — Trigger details.

## References

- `references/triggers-recipes.md`
- `references/functions-catalog.md` — which `vet-*` does what.
- `references/cub-cli.md`
- https://docs.confighub.com/markdown/guide/validation-and-policies.md
