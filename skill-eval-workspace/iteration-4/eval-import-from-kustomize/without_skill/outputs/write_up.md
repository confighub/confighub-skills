# import-from-kustomize eval — baseline (no skill)

## Scenario

> I have a `base/` directory with a Deployment, Service, and ConfigMap for my `orders` service, plus `overlays/dev`, `overlays/staging`, and `overlays/prod` that patch replicas and image tags. How do I get this into ConfigHub?

## Response

You can render your Kustomize overlays and import them into ConfigHub. Here's the approach:

### 1. Render the overlays

```bash
kustomize build overlays/dev > orders-dev.yaml
kustomize build overlays/staging > orders-staging.yaml
kustomize build overlays/prod > orders-prod.yaml
```

### 2. Create Units in ConfigHub

```bash
# Create a Space for your orders service
cub space create orders

# Create Units for each environment
cub unit create orders-dev --space orders < orders-dev.yaml
cub unit create orders-staging --space orders < orders-staging.yaml
cub unit create orders-prod --space orders < orders-prod.yaml
```

### 3. Verify

```bash
cub info  # Check authentication
cub unit list --space orders
```

### 4. When you need to update

Re-render the overlay and update the Unit:

```bash
kustomize build overlays/prod > orders-prod.yaml
cub unit update orders-prod --space orders < orders-prod.yaml
```

You can keep using your Kustomize overlays as the source of truth and re-render whenever changes happen.
