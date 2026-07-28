#!/bin/bash
# Emit a clean narrative digest (user prompts + assistant text) from a Claude
# Code transcript JSONL, stripping thinking / tool_use / tool_result noise.
# One bot turn spans many assistant lines; only text-bearing ones are kept.
#
# Usage: digest.sh <transcript.jsonl>

set -u
TX="${1:-}"
if [ -z "$TX" ] || [ ! -f "$TX" ]; then
  echo "digest.sh: transcript not found: '$TX'" >&2
  exit 1
fi

jq -r '
  if .type=="user" then
    (.message.content) as $c |
    if ($c|type)=="string" then "## User\n" + $c + "\n"
    elif ($c|type)=="array" then
      ([$c[] | select(.type=="text") | .text] | join("\n")) as $t |
      if ($t|length)>0 then "## User\n" + $t + "\n" else empty end
    else empty end
  elif .type=="assistant" then
    ([.message.content[]? | select(.type=="text") | .text] | join("\n")) as $t |
    if ($t|length)>0 then "## Assistant\n" + $t + "\n" else empty end
  else empty end
' "$TX"
