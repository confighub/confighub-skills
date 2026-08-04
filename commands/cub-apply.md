---
description: 'Deprecated one-release compatibility alias for apply/deploy requests. Routes to release-publish and never executes.'
argument-hint: '<apply or deploy intent>'
allowed-tools: []
---

# /confighub-skills:cub-apply (deprecated)

This is an observable compatibility shim for 0.4.x. Tell the user that
`release-publish` is the canonical skill, then load that skill and route the
original request unchanged:

```text
$ARGUMENTS
```

Preserve narrow Unit/Filter/ChangeSet intent as the requested scope. The
canonical skill must compare it with the whole `EffectiveReleaseSet`, disclose
any expansion, and ask again. It must also preserve the versioned-legacy
cancel-inflight route. This alias grants no tool permission and never turns a
chat confirmation into publication authority.
