# space-topology eval — baseline (no skill)

## Scenario

> We have two apps (web and api) and three environments (dev, staging, prod). All three environments are in the same cluster for now, but prod will move to its own cluster soon. How should I lay out my ConfigHub Spaces?

## Response

Based on general knowledge of ConfigHub, here's how I'd structure your Spaces:

### Option 1: One Space per app

```
web       ← all web units: web-dev, web-staging, web-prod
api       ← all api units: api-dev, api-staging, api-prod
```

Each app gets its own Space. Within the Space, use naming conventions to distinguish environments (e.g., `web-dev`, `web-staging`, `web-prod` as Unit slugs). You can add labels like `env=dev`, `env=staging`, `env=prod` to filter Units within each Space.

This keeps things simple — one Space per app, easy to manage.

### Option 2: One Space per environment

```
dev       ← web + api Units for dev
staging   ← web + api Units for staging  
prod      ← web + api Units for prod
```

Group by environment. Each Space maps to an environment and holds all apps.

### Workers

Since everything is in one cluster, create a single Worker and attach it to each Space that needs deployments.

### Moving prod to a new cluster

When prod moves, create a new Worker pointed at the prod cluster and update the prod Space(s) to use it.

### Verification

```bash
cub info   # check you're authenticated
cub space list   # see your Spaces
```
