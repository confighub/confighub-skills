---
name: release-publish
description: 'Manage immutable OCI Release bundles for a consuming Target — cub release publish to bundle the Units in a Space assigned to a Target (optionally pinned to a tagged revision) into a point-in-time OCI artifact, and cub release withdraw to remove one by its global ID. Phrases: publish a release, cut a release of the prod target, pin a release to tag v1.2.0, bundle the units for this target, list / get a release, withdraw release <id>, unpublish / tear down the OCI bundle. NOT for env-to-env or variant promotion (promote-release), and NOT for applying a Unit''s head to its Target (cub-apply).'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub unit diff *) Bash(cub release publish *) Bash(cub release withdraw *)
---

# release-publish

Create and remove **Releases**. A Release bundles the Units in a Space that are assigned to a given Target, captured at a point in time, and serves that snapshot as an **immutable OCI bundle**. `cub release publish` creates one; `cub release withdraw` removes one. A Release's bundled content is read-only once published — to change what it serves, publish a new Release.

Before acting, confirm `cub auth status` succeeds (it calls the server's `/me` to verify the token; if it fails, ask the user to run `cub auth login`). Confirm verbs and flags with `cub release <verb> --help` before composing — never invent flags.

## When to use

- "Publish a release", "cut a release of the prod target", "bundle the Units assigned to this Target as an immutable artifact".
- "Pin the release to tag v1.2.0" / "release the revisions tagged X" — the `--revision` tagged-snapshot flow.
- "List releases", "get / show release `<id>`", "which release has digest …".
- "Withdraw release `<id>`", "unpublish / tear down that OCI bundle".

## Do not load for

- Promoting a release env-to-env, fleet-wide, or standing up variant Spaces — that is the `cub variant` / ChangeSet flow in `promote-release`. (Different sense of "release.")
- Applying or publishing a Unit's current **head** to its OCI/ConfigHub Target so Argo/Flux converges the cluster — that's the rolling, live publish in `cub-apply`. A Release here is a separate, pinned, point-in-time snapshot, not the live Target stream.
- Rolling back by moving a Unit's head — `rollback-revision`.
- Confirming Argo/Flux pulled an artifact and the cluster converged — `verify-apply`.

## What a Release is (and is not)

- It bundles **only the Units assigned to the consuming Target** in the bundled Space — the same set `cub-apply` publishes live. The Target may live in a **different Space** than the bundled Units.
- It is **immutable and point-in-time**. `cub-apply` keeps a Target's published artifact tracking each Unit's head; a Release freezes a chosen revision of each bundled Unit so you can reference it later by `ReleaseID` / `Digest`.
- By default each bundled Unit is captured at its **head Revision**. With `--revision <tag>`, each Unit is pinned to the highest-numbered Revision carrying that Tag, falling back to head for any Unit with no matching tagged Revision.
- It carries no `--change-desc`: a Release is not versioned Unit data, so the publish/withdraw verbs take no change description (like Space/Target/Filter creates). Capture intent in the Tag you publish from and in what you tell the user.

## Preflight gates

Before publishing, confirm:

1. `cub auth status` succeeds.
2. The bundled Space exists and you can read its Units: `cub unit list --space <space-slug>`.
3. The consuming Target exists and has Units assigned to it. `cub target get <target-space>/<target-slug>` resolves it; `cub unit list --space <space-slug> --where "TargetID IS NOT NULL"` confirms there are Units to bundle. **Zero assigned Units → an empty/meaningless Release; stop** and route Target binding to `target-bind`.
4. If using `--revision <tag>`: the Tag slug resolves **in the bundled Units' Space** (`<space-slug>`, not the Target's Space). Confirm the Tag exists (`cub tag get <tag> --space <space-slug>`) and that the Units you care about actually carry a Revision with it (`cub revision list <unit-slug> --space <space-slug> --tag <tag>`); any Unit with no matching tagged Revision silently falls back to head.
5. Source readiness is the caller's call — pinning to a tag captures exactly that tagged state; publishing at head captures whatever head is **now**, including unapplied edits. If head has drift you don't want frozen, tag first (see `cub-apply` / `promote-release`) and publish `--revision`.

If any gate fails, stop and tell the user what's missing.

## Tool boundary

