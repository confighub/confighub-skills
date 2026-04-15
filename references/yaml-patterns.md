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

## Cross-environment variation

Do **not** template across envs. Use:

- One Space per app × environment/region.
- Upstream/downstream Unit relationships to clone base → env-specific.
- Functions to materialize the env-specific differences (e.g., `set-container-image` per env, `set-replicas` per env, `set-env-var` for env-specific config).

See `functions-catalog.md` for the full list.
