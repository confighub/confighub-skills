# drift-reconcile eval — baseline (no skill)

## Scenario

> Someone kubectl edit'd our `payments-api` Deployment in prod to set replicas to 10 during a traffic spike. The spike is over. ConfigHub says replicas should be 3. How do I reconcile this?

## Response

Since the spike is over and ConfigHub has the correct value (3 replicas), you just need to reapply the ConfigHub state to overwrite the manual cluster change:

```bash
cub unit apply payments-api --space payments-prod
```

This will push ConfigHub's desired state (replicas: 3) back to the cluster, overwriting the manual edit.

Alternatively, if you want to keep the higher replica count:

```bash
cub unit update payments-api --space payments-prod --set spec.replicas=10
cub unit apply payments-api --space payments-prod
```

To prevent this in the future, consider setting up an HPA (Horizontal Pod Autoscaler) instead of manually editing replicas.
