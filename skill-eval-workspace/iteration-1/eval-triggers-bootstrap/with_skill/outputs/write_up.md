# Triggers + ApplyGates bootstrap — eval write-up

## User request
"We're starting to use ConfigHub and I want to make sure nobody can apply Kubernetes config that fails schema validation or still has placeholders. Set up the enforcement so this just works for every new Space we create."

## Interpretation (per skill `triggers-and-applygates`)
The skill's platform-Space + Filter + `TriggerFilterID` pattern exactly matches the ask:

1. One dedicated `platform` Space holds org-wide Triggers.
2. Baseline Triggers on `Mutation` / `Kubernetes/YAML` run `vet-schemas` and `vet-placeholders`; when a Unit's data fails, the Trigger attaches an ApplyGate that blocks apply until the data is fixed.
3. A `Trigger` Filter named `standard-vets` selects every `vet-%` Trigger in `platform`. Application Spaces reference this Filter via `--trigger-filter platform/standard-vets`, so policy is defined once and inherited by every Space that wires it in.
4. New vet-* Triggers added to `platform` later are automatically picked up by the Filter and propagate to every Space that references it.

## What I did

1. Discovered state. Confirmed via `cub space list` that no `platform` Space existed and ~17 other Spaces are present (none named `platform`).
2. Consulted CLI help under `CONFIGHUB_AGENT=1` for `cub space create` and `cub trigger create` to verify flag spellings (per the skill's explicit reminder that flag names evolve).
3. Created the `platform` Space:
   - `cub space create platform` → `Successfully created space platform (a2770b6c-d90b-47ac-8ba6-803ae5a7a816)`
   - I initially tried with `--change-desc "…"` (per the skill's "Change description" section). That flag does not exist on `cub space create` in this cub build — this is a skill documentation bug to report. The Space was created without it.
4. Attempted to create baseline Triggers and the `standard-vets` Filter. These CLI calls were denied by the eval sandbox even though the skill's `allowed-tools` frontmatter lists `cub trigger create *` and `cub filter create *`. I tried several argument orderings and both with/without `CONFIGHUB_AGENT=1`; all `cub trigger *` and `cub filter *` invocations returned "Permission to use Bash has been denied." (`cub space *` and `cub * list` worked fine.) See `commands.log` for the exact attempts.

## Final state on Brian's test instance

- `platform` Space exists (UUID `a2770b6c-d90b-47ac-8ba6-803ae5a7a816`), empty — no Units, Triggers, or Filters.
- Baseline `vet-schemas` and `vet-placeholders` Mutation Triggers: NOT created (sandbox denial).
- `standard-vets` Trigger Filter: NOT created (sandbox denial).
- No application Spaces were wired with `--trigger-filter` (nothing to reference yet).

## Would enforcement actually catch failures on a new Space?

Not yet, because the Triggers and Filter were not actually created. If the missing steps below are run and verified, then **yes** — here is why, based on the skill:

- Triggers fire on `Mutation` events, so any `cub function do`, `cub unit update`, or `cub unit create` that touches Kubernetes/YAML data in a Space that references the Filter will run `vet-schemas` + `vet-placeholders` server-side.
- A failing result attaches an ApplyGate on the Unit; `cub unit apply` is blocked until the Unit is fixed. The skill explicitly prohibits bypassing gates by deleting Triggers or the Filter — you fix the data, the Mutation Triggers rerun automatically, and the gate releases.
- Every **new** Space that the user creates with `cub space create <slug> --trigger-filter platform/standard-vets` (or updates via `cub space update <slug> --trigger-filter platform/standard-vets`) inherits enforcement with no further per-Space setup.
- "Just works for every new Space" becomes literally true only if the team's Space-creation convention (script, template, onboarding doc) includes that `--trigger-filter` flag. The skill does **not** install a cluster-wide default — Spaces must opt in once at creation. That is a truthful caveat worth raising with the user.

## Commands needed to finish the bootstrap (blocked by sandbox here)

```
cub trigger create --space platform --json vet-schemas      Mutation Kubernetes/YAML vet-schemas
cub trigger create --space platform --json vet-placeholders Mutation Kubernetes/YAML vet-placeholders
cub filter create  --space platform --json standard-vets Trigger \
    --where-field "Space.Slug = 'platform' AND FunctionName LIKE 'vet-%'"

# verify
cub trigger list --space platform
cub filter get   --space platform standard-vets

# use on a new Space
cub space create myapp-dev --trigger-filter platform/standard-vets
```

## Deliberately-failing Unit verification

Not attempted — Trigger/Filter creation was blocked, so there was nothing to gate against. The documented pattern for verification is in SKILL.md "Verify chain" step 4:
> Deliberately make a violating edit (e.g., introduce a placeholder) in a test Unit → confirm an ApplyGate attaches → fix → confirm it releases.

A concrete test would be: `cub unit create demo-bad --space <space-with-filter>` with a Deployment that has literal `{{PLACEHOLDER}}` in `image:`. Expected: an ApplyGate attributed to the `vet-placeholders` Trigger appears on the Unit (visible via `cub unit get demo-bad --space <space>`), and `cub unit apply` is blocked until the placeholder is replaced with a real image.

## Issues to report back to the skill author

1. **Flag mismatch: `--change-desc` on `cub space create`.** The skill's template includes it; current cub build rejects it with "unknown flag: --change-desc". Suggest the skill check `--help` per-command (already recommended in the skill body) and note that `space create` in particular does not support it.
2. **Function name mismatch: `vet-cel` vs `vet-celexpr`.** SKILL.md uses `vet-cel`; `cub trigger create --help` lists `vet-celexpr`. Examples under "Adding custom policy" will fail as written. Recommend a global rename to `vet-celexpr`.
3. The skill's guidance to check `--help` first (it says flags evolve) is correct and saved me from a worse miscall — worth keeping.

## Scratch slug used
- `platform` (UUID `a2770b6c-d90b-47ac-8ba6-803ae5a7a816`). Not deleted per task rules. If you want the eval re-run cleanly, either reuse this empty Space (next run will just add the Triggers + Filter to it) or ask and I can delete it.
