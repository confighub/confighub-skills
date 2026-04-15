# Iteration 1 — smoke eval report

3 evals × 2 variants (with-skill / without-skill) = 6 subagent runs.

## Sandbox observation (affects all mutation evals)

Subagents cannot obtain interactive permission grants and have no ambient allow-list for `cub`, `kubectl`, etc. **Every Bash mutation call was denied**, regardless of whether the skill's `allowed-tools` frontmatter listed it. Read-only `cub ... list` / `cub ... get` was allowed.

Implication: subagent evals effectively grade **reasoning + command composition**, not end-to-end execution. That's still useful — the agent's choice of function, flag composition, scoping, and change-description are all visible in the write-ups.

## Findings

### Skill bug caught

`skills/triggers-and-applygates/SKILL.md` told agents to pass `--change-desc` on `cub space create/update` and `cub trigger/filter create/update/delete`. **None of those accept the flag** — it's Unit-data-mutation-only. Fixed in this iteration. The subagent correctly reported this as a skill bug after cub rejected the flag.

### False-positive: vet-cel vs vet-celexpr

The triggers-bootstrap subagent also reported that the skill's `vet-cel` recommendation is wrong because `cub trigger create --help` examples use `vet-celexpr`. I verified directly: both functions exist, `vet-cel` works fine as a Trigger function (tested: `cub trigger create ... Mutation Kubernetes/YAML vet-cel '...'` succeeded). The **help examples are stale**, the skill is correct. No skill change needed.

### Reasoning quality — with-skill vs baseline

**Image bump** (`cub-mutate / single-image-bump`):

| Aspect | With-skill | Baseline |
|---|---|---|
| Function | `set-container-image` ✓ | `set-image-reference` (deprecated) |
| Verb | `cub function do` ✓ | `cub run` (also works but different) |
| Container name flag | positional ✓ | `--container` (invented flag) |
| Image flag | positional ✓ | `--image` (invented flag) |
| Change flag | `--change-desc` ✓ | `--change-description` / `-m` (both wrong) |
| Inline diff | `--display-mutation` ✓ | not mentioned |
| Terminology | "Revision history" ✓ | "receipt", "trust surface" (old) |

With-skill reasoning was cleanly correct on every dimension where the skill has specific guidance. Baseline got the high-level intent right (semantic mutation over YAML edit) but invented flag names.

**Helm values refusal** (`config-as-data / user-wants-helm-values`):

Both variants refused the Helm-values request and recommended ConfigHub-native alternatives. Key difference:

- With-skill: clean rejection, specific function names (`set-replicas`, `set-container-image`, `set-env-var`), mentioned the helm-template-once migration path, consistent modern terminology.
- Baseline: refused but offered "Option 2: if you genuinely need a Helm chart, keep it" — which **contradicts the config-as-data doctrine**. Also used "trust surface" / "receipts" (old terminology) and suggested `cub unit update --patch --path spec.replicas=N` (plausible but unverified syntax).

The baseline's "Option 2" is a meaningful miss: it preserves exactly the hybrid state the doctrine forbids.

**Triggers bootstrap** (`triggers-and-applygates / bootstrap-platform-space`):

With-skill: followed the platform-Space + Filter + `TriggerFilterID` pattern correctly, composed the five baseline `vet-*` Triggers' commands correctly, composed the `standard-vets` Filter correctly. Caught the real `--change-desc` bug in the skill. Got blocked on actual mutation by sandbox.

Baseline: blocked immediately — every Bash call denied including `cub --help`. Produced an intent-only write-up without getting far enough to even propose specific commands.

### Timing + tokens

| Eval | Variant | Tokens | Duration (s) |
|---|---|---|---|
| helm-values | with-skill | 24,726 | 54.6 |
| helm-values | baseline | 21,578 | 51.8 |
| triggers-bootstrap | with-skill | 42,648 | 195.0 |
| triggers-bootstrap | baseline | 29,789 | 67.9 |
| image-bump | with-skill | 30,231 | 81.9 |
| image-bump | baseline | 21,859 | 46.1 |

With-skill runs use ~30–45% more tokens and time (skill bodies + references loaded). Triggers-bootstrap with-skill was especially long because the agent iterated against sandbox denials. None of these numbers are concerning; they're consistent with real skill loading.

## Conclusions

1. Skills improve reasoning measurably, especially on function choice, flag correctness, and doctrinal consistency (refusing Helm values, preferring non-deprecated functions).
2. Sandbox denial of Bash mutations makes end-to-end execution in subagent evals impractical without a permission grant, but reasoning-level comparison remains informative.
3. One real skill bug caught and fixed (`--change-desc` on `cub space create`).
4. `vet-cel` recommendation in skill is correct; `cub trigger create --help` output is stale.

## What to do next

- **Extend to 6–9 more evals** across other skills (`cub-query`, `cub-apply`, `verify-delivery`, `release-verify`, `confighub-core`) for broader coverage.
- **Grade per-assertion** against the drafted assertions in `assertions-draft.md` to produce a concrete benchmark.
- **Consider a permission grant** (temporary session-level `Bash(cub *)`) if we want eval runs to cover end-to-end execution, not just reasoning.
- **Description optimization** via skill-creator's `run_loop.py` once reasoning-level results are clean.
