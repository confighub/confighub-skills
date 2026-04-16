# rollback-revision eval — with-skill

## Scenario

> My teammate ran `cub unit apply --revision 5` on `orders-api` in prod to "roll back" to the previous version. But the bad revision 6 is still head and keeps showing up. What's wrong, and how do I actually roll back?

## Diagnosis

`cub unit apply --revision 5` applied revision 5's data to the cluster — but it **did not move the Unit's head**. Revision 6 is still head. This means:

- The next `cub-mutate` / `promote-release` / merge branches from revision 6 (the "bad" one), re-introducing the bad state.
- The Unit shows `HeadRevisionNum = 6` but `LiveRevisionNum = 5` — a permanent divergence that will confuse every downstream tool.
- `--revision` on `cub unit apply` is for *inspecting* or *diffing* an older revision, never for rolling back.

**`cub unit apply --revision <N>` is NOT a rollback.** It leaves head unchanged, so the bad state comes back on the next forward change.

## The correct rollback: `cub unit update --restore`

```bash
# 1. Confirm current state
cub revision list orders-api --space orders-prod
# HeadRevisionNum: 6, LiveRevisionNum: 5

# 2. Restore head to revision 5's data — creates a NEW revision (7) whose data = revision 5's data
cub unit update --space orders-prod orders-api \
  --restore 5 \
  --change-desc "Rollback orders-api to revision 5 (undo bad revision 6).

User prompt: teammate used apply --revision which doesn't move head; doing proper rollback
Clarifications: revision 6 had a broken image tag"

# 3. Confirm head moved
cub revision list orders-api --space orders-prod
# HeadRevisionNum: 7 (restored from 5), bad revision 6 stays in history for audit

# 4. Diff to confirm
cub unit diff orders-api --space orders-prod
# Should show head data = revision 5's data

# 5. Apply the new head
cub unit apply orders-api --space orders-prod --wait
```

### Why --restore is the only rollback mechanism

- Creates a **new head revision** whose data equals the target revision's data.
- Every subsequent mutation branches from the restored head — the "bad" state stays gone.
- The rolled-back revision stays in audit history (can't and shouldn't be deleted).
- Works with named targets: `--restore Tag:<tag>`, `--restore Before:ChangeSet:<slug>`, `--restore -1` (relative).

### Optionally tag the rollback

```bash
cub tag create --space orders-home rollback-orders-api-20260415 \
  --annotation "description=Rollback orders-api rev 6; broken image tag"
cub unit tag orders-home/rollback-orders-api-20260415 --space orders-prod --unit orders-api
```

## Verify

```bash
# Data matches revision 5
cub unit get orders-api --space orders-prod --yaml

# Revision list shows new head (7) with rollback change-desc
cub revision list orders-api --space orders-prod

# After apply: LiveRevisionNum = HeadRevisionNum = 7
cub unit bridgestate orders-api --space orders-prod
```

## Tool boundary

Hand off to `cub-apply` for the post-restore apply. If the bad state also went to staging, rollback there separately.
