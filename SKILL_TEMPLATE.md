# Shared skill template

Every `SKILL.md` in this repo starts from this scaffold. Keep skills under ~300 lines; push depth into `references/`.

```markdown
---
name: <skill-slug>
description: <One sentence on what the skill does AND when to trigger, including phrases a user would actually say. End with 1–2 concrete "do NOT load for" cases. Be a bit pushy — Claude undertriggers by default.>
phase: decide | act | verify | completion | cross-cutting
allowed-tools: []
read-capability-subset: <matching skill_id in compatibility/read-capability-subsets.v1.json>
---

# <skill-name>

**Execution mode:** follow [`references/execution-modes.md`](references/execution-modes.md). Keep `allowed-tools: []`, so the Skill preapproves no tool. A standalone requested mutation becomes one exact Bash call submitted to the host permission system; a separately installed governance overlay may stop it before Bash.

One or two sentences on what the skill enables, in plain terms.

## When to use

- <explicit user phrasings>
- <implicit intents this should cover>

## Do not load for

- <adjacent tasks that look similar but need a different skill>
- <cases where another tool is more appropriate>

## Preflight gates

Before acting, confirm:

1. `cub auth status` succeeds — it contacts the server's `/me` endpoint to confirm the token is still valid (not just local login state). If it fails, ask the user to run `cub auth login` (an interactive browser sign-in an agent cannot complete).
2. Target Space and object identity can be read; record any missing permission as a blocker rather than probing with a write.
3. <skill-specific gates>

If any gate fails, stop and tell the user what's missing.

## Tool boundary

- Host permission: only reads in this Skill's declared capability subset; the pack preapproves no Bash call.
- Standalone mutation steps: each ConfigHub mutation, including native approval and Release publication, uses one exact host-permission call; bind exact identity/scope and `--change-desc` where supported.
- Not allowed: credentials/secrets, unbounded files, plugin/exec loading, refresh/network side effects, arbitrary functions, unknown flags, or stronger atomicity claims than the invoked provider operation supports.

## The loop

Numbered imperative steps. Explain **why** each step matters, not just what. Keep the loop small and named.

## Change description

Every supported configuration-data mutation must pass a short, model-authored
`--change-desc` following `references/execution-modes.md`:

```
Update reviewed configuration for requested rollout
```

For bulk `cub run`, the same description is recorded in every affected Unit;
phrase it so it makes sense at the per-Unit level. Never interpolate verbatim
prompt or clarification text into shell source.

## Stop conditions

- <concrete conditions under which this skill hands back control>
- If preflight fails, never proceed by "trying anyway."

## Verify chain

How to prove a permitted command landed (not just that it returned success). Typically a short sequence of read-only commands ending in an immutable ConfigHub identity plus controller/runtime assertions or named gaps.

## Evidence

- ConfigHub GUI page the user can open to review the change (use `cub unit open <unit> --space <space> --print-url` or `cub unit open <unit> --space <space> --revisions --print-url`; verify object identity before treating a URL as proof).
- Any relevant controller UI (Argo / Flux) for delivery verification.

## References

- `references/cub-cli.md` — CLI discipline.
- `references/functions-catalog.md` — which function to prefer.
- <other refs this skill needs>
```

## Evals

Every skill ships with `evals/evals.json` holding realistic end-user prompts and a top-level `execution_policy: "STANDALONE_HOST_ASK_WITH_OPTIONAL_OVERLAY"`. Eval names are stable IDs and must appear in `compatibility/no-loss-inventory.v1.json`; renames require explicit `REPLACED_BY` aliases, never deletion. Mutating scenarios must assert exact scope, one-command host permission, overlay blocking, and postcondition verification as well as command correctness.
