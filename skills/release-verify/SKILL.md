---
name: release-verify
description: Load ONLY after reconciliation-check has confirmed ConfigHub, controller, and cluster all agree. The final read-only completion step — switches the session to read-only, surfaces the Revision history with its --change-desc provenance, prints the applied diff, and opens the canonical GUI review links (cub unit get --web, cub revision list --web) so the user has something clickable to file with the release. Stops further mutation in this session unless the user explicitly asks for a new change. Phrases that trigger: "close this out", "is it done?", "wrap it up", "show me what changed", "we're good — final confirmation". Do not load if verify-delivery or reconciliation-check haven't passed — completion would be premature. Do not use as a substitute for the earlier verification skills.
phase: completion
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *)
---

# release-verify

The stop-signal at the end of the ops loop. Read-only, revision-history-oriented, heavy on GUI review links.

## Why it matters

The story a release tells only sticks if it's documented at the moment it converges. The revision history carries the `--change-desc` composed at mutation time (user prompt + clarifications), and the ConfigHub GUI is the canonical page to point a reviewer at. This skill surfaces both and then stops so nothing else in the session accidentally re-opens the change.

## When to use

- `verify-delivery` has passed and `reconciliation-check` shows three-way agreement.
- User says "close this out" / "we're done" / "show me what changed" / "final confirmation, please".
- End of an incident-response flow where the fix has been applied and converged.

## Do not load for

- Before verification is complete. Completion would be premature and misleading.
- As a general "is it done?" answer — that's what `verify-delivery` answers. This skill is the *after* of a yes from that one.
- To substitute for `verify-delivery` / `reconciliation-check` — those are prerequisites.

## Preflight gates

1. `cub context get` returns a user.
2. For each Unit in scope:
   - `LiveRevisionNum = LastAppliedRevisionNum = HeadRevisionNum` (the change has converged).
   - `LastActionError` is empty.
   - `LEN(ApplyGates) = 0`.
   - Three-way check has been run in this session (via `reconciliation-check`) or is trivially satisfied (no controller layer).
   If any of these fail, stop and route back to the appropriate verify skill.

## The loop

### 1. Enumerate the scope

Usually the same Units that went through `cub-apply` / `verify-delivery` / `reconciliation-check`. The user typically names a release, a unit, or a space.

### 2. Surface the revision + change-desc for each Unit

```bash
cub revision list <slug> --space <s>
```

The `DESCRIPTION` column carries each Revision's `--change-desc`, which includes the verbatim user prompt and condensed clarifications from the moment the mutation happened. That's what makes the Revision history self-explaining — the audit trail reads like the intent that produced it.

For a focused view of what actually changed end-to-end:

```bash
cub unit diff <slug> --space <s> --from <pre-release-revision> --to LiveRevisionNum
```

### 3. Open the review links in the GUI

Prefer `--web` forms over hand-built URLs:

```bash
cub unit get <slug> --space <s> --web
cub revision list <slug> --space <s> --web
cub space get <s> --web
```

For each review link, tell the user what they'll see there and why it's the authoritative page (e.g., "the Unit page shows live state + revision history + who approved what").

### 4. Optionally tag the release

Only if the user explicitly asks. Tagging is a mutation (see `cub-mutate`) but it's a small, intentional, completion-time action:

```bash
cub unit tag release-v1.2.3 --space <s> --unit <slug>
```

### 5. Stop

Switch the session to read-only. Explicitly tell the user:

- What landed (summary).
- The review links to file / share.
- "No further changes in this session unless you start a new one."

If the user then asks for another change, treat it as a new session and route to `cub-mutate` / `cub-apply` with fresh preflight gates. Don't thread a new change through this skill.

## Tool boundary

Read-only. Exception: `cub unit tag` at the user's explicit request at the end (step 4). No other mutations — no `cub unit update`, no `cub function do`, no `cub unit apply`, no `kubectl`/`argocd`/`flux` actions.

## Stop conditions

- Preflight gates fail (any Unit not converged / has gates / has action error). Stop and route back to the right verify skill.
- User asks for a change mid-completion. Treat as a new session; don't layer mutation onto the completion step.
- User asks for a tag that would overwrite an existing release tag without confirmation. Ask first.

## Verify chain

The skill *is* the completion. "Verification" here is confirming the scope is stable:

1. `cub unit get <slug> --space <s>` — `LiveRevisionNum = HeadRevisionNum`, no gates, no error.
2. `cub revision list <slug> --space <s>` — most recent revision carries the expected `--change-desc`.
3. Review links open and render the expected state.

## Evidence

- `cub unit get <slug> --space <s> --web` — authoritative Unit page (data, live state, revisions, gates, approvals).
- `cub revision list <slug> --space <s> --web` — revision history with the composed `--change-desc` strings.
- `cub space get <s> --web` — Space page with attached Triggers/Filter and per-Unit summary.
- For releases the user tagged: `cub unit get <slug> --space <s> --revision Tag:release-vX.Y.Z --web`.

## References

- `references/cub-cli.md` — `--web` review-link discipline.
- `references/revisions.md` — full Revision data model, so you can explain what's in a Revision when a reviewer asks.
- `references/filters-and-queries.md` — scoping recipes for multi-Unit releases.
- Companion skills: `verify-delivery` (must pass first), `reconciliation-check` (must pass first), `cub-apply` (upstream of this completion step), `cub-mutate` (what composed the `--change-desc` recorded here).
