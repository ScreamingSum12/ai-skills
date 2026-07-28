#!/bin/bash
# Emit a clean narrative digest from a Claude Code transcript JSONL.
#
# Two things this does that a naive text-extract does not:
#   1. Counts turns honestly. Only GENUINE user prompts become "## User" —
#      tool results, task notifications and local-command echoes all arrive as
#      user-role entries and are filtered out. Genuine prompts carry
#      `promptSource` and no `toolUseResult`.
#   2. Collapses turns. One assistant turn spans many assistant entries; those
#      are merged into a single "## Assistant" block so `grep -c '^## User'`
#      actually means "number of user turns".
#
# Usage: digest.sh <transcript.jsonl>

set -u
TX="${1:-}"
if [ -z "$TX" ] || [ ! -f "$TX" ]; then
  echo "digest.sh: transcript not found: '$TX'" >&2
  exit 1
fi

jq -s -r '
  def clean:
    gsub("(?s)<system-reminder>.*?</system-reminder>"; "")
    | gsub("(?s)<local-command-caveat>.*?</local-command-caveat>"; "")
    | sub("^\\s+"; "") | sub("\\s+$"; "");

  # Harness-injected pseudo-prompts that are not the human speaking.
  def injected:
    test("^\\s*<(task-notification|local-command|command-name|command-message|command-stdout|system-reminder)");

  [ .[]
    | select(.type == "user" or .type == "assistant")
    | select((.isSidechain // false) | not)
    | if .type == "user" then
        select(has("promptSource") and (has("toolUseResult") | not))
        | ( .message.content
            | if type == "string" then .
              else ([ .[]? | select(.type == "text") | .text ] | join("\n")) end
          ) as $t
        | select(($t | injected) | not)
        | { role: "user", text: ($t | clean) }
      else
        ( [ .message.content[]? | select(.type == "text") | .text ] | join("\n") ) as $t
        | { role: "assistant", text: ($t | clean) }
      end
    | select(.text | length > 0)
  ]
  # Merge consecutive same-role entries into one turn.
  | reduce .[] as $m ([];
      if (length > 0) and (.[-1].role == $m.role)
      then .[0:-1] + [ { role: $m.role, text: (.[-1].text + "\n\n" + $m.text) } ]
      else . + [$m] end)
  | .[]
  | "## " + (if .role == "user" then "User" else "Assistant" end) + "\n" + .text + "\n"
' "$TX"
