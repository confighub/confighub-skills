# Find release: checkout v0.4.2

## Response to user

I queried your local ConfigHub instance and **there is no `checkout` service or `v0.4.2` release deployed anywhere in it**. Here's what I actually found:

- **Spaces that exist (4):** `default`, `test-space`, `platform`, `skill-examples`
- **Total units across all spaces:** 2, both in `skill-examples`:
  - `hello-app` (status `NotLive`)
  - `hello-ns` (status `NotLive`)
- **No unit** has a slug or display name matching `checkout` or `0.4.2`.
- No tags/labels matching that version were discoverable via unit search either.

Possibilities:
1. You may be thinking of a different ConfigHub instance (a team/cloud instance rather than your local one). Run `cub info` or `cub context get` to confirm which server you're pointed at.
2. The `checkout` service may live in a different product/tool (e.g., an Argo Application, a Git repo, a container registry) rather than ConfigHub. If it's Argo-managed, I can check `argocd app list` or `kubectl get applications -A`.
3. If you expected it to be here and it isn't, it may never have been onboarded to this instance.

Tell me which instance you meant, or which tool owns the `checkout` release, and I'll track it down.

## Commands run (with real output)

### 1. List all spaces
```
$ cub space list
NAME              ENVIRONMENT    #UNITS    #LINKS    #TAGS    #CHANGESETS    #FILTERS    #VIEWS    #INVOCATIONS    #TRIGGERS    #WORKERS    #TARGETS    #ATTRIBUTES
default                          0         0         0        0              1           1         0               0            1           0           0
test-space                       0         0         0        0              0           0         0               1            0           0           0
platform                         0         0         0        0              0           0         0               0            0           0           0
skill-examples                   2         0         0        0              0           0         0               0            0           0           0
```

### 2. List all units across all spaces
```
$ cub unit list --space '*'
NAME         SPACE             STATUS     LAST-CHANGE-DESCRIPTION
hello-app    skill-examples    NotLive    Ensure every namespaced resource has a namespace field...
hello-ns     skill-examples    NotLive    Add pod-security labels (baseline enforce, restricted warn)...
```
Only 2 units total. Neither is `checkout`.

### 3. Filter by slug = checkout
```
$ cub unit list --space '*' --where "Slug LIKE '%checkout%'"
(no rows)
```

### 4. Filter by display name = checkout
```
$ cub unit list --space '*' --where "DisplayName LIKE '%checkout%'"
(no rows)
```

### 5. Filter by version string 0.4.2
```
$ cub unit list --space '*' --where "Slug LIKE '%0.4.2%'"
(no rows)
```

## Reasoning notes

- ConfigHub models deployed configuration as **Units** within **Spaces** (which typically represent environments/clusters). To answer "where is X deployed" I needed to (a) enumerate all spaces and (b) find any unit referring to the `checkout` service at version `v0.4.2`.
- Tried `--where` SQL-like filtering on `Slug` and `DisplayName` with `LIKE '%checkout%'` and `LIKE '%0.4.2%'`. The filter API rejects `OR`, so I ran each predicate separately.
- Image tags / versions could also live inside the unit's config body rather than its name — but with only 2 unrelated units in the whole instance, a body-content grep wouldn't change the answer: the service isn't here.
- This is Brian's local dev instance (per CLAUDE.md), so the most likely explanation is wrong-instance or wrong-tool, not a query-depth issue.
