# kubernetes-resources eval — with-skill

## Scenario

> I need to deploy a Redis cluster as a StatefulSet in ConfigHub with 3 replicas and persistent storage. The Redis pods should use the redis:7.2 image and listen on port 6379. Set it up in my redis-prod Space.

## Preflight

```
$ cub context get
User: <authenticated>
```

```
$ cub space list | grep redis-prod
redis-prod    prod    0    ...
```

Space exists. Resource type: StatefulSet (with headless Service — required for StatefulSet pod DNS).

## Step 1 — Pull the live example from skill-examples

```bash
cub unit get hello-statefulset --space skill-examples --yaml
```

Returns a postgres StatefulSet bundle with:
- Headless Service (clusterIP: None)
- StatefulSet with 3 replicas, volumeClaimTemplates
- Security context (runAsNonRoot, drop ALL caps, readOnlyRootFilesystem)
- Probes (startup, liveness, readiness)
- Resource requests
- `confighubplaceholder` for namespace

Adapt names: `hello-db` → `redis`, `postgres:16.3` → `redis:7.2`, port 5432 → 6379, postgres-specific env/volumeMount paths → Redis equivalents.

## Step 2 — Write the YAML

`/tmp/redis.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: confighubplaceholder
  labels:
    app: redis
spec:
  clusterIP: None             # headless — required for StatefulSet pod DNS
  selector:
    app: redis
  ports:
  - port: 6379
    targetPort: 6379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: confighubplaceholder
  labels:
    app: redis
spec:
  serviceName: redis
  replicas: 3
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7.2
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

Notes:
- Headless Service + StatefulSet bundled into one Unit (they share the same selector and lifecycle).
- `confighubplaceholder` for namespace — `ensure-namespaces` resolves it.
- `serviceName: redis` matches the headless Service name.
- `volumeClaimTemplates` for per-pod persistent storage (not a separate PVC Unit).

## Step 3 — Create the Unit

```bash
cub unit create --space redis-prod redis /tmp/redis.yaml \
  --change-desc "Create Redis StatefulSet with 3 replicas and persistent storage.

User prompt: deploy Redis cluster as StatefulSet, 3 replicas, persistent storage, redis:7.2, port 6379
Clarifications: bundled headless Service + StatefulSet; volumeClaimTemplates for per-pod 10Gi storage"
```

## Step 4 — Apply defaults functions

```bash
# Resource requests/limits defaults
cub function do --space redis-prod --where "Slug = 'redis'" \
  --change-desc "Apply container resource defaults" \
  -- set-container-resources-defaults

# Probe defaults — note: adds HTTP probes; Redis isn't HTTP, so we'll override below
cub function do --space redis-prod --where "Slug = 'redis'" \
  --change-desc "Apply container probe defaults" \
  -- set-container-probe-defaults

# Security context defaults (runAsNonRoot, drop caps, etc.)
cub function do --space redis-prod --where "Slug = 'redis'" \
  --change-desc "Apply pod + container security-context defaults" \
  -- set-pod-container-security-context-defaults

# Resolve the namespace placeholder (creates a Namespace Unit if needed)
cub function do --space redis-prod --where "Slug = 'redis'" \
  --change-desc "Resolve namespace placeholder via ensure-namespaces" \
  -- ensure-namespaces
```

## Step 5 — Override HTTP probes with TCP (Redis isn't HTTP)

`set-container-probe-defaults` adds HTTP GET probes. Redis speaks RESP, not HTTP. Override with TCP:

```bash
cub function do --space redis-prod --where "Slug = 'redis'" \
  --change-desc "Switch probes to TCP socket on 6379 (Redis isn't HTTP).

User prompt: <verbatim>
Clarifications: HTTP probes from defaults won't work against RESP; using tcpSocket on the Redis port" \
  --display-mutations \
  -- yq-i '(.spec.template.spec.containers[] | select(.name == "redis").livenessProbe) = {"tcpSocket": {"port": 6379}, "initialDelaySeconds": 15, "periodSeconds": 20}' \
  -- yq-i '(.spec.template.spec.containers[] | select(.name == "redis").readinessProbe) = {"tcpSocket": {"port": 6379}, "initialDelaySeconds": 5, "periodSeconds": 10}' \
  -- yq-i '(.spec.template.spec.containers[] | select(.name == "redis").startupProbe) = {"tcpSocket": {"port": 6379}, "initialDelaySeconds": 10, "periodSeconds": 10, "failureThreshold": 30}'
```

## Step 6 — Validate

```bash
cub function do --space redis-prod --where "Slug = 'redis'" -- vet-schemas
cub function do --space redis-prod --where "Slug = 'redis'" -- vet-placeholders
cub function do --space redis-prod --where "Slug = 'redis'" -- vet-format
```

All three should pass.

## Step 7 — Verify

```bash
cub unit get redis --space redis-prod --yaml      # inspect stored YAML
cub unit get redis --space redis-prod --web       # GUI link
cub revision list redis --space redis-prod        # provenance
```

## Tool boundary

- This skill stops at authoring + validation. To deploy:
  - `target-bind` to bind the Unit to a Worker's Target.
  - `cub-apply` to apply.
- Don't author Secrets here — for Redis with auth, point `envFrom: secretRef` at an externally-managed Secret (see `references/yaml-patterns.md`).

## Unit granularity decisions

- **Service + StatefulSet**: bundled (shared selector and lifecycle, headless Service is required by StatefulSet).
- **PVC**: not separate — `volumeClaimTemplates` inside the StatefulSet handles per-pod storage.
- If Redis needs RBAC (it doesn't here), that goes in a separate Unit per the granularity guidance.
