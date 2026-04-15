# Triggers Bootstrap — Without-Skill Baseline

## What I was asked to do

Set up enforcement so that no one can apply Kubernetes config to ConfigHub
that (a) fails schema validation or (b) still contains placeholders, and
make it "just work" for every newly created Space.

## What I actually did

**Nothing on the live ConfigHub instance.** Every `Bash` call I attempted
was rejected by the harness with `Permission to use Bash has been denied`,
including the initial `CONFIGHUB_AGENT=1 cub --help` discovery call and
even `mkdir` for the output directory. Without shell access I cannot:

- enumerate the real `cub` verb surface for this build,
- create Spaces, Filters, Functions, or Triggers,
- verify current cluster/ConfigHub auth state,
- demonstrate that a failing unit is actually rejected.

I did not guess flag names or fabricate output. Per the repo's Reality
Rule, I am labeling this run **unverified** and describing the plan I
would have executed.

## Final state

- Live ConfigHub state: **unchanged**. No Spaces, Triggers, Filters, or
  Functions were created by this agent.
- Scratch Spaces used: **none**.
- Output artifacts: this `write_up.md` and a `commands.log` noting that
  no commands ran.

## Would the enforcement actually catch failures on a new Space?

**No — because nothing was installed.** A future Space created right now
would have no triggers attached and would accept invalid / placeholder
YAML the same as before.

## The plan I would have run (had Bash been available)

ConfigHub enforces policy via **Triggers** that fire on lifecycle events
(`PreCreate` / `PreUpdate` / `PreApply`) and call a **Function** against
the unit's rendered data. A failing function return blocks the write.

Shape of the bootstrap (names to be confirmed against `cub trigger --help`
and `cub function list`):

1. **Discover the real surface first**
   - `CONFIGHUB_AGENT=1 cub --help`
   - `CONFIGHUB_AGENT=1 cub trigger --help`
   - `CONFIGHUB_AGENT=1 cub function list --space '*'` to find the
     built-in Kubernetes validators (typically something like
     `validate-yaml`, `yq`-based schema checks, `cel` validators, and a
     "no unresolved placeholders" / template-rendering check).
   - `CONFIGHUB_AGENT=1 cub trigger list` to see what already exists.

2. **Create two Triggers per enforcement concern, scoped broadly**

   a. **Schema validation trigger**
      - Event: `PreApply` (and ideally `PreUpdate` to catch bad revisions
        before they're even saved as applyable).
      - Function: the built-in Kubernetes schema validator (e.g.
        `cub function` for `validate-kubernetes` / `vet-yaml` —
        exact name TBD from `cub function list`).
      - Enforcement: blocking (fail closed).
      - Scope: all Spaces (no filter) OR a wildcard-matching filter so
        it auto-attaches to new Spaces.

   b. **Placeholder / unresolved-template trigger**
      - Event: `PreApply` + `PreUpdate`.
      - Function: a CEL or regex-based validator that rejects unit data
        matching `{{ ... }}`, `${...}`, `<PLACEHOLDER>`, or the project's
        agreed placeholder sentinel. If no such builtin exists, I'd
        create one with `cub function create` using a CEL expression like
        `!data.matches("\\{\\{.*\\}\\}|<[A-Z_]+>")`.
      - Enforcement: blocking.

3. **Make it "just work" for every new Space**

   ConfigHub Triggers can be defined at an organization / cross-space
   scope, OR they can be attached via a **Filter** that matches `Space.*`.
   The right mechanism depends on this build:

   - If `cub trigger create` supports `--space '*'` or an org-level
     scope, use that directly.
   - Otherwise, create a Filter that matches all Spaces and attach both
     triggers to it. New Spaces auto-inherit.
   - As a third fallback, add a small `cub space create` wrapper or
     post-create hook that applies the two triggers to any freshly
     created Space — but this is the least desirable option because it
     bypasses ConfigHub's own governance surface.

4. **Prove it works (the UVB step)**

   - Create a scratch Space `trigger-bootstrap-verify-<ts>`.
   - Attempt to create a unit with bad YAML (`image: :::`) —
     expect `PreUpdate` reject.
   - Attempt to create a unit with `image: {{ .Values.image }}` —
     expect placeholder reject.
   - Create a valid unit — expect pass.
   - Capture each rejection's receipt/message to show the user.
   - Leave the scratch Space in place (per Non-Negotiable #10 — don't
     delete what the eval will want to inspect), or note its slug in
     this write-up.

5. **Document the residue**

   - Append to `reports/STATUS.md`: Tried / Succeeded / Failed / Next.
   - Surface the two trigger IDs and the filter ID as the trust proof.

## What I'd ask the user before proceeding next time

- Confirmation that `cub auth` is fresh (per Non-Negotiable #8).
- Which Kubernetes schema validator this org prefers as canonical —
  the built-in one, or a CEL-based contract, or `confighub-scan`.
- The exact placeholder grammar they want rejected (`{{...}}` only, or
  also `<TODO>` / `FIXME` / `CHANGEME`).

## One-line status

No live changes made; Bash was denied for the entire run, so the
enforcement is **not** in place and a new Space today would **not** be
protected.
