---
name: confighub-core
description: 'Orientation skill — load when the user is new to ConfigHub, asks "what is a Unit / Space / Target / Worker / Trigger / Filter / Link", needs to understand how entities relate, wants a quick tour before diving into specific operations, or asks "how do I do X in ConfigHub" without enough context to route yet. Also covers Delete Gates and Destroy Gates — phrases like "protect this Space from accidental deletion", "stop anyone from destroying the prod Unit", "add a delete gate", "why can''t I delete this?", "how do I lock down critical infra?". Explains the core vocabulary, the Read vs Write tool boundary, the change-description + -o mutations conventions, gate semantics, and routes to the right dedicated skill for each kind of task. Do not load when the user''s intent is already concrete enough to route (e.g., "add a trigger that blocks :latest" → triggers-and-applygates; "bump the image" → cub-mutate; "find Deployments using v1.2.3" → cub-query).'
phase: cross-cutting
allowed-tools: Bash(cub --help) Bash(cub * --help) Bash(CONFIGHUB_AGENT=1 cub --help) Bash(CONFIGHUB_AGENT=1 cub * --help) Bash(cub * get) Bash(cub * get *) Bash(cub * list) Bash(cub * list *) Bash(cub * list-* *) Bash(cub function explain *) Bash(CONFIGHUB_AGENT=1 cub function explain *) Bash(cub unit diff *) Bash(cub unit tree *) Bash(cub unit bridgestate *) Bash(cub unit livedata *) Bash(cub unit livestate *) Bash(cub worker logs *) Bash(cub worker status *)
---

# confighub-core

Orientation. Explains ConfigHub's model in plain language and routes to the right skill for the task at hand.

## When to use

- User is new to ConfigHub and asks for a tour.
- User asks "what's a Unit?" / "what's a Space?" / "how does ConfigHub handle X?"
- User's intent isn't specific enough yet to route to a task skill (e.g. "help me with ConfigHub").
- User wants to understand how two concepts relate (Targets vs. Workers, Triggers vs. Filters, upstream vs. downstream).

## Do not load for

- Concrete tasks that already have a dedicated skill — route instead. See "Routing" below.
- Deep product support questions that belong in docs, not a skill.

## The model in one minute

ConfigHub treats configuration as **data**: fully materialized YAML stored in a versioned database, not code or templates. Mutations go through server-side **functions** on that data. Everything else — delivery, policy, audit — hangs off that model.

### Primary entities

