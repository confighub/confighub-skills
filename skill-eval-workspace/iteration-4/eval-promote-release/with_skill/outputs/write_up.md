# promote-release eval — with-skill

## Scenario

> We have 6 Units in `orders-prod` that are behind their staging upstreams. Promotion-preflight gave us a `go`. Run the promotion.

## Preflight

```
$ cub context get
User: <authenticated>
```

Preflight scope (from promotion-preflight):
- Filter: `orders-home/orders-app`
- Destination: `orders-prod`
- Count: 6 Units behind upstream
- ChangeSet: `release-20260415-a3b2c1`
- Recommendation: `go`

Confirm no other open ChangeSet on the scope:

```bash
cub unit list --space orders-prod --filter orders-home/orders-app --where "LEN(ChangeSetID) > 0"
# (empty — good)
```

## Shape A — pull via `cub unit update --upgrade`

This is env-by-env promotion (staging → prod), so Shape A.

```bash
HOME_SPACE=orders-home
TO_SPACE=orders-prod
APP_FILTER=$HOME_SPACE/orders-app
CHANGESET_SLUG=release-20260415-a3b2c1
CHANGESET_REF=$HOME_SPACE/$CHANGESET_SLUG

# 1. Create the ChangeSet in the home Space.
cub changeset create --space $HOME_SPACE $CHANGESET_SLUG \
  --description "Promote orders staging → prod; 6 Units"

# 2. Open the ChangeSet on the scope.
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --changeset $CHANGESET_REF \
  --change-desc "Open $CHANGESET_SLUG — begin promotion to prod"

# 3. Bulk upgrade: every downstream Unit pulls its upstream head.
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --changeset $CHANGESET_REF \
  --upgrade \
  --change-desc "Upgrade to upstream head as part of $CHANGESET_SLUG.

User prompt: promote orders from staging to prod
Clarifications: 6 Units in scope per promotion-preflight go recommendation"

# 4. Review diffs before closing.
for u in $(cub unit list --space $TO_SPACE --filter $APP_FILTER --quiet --jq '.[].Slug'); do
  echo "=== $u ==="
  cub unit diff "$u" --space $TO_SPACE --from-revision -2
done

# 5. Close the ChangeSet.
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --changeset -
```

### Why wrap in a ChangeSet

- **Locks** the scope — no concurrent mutations can interleave.
- **Groups** revisions for atomic approval and apply.
- **Rollback** is one command: `--restore Before:ChangeSet:$CHANGESET_REF`.
- **Audit** — every Unit's revision history carries the ChangeSet tags.

### If approval is required

```bash
cub unit approve --space $TO_SPACE \
  --filter $APP_FILTER \
  --revision ChangeSet:$CHANGESET_REF
```

Route to the approver per preflight's approval plan.

### Hand off to cub-apply

```bash
cub unit apply --space $TO_SPACE \
  --filter $APP_FILTER \
  --revision ChangeSet:$CHANGESET_REF \
  --wait --timeout 10m0s
```

From here, `cub-apply` / `verify-delivery` / `reconciliation-check` / `release-verify` own the runtime.

### If rollback is needed later

```bash
cub tag create --space $HOME_SPACE rollback-$CHANGESET_SLUG \
  --annotation "description=Rollback $CHANGESET_SLUG"
cub unit update --patch --space $TO_SPACE \
  --filter $APP_FILTER \
  --restore "Before:ChangeSet:$CHANGESET_REF" \
  --tag $HOME_SPACE/rollback-$CHANGESET_SLUG \
  --change-desc "Rollback $CHANGESET_SLUG."
cub unit apply --space $TO_SPACE --filter $APP_FILTER --wait
```

## Verify

```bash
# All Units upgraded — no rows in needs-upgrade
cub unit list --space $TO_SPACE --filter platform/needs-upgrade
# (empty)

# Revisions tagged with ChangeSet
cub revision list --space $TO_SPACE --filter $APP_FILTER --where "ChangeSet.Slug = '$CHANGESET_SLUG'"

# ChangeSet closed
cub changeset get --space $HOME_SPACE $CHANGESET_SLUG
```
