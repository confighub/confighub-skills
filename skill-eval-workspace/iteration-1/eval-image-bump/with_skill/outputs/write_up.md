# Eval: Image Bump via cub-mutate skill

## Function chosen

`set-container-image` (non-deprecated, purpose-built).

Per `skills/cub-mutate/SKILL.md` decision tree and function table:

- The change is a single-field change (container image) on one Unit.
- The purpose-built function is `set-container-image <container> <image>`.
- Deprecated alternatives to avoid (called out in SKILL.md): `set-image`, `set-image-reference`, `set-image-uri`.
- `set-container-image-reference` is for tag-only bumps; here we're setting the full image reference, so `set-container-image` is the right match.

## Scope

Single Unit: `--space skill-examples --where "Slug = 'hello-app'"`.

## Full command line

```bash
cub function do \
  --space skill-examples \
  --where "Slug = 'hello-app'" \
  --change-desc "Bump hello-app container image to ghcr.io/acme/hello-app:v0.2.0 (CI release).

User prompt: Bump the hello-app image in the skill-examples space to ghcr.io/acme/hello-app:v0.2.0. CI just cut that release.
Clarifications: none" \
  --display-mutation \
  -- \
  set-container-image hello-app ghcr.io/acme/hello-app:v0.2.0
```

### --change-desc composition

Composed per SKILL.md section 4:

- Summary line: "Bump hello-app container image to ghcr.io/acme/hello-app:v0.2.0 (CI release)."
- Blank line.
- `User prompt:` verbatim user request.
- `Clarifications: none` — the request was unambiguous (space, unit slug, container name, full image ref all provided in context).

## Did the mutation succeed?

**Blocked by harness permissions.** The Bash tool denied every attempt to execute `cub function do ...`, even though the skill's frontmatter declares `Bash(cub function do *)` in `allowed-tools`. Read-only `cub unit get` calls were allowed.

Per the task instruction ("If you hit permission prompts, proceed best-effort and report what happened"), I documented the intended command and pre-state instead of bypassing the denial.

## Pre-state verification (what was allowed)

`cub unit get hello-app --space skill-examples --data-only` confirmed:

- Unit `hello-app` exists in Space `skill-examples`.
- Container named `hello-app` currently references `ghcr.io/acme/hello-app:v0.1.0`.
- Head Revision Num: 6; Last Change Description references `ensure-namespaces`.
- Toolchain: Kubernetes/YAML (matches the `set-container-image` function's target toolchain).

## Planned verification chain (not executed due to permission block)

1. `cub unit get hello-app --space skill-examples --data-only` — confirm `image: ghcr.io/acme/hello-app:v0.2.0` under `spec.template.spec.containers[0]`.
2. `cub revision list hello-app --space skill-examples` — confirm a new head revision (7) with the composed `--change-desc`.
3. `cub unit get hello-app --space skill-examples --web` — open the Unit for visual trust.

## Notes

- `--display-mutation` was included per SKILL.md §5 so the applied diff prints inline.
- `--wait` was not added because this is a single-Unit mutation, not a bulk run.
- No ApplyGate or Trigger was encountered (nothing ran); SKILL.md preflight gate 3 would have been a soft warning only.
