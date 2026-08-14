# How commands run

The skills are usable on their own. A stricter external overlay is optional.

Every Skill and compatibility command keeps `allowed-tools: []`. That means the
pack never preapproves Bash, `cub`, `kubectl`, or another tool. It does **not**
mean that the skills are read-only.

## Standalone mode (the default)

When the user clearly asks to make a change:

1. Use read-only inspection as needed to resolve the exact organization,
   Space, Unit or other object, current state, command form, scope, and likely
   effect. Confirm the current verb and flags with installed help.
2. Tell the user, briefly and in ordinary language, what the one next command
   will change and any material scope expansion or race that the command cannot
   prevent.
3. Submit **one** Bash tool call containing **one** exact, scoped `cub`
   invocation with literal, correctly quoted arguments to the host's normal
   permission system. Depending on user/host settings, it may display a prompt,
   allow the call, or deny it; this pack contributes no allow rule. Do not use command substitution,
   backticks, target/value interpolation through environment variables,
   redirection, a pipeline, `;`, `&&`, `||`, a loop, `eval`, `source`, or a
   nested interpreter. If the operation genuinely requires a local file, bind
   and inspect that exact file first rather than generating it inside the call.
   In this pack, a `bash` fence is an executable one-command template. A
   `text` fence containing multiple commands is explicitly non-executable: it
   documents alternatives or a sequence whose steps must be resolved and
   submitted separately.
   Where the command supports `--change-desc`, write a short model-authored
   summary, not the verbatim user prompt. Limit it to 1–120 characters from
   `A-Z`, `a-z`, `0-9`, space, `.`, `,`, `:`, `/`, `_`, and `-`, and pass it as
   one single-quoted literal argument. Reject CR, LF, control characters, and
   shell metacharacters instead of trying to interpolate them. The shared chat
   transcript and ConfigHub result carry the fuller request context.
4. If the host allows the call, inspect its result and verify the postcondition
   read-only before moving to a separate next mutation.
5. If the host denies the call, Bash is unavailable, or the session is
   explicitly coached, say that nothing ran. Only then show the exact command
   for the user to run in their own terminal and ask them to return the output.

For unchanged scope, effect, and preconditions, a clear request plus the host
permission decision is the standalone interaction. Do not require Pilot, a
second approval system, a special confirmation file, or a redundant round of
chat confirmation. A materially changed scope, effect, or failed precondition
does require a focused new decision before submission. Do not invent or name an
extra approval component that is not part of the standalone skills architecture.
The host decision authorizes the attempted literal command; it is not a
replacement for exact scoping, command validation, secret handling, or the
destructive-command checks below.

An ambiguous request, unresolved target, unexpected scope expansion, missing
permission, failed safety precondition, suspected credential/secret exposure,
or unsupported command remains a reason to stop and ask a focused question.
For destructive commands, verify the exact installed help in the same session,
inventory dependencies and impact, and keep that help/read step separate from
the later one-command mutation prompt.

## Optional governance overlay

A separately installed product such as Pilot may inject a stricter policy for
its own session. If that external context explicitly says to stop, requires a
different approval, or denies a command class, obey it **before** calling Bash.
The overlay owns that extra policy; this reusable skill pack does not assume it
is present and does not implement or name its internal approval machinery.

## Claims after execution

Host permission authorizes an attempted command; it does not prove the command
succeeded or that a controller or cluster converged. Report the command result,
then gather the evidence required by the owning skill. Be precise about known
provider races: a fresh pre-read can reduce uncertainty, but it is not an atomic
compare-and-swap unless the invoked operation actually accepts and checks the
expected values.
