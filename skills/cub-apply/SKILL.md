---
name: cub-apply
description: 'Deprecated 0.4.x compatibility identity for prior cub-apply/apply/deploy requests. Grants no tools, performs no operation, and routes the unchanged intent to release-publish with its whole-Space scope and safety checks.'
phase: act
allowed-tools: []
read-capability-subset: none
compatibility-stub: true
---

# cub-apply (deprecated compatibility stub)

**Execution mode:** follow [`references/execution-modes.md`](../../references/execution-modes.md). This routing stub grants no automatic tool permission and invokes no command itself. It exists for one compatibility release so
direct Skill invocations do not disappear silently.

Tell the user that `release-publish` is the current canonical skill, then route
the original request and all supplied scope unchanged. Do not reinterpret a
narrow Unit, Filter, ChangeSet, or cross-Space intent as whole-Space approval.
`release-publish` must compute the complete `EffectiveReleaseSet`, disclose any
scope expansion, and ask again. It must preserve the historical-only
cancel-inflight explanation and all current Release/provider limitations.

This stub is intentionally non-operational. `release-publish`, once loaded,
owns any standalone host-permission call; routing itself never ran a tool.
