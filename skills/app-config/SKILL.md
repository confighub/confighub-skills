---
name: app-config
description: 'Turn an app config file (.env, .properties, .yaml, .json, .toml, .ini, text) into a versioned AppConfig Unit and render it to a Kubernetes ConfigMap via an Upsert link + render-configmap Invocation (no worker/Target). For: use my .env with ConfigHub, ConfigMap like configMapGenerator, envFrom injection. Not for raw ConfigMap authoring (use confighub-core).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit data *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub function *) Bash(cub invocation create *) Bash(cub link create *) Bash(cub link update *) Bash(cub trigger create *) Bash(kubectl get *) Bash(kubectl describe *)
---

# app-config

Turn a user's application configuration file — `.env`, `.properties`, `.yaml`, `.json`, `.toml`, `.ini`, or plain text — into a versioned ConfigHub Unit, then render it into a Kubernetes `ConfigMap` via an **Upsert link** carrying a `render-configmap` Invocation. No server worker and no Target are needed — rendering is a normal ConfigHub function that runs during link resolution.

Canonical doc: `https://docs.confighub.com/markdown/guide/app-config.md`. Confirm flags with `cub <verb> --help` before composing.

## Why this matters

ConfigHub's `AppConfig/*` toolchains let the user keep config in its native format (devs read `.properties` like `.properties`, not wrapped YAML) while everything else still works: revision history, `set-string-path` / `set-int-path` / `set-bool-path` mutations, `vet-jsonschema` validation, variants / upstream-downstream, Needs/Provides. The render step ships it as a `ConfigMap` — either an immutable hashed one (Kustomize-style; old pods keep reading old ConfigMaps during a rolling update) or a mutable stable-named one (with a content-hash annotation on the pod template to trigger rolling restarts).

## Supported formats (ToolchainType)

| Toolchain | File | When |
| --- | --- | --- |
| `AppConfig/Env` | `.env` | `envFrom` injection (pair with `--as-key-value true` on the Invocation); simple key=value. |
| `AppConfig/Properties` | `.properties` | Java apps. |
| `AppConfig/YAML` | `.yaml` | Most frameworks; full structured config. |
| `AppConfig/JSON` | `.json` | Node / JVM apps that prefer JSON. |
| `AppConfig/TOML` | `.toml` | Rust / Python apps. |
| `AppConfig/INI` | `.ini` | Legacy apps. |
| `AppConfig/Text` | `.txt` | Plain text; metadata in YAML frontmatter delimited by `---`. |

Pick the format **before** creating the Unit — `ToolchainType` is set at Unit-create and not changeable afterward. Match what the app already reads.

## Required metadata fields

Every AppConfig file carries two ConfigHub metadata fields — stripped when rendering the ConfigMap:

- **`configHub.configName`** — unique name for this config file. Also becomes the ConfigMap data key (with the file suffix appended: `MyApplicationConfig.ini`).
- **`configHub.configSchema`** — a schema identifier, conceptually like a Kubernetes resource type. Used with `vet-jsonschema`, and as the first positional argument to `set-*-path` functions.

Syntax by format: YAML/JSON top-level `configHub:` key; TOML/INI `[configHub]` section; Properties/Env dotted `configHub.configName=...`; Text YAML frontmatter under a `configHub` key. See the doc for side-by-side examples.

## When to use

- User has a concrete config file and needs it delivered as a ConfigMap.
- User wants ConfigMap changes to trigger a workload rolling restart without `kubectl rollout restart`.
- "like `kubectl create configmap`" / "like `configMapGenerator`" / "versioned ConfigMap."
- Inject a `.env` as container env vars via `envFrom`.
- Schema validation on application config (`vet-jsonschema`).

## Do not load for

- Authoring a raw Kubernetes `ConfigMap` YAML directly (use `confighub-core` + `cub-mutate`) — fine for small static ConfigMaps with no rendering / history / hashing story.
- Secrets — use an external SecretStore (see `references/yaml-patterns.md`).
- Helm-chart `ConfigMap`s — the chart already renders them; use `import`.

