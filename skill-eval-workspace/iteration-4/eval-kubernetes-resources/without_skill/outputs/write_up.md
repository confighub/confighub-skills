# kubernetes-resources eval — baseline (no skill)

## Scenario

> I need to deploy a Redis cluster as a StatefulSet in ConfigHub with 3 replicas and persistent storage. The Redis pods should use the redis:7.2 image and listen on port 6379. Set it up in my redis-prod Space.

## Response

Here's how to set up the Redis StatefulSet in ConfigHub:

### 1. Write the YAML

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: redis-prod
spec:
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

Save as `/tmp/redis.yaml`.

### 2. Create the Unit

```bash
cub unit create redis --space redis-prod < /tmp/redis.yaml
```

### 3. Apply

```bash
cub unit apply redis --space redis-prod
```

### 4. Verify

```bash
kubectl get statefulset -n redis-prod
kubectl get pods -n redis-prod
```

You should see 3 redis pods come up with persistent volumes.