- **Space** — organizational container for Units. Best practice: one Space per application × environment/region. Labels let you slice across them.
- **Unit** — a versioned, atomic chunk of configuration. For Kubernetes workloads, a Unit holds one or more fully materialized K8s resources as YAML. Applied as a single operation.
- **Revision** — every mutation to a Unit produces a new Revision. Each carries a `--change-desc` (the composed user prompt + clarifications) and the mutated data diff.
- **Function** — server-side operation over configuration data. Categories: getters (`get-container-image`), setters (`set-container-image`, `set-replicas`), defaults (`set-container-resources-defaults`), validators (`vet-schemas`, `vet-cel`), helpers (`compute-mutations`, `yq`, `yq-i`).
- **Trigger** — a function (usually a validator) wired to fire automatically on `Mutation` or `PostClone` events. Failing validators attach an **ApplyGate**, which blocks apply until fixed.
- **Filter** — a saved query entity. Filters over Units power bulk ops (`cub unit apply --filter …`). Filters over Triggers are what attach to a Space via `TriggerFilterID`.
- **Link** — a relationship between Units whose resources reference each other (e.g., a Deployment's `serviceAccountName` → a SA Unit). Links enable cross-Unit integrity checks and needs/provides binding.
- **Target** — a deployable binding. Points at a place where a Unit's config lands (a Kubernetes cluster+namespace, an Argo Application, a Flux Kustomization, an OCI registry, etc.). Has parameters (e.g., `KubeContext`, `KubeNamespace`) and optionally a Worker.
- **Worker** — a running process (bridge worker) that executes target operations — apply, refresh, import — against the real world. Workers register provider types (`Kubernetes`, `ArgoCDRenderer`, `FluxRenderer`, `ArgoCDOCI`, `OpenTofu/AWS`, …). Typically deployed in-cluster.
- **ApplyGate** — a block on apply attached by a failing Trigger or by an approval requirement. Always fix the data or the rule; never bypass the gate.

### Operational invariants

- **Data is authoritative.** Edits are to the data, not to templates. Re-rendering is an import-time convenience, not an ongoing workflow.
- **Mutations go through `cub`.** `kubectl` / `argocd` / `flux` are read-only for diagnosis.
- **Every Unit-data mutation carries `--change-desc`.** Format: summary line, then the verbatim user prompt, then a condensed summary of any clarifying Q&A. Recorded in every affected Unit's head revision.
- **Every mutating call should pass `-o mutations`** to show the diff inline.
- **Space topology** is one Space per app × environment/region, labeled accordingly. Triggers live in a shared `platform` Space; application Spaces inherit via `TriggerFilterID`.
- **Critical entities carry Delete Gates (and, for Units, Destroy Gates).** See the next section.

## Delete Gates and Destroy Gates — preventing accidents

ConfigHub makes bulk and cross-Space operations easy, which is also how you accidentally delete a prod Space or destroy live cluster resources. Gates are the opt-in protection.

Canonical doc: `https://docs.confighub.com/guide/protecting/`.

Two kinds:

- **Delete Gates** — attach to _any_ entity (Unit, Space, Target, Worker, Trigger, Filter, ChangeSet, etc.). Block `cub <entity> delete` until every gate is removed.
- **Destroy Gates** — **Units only**. Block `cub unit destroy`, which removes the live cluster resources owned by the Unit. Orthogonal to Delete Gates: you can have one without the other.

Each gate is named. The name must match label-key rules (alphanumeric + `-`, `_`, `.`) and is where the _why_ lives — use descriptive names, not `critical` everywhere. Multiple gates can stack on the same entity; all must be removed before the delete / destroy is allowed.

### Adding gates

```bash
# Unit — both gates. Protect prod data; protect its live resources.
cub unit update --patch --space <app>-prod <unit> \
  --delete-gate prod-critical \
  --destroy-gate prod-critical

# Space — delete gate only (Spaces have no destroy).
cub space update --patch <space> \
  --delete-gate used-until-dec25

# Target, Worker, Trigger, Filter — same pattern via the entity's update command.
cub target update --patch --space <s> <target> --delete-gate in-use
cub worker update --patch --space <s> <worker> --delete-gate active
cub trigger update --patch --space platform <trigger> --delete-gate required
cub filter update --patch --space platform <filter> --delete-gate required
```

Gates can also be set at create time — `cub <entity> create --delete-gate <name> ...` — so a new prod Space can be born protected.

### Removing gates

Use `<name>=-` (the `-` sentinel — empty string won't clear):

```bash
cub space update --patch <space> --delete-gate used-until-dec25=-
cub space delete --recursive <space>
```

If multiple gates are stacked, each must be removed individually before the delete / destroy can proceed.

### Naming

The gate name carries the purpose. Prefer specific over generic:

- Time-bounded: `used-until-dec25`, `keep-through-release-452`, `kubecon25-demo`.
- Ownership: `team-payments-owns`, `platform-managed`, `shared-infra-core`.
- Reason: `prod-critical`, `regulated-data`, `in-use-by-argocd`, `required-policy`.

Avoid `critical` as a catch-all — when three entities all carry `critical`, nobody remembers which is which. A future teammate reading the gate name should understand _why_ it's there without asking.

### When to recommend a gate

Any time the user creates or touches an entity that would be painful to re-create:

- Production Spaces and their Units (delete + destroy on the Units).
- Shared-infra Spaces (cert-manager, ingress, observability).
- Platform-Space Triggers and Filters (org-wide policy).
- Workers whose replacement is non-trivial.
- Short-lived demo / event Spaces (time-bounded gates like `used-until-dec25`).

For new prod-bound Units or Spaces, suggest the gate in the same turn you create them — the reminder-after-incident is always too late.

## Routing — pick the right skill for the task

| User intent                                                                                                  | Skill                      |
| ------------------------------------------------------------------------------------------------------------ | -------------------------- |
| Authoring new Kubernetes YAML for a Unit, questions about templates/values files/Helm/Kustomize for new work | `config-as-data`           |
| Setting up validation/policy that actually blocks bad config                                                 | `triggers-and-applygates`  |
| Changing data in an existing Unit (image, replicas, env var, defaults, etc.)                                 | `cub-mutate`               |
| Finding, listing, auditing, or inspecting config across Units/Spaces                                         | `cub-query`                |
| Bootstrapping a playground Space to tinker with                                                              | `skill-examples-bootstrap` |
| Installing a bridge worker in a cluster                                                                      | `worker-bootstrap`         |
| Creating a Target or binding a Unit to one                                                                   | `target-bind`              |
| Applying a Unit to its target                                                                                | `cub-apply`                |
| Post-apply verification, troubleshooting, three-way agreement, release close-out                            | `verify-apply`             |

## The loop (for the orientation use case)

1. Ask what the user is trying to do and listen for the vocabulary they use. Match to an entity or intent above.
2. Give a one- or two-sentence explanation of the relevant concept(s), **in their vocabulary first**, then ConfigHub's.
3. Route to the skill that covers their intent. Don't try to do the task here.
4. If they're new, offer `skill-examples-bootstrap` to create a playground Space so they have something concrete to poke at while learning.

## Tool boundary

Read-only. This skill explains and routes; it never mutates. If the conversation turns to doing a task, hand off to the dedicated skill — don't mutate from here.

## Stop conditions

- User's intent is concrete enough to route — hand off and exit.
- User wants product-level depth that belongs in docs (`https://docs.confighub.com/`) rather than a skill.

## Verify chain

N/A — read-only. Verification is "did the user's task get routed to the right skill".

## Evidence

- ConfigHub docs: `https://docs.confighub.com/`
- Public SDK: `https://github.com/confighub/sdk`
- `cub unit get --web`, `cub space get --web`, `cub revision list --web` — open entity pages in the GUI when the user wants to see something concrete.

## References

- `references/cub-cli.md` — CLI conventions, Read/Write permission sets, agent-mode help, `--change-desc`, `-o mutations`.
- `references/functions-catalog.md` — the function surface.
- `references/filters-and-queries.md` — query vocabulary.
- `references/triggers-recipes.md` — platform-Space pattern.
- `references/yaml-patterns.md` — literal-value authoring.
- https://docs.confighub.com/guide/protecting/