## Preflight gates

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. Target Space exists; user has write permission.
3. **Toolchain decided** — match the existing file's format.
4. **Mode decided** — immutable (default; hashed name, history for old pods) or mutable (stable name, `confighub.com/Hash` annotation). Default to immutable for workload-config-with-rolling-updates; mutable for simpler cases or when a single stable name matters.
5. **`envFrom` vs volume decided** — `.env` with `--as-key-value true` is consumed via `envFrom`; other formats mount as a volume file.
6. The downstream Namespace and workload are (or will be) Units — Needs/Provides linkage expects both sides as Units.

## The loop

### 1. Author the AppConfig file

Include the two metadata fields. Example `app.env`:

```
configHub.configName=MyApplicationConfig
configHub.configSchema=SimpleApp
APP_NAME=MyApplication
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_SSL_ENABLED=true
```

`AppConfig/Env` treats all values as strings; the other formats (except `AppConfig/Text`) also support int and bool.

### 2. Create the AppConfig Unit

```bash
cub unit create --space <space> <config-slug> <file> --toolchain AppConfig/<Fmt> \
  --change-desc "Seed <config-slug> application config from <file>.

User prompt: <verbatim>
Clarifications: <e.g. 'source: ./app.env at <git ref>'>"
```

`ToolchainType` is locked in here. Edit later with `cub function do`, not by re-creating (you'd lose history).

### 3. Mutate values (optional)

`set-*-path` takes the `configSchema` first, then the dotted path, then the value:

```bash
cub function do --space <space> --unit <config-slug> --toolchain AppConfig/Env -o mutations \
  --change-desc "Point DATABASE_HOST at prod. User prompt: <verbatim>. Clarifications: <condensed>" \
  -- set-string-path SimpleApp DATABASE_HOST postgres.prod.internal
cub function do --space <space> --unit <config-slug> --toolchain AppConfig/Properties \
  -- set-bool-path SimpleApp database.ssl.enabled false
```

Validate against a registered schema (works for all AppConfig formats):

```bash
cub function vet --space <space> --unit <config-slug> --toolchain AppConfig/INI -- vet-jsonschema
```

### 4. Create the downstream ConfigMap Unit and resolve its namespace

```bash
cub unit create --space <space> <configmap-slug>
cub link create --space <space> - <configmap-slug> <namespace-slug>   # Needs/Provides fills the namespace placeholder
```

### 5. Create the render-configmap Invocation

One Invocation per (toolchain, mode) combination. `--immutable true` (default) or `--immutable false`; add `--as-key-value true` for `.env` + `envFrom`:

```bash
cub invocation create --space <space> render-<fmt>-immutable AppConfig/<Fmt> render-configmap --immutable true
```

### 6. Wire the Upsert link (this is what renders)

```bash
cub link create --space <space> --wait - <configmap-slug> <config-slug> \
  --update-type Upsert --auto-update \
  --transform-invocation <space>/render-<fmt>-immutable
```

The render runs during link resolution — no `cub unit apply` of the AppConfig Unit, no worker, no Target. Inspect the result:

```bash
cub unit data --space <space> <configmap-slug>     # the rendered ConfigMap
```

`--auto-update` re-renders the ConfigMap into `<configmap-slug>` whenever `<config-slug>` changes.

### 7. (Immutable only) Bound history with a prune trigger

Upsert appends a new immutable ConfigMap each time upstream changes. Cap retention with a Mutation Trigger on the Space:

```bash
cub trigger create --space <space> prune-configmaps Mutation Kubernetes/YAML prune-configmaps \
  --where-unit "ConfigHub.ResourceType = 'v1/ConfigMap'" --revision-history-limit 10
```

It groups ConfigMaps by `confighub.com/ResourceNameStableCore`, keeps the newest (tagging the latest `confighub.com/RenderRevision: Latest`), removes the rest; mutable ConfigMaps are ignored.

### 8. Link the workload Unit

```bash
cub link create --space <space> - <workload-slug> <configmap-slug>
```

### 9. Workload YAML — pattern depends on mode

**Immutable** — name changes per revision; reference `confighubplaceholder`:

```yaml
spec:
  template:
    spec:
      volumes:
        - name: config-volume
          configMap:
            name: confighubplaceholder   # resolved to the latest hashed name
```

Optionally scope the workload→configmap link to the latest revision: `--where-resource "metadata.annotations.confighub~1com/RenderRevision = 'Latest'"` (`~1` is the JSON-Pointer-like escape for `/`).

**Mutable** — stable name; a hash annotation drives rolling updates:

```yaml
spec:
  template:
    metadata:
      annotations:
        confighub.com/Hash: confighubplaceholder   # resolved to the content hash
    spec:
      volumes:
        - name: config-volume
          configMap:
            name: <config-slug>          # stable, no hash suffix
```

**`envFrom`** (either mode — `confighubplaceholder` immutable, stable name mutable):

```yaml
spec:
  template:
    spec:
      containers:
        - name: main
          envFrom:
            - configMapRef:
                name: confighubplaceholder
```

The ConfigMap and workload Units are deployed by `cub-apply` like any other Unit; this skill stops once the render pipeline is wired and the rendered ConfigMap is present.

## Tool boundary

- Allowed: `cub unit create/update`, `cub function do` / `cub function vet` (`set-*-path` / `vet-jsonschema`), `cub invocation create`, `cub link create/update`, `cub trigger create` (prune-configmaps), read-only `cub unit data/livedata/diff/get/list`, read-only `kubectl get/describe` on the resulting ConfigMap.
- Not allowed: `kubectl create/edit configmap` (bypasses ConfigHub), raw `ConfigMap` YAML in an `AppConfig/*` Unit (wrong toolchain), multiple schemas in one Unit (`configSchema` is one per Unit), rendering `Secret`s this way (use a SecretStore).

## Stop conditions

- User asks to switch toolchain on an existing Unit — `ToolchainType` is immutable post-create; migrating means a new Unit + relink. Call it out.
- Mode choice deferred — ask; the workload YAML depends on it.
- File missing `configHub.configName` / `configHub.configSchema` — stop; fix the file first.
- Downstream Namespace isn't a Unit — Needs/Provides can't resolve the namespace placeholder. Route to `confighub-core` or `import` first.

## Verify chain

1. `cub unit data --space <space> <configmap-slug>` — the rendered `ConfigMap` resource is present (immutable: hashed-name entries; mutable: one stable-named ConfigMap).
2. After a value change upstream: `cub unit data <configmap-slug>` reflects it (auto-update re-rendered).
3. After the ConfigMap + workload Units are applied via `cub-apply`: `kubectl get configmap -n <ns>` shows the hashed name (immutable) or stable name (mutable); mutable-mode pod template `confighub.com/Hash` matches the ConfigMap's hash.

## Evidence

- `cub unit get --space <space> <config-slug> --web` — the AppConfig Unit in the GUI.
- `cub unit data --space <space> <configmap-slug> --web` — rendered ConfigMap.
- `cub revision list --space <space> <config-slug> --web` — provenance of every config change.

## References

- `https://docs.confighub.com/markdown/guide/app-config.md` — canonical walkthrough (Upsert path + legacy path).
- `references/cub-cli.md` — `--change-desc` / `-o mutations` / four Unit views.
- `references/yaml-patterns.md` — `confighubplaceholder` + Needs/Provides receivers.
- `references/functions-catalog.md` — `set-string-path` / `set-int-path` / `set-bool-path` / `vet-jsonschema` / `render-configmap` / `prune-configmaps`.
- Companion skills: `confighub-core` (raw-ConfigMap authoring; Links / Needs-Provides doctrine), `cub-mutate` (bulk AppConfig edits), `cub-apply` (deploy the ConfigMap + workload Units), `verify-apply` (post-apply checks).
