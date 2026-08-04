---
name: cub-apply
description: 'Deprecated 0.4.x compatibility identity for prior cub-apply/apply/deploy requests. Grants no tools, performs no operation, and routes the unchanged intent to release-publish with its whole-Space scope and authority blocks.'
phase: act
allowed-tools: []
read-capability-subset: none
compatibility-stub: true
---

# cub-apply (deprecated compatibility stub)

**Authority boundary:** this stub grants no tools and cannot inspect, mutate,
publish, cancel, or verify anything. It exists for one compatibility release so
direct Skill invocations do not disappear silently.

Tell the user that `release-publish` is the current canonical skill, then route
the original request and all supplied scope unchanged. Do not reinterpret a
narrow Unit, Filter, ChangeSet, or cross-Space intent as whole-Space approval.
`release-publish` must compute the complete `EffectiveReleaseSet`, disclose any
scope expansion, and ask again. It must preserve the versioned-legacy
cancel-inflight explanation and all current Release/provider authority blocks.

This stub is intentionally non-operational. It does not emit a command, treat
chat confirmation as authority, or claim that routing itself ran a tool.
