# Shared skill template

Every `SKILL.md` in this repo starts from this scaffold. Keep skills under ~300 lines; push depth into `references/`.

```markdown
---
name: <skill-slug>
description: <One sentence on what the skill does AND when to trigger, including phrases a user would actually say. End with 1–2 concrete "do NOT load for" cases. Be a bit pushy — Claude undertriggers by default.>
phase: decide | act | verify | close | cross-cutting
allowed-tools: <Read set always; add Write set for mutating skills; add read-only diagnostics like Bash(kubectl get *), Bash(argocd app get *), Bash(flux get *) where the skill needs them. See references/cub-cli.md for the canonical Read and Write sets. Never grant Bash(cub *) or Bash(cub * delete *). Never grant mutating kubectl/argocd/flux patterns — mutations go through cub.>
---

# <skill-name>

One or two sentences on what the skill enables, in plain terms.

## When to use

- <explicit user phrasings>
- <implicit intents this should cover>

## Do not load for

- <adjacent tasks that look similar but need a different skill>
- <cases where another tool is more appropriate>

## Preflight gates

Before acting, confirm:

1. `cub auth login` is current (`cub context get` returns a user).
2. Target Space exists and the user has write permission.
3. <skill-specific gates>

If any gate fails, stop and tell the user what's missing.

## Tool boundary

- Mutations: `cub unit update`, `cub function do`, `cub run` — always with `--change-desc`.
- Read-only diagnosis: `kubectl get`, `argocd app get`, `flux get` are allowed.
- Not allowed: `kubectl apply/edit/patch/delete`, `argocd app sync` as a mutation, raw `helm install/upgrade`, editing values files outside ConfigHub.

## The loop

Numbered imperative steps. Explain **why** each step matters, not just what. Keep the loop small and named.

## Change description

Every mutation call must pass `--change-desc`. Compose it as:

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

How to prove the change landed (not just that `cub` returned success). Typically a short sequence of read-only commands ending in either a ConfigHub URL the user can click or a specific assertion.

## Trust surface

- ConfigHub GUI page the user can open to review the change (prefer `cub unit get --web` or `cub revision list --web` over hand-built URLs).
- Any relevant controller UI (Argo / Flux) for delivery verification.

## References

- `references/cub-cli.md` — CLI discipline.
- `references/functions-catalog.md` — which function to prefer.
- <other refs this skill needs>
```

## Evals

Every skill ships with `evals/evals.json` holding 2–3 realistic end-user prompts (see skill-creator methodology). Start without assertions; add them after the first run.
