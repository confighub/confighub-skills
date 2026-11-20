#!/usr/bin/env bash
# Load the reference for explicit platform work. App prompts get no extra context.
quiet() { printf '{}\n'; exit 0; }
[[ -t 0 ]] && quiet
command -v jq >/dev/null || quiet
prompt=$(jq -er '.prompt | select(type == "string")' 2>/dev/null) || quiet
shopt -s nocasematch

product='(^|[^[:alnum:]_])(confighub|cub)([^[:alnum:]_]|$)'
[[ $prompt =~ $product ]] || quiet
full='(^|[^[:alnum:]_])(full confighub|confighub platform|plain cub)([^[:alnum:]_]|$)'
mini='(^|[^[:alnum:]_])mini([^[:alnum:]_]|$)|/confighub:'
command='(^|[^[:alnum:]_])cub[[:space:]]+(--[[:alnum:]-]+|apply|auth|changeset|changeorder|changeworkflow|component|context|function|helm|kustomize|link|organization|release|serviceaccount|space|target|trigger|unit|version)([^[:alnum:]_-]|$)'
app='(^|[^[:alnum:]_])(apps?|applications?|starters?|previews?|settings?|sandbox|daytona)([^[:alnum:]_]|$)'
resource='(^|[^[:alnum:]_])(shared hub|service accounts?|changeorders?|changeworkflows?|units?|spaces?|targets?|releases?|api)([^[:alnum:]_]|$)'

if [[ ! $prompt =~ $full ]]; then
  [[ $prompt =~ $mini ]] && quiet
  if [[ ! $prompt =~ $command ]]; then
    [[ $prompt =~ $app ]] && quiet
    [[ $prompt =~ $resource ]] || quiet
  fi
fi
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Use confighub-lookup for this platform question. Read the installed cub help before composing a command. Check sign-in only for an operation that needs the selected server."}}'
