---
name: app-config
description: 'Use when the user wants to manage application configuration files (properties, env, toml, ini, yaml, json, text) and deploy them as Kubernetes ConfigMaps — phrases like "I have a .env / .properties / application.yaml file, how do I use it with ConfigHub?", "generate a ConfigMap like kustomize configMapGenerator", "like kubectl create configmap but versioned", "inject env vars via envFrom", "ConfigMap with content hash for rolling restart", "mutable vs immutable ConfigMap", "validate my application config with a schema", "propagate config changes to the workload without kubectl edit". Authors an AppConfig Unit in the right toolchain, sets up the ConfigMapRenderer Target, links the rendered ConfigMap to the workload via Needs/Provides, and picks immutable (hashed name, history) or mutable (stable name + hash annotation) mode. Do not load for authoring a Kubernetes `ConfigMap` resource directly in a `Kubernetes/YAML` Unit (use `config-as-data` + `cub-mutate`), for Secrets (separate SecretStore story — see `references/yaml-patterns.md`), or for migrating Helm values files (use `import-from-helm` — charts already render their own ConfigMaps).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub unit create *) Bash(cub unit update *) Bash(cub unit set-target *) Bash(cub unit apply *) Bash(cub function do *) Bash(cub worker create *) Bash(cub target create *) Bash(cub target update *) Bash(cub link create *) Bash(cub link update *) Bash(kubectl get *) Bash(kubectl describe *)
---

# app-config

Turn a user's application configuration file — `.env`, `.properties`, `.yaml`, `.json`, `.toml`, `.ini`, or plain text — into a versioned ConfigHub Unit, then render and deploy it as a Kubernetes ConfigMap via the built-in `ConfigMapRenderer` bridge.

Canonical doc: `https://docs.confighub.com/guide/app-config/`.

## Why this matters

ConfigHub's `AppConfig/*` toolchains let the user keep config in its native format (devs read `.properties` like `.properties`, not as wrapped YAML) while everything else in ConfigHub still works: revision history, `set-string-path` / `set-int-path` / `set-bool-path` mutations, `vet-jsonschema` validation, variant / upstream-downstream, Needs/Provides. The renderer then ships it as a `ConfigMap` — either an immutable hashed one (Kustomize-style, supports rolling updates with old pods still reading old ConfigMaps) or a mutable stable-named one (with a content-hash annotation on the pod template to trigger rolling restarts).

## Supported formats (ToolchainType)

| Toolchain              | File          | When                                                                          |
| ---------------------- | ------------- | ----------------------------------------------------------------------------- |
| `AppConfig/Env`        | `.env`        | `envFrom` injection (pair with `--option AsKeyValue=true`); simple key=value. |
| `AppConfig/Properties` | `.properties` | Java apps.                                                                    |
| `AppConfig/YAML`       | `.yaml`       | Most app frameworks; full structured config.                                  |
| `AppConfig/JSON`       | `.json`       | Node / JVM apps that prefer JSON.                                             |
| `AppConfig/TOML`       | `.toml`       | Rust / Python apps.                                                           |
| `AppConfig/INI`        | `.ini`        | Legacy apps.                                                                  |
| `AppConfig/Text`       | `.txt`        | Plain text; metadata in YAML frontmatter delimited by `---`.                  |

Pick the format **before** creating the Unit — `ToolchainType` is set at Unit-create and not changeable afterward. Matching what the application already reads is almost always right; a one-way conversion to a "better" format is extra churn without payoff.

## Required metadata fields

Every AppConfig file must carry two ConfigHub metadata fields — ConfigHub strips them when rendering the ConfigMap:

