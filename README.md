# confighub-skills

A Claude Code plugin that helps an agent work with [ConfigHub](https://docs.confighub.com/) and its CLI, `cub`.

ConfigHub changes quickly, so the plugin doesn't try to carry ConfigHub's behavior. Its one skill, `confighub-lookup`, tells the agent where to look up how the installed release behaves:

- `cub`'s agent overview, `CONFIGHUB_AGENT=1 cub --help-overview`, and the help of each command it is about to run;
- `cub <entity> explain` for entity fields, and `cub function explain` for functions;
- the ConfigHub docs as raw markdown, starting at `https://docs.confighub.com/markdown/index.md`.

It also gives the rules for changing configuration safely, which don't change between releases. Examples: preview with `--dry-run`, run one literal command per change, and never bypass a safeguard.

The skill's commands and docs paths were last checked against ConfigHub **v0.8.29**.

## Install or update

`cub` must be on `PATH`, and `cub auth status` must succeed. `kubectl`, `argocd` and `flux` are optional, for reading what is running. Helm onboarding needs the `cub-helm` plugin: `cub plugin install confighub/cub-helm`.

Install from the ConfigHub marketplace with these two commands:

```bash
claude plugin marketplace add https://github.com/confighub/confighub-skills
```

```bash
claude plugin install confighub-skills@confighub
```

Update an existing installation with these two commands, then restart Claude Code:

```bash
claude plugin marketplace update confighub
```

```bash
claude plugin update confighub-skills@confighub
```

## How commands run

The skill grants no tool permissions (`allowed-tools: []`). The host's permission settings decide whether each command runs. The skill asks the agent to:

- submit each change as one command with literal arguments;
- say what the command will change first;
- read back what it did afterwards.

## Repository layout

```text
.claude-plugin/   plugin and marketplace manifests
hooks/            a reminder to load the skill for ConfigHub work
skills/           the confighub-lookup skill
tools/            validation
```

## Validate

```bash
./tools/validate
```

It checks that:

- each skill's frontmatter names its directory and grants no tools;
- each `bash` block holds one command;
- the manifests and the hook's output are valid JSON.

When `cub` is on `PATH`, or `CUB` names it, it also checks that each `cub` command the skill shows exists and takes the flags it is shown with. Run it with the newest `cub` release after each ConfigHub release, and update the version above.

## Earlier skills

Up to version 0.4.5, this repository held fifteen task-specific skills (`confighub-core`, `cub-query`, `cub-mutate`, `release-publish`, `promote-release` and others), plus a compatibility apparatus that pinned them to one `cub` release. Version 0.5.0 replaced them with `confighub-lookup`. The knowledge they carried that is still true is now in `cub`'s help and the ConfigHub docs. Git history keeps them.
