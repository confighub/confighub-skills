# Assertions drafted while subagents run

Applied to each eval's output after grading. Each assertion should be objectively verifiable from `write_up.md` + `commands.log`.

## eval-config-as-data-helm-values

What the with-skill agent should do:
- Decline the values.yaml request cleanly (not add a values file, not add template syntax).
- Explain the config-as-data rule: Units contain literal YAML, no parameterization at rest.
- Recommend the ConfigHub-native alternative: one Space per environment, functions for per-env differences (`set-replicas`, `set-container-image`, `set-env-var`), upstream/downstream Unit relationships.

Assertions (pass/fail per run):
1. `declines_helm_values` — does not recommend or create a values.yaml, `--set`, or template syntax.
2. `explains_literal_yaml` — states that Units contain literal, fully-materialized YAML without parameterization.
3. `recommends_space_per_env` — recommends one Space per application × environment (or per environment) as the variation boundary.
4. `names_specific_functions` — mentions at least one concrete cub function for per-env variation (e.g., `set-container-image`, `set-replicas`, `set-env-var`).
5. `offers_upstream_downstream` — mentions upstream/downstream Unit relationships or unit cloning for baseline reuse.
6. `no_mutation_to_introduce_templates` — does not run cub commands to create a templating construct in a Unit.

## eval-triggers-bootstrap

What the with-skill agent should do:
- Create a platform Space (or confirm one exists) to hold shared Triggers.
- Create Mutation-event Triggers for Kubernetes/YAML invoking at minimum `vet-schemas` and `vet-placeholders`; ideally also `vet-format`, `vet-merge-keys`, `vet-immutable`.
- Create a Filter of type Trigger selecting those Triggers.
- Demonstrate (or at least document) `cub space create --trigger-filter <platform-space>/<filter-slug>` so new Spaces inherit.
- Never suggest bypassing a gate.

Assertions:
1. `created_platform_space` — created a Space to hold shared Triggers (slug = `platform` or reasonable equivalent).
2. `created_vet_schemas_trigger` — created a Trigger invoking `vet-schemas` on Mutation for Kubernetes/YAML.
3. `created_vet_placeholders_trigger` — created a Trigger invoking `vet-placeholders` on Mutation for Kubernetes/YAML.
4. `created_additional_vet_triggers` — created at least one of `vet-format`, `vet-merge-keys`, `vet-immutable`.
5. `created_trigger_filter` — created a Filter of type `Trigger` selecting the platform Triggers.
6. `documented_or_demonstrated_trigger_filter_attachment` — showed how new Spaces use `--trigger-filter` to inherit.
7. `never_suggests_gate_bypass` — response does not recommend deleting Triggers or bypassing ApplyGates.

## eval-image-bump

What the with-skill agent should do:
- Run `cub function do` invoking `set-container-image` (not the deprecated `set-image`) with container name `hello-app` and new image `ghcr.io/acme/hello-app:v0.2.0`, scoped via `--space skill-examples --where "Slug = 'hello-app'"`.
- Pass `--change-desc` containing the user's verbatim prompt and ideally a condensed clarifications note.
- Pass `--display-mutation` to surface the diff inline.
- Verify via `cub unit get` or `cub revision list` afterward.
- Does not hand-edit the YAML.

Assertions:
1. `uses_cub_function_do` — invoked via `cub function do`, not `cub unit update` with a file.
2. `uses_set_container_image` — used `set-container-image` (not deprecated `set-image`).
3. `correct_container_name` — passed `hello-app` as the container name.
4. `correct_new_image` — passed `ghcr.io/acme/hello-app:v0.2.0` exactly.
5. `passes_change_desc` — included `--change-desc` flag with text that includes the user's prompt (verbatim or paraphrased clearly).
6. `passes_display_mutation` — included `--display-mutation` flag.
7. `no_hand_edit` — did not download the YAML to a local file and re-upload wholesale.
8. `verified_after` — ran `cub unit get` or `cub revision list` to confirm the change landed.

---

Notes for grading:
- Some assertions require inspecting the `commands.log` (did they actually run the right command?). Others require inspecting `write_up.md` (what did they say to the user?).
- A baseline (without-skill) run that passes several of these would indicate the skill adds less value than hoped; that's informative.
- A with-skill run that fails key assertions is a skill-improvement signal.
