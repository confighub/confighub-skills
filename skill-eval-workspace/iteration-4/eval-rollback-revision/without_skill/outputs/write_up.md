# rollback-revision eval — baseline (no skill)

## Scenario

> My teammate ran `cub unit apply --revision 5` on `orders-api` in prod to "roll back" to the previous version. But the bad revision 6 is still head and keeps showing up. What's wrong, and how do I actually roll back?

## Response

It sounds like `cub unit apply --revision 5` deployed revision 5 to the cluster but didn't update the Unit's current version pointer. The Unit still thinks revision 6 is the latest.

To properly roll back, you should update the Unit to point at the older revision:

```bash
# Check current state
cub unit get orders-api --space orders-prod

# Roll back by re-applying the content from revision 5
cub revision get 5 --unit orders-api --space orders-prod --yaml > /tmp/rev5.yaml
cub unit update orders-api --space orders-prod < /tmp/rev5.yaml --change-description "Roll back to revision 5"

# Re-apply
cub unit apply orders-api --space orders-prod
```

This should set the head to a new revision with the content from revision 5.

Alternatively, you could try:

```bash
cub unit apply --revision 5 --space orders-prod orders-api --force
```

to make it stick as the current version.
