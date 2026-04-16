# import-from-cluster eval — baseline (no skill)

## Scenario

> We've been kubectl-applying everything in our `payments` namespace for two years. There's no Helm chart, no ArgoCD — just a bunch of YAML files in a git repo that someone applies. How do I bring this under ConfigHub management?

## Response

To bring your existing kubectl-managed resources into ConfigHub:

### 1. Export your current state

```bash
kubectl get all -n payments -o yaml > payments-namespace-export.yaml
```

### 2. Create a Space and Unit in ConfigHub

```bash
cub space create payments
cub unit create payments --space payments
```

### 3. Import the YAML

```bash
cub unit update payments --space payments < payments-namespace-export.yaml
```

### 4. Set up a Worker and Target

You'll need a Worker running in your cluster to deploy changes:

```bash
cub worker create payments-worker --space payments
# Install the worker in your cluster
cub worker install payments-worker --space payments | kubectl apply -f -
```

### 5. Going forward

Now you can manage changes through ConfigHub:

```bash
# Edit the Unit
cub unit update payments --space payments < updated-payments.yaml --change-description "Update replicas"

# Apply changes
cub unit apply payments --space payments
```

This gives you audit trails and rollback capability that you didn't have with raw kubectl.
