# app-config eval — baseline (no skill)

## Scenario

> I have a Java application that reads `application.properties`. I want to manage that file in ConfigHub and deploy it as a ConfigMap that auto-restarts pods when it changes. Walk me through it.

## Response

You can manage your `application.properties` in ConfigHub by creating a ConfigMap Unit:

### 1. Create a ConfigMap YAML

```yaml
# /tmp/my-app-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-config
  namespace: my-app
data:
  application.properties: |
    spring.datasource.url=jdbc:postgresql://postgres.prod.internal:5432/mydb
    spring.datasource.username=app
    server.port=8080
    logging.level.root=INFO
```

### 2. Create a Unit in ConfigHub

```bash
cub unit create my-app-config --space my-app-prod < /tmp/my-app-config.yaml
```

### 3. Apply

```bash
cub unit apply my-app-config --space my-app-prod
```

### 4. Auto-restart pods

To get pods to restart when the ConfigMap changes, you have a few options:

**Option A: Use a hash annotation manually**

In your Deployment, add an annotation that matches a hash of the ConfigMap. You'd need to compute the hash yourself when updating.

**Option B: Use `kubectl rollout restart` after each ConfigMap update**

```bash
cub unit apply my-app-config --space my-app-prod
kubectl rollout restart deployment/my-app -n my-app
```

**Option C: Use a tool like Reloader**

Install the [Stakater Reloader](https://github.com/stakater/Reloader) operator in your cluster to automatically restart pods when ConfigMaps change.
