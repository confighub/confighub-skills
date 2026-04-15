# Helm-style values.yaml on top of a ConfigHub Unit

## (a) What I'd tell the user

Short version: don't add a `values.yaml`. In ConfigHub, the Unit *is* the data — the YAML inside a Unit is fully materialized, with literal values for every field. The moment you layer a values file or template on top, you lose the things you're actually using ConfigHub for: query across Units, mutation-graph, revision history, cub functions operating on real data, and clean diffs.

The ConfigHub-native way to get "tweak replicas and image tag per environment" is:

1. **One Space per environment** (e.g. `myapp-dev`, `myapp-staging`, `myapp-prod`). The Space is your parameterization boundary — it replaces `values-dev.yaml` / `values-prod.yaml`.
2. **Your current Unit becomes the upstream/baseline.** Clone it into each env Space as a downstream Unit. Changes to the baseline flow down; env-specific overrides stay local to each downstream.
3. **Apply the per-env differences with cub functions, not a values file.** Each call records a clean revision:
   - `cub function do ... set-replicas --num 3` (or whatever the env needs)
   - `cub function do ... set-container-image --container <name> --image myapp:v1.4.2`
   - For other knobs: `set-env-var`, `set-container-resources-defaults`, etc.

That gives you exactly what a values file gives you (per-env replica count + image tag) with three things a values file can't: a diff view in the GUI, revision history per change, and the ability to promote an image tag through envs as a governed operation rather than a text edit.

If there's a specific field you expected to put in `values.yaml` that doesn't map cleanly to an existing function, tell me what it is — we either use a more general function, or (rare) hand-edit the downstream Unit's YAML directly. Still no template layer.

One thing to flag: if you're migrating from an existing Helm chart, that's a one-shot `helm template` → store the rendered YAML as a Unit → never re-render. Different flow; let me know and I'll walk through it.

## (b) Commands — recommended next steps (not executed)

I didn't mutate anything; this is conversational. If you want to proceed, here's the concrete shape, assuming your current Unit is `myapp` in Space `myapp-base`:

```bash
# 1. Create per-env spaces
cub space create myapp-dev
cub space create myapp-prod

# 2. Clone baseline into each env as downstream
cub unit create --space myapp-dev  myapp --upstream-unit myapp --upstream-space myapp-base \
  --change-desc "dev downstream of myapp

User prompt: have a values.yaml where I can tweak the replica count and image tag per environment
Clarifications: using Space-per-env instead of values file"

cub unit create --space myapp-prod myapp --upstream-unit myapp --upstream-space myapp-base \
  --change-desc "prod downstream of myapp

User prompt: <same>
Clarifications: <same>"

# 3. Apply env-specific replicas + image tag via functions
cub function do --space myapp-dev  --where "Slug = 'myapp'" set-replicas --num 1 \
  --change-desc "dev: 1 replica

User prompt: tweak replica count per environment
Clarifications: none"

cub function do --space myapp-prod --where "Slug = 'myapp'" set-replicas --num 3 \
  --change-desc "prod: 3 replicas

User prompt: tweak replica count per environment
Clarifications: none"

cub function do --space myapp-dev  --where "Slug = 'myapp'" \
  set-container-image --container myapp --image myapp:dev-latest --change-desc "..."
cub function do --space myapp-prod --where "Slug = 'myapp'" \
  set-container-image --container myapp --image myapp:v1.4.2      --change-desc "..."

# 4. Inspect + verify
cub unit get myapp --space myapp-dev --web
cub function do --space myapp-dev --where "Slug = 'myapp'" vet-placeholders
cub function do --space myapp-dev --where "Slug = 'myapp'" vet-schemas
```

Exact function flag names (`--num`, `--container`, `--image`) should be confirmed with `cub function explain set-replicas` / `cub function explain set-container-image` before running — I'd normally do that first.

## (c) Reasoning notes

- The `config-as-data` skill is explicitly triggered by "values file" and "parameterize" phrasing. Its core rule: Units contain fully-materialized literal YAML; no templates, no values files, no overlays layered on stored Units.
- The skill prescribes a direct substitute for values-file parameterization: **Space-per-env + upstream/downstream Units + functions for per-env deltas.** That maps 1:1 to the user's two asks (replicas, image tag).
- I did not run `cub` commands because (i) the task is framed as conversational, (ii) I don't know the user's existing Space/Unit slug, and (iii) mutations require a `--change-desc` that quotes the verbatim user prompt — better to show the pattern and let the user approve.
- Stop condition from the skill: if the user insists on a values file after hearing the rule, I hand back. I've framed the response to make the rule clear once, offer the native alternative concretely, and leave the door open for the migration-from-Helm case which has a different (one-shot render) flow.
