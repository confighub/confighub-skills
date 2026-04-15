---
name: config-as-data
description: Use whenever the user is authoring or modifying Kubernetes configuration stored in ConfigHub, or is about to reach for Helm, Kustomize, Jsonnet, cdk8s, or a values file. This skill enforces the "configuration as data" doctrine — Units contain fully-materialized, literal YAML, mutated in place via cub functions or direct edits, never re-rendered from templates. Load this proactively any time the user says things like "add a chart", "values file", "overlay", "template this", "parameterize", "set up Helm for this", "make this reusable across envs", or starts generating K8s YAML that will be stored in ConfigHub. Do not load for: pure import-from-helm / import-from-kustomize flows (those have their own skills that handle one-shot render + store), or authoring config outside ConfigHub.
phase: cross-cutting
allowed-tools: Bash(cub context get *) Bash(cub space list *) Bash(cub space get *) Bash(cub unit list *) Bash(cub unit get *) Bash(cub revision list *) Bash(cub revision get *) Bash(cub trigger list *) Bash(cub trigger get *) Bash(cub filter list *) Bash(cub filter get *) Bash(cub target list *) Bash(cub target get *) Bash(cub worker list *) Bash(cub worker get *) Bash(cub link list *) Bash(cub link get *) Bash(cub function list *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(CONFIGHUB_AGENT=1 cub function list *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub space create *) Bash(cub space update *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub function do *) Bash(cub run *) Bash(cub link create *) Bash(cub link update *) Bash(kubectl create *) Bash(kubectl explain *)
---

# config-as-data

Authoring discipline for Kubernetes configuration stored in ConfigHub.

## The rule

A ConfigHub Unit contains **fully materialized YAML with literal values for every field**. Code (functions) operates on data. Data is the source of record. This is not a style preference — it's what makes ConfigHub's query, validation, mutation-graph, and revision-history features work. Re-rendered or templated Units break all of those.

If you're tempted to reach for Helm, Kustomize, Jsonnet, cdk8s, or a values file to *author* new configuration for ConfigHub, stop and re-read this skill.

## When to use

- User is creating a new Kubernetes resource to store in a Unit.
- User is about to add a Helm chart or Kustomize overlay to a Unit's source.
- User asks how to "parameterize" a Unit, share config across environments, or keep a values file alongside YAML.
- User asks how to do something "like Helm values" or "like Kustomize overlays" in ConfigHub.
- User starts templating YAML (`{{ .Values.x }}`, `${VAR}`, `<% %>`) that will end up in a Unit.

## Do not load for

- One-shot `import-from-helm` / `import-from-kustomize` (those skills render once, then this discipline takes over for subsequent edits).
- Authoring config that will live in git or a chart repo, not in ConfigHub.
- Pure read / query tasks.

## Preflight gates

1. `cub context get` returns a user and a default space.
2. User has write permission on the target Space.
3. If authoring new config, confirm with the user which Space this Unit belongs to. Best practice: one Space per app × environment/region.

## The loop

### 1. Establish intent — authoring or migrating?

- **New resource from scratch.** Go to step 2.
- **Migrating existing Helm/Kustomize.** The right skill is `import-from-helm` or `import-from-kustomize` (future). If those aren't available, render once with `helm template` or `kustomize build`, strip runtime-only fields, and store the output as a Unit — then never re-render.

### 2. Produce literal YAML

Scaffold from Kubernetes itself, not from a chart:

```bash
kubectl create deployment my-app --image=confighubplaceholder:confighubplaceholder \
  --dry-run=client -o yaml \
  | egrep -v "creationTimestamp|status" > my-app.yaml
```

Use `confighubplaceholder` for string fields and `999999999` for numeric fields that need to be supplied later. `vet-placeholders` will block apply while any remain.

For fields `kubectl create` doesn't cover, hand-author literal YAML — don't template. Consult `references/yaml-patterns.md` for common shapes.

### 3. Store in a Unit

```bash
cub unit create --space <space> <unit-slug> my-app.yaml \
  --change-desc "<summary>

User prompt: <verbatim>
Clarifications: <condensed or 'none'>"
```

### 4. Fill in defaults via functions (not by hand)

Prefer the defaults functions over hand-editing — they're hermetic, idempotent, and record a clean revision:

```bash
cub function do --space <space> --where "Slug = '<unit-slug>'" \
  set-container-resources-defaults --change-desc "..."

cub function do --space <space> --where "Slug = '<unit-slug>'" \
  set-container-probe-defaults --change-desc "..."

cub function do --space <space> --where "Slug = '<unit-slug>'" \
  set-pod-container-security-context-defaults --change-desc "..."
```

For Namespaces: `set-pod-security-defaults`. To guarantee `namespace:` is set: `ensure-namespaces`.

### 5. Make env-specific variations via Units, not templates

To vary config across environments:

- Create one Space per app × environment/region.
- Use upstream → downstream Unit relationships to clone baseline.
- Apply differences via functions: `set-container-image`, `set-replicas`, `set-env-var`, etc. — each recorded as a revision.

Don't introduce a values file. Don't introduce an overlay. The Space is the parameterization boundary.

## Tool boundary

- Allowed: `cub` (mutations), `kubectl create --dry-run=client` and `kubectl explain` (scaffolding only), reading existing chart/overlay content for one-shot import.
- Not allowed: `helm install/upgrade`, `kustomize build` piped into ongoing editing, writing values files alongside a Unit's YAML, introducing template syntax into a Unit's data.

## Change description

Every `cub unit create`, `cub unit update`, `cub function do`, `cub run` call must pass `--change-desc`:

```
<summary line>

User prompt: <verbatim user prompt>
Clarifications: <condensed: "user confirmed target env is prod" / "user chose bundle granularity per-app" / "none">
```

## Stop conditions

- User insists on keeping a values file or template in the Unit. Explain the rule once; if they still want it, stop and hand back — this isn't the skill for that.
- Required field can only be filled correctly at apply time (e.g., a rendered secret from an external system). Use a placeholder + a function that fills it at apply — don't template.

## Verify chain

1. `cub unit get <slug> --space <space>` — inspect the stored YAML; confirm it is literal.
2. `cub function do --space <space> --where "Slug = '<slug>'" vet-placeholders` — no remaining placeholders (unless intentional for later fill).
3. `cub function do --space <space> --where "Slug = '<slug>'" vet-schemas` — valid against the target K8s version.
4. `cub function do --space <space> --where "Slug = '<slug>'" vet-format` — clean YAML.

## Trust surface

- `cub unit get <slug> --space <space> --web` — opens the Unit in the GUI so the user can see the literal YAML and revision history.

## References

- `references/cub-cli.md`
- `references/functions-catalog.md`
- `references/yaml-patterns.md`
- Upstream doctrine: the "Configuration as Data" page at https://docs.confighub.com/
