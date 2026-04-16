# promotion-preflight eval — baseline (no skill)

## Scenario

> We want to promote our `orders` app from staging to prod. Is staging ready? What do I need to check?

## Response

Before promoting from staging to prod, here's a checklist:

### 1. Check staging is healthy

```bash
cub info  # verify authentication
cub unit list --space orders-staging
```

Make sure all Units are in a good state. Check that deployments are running:

```bash
kubectl get pods -n orders-staging
```

### 2. Review what's changed

Look at the recent changes in staging:

```bash
cub unit get orders --space orders-staging
```

### 3. Run any tests

Make sure your staging tests pass and the application is behaving correctly.

### 4. Promote

Once satisfied, you can copy the configuration to prod:

```bash
cub unit update orders --space orders-prod --upgrade
cub unit apply orders --space orders-prod
```

### 5. Verify

```bash
kubectl get pods -n orders-prod
```

Make sure pods come up healthy.
