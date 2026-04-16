# Authoring plain, literal Kubernetes YAML

Everything here assumes **Configuration as Data**: fully materialized YAML stored in Units. No template syntax, no values-file split.

## Starting from scratch

Use `kubectl create … --dry-run=client -o yaml` (via the `kube-gen` helper or directly) to produce skeletons, then store the result in a Unit. Edit from that point forward via `cub function do` or direct edits — never re-render.

```bash
kubectl create deployment my-app --image=confighubplaceholder:confighubplaceholder \
  --dry-run=client -o yaml | egrep -v "creationTimestamp|status" > deploy.yaml
cub unit create --space myapp-dev my-app deploy.yaml \
  --change-desc "Bootstrapped my-app deployment from dry-run scaffold"
```

## Placeholders

`confighubplaceholder` (string) and `999999999` (number) are recognized placeholder literals. `vet-placeholders` catches any that remain before apply, and helpers like `set-default-names` / `ensure-namespaces` fill them in deliberately.

Use placeholders to mark "must be supplied" — don't leave fields out.

## Namespace convention

Every namespaced resource should have an explicit `namespace:`. When scaffolding, set it to `confighubplaceholder` and resolve per-Space via `set-attributes` or a direct function invocation before apply. `ensure-namespaces` adds the field where missing.

## Workloads — Deployment / StatefulSet / DaemonSet / Job / CronJob

Minimum viable shape (apply defaults functions to fill gaps):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: confighubplaceholder
  labels:
    app: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: main
          image: ghcr.io/myorg/my-app:v1.2.3
          ports:
            - containerPort: 8080
```

Then:

```bash
cub function do --space myapp-dev --where "Slug = 'my-app'" \
  set-container-resources-defaults --change-desc "Fill resource defaults"
cub function do --space myapp-dev --where "Slug = 'my-app'" \
  set-container-probe-defaults --change-desc "Fill probe defaults"
cub function do --space myapp-dev --where "Slug = 'my-app'" \
  set-pod-container-security-context-defaults --change-desc "Fill security context defaults"
```

This produces a full literal manifest without templating — and each step is recorded in the revision history.

## Namespaces

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp-prod
```

`set-pod-security-defaults` adds `pod-security.kubernetes.io/enforce: baseline` and `pod-security.kubernetes.io/warn: restricted` labels.

## Services / Ingress / NetworkPolicy

Plain YAML only. Don't parameterize the selector; it's a literal string. For cross-env variation, use one Unit per Space.

## RBAC

Write the ServiceAccount, Role/ClusterRole, and RoleBinding/ClusterRoleBinding as separate resources — either one Unit per kind or one Unit per app-scoped bundle, depending on how you want to version them. Default to bundling the SA + Role + Binding together when they only make sense together.

## ConfigMap / Secret

ConfigMaps: plain data under `data:`. Hash-and-propagate via `set-hash` if you want automatic redeploys on content change.

Secrets: store references to external secret managers (ExternalSecrets, SecretStore) rather than literal values. ConfigHub Units are not a secret vault — put the reference in the Unit, keep material elsewhere.

## Unit granularity

A Unit applies atomically. Guidelines:

