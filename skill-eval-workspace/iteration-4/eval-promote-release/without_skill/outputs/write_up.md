# promote-release eval — baseline (no skill)

## Scenario

> We have 6 Units in `orders-prod` that are behind their staging upstreams. Promotion-preflight gave us a `go`. Run the promotion.

## Response

To promote the 6 Units from staging to prod:

```bash
# Upgrade each Unit to match its upstream
cub unit update orders-api --space orders-prod --upgrade --change-description "Promote from staging"
cub unit update orders-worker --space orders-prod --upgrade --change-description "Promote from staging"
cub unit update orders-cron --space orders-prod --upgrade --change-description "Promote from staging"
cub unit update orders-api-config --space orders-prod --upgrade --change-description "Promote from staging"
cub unit update orders-worker-config --space orders-prod --upgrade --change-description "Promote from staging"
cub unit update orders-shared --space orders-prod --upgrade --change-description "Promote from staging"

# Apply all changes
cub unit apply orders-api --space orders-prod
cub unit apply orders-worker --space orders-prod
cub unit apply orders-cron --space orders-prod
cub unit apply orders-api-config --space orders-prod
cub unit apply orders-worker-config --space orders-prod
cub unit apply orders-shared --space orders-prod
```

Verify the promotion:

```bash
kubectl get pods -n orders-prod
cub unit list --space orders-prod
```