- **`configHub.configName`** — a unique name for this config file. Also becomes the ConfigMap data key (with the format's file suffix appended: `MyApplicationConfig.ini`).
- **`configHub.configSchema`** — a schema identifier, conceptually like a Kubernetes resource type (`apps/v1/Deployment`). Used with `vet-jsonschema` for validation, and as the first positional argument to `set-*-path` functions when mutating values.

Format-specific syntax:

- YAML / JSON: top-level `configHub:` key (YAML) or `"configHub": { ... }` (JSON).
- TOML / INI: a `[configHub]` section.
- Properties / Env: dotted `configHub.configName=...` / `configHub.configSchema=...` lines.
- Text: YAML frontmatter at the top, delimited by `---`, fields under a `configHub` key.

See the published doc for side-by-side examples in each format.

## When to use

- User has a concrete config file for an app and needs it delivered to the cluster as a ConfigMap.
- User wants ConfigMap content changes to trigger workload rolling restart without hand-writing `kubectl rollout restart`.
- User asks "like `kubectl create configmap`" / "like `configMapGenerator`" / "versioned ConfigMap."
- User wants to inject a `.env` as container environment variables via `envFrom`.
- User wants schema validation on an application config (`vet-jsonschema`).

## Do not load for

- Authoring a raw Kubernetes `ConfigMap` YAML directly (use `config-as-data` + `cub-mutate`). That path is fine for small static ConfigMaps with no rendering / history / hashing story.
- Secrets — wrong tool. Handle via an external SecretStore; see `references/yaml-patterns.md`.
- Helm-chart `ConfigMap`s — the chart already renders them; use `import-from-helm`.
- Flux / Argo-managed app config — the renderer bridges under `import-from-flux` / `import-from-argocd` handle those.

## Preflight gates

1. `cub organization list` succeeds and shows the right organization (proves a valid token; `cub context get` / `cub info` / `cub version` don't require one).
2. Target Space exists; user has write permission.
3. **Toolchain decided** — match the existing file's format if the user has one, otherwise the format the app actually reads.
4. **Mode decided** — immutable (default, hashed name, history for old pods during rolling update) or mutable (`RevisionHistoryLimit=0`, stable name, `confighub.com/Hash` annotation on pod template). If the user doesn't know, recommend immutable for workload-config-with-rolling-updates; mutable for simpler single-cluster cases where the content rarely changes or a single stable name matters for observability tooling.
5. **`envFrom` vs volume decided** — `.env` units with `AsKeyValue=true` can be consumed via `envFrom`; other formats mount as a volume file.
6. The workload Unit that will consume this ConfigMap is already in ConfigHub (or will be during this flow). Needs/Provides linkage expects both sides as Units.

## The loop

### 1. Author the AppConfig file

Include the two metadata fields per the format. Example `app.env`:

```
configHub.configName=MyApplicationConfig
configHub.configSchema=SimpleApp
APP_FEATURES_0=authentication
APP_FEATURES_1=logging
APP_NAME=MyApplication
APP_VERSION=1.0.0
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_SSL_ENABLED=true
```

Note for AppConfig/Env: all values are treated as strings. The other AppConfig ToolchainTypes, other than AppConfig/Text, support int and bool values as well.

### 2. Create the Unit

```bash
cub unit create --space <space> <config-slug> <file> \
  --toolchain AppConfig/<Fmt> \
  --change-desc "Seed <config-slug> application config from <file>.

User prompt: <verbatim>
Clarifications: <condensed — e.g. 'source: ./app.env at <git ref>'>"
```

`ToolchainType` is locked in here. If the file needs edits afterward, prefer `cub function do` over re-creating the Unit (you'd lose the revision history).

### 3. Mutate values (optional)

`set-*-path` functions take the `configSchema` as the first positional argument, then the dotted path, then the value:

```bash
cub function do --space <space> --unit <config-slug> --toolchain AppConfig/Env \
  --change-desc "Point DATABASE_HOST at prod. User prompt: <verbatim>. Clarifications: <condensed>" \
  -o mutations \
  -- set-string-path SimpleApp DATABASE_HOST postgres.prod.internal

cub function do --space <space> --unit <config-slug> --toolchain AppConfig/Properties \
  --change-desc "Turn off dev-only flag. User prompt: <verbatim>. Clarifications: <condensed>" \
  -- set-bool-path SimpleApp database.ssl.enabled false

cub function do --space <space> --unit <config-slug> --toolchain AppConfig/Properties \
  --change-desc "Bump DB port. User prompt: <verbatim>. Clarifications: <condensed>" \
  -- set-int-path SimpleApp database.port 5433
```

For schema validation (requires a schema registered with ConfigHub):

```bash
cub function do --space <space> --unit <config-slug> --toolchain AppConfig/INI -- vet-jsonschema
```

`vet-jsonschema` works for all AppConfig ToolchainTypes, not just AppConfig/JSON and AppConfig/YAML.

### 4. Ensure the server-worker exists

The `ConfigMapRenderer` runs inside the ConfigHub server — no external Worker process required. Create (or re-create idempotently) the server-worker:

```bash
cub worker create --space default --allow-exists --is-server-worker server-worker
```

The Space is flexible; `default/server-worker` is the conventional home. Reference it cross-Space via `<space>/<worker>` syntax.

### 5. Create the ConfigMapRenderer Target

Pick mode via `RevisionHistoryLimit`:

```bash
# Immutable mode (default, 10 revisions retained for rolling updates).
cub target create --space <space> <target-slug> '' default/server-worker \
  --provider ConfigMapRenderer \
  --toolchain AppConfig/<Fmt> \
  --livestate-type Kubernetes/YAML

# Immutable, custom retention.
cub target create --space <space> <target-slug> '' default/server-worker \
  --provider ConfigMapRenderer \
  --toolchain AppConfig/<Fmt> \
  --livestate-type Kubernetes/YAML \
  --option RevisionHistoryLimit=5

# Mutable (single stable-named ConfigMap, hash annotation for rolling restarts).
cub target create --space <space> <target-slug> '' default/server-worker \
  --provider ConfigMapRenderer \
  --toolchain AppConfig/<Fmt> \
  --livestate-type Kubernetes/YAML \
  --option RevisionHistoryLimit=0
```

For `.env` + `envFrom`, also set `AsKeyValue=true` so each key-value pair becomes a ConfigMap data entry (not one big file):

```bash
cub target create --space <space> <target-slug>-kv '' default/server-worker \
  --provider ConfigMapRenderer \
  --toolchain AppConfig/Env \
  --livestate-type Kubernetes/YAML \
  --option AsKeyValue=true
```

### 6. Bind the Unit to the Target and apply

```bash
cub unit set-target --space <space> <config-slug> <target-slug>
cub unit apply --space <space> <config-slug> --wait
```

Inspect the rendered ConfigMap:

```bash
cub unit livestate --space <space> <config-slug>    # full live resource (see references/cub-cli.md)
```

### 7. Create a `Kubernetes/YAML` sink Unit for the rendered ConfigMap(s)

The renderer produces one or more ConfigMaps (one per revision in immutable mode, or one stable ConfigMap in mutable mode). A dedicated sink Unit holds them so downstream workloads can link to a single reference:

```bash
cub unit create --space <space> <configmap-slug>
cub link create --space <space> - <configmap-slug> <namespace-slug>    # resolve namespace placeholder
cub link create --space <space> --wait - <configmap-slug> <config-slug> \
  --use-live-state --auto-update --update-type MergeUnits
```

The `<configmap-slug>` ← `<config-slug>` link with `--use-live-state --auto-update --update-type MergeUnits` is what keeps the sink Unit populated with the latest rendered ConfigMap(s) as they change.

### 8. Link the workload Unit

Now wire the workload into the sink so Needs/Provides resolves the ConfigMap reference:

```bash
cub link create --space <space> - <workload-slug> <configmap-slug>
```

### 9. Workload YAML — placeholder pattern depends on mode

**Immutable mode** — ConfigMap name changes per revision; use `confighubplaceholder` in the workload's ConfigMap references:

```yaml
spec:
  template:
    spec:
      containers:
        - name: main
          volumeMounts:
            - name: config-volume
              mountPath: /etc/app/app.properties
              subPath: app.properties
      volumes:
        - name: config-volume
          configMap:
            name: confighubplaceholder # resolved to the latest hashed name
```

Optionally scope the link to the latest rendered revision so older ConfigMaps aren't in scope:

```bash
cub link create --space <space> - <workload-slug> <configmap-slug> \
  --where-resource "metadata.annotations.confighub~1com/RenderRevision = 'Latest'"
```

(`~1` is the JSON-Pointer-like escape for `.` in the annotation key.)

**Mutable mode** — stable name, triggered by a hash annotation on the pod template:

```yaml
spec:
  template:
    metadata:
      annotations:
        confighub.com/Hash: confighubplaceholder # resolved to the content hash
    spec:
      containers:
        - name: main
          volumeMounts:
            - name: config-volume
              mountPath: /etc/app/app.properties
              subPath: app.properties
      volumes:
        - name: config-volume
          configMap:
            name: my-config # the Unit slug (no hash suffix)
```

When ConfigHub renders a new ConfigMap, the `Hash` annotation on the pod template changes, which Kubernetes treats as a pod-template change and triggers a rolling update.

**`envFrom` injection** (either mode — use `confighubplaceholder` in immutable mode or the stable name in mutable mode):

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

## Tool boundary

- Allowed: `cub unit create/update/set-target/apply`, `cub function do` (AppConfig-aware `set-*-path` / `vet-jsonschema`), `cub worker create --is-server-worker`, `cub target create/update` for ConfigMapRenderer, `cub link create/update` for Needs/Provides wiring, read-only `cub unit livestate/livedata/diff/get/list`, read-only `kubectl get/describe` on the resulting ConfigMap for verification.
- Not allowed: `kubectl create/edit configmap` (bypasses ConfigHub), writing raw `ConfigMap` YAML into an `AppConfig/*` Unit (wrong toolchain), mixing multiple configuration schemas into one Unit (`configSchema` is one per Unit), rendering `Secret`s through this path (use a SecretStore).

## Stop conditions

- User asks to switch toolchain on an existing Unit — ToolchainType is immutable post-create; migrating means a new Unit (and relinking the workload). Call that out before proceeding.
- Mode choice deferred ("just pick one") — ask. The workload YAML pattern depends on it.
- Config file is missing `configHub.configName` or `configHub.configSchema` — stop; fix the file first (functions like `set-*-path` depend on `configSchema` as argument).
- User wants the rendered ConfigMap to land in a namespace that isn't a ConfigHub Unit — Needs/Provides won't resolve the namespace placeholder. Stop and route to `config-as-data` or `import-from-cluster` to bring the Namespace into ConfigHub first.
- User expects old ConfigMaps in immutable mode to linger indefinitely — they won't; `RevisionHistoryLimit` caps it. For longer retention, raise the limit explicitly; do not try to preserve old ConfigMaps out of band.

## Verify chain

1. `cub unit livestate --space <space> <config-slug>` — shows the rendered `ConfigMap` resource.
2. `cub unit list --space <space> -o jq='.[] | select(.Unit.Slug == "<configmap-slug>") | .Unit | {HeadRevisionNum, LiveRevisionNum, LastAppliedRevisionNum}'` — sink Unit caught up.
3. `kubectl get configmap -n <ns>` — immutable mode: hashed name ending in `-<hash>`; mutable mode: stable name = Unit slug.
4. Mutable mode only: `kubectl get pod -n <ns> -l <selector> -o jsonpath='{.items[0].spec.template.metadata.annotations.confighub\.com/Hash}{"\n"}'` — matches the ConfigMap's `confighub.com/Hash` annotation; pod restarts on change.
5. For `envFrom`: `kubectl exec -n <ns> <pod> -- env | sort` shows the injected keys.

## Evidence

- `cub unit get --space <space> <config-slug> --web` — the AppConfig Unit in the GUI.
- `cub unit livestate --space <space> <config-slug> --web` — rendered ConfigMap.
- `cub revision list --space <space> <config-slug> --web` — provenance of every config change.

## References

- `https://docs.confighub.com/guide/app-config/` — canonical walkthrough.
- `references/cub-cli.md` — `--change-desc` / `-o mutations` / the four Unit views / `--where` AND-only.
- `references/yaml-patterns.md` — `confighubplaceholder` pattern and Needs/Provides receivers.
- `references/functions-catalog.md` — `set-string-path` / `set-int-path` / `set-bool-path` / `vet-jsonschema`.
- Companion skills: `config-as-data` (raw-ConfigMap authoring when app-config isn't a fit), `cub-mutate` (the bulk / ChangeSet-wrapped path when editing many AppConfig Units together), `target-bind` (Target + Worker basics), `cub-apply` (the apply verb), `verify-apply` (post-apply checks).