- Mutations: `cub release publish` (create a bundle) and `cub release withdraw` (remove one) — the only two write verbs this skill owns.
- Read-only: `cub release get/list`, `cub target get`, `cub unit list`, `cub revision list`, `cub tag get`, `cub unit diff` for preflight and verification.
- Not allowed here: `cub unit apply` / live Target publish (→ `cub-apply`), `cub variant *` / ChangeSet promotion (→ `promote-release`), any `cub * delete`, mutating `kubectl`/`argocd`/`flux`. Tagging revisions to publish from is done in `cub-apply` / `promote-release`, not here.

## Publish

```bash
# Bundle each assigned Unit at its head Revision.
cub release publish <space-slug> <target-space>/<target-slug>

# Bundle each assigned Unit at the Revision tagged "v1.2.0" (tag resolved in <space-slug>).
cub release publish --revision v1.2.0 <space-slug> <target-space>/<target-slug>
```

- **Arg 1** `<space-slug>` — the Space whose Units are bundled; this becomes the Release's Space (a Space ID is also accepted).
- **Arg 2** the consuming Target as `<target-space>/<target-slug>`. A bare `<target-slug>` resolves in the selected/default Space — prefer the qualified form so a cross-Space Target isn't silently missed; a Target ID also works.
- On success the output shows the `ReleaseID`, `Digest`, `Manifest Digest`, Target, Space, and (if pinned) Tag. Record the `ReleaseID` and `Digest` — those are how the Release is referenced and withdrawn later.

## Withdraw

`cub release withdraw` is **destroy-class**: it removes the immutable bundle, and is gated the same way tearing down live resources is. Treat it like a teardown, not an undo.

```bash
# Located by global Release ID — no --space needed.
cub release withdraw 61f26b06-3c34-4363-8b9d-7d0a7c2b5f1c
```

- The Release is found by its **org-unique ID regardless of Space**, so `--space` is not required (it lives in its bundled Units' Space, which need not be your default). Confirm what you're about to remove first: `cub release get --space <space> <release-id>` (or `cub release list --space '*' --where "ReleaseID = '<id>'"`).
- **DestroyGate block:** if any Unit in the bundle has an outstanding **Destroy Gate**, withdrawal is blocked until the gate clears — that gate exists precisely to stop a teardown of live resources. Do **not** clear a prod Destroy Gate to force a withdraw without the user's explicit say-so; surface the gate and stop (`confighub-core` covers gate semantics).

## Stop conditions

- The consuming Target has **no assigned Units** in the bundled Space → nothing to bundle; route to `target-bind`.
- `--revision <tag>` resolves to no tagged Revision on the Units that matter → confirm head-fallback is intended, or tag first.
- Withdraw without the user's explicit confirmation of **which** Release (by ID/Digest) and that they accept it's destroy-class — confirm, don't guess.
- Withdraw blocked by a Destroy Gate → surface the gate; never clear a prod gate to force it.
- The user actually wants live cluster delivery, env promotion, or rollback → hand off (`cub-apply`, `promote-release`, `rollback-revision`).

## Verify chain

- **After publish:** `cub release get --space <space-slug> <release-id>` shows the new Release with its `Digest`/`Manifest Digest`, Target, Space, and Tag; `cub release list --space <space-slug>` lists it. Cross-check the Target and (if pinned) Tag match intent.
- **After withdraw:** `cub release get --space <space> <release-id>` returns not-found, and the Release no longer appears in `cub release list --space <space>` (or the org-wide `--space '*' --where "ReleaseID = '<id>'"`).

## Evidence

- `cub release get --space <space> <release-id> --web` — the Release entity (digest, Target, Space, Tag) the user can open.
- `cub release list --space <space> --web` — Releases in the Space.
- For whether a delivery tool consumed an artifact / the cluster converged, hand off to `verify-apply` — that's not what `cub release` reports.

## References

- `cub release --help`, `cub release publish --help`, `cub release withdraw --help`, `cub release get/list --help` — authoritative flags and args.
- `references/revisions.md` — Revision model and `Tag:<name>` semantics behind `--revision`.
- `references/cub-cli.md` — `--where` vs `--filter`, `--select`, `-o json/jq`, org-wide `--space '*'` search.
- Companion skills: `confighub-core` (Targets, OCI delivery, Delete/Destroy Gates), `target-bind` (assigning Units to a Target before publishing), `cub-apply` (live head publish vs this pinned snapshot), `promote-release` (env/variant promotion), `verify-apply` (delivery convergence).
- `https://docs.confighub.com/markdown/index.md`.
