#!/usr/bin/env bash
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"For ConfigHub work, invoke the confighub-lookup skill before acting: look up the installed cub's help and the current docs rather than recalling them."}}
JSON
