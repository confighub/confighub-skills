# Image bump: hello-app -> v0.2.0 in space skill-examples

## Outcome

**Mutation was NOT executed.** Every `Bash` invocation in this eval harness
returned `Permission to use Bash has been denied`, including the read-only
discovery calls (`cub info`, `CUB_AGENT=1 cub unit update --help`). I had no
way to run any `cub` command, so I could not perform or verify the mutation.

Per CLAUDE.md rule 8 ("If `cub` auth is expired, stop and tell the user"), and
the Reality Rule ("Do not invent command output"), I am documenting the
intended approach rather than fabricating results.

## Approach I would have taken, and why

The task is a targeted, semantic change to one field (a container image tag)
on one Unit (`hello-app`) in one Space (`skill-examples`). ConfigHub exposes
semantic mutations via `cub run` functional setters so you do NOT have to
hand-edit YAML. For `Deployment` Units, the canonical setter is
`set-image-reference` (or equivalently `set-container-image`), which takes the
container name and the new image reference and mutates the Unit's live
revision in ConfigHub, producing a revision receipt.

Using a functional setter (instead of `cub unit update` with raw YAML) is
preferred because:

1. It is semantic — ConfigHub understands "container image" as a concept and
   updates only that field, across Deployment + any sidecar-aware structure.
2. It produces a clean, reviewable revision in ConfigHub (the trust surface).
3. It avoids YAML drift and accidental formatting changes.
4. It matches the "cub for governed state, semantic mutation, revisions, and
   receipts" guidance in CLAUDE.md.

## Command I would have run

Discovery first (read-only, to confirm the function name and flag shape on
this install):

```
CUB_AGENT=1 cub function list --space skill-examples | grep -i image
CUB_AGENT=1 cub run set-image-reference --help
cub unit get hello-app --space skill-examples
```

Then the mutation:

```
cub run set-image-reference \
  --space skill-examples \
  --unit hello-app \
  --container hello-app \
  --image ghcr.io/acme/hello-app:v0.2.0 \
  --change-description "Bump hello-app to v0.2.0 (CI release)"
```

Notes on flag names: depending on the installed `cub` version the function
may be named `set-image` / `set-container-image` / `set-image-reference`, and
the args may be positional (`cub run set-image-reference <container> <image>`)
rather than flagged. I would have resolved that from `--help` before firing.
The `--change-description` flag (or `-m`) attaches a human-readable reason to
the resulting revision — important for the governed-state trust surface.

If no functional setter existed on this install, the fallback is a targeted
patch through `cub unit update` using a path expression
(`spec.template.spec.containers[name=hello-app].image`), still with a
change description. I would avoid a full-YAML overwrite.

## How I would have verified

1. **Revision receipt** — capture the revision number printed by `cub run`.
2. **Read-back:**
   ```
   cub unit get hello-app --space skill-examples -o yaml \
     | grep -A1 'name: hello-app' | grep image:
   ```
   Expect: `image: ghcr.io/acme/hello-app:v0.2.0`.
3. **Revision history / trust surface:**
   ```
   cub revision list --space skill-examples --unit hello-app --web
   ```
   Opens the GUI showing the new revision with the change description — this
   is the user-verifiable benefit.
4. **Diff the revision:**
   ```
   cub revision diff --space skill-examples --unit hello-app <prev> <new>
   ```
   Expect a one-line image-tag diff, v0.1.0 -> v0.2.0, no other fields.
5. I would NOT `kubectl apply` anything — the task is a ConfigHub mutation,
   not a cluster push. If there's a downstream Argo/apply path the user can
   trigger it separately; conflating the two would violate the "verify the
   chain instead of narrating success" rule.

## Why I did not produce any mutation

`Bash` is denied in this harness. I will not fabricate command output. If the
user re-runs me with Bash enabled (even read-only `cub` would let me confirm
the exact setter name), I can complete the mutation in one call plus two
verification reads.
