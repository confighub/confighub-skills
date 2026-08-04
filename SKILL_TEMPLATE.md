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

**Authority boundary:** this companion is knowledge/read-only. It may inspect and prepare an exact proposal, but it must not execute mutations. The external mutation broker is `NOT_INTEGRATED`, so executable paths end in `ASK` or `BLOCK`.

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

- Host-ASK: only reads in this skill's declared capability subset; no raw Bash is auto-allowed until a typed final-argv wrapper exists.
- Proposal-only: every ConfigHub mutation, including native approval and Release publication; bind exact identity/scope and `--change-desc` where supported.
- Not allowed: credentials/secrets, unbounded files, plugin/exec loading, refresh/network side effects, arbitrary functions, unknown flags, or any mutation without the external broker and provider CAS.

## The loop

Numbered imperative steps. Explain **why** each step matters, not just what. Keep the loop small and named.

## Change description

Every proposed configuration-data mutation must pass `--change-desc`. Compose it as:

```
<one-line summary>

User prompt: <verbatim user prompt, trimmed if very long>
Clarifications: <condensed summary of any Q&A — one line per resolved ambiguity, or "none">
```

For bulk `cub run`, the same description is recorded in every affected unit; phrase it so it makes sense at the per-unit level.

## Stop conditions

- <concrete conditions under which this skill hands back control>
- If preflight fails, never proceed by "trying anyway."

## Verify chain

How to prove externally authorized execution landed (not just that a command returned success). Typically a short sequence of read-only commands ending in an immutable ConfigHub identity plus controller/runtime assertions or named gaps.

## Evidence

- ConfigHub GUI page the user can open to review the change (use `cub unit open <unit> --space <space> --print-url` or `cub unit open <unit> --space <space> --revisions --print-url`; verify object identity before treating a URL as proof).
- Any relevant controller UI (Argo / Flux) for delivery verification.

## References

- `references/cub-cli.md` — CLI discipline.
- `references/functions-catalog.md` — which function to prefer.
- <other refs this skill needs>
```

## Evals

Every skill ships with `evals/evals.json` holding realistic end-user prompts and a top-level `execution_policy: "PROPOSE_ONLY_UNTIL_EXTERNAL_BROKER"`. Eval names are stable IDs and must appear in `compatibility/no-loss-inventory.v1.json`; renames require explicit `REPLACED_BY` aliases, never deletion. Mutating scenarios must assert proposal/authority behavior as well as command correctness.
