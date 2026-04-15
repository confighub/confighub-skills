---
name: skill-examples-bootstrap
description: Use when the user wants a working ConfigHub playground to exercise the other skills against — phrases like "set up the skill-examples space", "bootstrap the examples", "give me a Unit to tinker with", "walk me through with a real example", "I'm new to ConfigHub, show me something I can poke at", or "reset the examples". Creates (or refreshes) a `skill-examples` Space with two seed Units — a `hello-ns` Namespace and a `hello-app` Deployment+Service bundle — and applies the canonical defaults-function chain so the end state demonstrates config-as-data with provenance intact. Idempotent: re-running is safe. Do not load for creating real application Spaces (use config-as-data + space setup directly) or for bootstrapping triggers/policy (use triggers-and-applygates).
phase: cross-cutting
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub space create *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub function do *) Bash(kubectl create *) Bash(mkdir -p /tmp/*) Bash(yq *)
---

# skill-examples-bootstrap

Creates a ConfigHub playground Space so users can exercise the other skills against a real, well-formed example.

## When to use

- User asks for a playground / example / sandbox to try ConfigHub against.
- User is new and needs something concrete to tinker with.
- `skill-examples` Space is missing or has been damaged and the user wants it back.
- User says "reset" or "refresh" the examples.

## Do not load for

- Creating real app Spaces (use `config-as-data` + direct `cub space create`).
- Setting up Triggers / policy (use `triggers-and-applygates`).
- Importing existing Helm or Kustomize configs (future `import-*` skills).

## What gets created

**Space:** `skill-examples`

**Units in that Space:**

- `hello-ns` — `v1/Namespace` named `hello`, with pod-security labels applied via `set-pod-security-defaults`.
- `hello-app` — `apps/v1/Deployment` + `v1/Service` bundle for a placeholder app listening on port 8080, with:
  - Resource requests filled by `set-container-resources-defaults`.
  - All three probes filled by `set-container-probe-defaults`.
  - Pod + container security contexts filled by `set-pod-container-security-context-defaults`.
  - `namespace:` filled with `confighubplaceholder` by `ensure-namespaces`.

Every mutation call passes `--change-desc` with the user prompt verbatim so the revision history demonstrates provenance end-to-end.

## Preflight gates

1. `cub context get` returns a user.
2. `kubectl` is on PATH (used only for `kubectl create --dry-run=client`, no cluster needed).
3. Confirm with the user: is this a first-time bootstrap, or a refresh? A refresh preserves the Space but re-runs the recipe against the existing Units.

## The loop

### 1. Detect existing state

```bash
cub space get skill-examples 2>/dev/null
cub unit list --space skill-examples 2>/dev/null
```

Branch:

- **Space missing** → go to step 2 (full bootstrap).
- **Space present, Units missing** → skip space create, go to step 3.
- **Space + Units present** → go to step 4 (re-apply defaults; idempotent).

### 2. Create the Space

```bash
cub space create skill-examples
```

`cub space create` does not accept `--change-desc`; Spaces aren't versioned data.

### 3. Scaffold + upload Units

Scaffold literal YAML from `kubectl` in a temp dir:

```bash
mkdir -p /tmp/skill-examples-seed && cd /tmp/skill-examples-seed

# Strip metadata.creationTimestamp and .status with yq — a line-based egrep
# leaves nested children of `status:` behind (e.g., `loadBalancer: {}` from
# `kubectl create service clusterip`) which then get absorbed into `spec:`
# and fail `vet-schemas`.
kubectl create namespace hello --dry-run=client -o yaml \
  | yq 'del(.metadata.creationTimestamp, .status)' > hello-ns.yaml

kubectl create deployment hello-app \
  --image=ghcr.io/acme/hello-app:v0.1.0 --port=8080 \
  --dry-run=client -o yaml \
  | yq 'del(.metadata.creationTimestamp, .status)' > hello-app-deploy.yaml

kubectl create service clusterip hello-app --tcp=80:8080 \
  --dry-run=client -o yaml \
  | yq 'del(.metadata.creationTimestamp, .status)' > hello-app-svc.yaml

printf -- "---\n" > hello-app-bundle.yaml
cat hello-app-deploy.yaml >> hello-app-bundle.yaml
printf -- "---\n" >> hello-app-bundle.yaml
cat hello-app-svc.yaml >> hello-app-bundle.yaml
```

Upload:

```bash
cub unit create --space skill-examples hello-ns /tmp/skill-examples-seed/hello-ns.yaml \
  --change-desc "Seed hello namespace Unit for the skill-examples playground.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>"

cub unit create --space skill-examples hello-app /tmp/skill-examples-seed/hello-app-bundle.yaml \
  --change-desc "Seed hello-app Deployment+Service bundle for the skill-examples playground.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>"
```

### 4. Apply the defaults chain

Each function call is hermetic and idempotent, so re-running on an already-seeded Space produces no-op revisions (and no noise in the history if nothing changes).

On `hello-app`:

```bash
for fn in set-container-resources-defaults set-container-probe-defaults \
          set-pod-container-security-context-defaults ensure-namespaces; do
  cub function do --space skill-examples --where "Slug = 'hello-app'" \
    --change-desc "Apply $fn to hello-app.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>" \
    -- "$fn"
done
```

On `hello-ns`:

```bash
cub function do --space skill-examples --where "Slug = 'hello-ns'" \
  --change-desc "Apply pod-security labels to hello namespace.

User prompt: <verbatim>
Clarifications: <condensed or 'none'>" \
  -- set-pod-security-defaults
```

### 5. Show the user what to do next

Point them at the GUI and the other skills:

- `cub unit get hello-app --space skill-examples --web` — inspect the final literal YAML.
- `cub revision list hello-app --space skill-examples --web` — see the provenance chain.
- Suggest a concrete next move: "Try `cub-mutate` to bump the image tag", "Try `cub-query` to find all Deployments in `skill-examples`", "Set up `triggers-and-applygates` against `skill-examples` to see an ApplyGate in action."

## Tool boundary

- Allowed: `cub` read + create/update + `function do` (per frontmatter), `kubectl create --dry-run=client` (scaffolding only, never against a cluster).
- Not allowed: `cub * delete *` (users who want to clean up should do it explicitly), any mutating `kubectl`, any `helm`/`kustomize`.

## Stop conditions

- User is not authenticated (`cub context get` fails). Tell them to run `cub auth login`.
- User lacks permission to create Spaces in the current organization.
- `kubectl` not on PATH. Ask the user to install it (used for scaffolding only, no cluster needed).

## Verify chain

1. `cub space get skill-examples` — Space exists.
2. `cub unit list --space skill-examples` — both Units present.
3. `cub unit get hello-app --space skill-examples --yaml` — YAML contains `resources.requests`, all three probes, `securityContext`, and `namespace: confighubplaceholder`.
4. `cub revision list hello-app --space skill-examples` — revision history includes the defaults functions with user-prompt-bearing change descriptions.

## Evidence

- `cub space get skill-examples --web` — Space overview.
- `cub unit get hello-app --space skill-examples --web` — literal Unit YAML.
- `cub revision list hello-app --space skill-examples --web` — provenance chain.

## References

- `references/cub-cli.md` — CLI discipline + Read/Write permission sets.
- `references/yaml-patterns.md` — what makes the scaffolded YAML "good" literal YAML.
- `references/functions-catalog.md` — defaults functions used.
- Companion skill: `config-as-data` — the doctrine this recipe demonstrates.