- **One app bundle per Unit** (Deployment + Service + ConfigMap + SA + Role + Binding) for small apps: easy to reason about, single revision.
- **One resource per Unit** when you need independent versioning (e.g., the image changes per CI build but the Service config doesn't).
- **One Namespace per Unit** always — namespaces are long-lived and shared.

Split later rather than sooner if you're unsure; `compute-mutations`/`patch-mutations` can migrate resources between Units.

## StatefulSet + headless Service

For stateful workloads (databases, caches, message brokers). Bundle the StatefulSet + headless Service in one Unit — they share the same selector and lifecycle.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: confighubplaceholder
  labels:
    app: postgres
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: confighubplaceholder
  labels:
    app: postgres
spec:
  serviceName: postgres
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16.3
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: postgres-credentials
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```

Then apply defaults:

```bash
cub function do --space <space> --where "Slug = 'postgres'" \
  -- set-container-resources-defaults --change-desc "..."
cub function do --space <space> --where "Slug = 'postgres'" \
  -- set-container-probe-defaults --change-desc "..."
cub function do --space <space> --where "Slug = 'postgres'" \
  -- set-pod-container-security-context-defaults --change-desc "..."
```

Note: `set-container-probe-defaults` adds HTTP GET probes on the first `containerPort`. For databases, override with a TCP probe or exec command afterward via `yq-i`:

```bash
cub function do --space <space> --where "Slug = 'postgres'" \
  --change-desc "Switch to TCP liveness probe for postgres" \
  -- yq-i '
    with(select(.kind == "StatefulSet");
      .spec.template.spec.containers[0].livenessProbe = {"tcpSocket": {"port": 5432}, "initialDelaySeconds": 15, "periodSeconds": 20} |
      .spec.template.spec.containers[0].readinessProbe = {"tcpSocket": {"port": 5432}, "initialDelaySeconds": 5, "periodSeconds": 10}
    )'
```

## DaemonSet

For node-level agents (log collectors, monitoring exporters, CNI plugins). One Unit per DaemonSet. DaemonSets don't have `replicas` — they run on every matching node.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: confighubplaceholder
  labels:
    app: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      containers:
        - name: node-exporter
          image: prom/node-exporter:v1.8.1
          ports:
            - containerPort: 9100
              hostPort: 9100
          volumeMounts:
            - name: proc
              mountPath: /host/proc
              readOnly: true
            - name: sys
              mountPath: /host/sys
              readOnly: true
      volumes:
        - name: proc
          hostPath:
            path: /proc
        - name: sys
          hostPath:
            path: /sys
      tolerations:
        - operator: Exists
```

DaemonSets that need host access (monitoring, logging) legitimately use `hostPath` volumes and `hostPort`. Apply security context defaults, then override the specific fields that need host access.

## Job + CronJob

**One-shot Job** — for migrations, data processing, cleanup:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  namespace: confighubplaceholder
  labels:
    app: myapp
    job: db-migrate
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: ghcr.io/myorg/myapp:v1.2.3
          command: ["./migrate", "--target", "latest"]
          envFrom:
            - secretRef:
                name: myapp-db-credentials
```

**CronJob** — scheduled tasks:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
  namespace: confighubplaceholder
  labels:
    app: myapp
    job: backup
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 3600
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: backup
              image: ghcr.io/myorg/backup-tool:v1.0.0
              command: ["./backup", "--compress"]
```

Jobs and CronJobs use `restartPolicy: Never` (or `OnFailure`) — never `Always`. `backoffLimit` and `activeDeadlineSeconds` prevent runaway retries.

## Ingress

Expose a Service externally via HTTP/HTTPS. One Unit per Ingress — separate from the Service Unit so TLS config and routing rules version independently.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: confighubplaceholder
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp
                port:
                  number: 80
```

Always set `ingressClassName` explicitly — don't rely on a cluster default. Always configure TLS for production. The `cert-manager.io/cluster-issuer` annotation automates certificate provisioning.

## NetworkPolicy

Default-deny + explicit allow is the recommended pattern. Create a separate Unit for each policy so they version independently.

**Default deny all** — apply to every namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: confighubplaceholder
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

**Allow specific traffic** — per-app:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-myapp
  namespace: confighubplaceholder
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - protocol: TCP
          port: 5432
    - to: []
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

Always allow DNS egress (port 53) or pods can't resolve service names.

## RBAC

Bundle ServiceAccount + Role + RoleBinding in one Unit when they only make sense together. Use Role (namespaced) over ClusterRole unless the workload genuinely needs cross-namespace access.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp
  namespace: confighubplaceholder
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: myapp
  namespace: confighubplaceholder
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
    resourceNames: ["myapp-credentials"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: myapp
  namespace: confighubplaceholder
subjects:
  - kind: ServiceAccount
    name: myapp
    namespace: confighubplaceholder
roleRef:
  kind: Role
  name: myapp
  apiGroup: rbac.authorization.k8s.io
```

Principles:
- Grant only the verbs needed — never `*`.
- Use `resourceNames` to scope Secret access to specific secrets.
- Set `automountServiceAccountToken: false` on the ServiceAccount; only mount it on pods that need API access.
- Reference the ServiceAccount in the workload's `spec.template.spec.serviceAccountName`.

`set-automount-service-account-token-false` handles the pod-spec side:

```bash
cub function do --space <space> --where "Slug = 'myapp'" \
  -- set-automount-service-account-token-false --change-desc "..."
```

## HorizontalPodAutoscaler

One Unit per HPA. Keep separate from the workload Unit — scaling config changes independently from app config.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp
  namespace: confighubplaceholder
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 25
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 60
```

Always set `behavior.scaleDown.stabilizationWindowSeconds` to avoid flapping. The Worker's field-manager elision already handles HPA-managed `replicas` — ConfigHub won't fight the autoscaler.

## PodDisruptionBudget

One Unit per PDB. Keep separate from the workload.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp
  namespace: confighubplaceholder
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: myapp
```

Use `minAvailable` (how many must stay up) or `maxUnavailable` (how many can be down), not both. For replicas >= 3, `maxUnavailable: 1` is equivalent to `minAvailable: N-1` and is easier to reason about as replicas change.

## PersistentVolumeClaim

Standalone PVC for workloads that mount shared or pre-provisioned storage. One Unit per PVC when it outlives the workload (e.g., data volumes reattached across deployments). For StatefulSets, use `volumeClaimTemplates` instead (see above).

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-data
  namespace: confighubplaceholder
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: standard
```

## Cross-environment variation

Do **not** template across envs. Use:

- One Space per app × environment/region.
- Upstream/downstream Unit relationships to clone base → env-specific.
- Functions to materialize the env-specific differences (e.g., `set-container-image` per env, `set-replicas` per env, `set-env-var` for env-specific config).

See `functions-catalog.md` for the full list.
