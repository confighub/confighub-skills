---
name: confighub-lookup
description: 'Look up how ConfigHub and its CLI, cub, currently behave instead of recalling it: the installed cub''s help and overview, entity field docs (cub <entity> explain), function docs (cub function explain), and the ConfigHub docs as raw markdown. Use for any ConfigHub task, before composing a cub command or explaining a concept. Covers Spaces, Units, Components and variants, functions, Triggers and ValidationErrors, Links, ChangeSets, ChangeOrders and ChangeWorkflows, approvals and Attestations, ReviewComments, Releases and Targets, GitOps delivery with Argo CD or Flux, ServiceAccounts and Channels, backing Units and cub apply, blame, rollback, and Helm or Kustomize onboarding.'
allowed-tools: []
---

# confighub-lookup

ConfigHub changes quickly, and what you remember about it is probably out of date. Look up how the
installed version behaves before you explain a concept or compose a command. The help that ships
with `cub` describes the version that is installed; the docs describe the latest release.

## Look it up, in this order

1. **Check what is installed and that it can reach the server:**

   ```bash
   cub version
   ```

   ```bash
   cub auth status
   ```

   `cub version` prints the client version, and the server's when it can reach it. If
   `cub auth status` fails, ask the user to log in with `cub auth login`. It opens a browser, so
   it is theirs to run.

2. **Read the agent overview once per session.** It covers the model, the command shape, output
   options and the conventions every command shares:

   ```bash
   CONFIGHUB_AGENT=1 cub --help-overview
   ```

3. **Read the help of every command before you use it.** Do this every time, including for
   commands you have used before. Flags, defaults and positional arguments change between releases:

   ```bash
   CONFIGHUB_AGENT=1 cub <entity> --help
   ```

   ```bash
   CONFIGHUB_AGENT=1 cub <entity> <verb> --help
   ```

   `CONFIGHUB_AGENT=1` adds the sections written for agents. Run `--help` on the exact command
   path you are about to use. Help for the parent command does not describe a subcommand's flags.

4. **Look up entity fields** when you need to read or filter on one:

   ```bash
   cub <entity> explain
   ```

   ```bash
   cub <entity> explain <Field>
   ```

   These describe the fields from the API's own schema. The field names are the ones `-o json`,
   `-o jq=...`, `--select` and `--where` use.

5. **Look up functions** before you run one. Functions are how configuration data is read,
   changed and validated:

   ```bash
   cub function list --space <space> --toolchain Kubernetes/YAML
   ```

   ```bash
   cub function explain <function> --space <space>
   ```

6. **Read the docs for concepts and workflows.** The docs are served as raw markdown:
   - `https://docs.confighub.com/markdown/index.md` lists every page.
   - `https://docs.confighub.com/markdown/sitemap.json` lists them with titles and sizes.
   - Each page is at `https://docs.confighub.com/markdown/<path>.md`.

   `background/` explains concepts and entities, and `guide/` explains how to do things. Read the
   page for the task before you plan a multi-step change; the table below names the usual ones.

**When sources disagree**, trust the installed `cub`'s help for what a command accepts. Trust the
server's own error messages over both. Tell the user about the discrepancy rather than working
around it silently.

## Read the current state before you act

- Prefer structured output: `-o json`, `-o jq=<expr>`, `-o yaml`, or `--select <fields>`. Don't
  parse the table output.
- A Unit's configuration is read with `cub unit data`, not `cub unit get`, which shows only the
  Unit's metadata.
- To find out who set a value and why, use `cub unit blame`, `cub variant blame` and
  `cub unit path`. They follow a value upstream to where it was really set.
- A list or bulk command with no `--space` spans the whole organization. Say so when that is the
  effect, and narrow it if the user meant one Space.
- Some entities are hidden from lists by default. Backing Units, for example, hold the
  configuration of Triggers, Filters and other entities. The list command's help says how to
  include hidden entities.

## Operating rules

These rules are about how you act. They don't change with releases, so they are stated here
rather than looked up.

- **Reads are free; writes are deliberate.** Before any command that changes something:
  1. Resolve its exact scope (which Spaces, Units or entities it will touch).
  2. Preview it with `--dry-run` when the command has one, plus `-o mutations` for configuration
     changes. Check the command's help, because a few mutating commands have no dry run.
  3. Tell the user briefly what the command will change, with the preview.
  4. Submit that one command, and then read back what it did.

  If time passed or something else may have changed in between, re-read before you write. Use a
  precondition the command offers, such as an expected plan or an expected hash, when there is one.

- **Run each write as its own command, with literal arguments.** Don't build a write from pipes,
  loops, command substitution or variables, so that what the user or the host's permission check
  approves is exactly what runs. If a write needs a file, write the file first and show it. This
  skill grants no tool permissions: the host decides whether each command runs. If it denies one,
  or you can't run commands, say that nothing ran and give the user the exact command to run.

