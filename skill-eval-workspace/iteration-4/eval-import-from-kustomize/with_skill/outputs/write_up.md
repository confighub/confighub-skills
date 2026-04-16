# import-from-kustomize eval — with-skill

## Scenario

> I have a `base/` directory with a Deployment, Service, and ConfigMap for my `orders` service, plus `overlays/dev`, `overlays/staging`, and `overlays/prod` that patch replicas and image tags. How do I get this into ConfigHub?

## Preflight

```
$ cub context get
User: <authenticated>
```

Check kustomize is available:

```
$ kustomize version
v5.4.2
```

Check overlay structure:

```
$ ls overlays/
dev/  staging/  prod/
$ cat overlays/dev/kustomization.yaml
```

## Recommendation

### Space layout first (space-topology)

Each overlay maps to its own ConfigHub Space — environments are Spaces, not suffixes:

```
orders-dev      ← overlays/dev renders here
orders-staging  ← overlays/staging renders here
orders-prod     ← overlays/prod renders here
```

The Unit slug inside each Space is `orders` (not `orders-dev`).

### Two patterns — pick based on your intent

**Pattern A — render each overlay separately (recommended if overlays diverge significantly):**

Each overlay renders into its env-Space. No upstream link between them.

```bash
mkdir -p /tmp/kustomize-import

# Render each overlay
for env in dev staging prod; do
  kustomize build overlays/$env > /tmp/kustomize-import/orders-$env.yaml
done

# Create Units in each env-Space
for env in dev staging prod; do
  cub unit create --space "orders-$env" orders "/tmp/kustomize-import/orders-$env.yaml" \
    --change-desc "Import orders $env overlay from Kustomize at $(git rev-parse --short HEAD).

User prompt: <verbatim>
Clarifications: rendered via kustomize v5.4.2 from overlays/$env"
done
```

**Pattern B — render once + clone (recommended if overlays are mostly the same):**

Render the base (or dev overlay), import as a base Unit, then clone per-env with upstream links:

```bash
kustomize build overlays/dev > /tmp/kustomize-import/orders.yaml

cub unit create --space orders-dev orders /tmp/kustomize-import/orders.yaml \
  --change-desc "Import orders from Kustomize overlays/dev at $(git rev-parse --short HEAD).

User prompt: <verbatim>
Clarifications: base for clone-based promotion"

# Clone to staging and prod — edits in clones survive base re-renders
cub unit create --space orders-staging orders --upstream-unit orders-dev/orders
cub unit create --space orders-prod   orders --upstream-unit orders-dev/orders
```

Per-env customizations (replicas, image tags) go through `cub-mutate` functions on the clones, not by editing the clone directly:

```bash
cub function do set-replicas orders --space orders-prod \
  --replicas 5 \
  --change-desc "Set prod replicas to 5.

User prompt: <verbatim>
Clarifications: matches current overlays/prod patch"
```

### The trajectory

This is an onboarding tool. Over time you'll:
- Replace per-overlay `kustomization.yaml` with per-env cloned Units customized via `cub-mutate` functions
- Drop patch files in favor of named functions (`set-container-image`, `set-replicas`, `set-env-var`)
- Only re-render from Kustomize source when upstream base changes warrant it

### What NOT to do

- `kubectl apply -k overlays/prod` — that deploys to the cluster bypassing ConfigHub
- Edit the base Unit if using Pattern B — edits are clobbered on the next re-render
- Put all overlays into one Space with `-dev`/`-prod` suffix Unit slugs — collapses Space boundaries

### Verify

```bash
cub unit list --space orders-dev
cub unit get orders --space orders-dev --yaml | diff - /tmp/kustomize-import/orders-dev.yaml
cub revision list orders --space orders-dev  # Revision 1 with Kustomize provenance
```

### Hand off

Apply via `cub-apply`. Customization post-import via `cub-mutate`. Policy via `triggers-and-applygates`.
