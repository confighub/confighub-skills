---
name: app-config
description: 'Turn .env, properties, YAML, JSON, TOML, INI, or text into an AppConfig Unit and rendered ConfigMap via Upsert + render-configmap, or hash a hand-authored mutable ConfigMap with set-hash so linked workloads roll. Use for "use my .env", configMapGenerator-like config, envFrom, and a Deployment that never restarts on a ConfigMap change.'
phase: act
allowed-tools: []
read-capability-subset: app-config
---

# app-config

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This Skill grants no automatic tool permission. In standalone use, submit each exact requested write once to the host permission system; a stricter external overlay may stop it before Bash.

For an existing Unit, read its current `HeadRevisionNum` and `DataHash` immediately before the write and disclose that the stock convenience command does not carry those reviewed values as atomic preconditions. That race limits the claim you can make; it does not make this standalone Skill read-only.

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
- A **hand-authored mutable ConfigMap** whose changes should roll the workload that reads it — the `set-hash` path below, no AppConfig Unit involved.

## Do not load for

- Authoring a raw Kubernetes `ConfigMap` YAML directly (use `kubernetes-resources` + `cub-mutate`) — fine for small static ConfigMaps with no rendering or history story. If such a ConfigMap does need to roll its workload, come back for [`set-hash`](#hashing-a-hand-authored-mutable-configmap-set-hash).
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
  --change-desc 'Seed application config from reviewed file'
```

`ToolchainType` is locked in here. Edit later with `cub function set`, not by re-creating (you'd lose history).

### 3. Mutate values (optional)

`set-*-path` takes the `configSchema` first, then the dotted path, then the value:

```text
cub function set --space <space> --unit <config-slug> --toolchain AppConfig/Env -o mutations \
  --change-desc 'Point DATABASE_HOST at prod' \
  -- set-string-path SimpleApp DATABASE_HOST postgres.prod.internal
cub function set --space <space> --unit <config-slug> --toolchain AppConfig/Properties \
  --change-desc 'Disable reviewed database SSL setting' \
  -- set-bool-path SimpleApp database.ssl.enabled false
```

Validate against a registered schema (works for all AppConfig formats):

```bash
cub function vet --space <space> --unit <config-slug> --toolchain AppConfig/INI -- vet-jsonschema
```

### 4. Create the downstream ConfigMap Unit and resolve its namespace

```text
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

The render runs during link resolution — no runtime publication of the AppConfig Unit, worker, or Target is involved. Inspect the result:

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

After the host permits and the Skill verifies each wiring step, delivery uses a separate whole-Space `release-publish` call. This Skill owns the AppConfig/render/link/workload steps and their read-only postconditions, not publication.

## Hashing a hand-authored mutable ConfigMap (`set-hash`)

The rendering path above is for config that lives in an AppConfig Unit. When the user instead has a **plain, mutable ConfigMap Unit** they author and edit directly, and the problem is that changing it doesn't restart the Deployment that reads it, the answer is the same annotation the render path uses — just set by hand.

`confighub.com/Hash` is registered as a **provided** attribute on `v1/ConfigMap` and as a **needed** attribute on every workload's pod-template annotations, under the attribute name `configmap-hash`. So the wiring is: hash the ConfigMap, then let Needs/Provides copy the hash onto the pod template. A changed pod template is what makes Kubernetes roll the workload — the same trick a `kubectl rollout restart` performs manually, but driven by content.

### 1. Hash the ConfigMap's contents

```bash
cub function set --space <space> --unit <configmap-slug> \
  --where-resource "ConfigHub.ResourceType = 'v1/ConfigMap'" \
  --change-desc 'Hash ConfigMap contents for linked workload rollout' \
  -o mutations \
  -- set-hash data
```

`set-hash <path>` computes a SHA-256 over every value at `<path>` and writes the first 10 hex characters to `metadata.annotations.confighub.com/Hash`. For a ConfigMap the path is `data`. Scope it with `--where-resource` — `set-hash` matches any resource type, so an unscoped run in a Unit holding more than one resource hashes all of them.

It is hermetic and idempotent: identical content always yields the same hash, so re-running changes nothing. Re-run it after every edit to the ConfigMap — or, better, register it as a **Mutation Trigger** on the Space so the hash is never stale:

```bash
cub trigger create --space <space> hash-configmaps Mutation Kubernetes/YAML \
  --where-resource "ConfigHub.ResourceType = 'v1/ConfigMap'" \
  -- set-hash data
```

`--where-resource` restricts which resources the Trigger's function touches; `--where-unit` would
restrict which Units it runs on. Confirm both against `cub trigger create --help` before composing.

### 2. Receive the hash on the workload

Put a placeholder in the workload's pod template and link the two Units:

```yaml
spec:
  template:
    metadata:
      annotations:
        confighub.com/Hash: confighubplaceholder   # resolved to the ConfigMap's content hash
    spec:
      containers:
        - name: main
          envFrom:
            - configMapRef:
                name: <configmap-slug>             # stable name; no hash suffix
```

```bash
cub link create --space <space> - <workload-slug> <configmap-slug>
```

Resolution replaces the placeholder with the hash. When the ConfigMap's `data` changes, the hash changes, the pod-template annotation changes, and the next publish rolls the workload.

**Limitation:** when a workload references more than one ConfigMap, each hash is propagated separately — combining several into one annotation is not yet supported. Say so rather than wiring something that silently drops one.

**When to prefer the immutable render path instead:** if old pods must keep reading the old config through the rollout, use `render-configmap --immutable true` (the default) from the loop above. Hashing a mutable ConfigMap replaces its contents in place, so a pod that restarts mid-rollout for any reason picks up the new config.

## Tool boundary

- Host permission: read-only Unit/function/controller/runtime inspection in this Skill's declared capability subset; the pack preapproves no Bash call.
- Standalone mutation steps: Unit/function/Invocation/Link/Trigger writes each use one exact host-permission call; bind exact inputs and use `--change-desc` where supported.
- Not allowed: `kubectl create/edit configmap` (bypasses ConfigHub), raw `ConfigMap` YAML in an `AppConfig/*` Unit (wrong toolchain), multiple schemas in one Unit (`configSchema` is one per Unit), rendering `Secret`s this way (use a SecretStore).

## Stop conditions

- User asks to switch toolchain on an existing Unit — `ToolchainType` is immutable post-create; migrating means a new Unit + relink. Call it out.
- Mode choice deferred — ask; the workload YAML depends on it.
- File missing `configHub.configName` / `configHub.configSchema` — stop; fix the file first.
- Downstream Namespace isn't a Unit — Needs/Provides can't resolve the namespace placeholder. Route to `confighub-core` or `import` first.

## Verify chain

1. `cub unit data --space <space> <configmap-slug>` — the rendered `ConfigMap` resource is present (immutable: hashed-name entries; mutable: one stable-named ConfigMap).
2. After a value change upstream: `cub unit data <configmap-slug>` reflects it (auto-update re-rendered).
3. After a successful Space Release and controller sync: `kubectl get configmap -n <ns>` shows the hashed name (immutable) or stable name (mutable); mutable-mode pod template `confighub.com/Hash` matches the ConfigMap's hash. Bind this runtime read to the Release/manifest through `verify-apply`.

## Evidence

- `cub space open <space> --print-url` — AppConfig Space.
- `cub unit open <config-slug> --space <space> --print-url` — AppConfig Unit.
- `cub unit open <configmap-slug> --space <space> --revisions --print-url` — rendered ConfigMap provenance.

## References

- `https://docs.confighub.com/markdown/guide/app-config.md` — canonical walkthrough (Upsert path + legacy path).
- `references/cub-cli.md` — `--change-desc` / `-o mutations` / four Unit views.
- `references/yaml-patterns.md` — `confighubplaceholder` + Needs/Provides receivers.
- `references/functions-catalog.md` — `set-string-path` / `set-int-path` / `set-bool-path` / `vet-jsonschema` / `render-configmap` / `prune-configmaps` / `set-hash`.
- Companion skills: `kubernetes-resources` (raw-ConfigMap authoring), `confighub-core` (Links / Needs-Provides doctrine), `cub-mutate` (bulk AppConfig edits), `triggers-and-applygates` (the `set-hash` Mutation Trigger), `release-publish` (whole-Space OCI Release proposal), `verify-apply` (post-release checks).
