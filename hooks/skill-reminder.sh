#!/usr/bin/env bash
# Only one reminder per prompt. If the app plugin is absent its public guide
# is still usable. Never echo the prompt, file paths or account information.
app="Use the installed confighub:app-with-confighub skill first for this app request. If the app plugin is absent, use its public guide at https://github.com/confighubai/confighub-mini-plugin. Local app settings and previews need no hosted ConfigHub login."
daytona=" Daytona runs the app using its CLI or SDK. The ConfigHub Daytona starter tries a setting and returns a proposal for review. Read https://github.com/confighubai/confighub-mini-plugin/blob/main/examples/walkthroughs/starter-daytona.md. Use the existing Daytona sign-in if available. Verify the app response separately."
platform="Use confighub-lookup for this platform question. Read the installed cub help before composing a command. Check sign-in only for an operation that needs the selected server."
remind() {
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$1"
}

if [[ -t 0 ]]; then printf '{}\n'; exit 0; fi
event=$(cat)
shopt -s nocasematch
case "$event" in
  *confighub*|*cub*) ;;
  *) printf '{}\n'; exit 0 ;;
esac
if ! command -v jq >/dev/null; then
  remind "For app work, use the installed confighub:app-with-confighub skill first. Reserve confighub-lookup for explicit platform CLI and shared-hub questions."
  exit 0
fi
prompt=$(jq -er '.prompt | select(type == "string")' <<<"$event" 2>/dev/null) || { printf '{}\n'; exit 0; }
product='(^|[^[:alnum:]_])(confighub|cub)([^[:alnum:]_]|$)'
if ! [[ $prompt =~ $product ]]; then printf '{}\n'; exit 0; fi

app_job='(^|[^[:alnum:]_])(apps?|applications?|preview|settings?|starter|plugin|sandbox|daytona)([^[:alnum:]_]|$)'
app_verb='(^|[^[:alnum:]_])(build|create|make|attach|keep|deploy|run|try|stage|ship|start|remember|record|show)([^[:alnum:]_]|$)'
platform_topic='(^|[^[:alnum:]_])(cub|shared hub|service accounts?|changeorders?|changeworkflows?|units?|spaces?|targets?|releases?|api)([^[:alnum:]_]|$)'

cli_help='(^|[^[:alnum:]_])cub[[:space:]]+[[:alnum:]_-]+[[:space:]]+([[:alnum:]_-]+[[:space:]]+)?--help'
if [[ $prompt == *daytona* ]]; then app+="$daytona"; fi
if [[ $prompt != *"cub mini"* && $prompt =~ $cli_help ]]; then
  remind "$platform"
elif [[ $prompt == *"cub mini"* || $prompt == *"/confighub:"* || ( $prompt =~ $app_job && $prompt =~ $app_verb ) ]]; then
  remind "$app"
elif [[ $prompt =~ $platform_topic ]]; then
  remind "$platform"
else
  remind "$app"
fi
