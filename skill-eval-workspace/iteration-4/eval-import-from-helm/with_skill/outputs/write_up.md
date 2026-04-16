# import-from-helm eval — with-skill

## Scenario

> I'm running `cub helm install cert-manager jetstack/cert-manager --version v1.17.2`. Should I separate the CRDs into their own Unit?

## Preflight

Auth:

```
$ cub context get
User: <authenticated>
```

Helm repo:

```
$ helm repo list
NAME        URL
jetstack    https://charts.jetstack.io
```

```
$ helm search repo jetstack/cert-manager --versions | head -5
NAME                     	CHART VERSION	APP VERSION	DESCRIPTION
jetstack/cert-manager    	v1.17.2      	v1.17.2    	...
```

Good — repo added, version exists.

## Answer: you don't need to — `cub helm install` already does it

`cub helm install` automatically splits CRDs into their own Unit. Running:

```bash
cub helm install cert-manager jetstack/cert-manager \
  --space <target-space> \
  --namespace cert-manager \
  --version v1.17.2
```

…will create **two Units**:

1. **`cert-manager`** — main resources (Deployment, Service, ServiceAccount, RBAC, webhooks, etc.)
2. **`cert-manager-crds`** — CRDs from the chart's `crds/` directory (Certificate, Issuer, ClusterIssuer, CertificateRequest, etc.)

This split is the default behavior. No extra flags needed.

### Why CRDs are always separate (even automatically)

- CRDs must be applied and established before CRs that reference them. Separate Units let you sequence: `cub unit apply cert-manager-crds --wait` → `kubectl wait --for=condition=established` → `cub unit apply cert-manager --wait`.
- CRDs have different lifecycle and blast radius: deleting a CRD cascades to every CR. Updating CRDs can break existing CRs. You want that as a deliberate, auditable change — not mixed in with a workload update.
- Rollback of the workload Unit doesn't accidentally roll back CRD schema changes.

### Important flags you should add

1. **`--namespace cert-manager`** — always pass `--namespace`. cert-manager's chart computes `.Release.Namespace` into webhook Service hostnames, RBAC subject references, and ConfigMap keys. Without `--namespace`, rendered output won't match what `helm install` would produce.

2. **`--version v1.17.2`** — already pinned, good. Never install without `--version`.

3. **No `--change-desc`** — `cub helm install` does not accept `--change-desc`. Chart provenance (release name, repo/chart, version) is recorded as Unit labels.

### Verify

```bash
cub unit list --space <target-space> --where "Labels.helmrelease = 'cert-manager'"
```

Should show both `cert-manager` and `cert-manager-crds`.

### Apply order

```bash
# CRDs first
cub unit apply cert-manager-crds --space <target-space> --wait

# Wait for CRDs to be established
kubectl wait --for=condition=established --timeout=60s \
  crd/certificates.cert-manager.io \
  crd/issuers.cert-manager.io \
  crd/clusterissuers.cert-manager.io

# Then main resources
cub unit apply cert-manager --space <target-space> --wait
```

### Multi-env: clone, don't re-install

If you need cert-manager in staging + prod:

**Option A** (per-env values files): run `cub helm install` once per env-Space.

**Option B** (single config): install once into a base Space, clone per env:

```bash
cub unit create --space infra-staging cert-manager --upstream-unit infra-dev/cert-manager
cub unit create --space infra-prod   cert-manager --upstream-unit infra-dev/cert-manager
```

Customize the clones via `cub-mutate` (not by editing directly). When cert-manager releases a new version, `cub helm upgrade` on the base, then `cub unit update --upgrade` in each env-Space.

### Trajectory

This is an onboarding tool. Over time, you'll rely less on chart values and more on `cub-mutate` functions for customization. The chart is a bootstrap input, not an ongoing parameterization surface.

## Tool boundary

Hand off to `cub-apply` for deployment. Customizations post-install go through `cub-mutate`, not editing the base Unit directly.
