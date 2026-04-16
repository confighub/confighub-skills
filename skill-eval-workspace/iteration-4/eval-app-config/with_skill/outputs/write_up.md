# app-config eval — with-skill

## Scenario

> I have a Java application that reads `application.properties`. I want to manage that file in ConfigHub and deploy it as a ConfigMap that auto-restarts pods when it changes. Walk me through it.

## Preflight

```
$ cub context get
User: <authenticated>
```

Decisions to lock in before creating the Unit:

1. **Toolchain**: `AppConfig/Properties` (matches what the Java app already reads — never one-way convert)
2. **Mode**: **mutable** — single stable ConfigMap name, `confighub.com/Hash` annotation on the pod template triggers rolling restart on content change. Simpler than immutable for typical Java app cases.
3. **Mount**: volume file (Java apps load via classpath/Spring `application.properties`, not `envFrom`)

## Step 1 — Author the AppConfig file

`/tmp/application.properties`:

```
configHub.configName=MyApplicationConfig
configHub.configSchema=SimpleApp
spring.datasource.url=jdbc:postgresql://localhost:5432/mydb
spring.datasource.username=app
spring.profiles.active=prod
server.port=8080
logging.level.root=INFO
```

The two `configHub.*` metadata lines are required — they're stripped at render time. `configSchema` is the first positional argument to `set-*-path` functions.

## Step 2 — Create the Unit

```bash
cub unit create --space my-app-prod my-app-config /tmp/application.properties \
  --toolchain AppConfig/Properties \
  --change-desc "Seed my-app-config from application.properties.

User prompt: have a Java app reading application.properties, want it as a ConfigMap with auto-restart
Clarifications: source: ./application.properties at <git ref>"
```

`ToolchainType` is locked at create time — can't be changed later.

## Step 3 — Mutate values via functions (not by editing the file)

```bash
cub function do --space my-app-prod --unit my-app-config \
  --change-desc "Point datasource at prod DB. User prompt: <verbatim>. Clarifications: <condensed>" \
  --display-mutations \
  -- set-string-path SimpleApp spring.datasource.url jdbc:postgresql://postgres.prod.internal:5432/mydb

cub function do --space my-app-prod --unit my-app-config --toolchain AppConfig/Properties \
  --change-desc "Bump server port. User prompt: <verbatim>. Clarifications: <condensed>" \
  -- set-int-path SimpleApp server.port 8443
```

## Step 4 — Server-worker for ConfigMapRenderer

The renderer runs inside the ConfigHub server, not an external Worker.

```bash
cub worker create --space default --allow-exists --is-server-worker server-worker
```

## Step 5 — Create the ConfigMapRenderer Target (mutable mode)

`RevisionHistoryLimit=0` = mutable mode (single stable ConfigMap name).

```bash
cub target create --space my-app-prod my-app-config-renderer '' default/server-worker \
  --provider ConfigMapRenderer \
  --toolchain AppConfig/Properties \
  --livestate-type Kubernetes/YAML \
  --option RevisionHistoryLimit=0
```

## Step 6 — Bind and apply

```bash
cub unit set-target --space my-app-prod my-app-config my-app-config-renderer
cub unit apply --space my-app-prod my-app-config --wait
```

Inspect:

```bash
cub unit livestate --space my-app-prod my-app-config
```

## Step 7 — Sink Unit for the rendered ConfigMap

```bash
cub unit create --space my-app-prod my-app-configmap
cub link create --space my-app-prod - my-app-configmap my-app-namespace   # resolve namespace placeholder
cub link create --space my-app-prod --wait - my-app-configmap my-app-config \
  --use-live-state --auto-update --update-type MergeUnits
```

## Step 8 — Link the workload

```bash
cub link create --space my-app-prod - my-app-deployment my-app-configmap
```

## Step 9 — Workload YAML (mutable mode)

The pod template gets a `confighub.com/Hash` annotation that resolves to the ConfigMap content hash. Kubernetes treats annotation changes as pod-template changes and triggers a rolling update.

```yaml
spec:
  template:
    metadata:
      annotations:
        confighub.com/Hash: confighubplaceholder   # resolved to content hash
    spec:
      containers:
        - name: my-app
          image: my-app:1.0
          volumeMounts:
            - name: config-volume
              mountPath: /app/config/application.properties
              subPath: MyApplicationConfig.properties
      volumes:
        - name: config-volume
          configMap:
            name: my-app-config       # stable name = Unit slug, no hash suffix
```

## Verify

```bash
cub unit livestate --space my-app-prod my-app-config        # rendered ConfigMap
kubectl get configmap -n my-app                              # stable name = my-app-config
kubectl get pod -n my-app -l app=my-app -o jsonpath='{.items[0].spec.template.metadata.annotations.confighub\.com/Hash}{"\n"}'
# Matches the ConfigMap's confighub.com/Hash annotation; pod restarts on change.
```

## Tool boundary

Hand off cluster apply to `cub-apply` for the workload Unit. Never `kubectl create/edit configmap` — that bypasses ConfigHub.

## Stop conditions to watch

- ToolchainType is immutable — switching from Properties to YAML requires a new Unit and relinking the workload
- Don't put Secrets through this path — use an external SecretStore (see references/yaml-patterns.md)
