# Helm values.yaml on top of a ConfigHub Unit

## (a) What I'd tell the user

Short version: ConfigHub already gives you per-environment parameterization without needing a Helm `values.yaml` file on the side — and mixing the two tends to fight each other. Let me lay out the two real options and a recommendation.

### Option 1 (recommended): Use ConfigHub-native parameterization

ConfigHub's model is "config as data": the Unit *is* the source of truth, and you vary it per environment using spaces + upstream/downstream relationships plus mutators, not by layering a templating engine on top.

Concretely, for replica count and image tag:

1. Keep your current Unit (the Deployment) in a base space (e.g. `base`).
2. Create downstream spaces per environment (`dev`, `staging`, `prod`), each with a downstream Unit that inherits from the base.
3. In each downstream Unit, set the env-specific values with path-based mutations:
   - `cub unit update --patch --path spec.replicas=<N> <unit> --space <env>`
   - `cub unit update --patch --path 'spec.template.spec.containers.0.image=<repo>:<tag>' <unit> --space <env>`
   These become governed, reviewable revisions — the same trust surface as any other ConfigHub change.
4. Promote changes with `cub unit update --upgrade` (pulls base changes down) or by editing the downstream directly for env-only overrides.

You get the "tweak replicas + image tag per env" outcome, plus revisions, receipts, and a GUI diff — none of which a local `values.yaml` would give you.

### Option 2: If you genuinely need a Helm chart

If the goal is "I want to hand this to a Helm-based consumer," then the right move is to keep the chart as the Unit content: store the rendered Deployment (or the chart + values together) as Units, and still use ConfigHub spaces for per-env values. ConfigHub has Helm-aware import/toolchain support (see `cub` help for `helm` verbs) — but the `values.yaml` file stops being the per-env control plane; the ConfigHub space is.

### What I would NOT do

Create a `values.yaml` sitting next to the Unit as the per-env source of truth. That splits authority between a file and ConfigHub, and you lose the revision/receipt story for the two knobs you actually care about.

### Suggested next step

Tell me the Unit name + space and I'll set up `dev` / `staging` / `prod` downstream Units with replica + image-tag overrides, and show you the revisions in the GUI.

## (b) Commands I would run

I was not able to execute bash in this eval (permission denied), so these are the commands I would run, in order, once you confirm the Unit + space:

```bash
# 1. Confirm auth + current unit
cub info
cub unit list --space <base-space>
cub unit get <unit> --space <base-space>

# 2. Create per-env spaces downstream of base (if not already present)
cub space create dev     --upstream <base-space>
cub space create staging --upstream <base-space>
cub space create prod    --upstream <base-space>

# 3. Create downstream Units inheriting from the base Unit
cub unit create <unit> --space dev     --upstream-unit <unit> --upstream-space <base-space>
cub unit create <unit> --space staging --upstream-unit <unit> --upstream-space <base-space>
cub unit create <unit> --space prod    --upstream-unit <unit> --upstream-space <base-space>

# 4. Apply per-env overrides (replicas + image tag)
cub unit update <unit> --space dev \
  --patch --path spec.replicas=1 \
  --patch --path 'spec.template.spec.containers.0.image=myrepo/app:dev-abc123'

cub unit update <unit> --space staging \
  --patch --path spec.replicas=2 \
  --patch --path 'spec.template.spec.containers.0.image=myrepo/app:staging-abc123'

cub unit update <unit> --space prod \
  --patch --path spec.replicas=5 \
  --patch --path 'spec.template.spec.containers.0.image=myrepo/app:v1.4.0'

# 5. Show trust surface
cub unit get <unit> --space prod --web
cub revision list <unit> --space prod --web
```

Note: exact flag names (`--patch --path`, `--upstream-unit`, etc.) should be verified against `cub unit update --help` / `cub space create --help` before running — the repo CLAUDE.md is explicit about not inventing cub surfaces. If the patch-path verb differs, the pattern (downstream space + per-env override + revision) still holds; only the mutator syntax changes.

## (c) Reasoning notes

- The user framed this as "I want a values.yaml" but the underlying need is "tweak replicas + image tag per environment." Those are two different things.
- ConfigHub's config-as-data model already solves per-env parameterization via spaces + downstream Units + path mutations, with revisions and receipts as a free byproduct. A side-car `values.yaml` would undercut that by moving authority back into an ungoverned file.
- I want to be honest with the user instead of just doing what they asked — but I also want to give them a real path to the outcome (per-env replicas + image tag), not just say "no." Hence: recommendation + fallback + concrete next step.
- I deliberately did not mutate their Unit without knowing its name + base space. That's an ordinary-caution call, not a dev/test "just act" case, because I'd be creating 3 new spaces and 3 new Units.
