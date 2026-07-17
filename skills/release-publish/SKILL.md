---
name: release-publish
description: 'Manage immutable OCI Release bundles for a Space''s release Target — cub release publish <space-slug> bundles the Units in that Space assigned to the Space''s release Target (its ReleaseTargetID, set with cub space create/update --release-target), optionally pinned to a tagged revision via --revision, into a point-in-time OCI artifact; cub release withdraw removes one by its global ID. Phrases: publish a release of this space, cut a release, pin a release to tag v1.2.0, bundle the units into an OCI artifact, list / get a release, withdraw release <id>, unpublish / tear down the OCI bundle.'
phase: act
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub unit diff *) Bash(cub release publish *) Bash(cub release withdraw *)
---

# release-publish

Create and remove **Releases**. A Release bundles the Units in a Space that are assigned to that Space's **release Target** (its `ReleaseTargetID`), captured at a point in time, and serves that snapshot as an **immutable OCI bundle**. `cub release publish <space-slug>` creates one; `cub release withdraw <release-id>` removes one. A Release's bundled content is read-only once published — to change what it serves, publish a new Release.

Before acting, confirm `cub auth status` succeeds (it calls the server's `/me` to verify the token; if it fails, ask the user to run `cub auth login`). Confirm verbs and flags with `cub release <verb> --help` before composing — never invent flags.

## When to use

- "Publish a release", "cut a release of this Space", "bundle the Units assigned to this Space's release Target as an immutable artifact".
- "Pin the release to tag v1.2.0" / "release the revisions tagged X" — the `--revision` tagged-snapshot flow.
- "List releases", "get / show release `<id>`", "which release has digest …".
- "Withdraw release `<id>`", "unpublish / tear down that OCI bundle".

## Do not load for

- Promoting a release env-to-env, fleet-wide, or standing up variant Spaces — that is the `cub variant` / ChangeSet flow in `promote-release`. (Different sense of "release.")
- Deploying a Unit to its Target — a chosen revision, or head by default — that's `cub-apply`, a per-Unit deploy through the Target. A Release here is a separate thing: an immutable, point-in-time bundle of the Space's release-Target Units, not a per-Unit deploy.
- Rolling back by moving a Unit to a new Revision based on the rollback Revision — `rollback-revision`.
- Confirming Argo/Flux pulled an artifact and the cluster converged — `verify-apply`.

## What a Release is (and is not)

- It bundles **only the Units assigned to the Space's release Target** — the same set you would deploy to that Target with `cub-apply`. That release Target may live in a **different Space** than the bundled Units.
- It is **immutable and point-in-time**: it freezes a chosen revision of each bundled Unit into one artifact you reference later by `ReleaseID` / `Digest`, independent of any later edits to those Units.
- By default each bundled Unit is captured at its **head Revision**. With `--revision <tag>`, each Unit is pinned to the highest-numbered Revision carrying that Tag, falling back to head for any Unit with no matching tagged Revision.
- It carries no `--change-desc`: a Release is not versioned Unit data, so the publish/withdraw verbs take no change description (like Space/Target/Filter creates). Capture intent in the Tag you publish from and in what you tell the user.

## Preflight gates

Before publishing, confirm:

1. `cub auth status` succeeds.
2. The bundled Space exists and you can read its Units: `cub unit list --space <space-slug>`.
3. The bundled Space has a **release Target** set (its `ReleaseTargetID`) — `publish` resolves the consuming Target from it server-side, so with none set there is nothing to publish against. `cub space get <space-slug>` shows a **Release URL** row when the release Target is an OCI provider; `cub space get <space-slug> -o json` exposes `ReleaseTargetID` directly. If unset, set it with `cub space update <space-slug> --release-target <target-space>/<target-slug>` (that's Space config, outside this skill) before publishing.
4. That release Target has Units assigned to it in the bundled Space: `cub unit list --space <space-slug> --where "TargetID = '<release-target-id>'"` (or the looser `TargetID IS NOT NULL`) confirms there are Units to bundle. **Zero assigned Units → an empty/meaningless Release; stop** and route Target binding to `target-bind`.
5. If using `--revision <tag>`: the Tag slug resolves **in the bundled Units' Space** (`<space-slug>`, not the Target's Space). Confirm the Tag exists (`cub tag get <tag> --space <space-slug>`) and that the Units you care about actually carry a Revision with it (`cub revision list <unit-slug> --space <space-slug> --tag <tag>`); any Unit with no matching tagged Revision silently falls back to head.
6. Source readiness is the caller's call — pinning to a tag captures exactly that tagged state; publishing at head captures whatever head is **now**, including unapplied edits. If head has drift you don't want frozen, tag first (see `cub-apply` / `promote-release`) and publish `--revision`.

If any gate fails, stop and tell the user what's missing.

## Tool boundary

- Mutations: `cub release publish` (create a bundle) and `cub release withdraw` (remove one) — the only two write verbs this skill owns.
- Read-only: `cub release get/list`, `cub space get` (to confirm the Space's release Target), `cub target get`, `cub unit list`, `cub revision list`, `cub tag get`, `cub unit diff` for preflight and verification.
- Not allowed here: `cub unit apply` (deploying Units → `cub-apply`), `cub variant *` / ChangeSet promotion (→ `promote-release`), setting the Space's release Target (`cub space create/update --release-target` — Space config), any `cub * delete`, mutating `kubectl`/`argocd`/`flux`. Tagging revisions to publish from is done in `cub-apply` / `promote-release`, not here.

## Publish

```bash
# Bundle each assigned Unit at its head Revision.
cub release publish <space-slug>

# Bundle each assigned Unit at the Revision tagged "v1.2.0" (tag resolved in <space-slug>).
cub release publish --revision v1.2.0 <space-slug>
```

- **Only positional arg** `<space-slug>` — the Space whose assigned Units are bundled; this is also the Release's Space (a Space ID is also accepted). The consuming Target is **not** passed here: `publish` resolves it from the Space's `ReleaseTargetID` server-side, so the Space must already have a release Target set. To change which Target a Space releases to, set `cub space update <space-slug> --release-target …` before publishing — you cannot override it on the publish command.
- `--revision <tag>` — optional; pins each bundled Unit to the highest-numbered Revision carrying that Tag (Tag resolved in `<space-slug>`), falling back to head for any Unit without a matching tagged Revision.
- On success the output shows the `ID` (the ReleaseID), `Digest`, `Manifest Digest`, `Organization ID`, `Created At`, and `Space` (plus a `Tag` row when you published with `--revision`). Record the `ReleaseID` and `Digest` — those are how the Release is referenced and withdrawn later. The consuming Target is **not** echoed on the Release; it lives on the Space as `ReleaseTargetID`.

## Withdraw

`cub release withdraw` is **destroy-class**: it removes the immutable bundle, and is gated the same way tearing down live resources is. Treat it like a teardown, not an undo.

```bash
# Located by global Release ID — no --space needed.
cub release withdraw 61f26b06-3c34-4363-8b9d-7d0a7c2b5f1c
```

- The Release is found by its **org-unique ID regardless of Space**, so `--space` is not required (it lives in its bundled Units' Space, which need not be your default). Confirm what you're about to remove first: `cub release get --space <space> <release-id>` (or `cub release list --space '*' --where "ReleaseID = '<id>'"`).
- **DestroyGate block:** if any Unit in the bundle has an outstanding **Destroy Gate**, withdrawal is blocked until the gate clears — that gate exists precisely to stop a teardown of live resources. Do **not** clear a prod Destroy Gate to force a withdraw without the user's explicit say-so; surface the gate and stop (`confighub-core` covers gate semantics).

## Stop conditions

- The bundled Space has **no release Target** set (`ReleaseTargetID` unset) → `publish` has no Target to resolve; set it with `cub space update --release-target` (Space config) first, don't guess one.
- The Space's release Target has **no assigned Units** in the bundled Space → nothing to bundle; route to `target-bind`.
- `--revision <tag>` resolves to no tagged Revision on the Units that matter → confirm head-fallback is intended, or tag first.
- Withdraw without the user's explicit confirmation of **which** Release (by ID/Digest) and that they accept it's destroy-class — confirm, don't guess.
- Withdraw blocked by a Destroy Gate → surface the gate; never clear a prod gate to force it.
- The user actually wants to deploy/apply Units to their Target, env promotion, or rollback → hand off (`cub-apply`, `promote-release`, `rollback-revision`).

## Verify chain

- **After publish:** `cub release get --space <space-slug> <release-id>` shows the new Release with its `Digest` / `Manifest Digest` and `Space` (plus a `Tag` row when you published with `--revision`), and `cub release list --space <space-slug>` lists it. The consuming Target isn't recorded on the Release — to confirm which Target the Space released to, use `cub space get <space-slug>`.
- **After withdraw:** `cub release get --space <space> <release-id>` returns not-found, and the Release no longer appears in `cub release list --space <space>` (or the org-wide `--space '*' --where "ReleaseID = '<id>'"`).

## Evidence

- `cub release get --space <space> <release-id> --web` — the Release entity (digest, Space, Tag) the user can open.
- `cub release list --space <space> --web` — Releases in the Space.
- For whether a delivery tool consumed an artifact / the cluster converged, hand off to `verify-apply` — that's not what `cub release` reports.

## References

- `cub release --help`, `cub release publish --help`, `cub release withdraw --help`, `cub release get/list --help` — authoritative flags and args.
- `cub space create --help`, `cub space update --help` — the `--release-target` flag that sets the Space's `ReleaseTargetID` (what `publish` resolves the consuming Target from).
- `references/revisions.md` — Revision model and `Tag:<name>` semantics behind `--revision`.
- `references/cub-cli.md` — `--where` vs `--filter`, `--select`, `-o json/jq`, org-wide `--space '*'` search.
- Companion skills: `confighub-core` (Targets, OCI delivery, Delete/Destroy Gates), `target-bind` (assigning Units to a Target before publishing), `cub-apply` (deploying Units to a Target vs this immutable bundle), `promote-release` (env/variant promotion), `verify-apply` (delivery convergence).
- `https://docs.confighub.com/markdown/index.md`.