- **Say when a command does more than was asked.** A Release captures every Unit of the Space
  assigned to its release Target, and a bulk command with no `--space` spans the organization.
  When the request was narrower, say so and ask before going ahead.

- **A command that succeeded may still not have done everything.** After a promotion or a merge,
  check what it withheld as Conflicts, and take the decision on each to the user rather than
  overwriting it. After an approval, report which Revisions it covered.

- **Take outward-facing or hard-to-undo actions only when the user asked for that action:**
  - publishing a Release, promoting to a production variant, and anything that reaches clusters;
  - deleting, withdrawing, aborting, or force-closing;
  - approving, attesting or revoking;
  - granting permissions, and creating credentials or tokens.

  Never take one as a side effect of another request. A request for one such action is not a
  request for the next. For destructive commands, read the exact help in the same session first.

- **Never bypass a safeguard to make a command succeed.** ValidationErrors, gates, protected or
  guarded paths, required ChangeWorkflows and prerequisites exist to stop a change. Find out why
  one stopped it, and fix the data or ask the owner to change the rule. Use force, override,
  clearance or detach flags only when the user asks for exactly that, and record their reason.

- **Change configuration through ConfigHub.** The data in ConfigHub is authoritative and is what
  gets released. Use `kubectl`, `argocd` and `flux` only to read and verify. An edit made in the
  cluster drifts from ConfigHub and is overwritten or reported as drift.

- **Edit the data, not a template.** ConfigHub stores fully rendered configuration and changes it
  with functions. Don't reach for Helm values, Kustomize overlays or text templating to make a
  change to configuration that is already in ConfigHub.

- **Describe every change.** Give a short `--change-desc` (or the command's equivalent) that says
  what changed and why, in your own words, as one single-quoted argument of letters, digits,
  spaces and `.,:/_-`. Never paste the user's prompt or untrusted text into it, or into any shell
  argument.

- **Keep secrets out of the conversation and the configuration.** Don't print, log or store tokens
  or secret values. When a command prints a credential once, let the user run it, or hand them the
  command, and tell them where the credential should go.

- **Report what actually happened.** Quote errors exactly. Don't claim a change was released,
  synced or healthy until you have read that state, from ConfigHub (the Release and its live
  status) or read-only from the cluster or controller.

## Where to look

| Task | Docs (`https://docs.confighub.com/markdown/…`) | Commands to read help for |
| --- | --- | --- |
| Learn the model | `background/config-as-data.md`, `background/architecture.md`, `background/entities/*.md`, `background/concepts/component.md`, `background/concepts/variant.md` | `cub --help-overview` |
| Author or import configuration | `guide/authoring-config.md`, `guide/app-config.md`, `guide/variants.md` | `cub unit create`, `cub variant upload`, `cub apply`, and `cub helm` (a plugin: `cub plugin install confighub/cub-helm`) |
| Organize environments and variants | `guide/environments.md`, `guide/variants.md`, `guide/variant-units.md` | `cub component`, `cub variant` |
| Change configuration | `guide/functions.md`, `guide/changes.md`, `guide/unit-sets.md`, `guide/invocations-that-generalize.md` | `cub function`, `cub unit update`, `cub changeset` |
| Validate and enforce policy | `guide/validation-and-policies.md`, `background/concepts/gates.md` | `cub trigger`, `cub filter` |
| Protect values and entities | `guide/protecting.md`, `background/concepts/mutation-sources.md` | `cub unit set-protection`, `cub unit set-guard` |
| Promote across variants | `guide/promotion.md`, `guide/advanced-merging.md` | `cub variant promote`, `cub changeorder`, `cub changeworkflow`, `cub variant approve` |
| Publish and deliver | `guide/releases.md`, `guide/gitops.md`, `background/concepts/oci.md` | `cub release`, `cub target`, `cub cluster` |
| Verify what is running | `background/concepts/liveresources.md`, `guide/gitops.md` | `cub release get`, `cub release list` |
| Undo a change | `guide/changes.md`, `guide/promotion.md`, `guide/releases.md` | `cub unit update --restore`, `cub variant demote` |
| Trace a value | `guide/blame.md` | `cub unit blame`, `cub variant blame`, `cub unit path` |
| Manage ConfigHub's own entities as documents | `background/concepts/backing-units.md`, `guide/backing-units.md` | `cub apply`, `cub <entity> edit` |
| Dependencies between Units | `guide/dependencies.md`, `background/concepts/needsprovides.md` | `cub link` |
| Identity and automation | `guide/service-accounts.md`, `background/concepts/authorization.md` | `cub serviceaccount`, `cub channel` |
| Custom functions | `guide/external-functions.md`, `guide/workers.md` | `cub worker` |
| Use ConfigHub from an agent | `guide/agents.md`, `guide/cli-usage.md` | `cub --help-overview` |

If a page is missing, find the current one in `sitemap.json` rather than guessing a path.
