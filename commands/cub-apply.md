---
description: 'Deprecated one-release compatibility alias for apply/deploy requests. Routes unchanged intent to release-publish, which owns any standalone host-permission call.'
argument-hint: '<apply or deploy intent>'
allowed-tools: []
---

# /confighub-skills:cub-apply (deprecated)

Follow [`references/execution-modes.md`](../references/execution-modes.md).
This shim adds no permission rule of its own.

This is an observable compatibility shim for 0.4.x. Tell the user that
`release-publish` is the canonical skill, then load that skill and route the
original request unchanged:

```text
$ARGUMENTS
```

Preserve narrow Unit/Filter/ChangeSet intent as the requested scope. The
canonical skill must compare it with the whole `EffectiveReleaseSet`, disclose
any expansion, and ask again. It must also preserve the historical-only
cancel-inflight route. This alias grants no tool permission and never turns a
chat confirmation into publication authority.
