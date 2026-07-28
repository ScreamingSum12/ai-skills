#!/bin/bash
# Single entry point for artifact-mode's per-turn bookkeeping.
#
# The primary agent must NOT rely on remembering the session id, transcript
# path, or whether the keeper was already spawned — long sessions get
# compacted and that memory is lost. Everything is re-derived from the cwd and
# persisted to disk, so any turn can recover full state with one call.
#
# Usage:
#   turn.sh on                     # activate artifact mode for this session
#   turn.sh off                    # deactivate
#   turn.sh status                 # (default) refresh digest, print state + ACTION
#   turn.sh mark-spawned <name>    # record the keeper's agent name
#   turn.sh mark-published <url>   # record the published artifact URL
#
# status prints KEY=VALUE lines. ACTION is the decision the agent acts on:
#   SKIP     — do nothing this turn (see REASON)
#   SPAWN    — spawn the keeper, folding this turn's delta into the spawn prompt
#   DISPATCH — SendMessage the delta to the existing keeper (see KEEPER)

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AM_DIR="${AM_DIR:-$HOME/.claude/conversation-artifacts}"
MIN_TURNS="${AM_MIN_TURNS:-3}"
mkdir -p "$AM_DIR"

loc=$(bash "$HERE/locate-session.sh") || exit 1
SID=${loc%%$'\t'*}
TXP=${loc#*$'\t'}
STATE="$AM_DIR/$SID.state.json"
DIGEST="$AM_DIR/$SID.digest.md"

read_field() { # <field> <default>
  if [ -f "$STATE" ]; then
    jq -r --arg d "$2" ".$1 // \$d" "$STATE" 2>/dev/null || printf '%s' "$2"
  else
    printf '%s' "$2"
  fi
}

write_state() { # <jq-assignment-expr>
  local base='{}'
  [ -f "$STATE" ] && base=$(cat "$STATE")
  printf '%s' "$base" | jq \
    --arg sid "$SID" --arg txp "$TXP" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    ". + {session_id:\$sid, transcript:\$txp, updated:\$now} | $1" > "$STATE.tmp" \
    && mv "$STATE.tmp" "$STATE"
}

case "${1:-status}" in
  on)
    write_state '. + {active:true} | .keeper //= "" | .url //= ""'
    echo "SESSION_ID=$SID"
    echo "TRANSCRIPT=$TXP"
    echo "ACTIVE=true"
    ;;
  off)
    write_state '. + {active:false}'
    echo "ACTIVE=false"
    ;;
  mark-spawned)
    write_state "$(printf '. + {keeper:"%s"}' "${2:?usage: turn.sh mark-spawned <name>}")"
    echo "KEEPER=${2}"
    ;;
  mark-published)
    url=${2:?usage: turn.sh mark-published <url>}
    write_state "$(printf '. + {url:"%s"}' "$url")"
    printf '%s' "$url" > "$AM_DIR/$SID.url"
    echo "URL=$url"
    ;;
  status)
    active=$(read_field active false)
    echo "SESSION_ID=$SID"
    echo "TRANSCRIPT=$TXP"
    echo "AM_DIR=$AM_DIR"
    echo "DIGEST=$DIGEST"
    echo "ARTIFACT_HTML=$AM_DIR/$SID.artifact.html"
    echo "ACTIVE=$active"

    if [ "$active" != "true" ]; then
      echo "ACTION=SKIP"
      echo "REASON=inactive"
      exit 0
    fi

    bash "$HERE/digest.sh" "$TXP" > "$DIGEST" || exit 1
    turns=$(grep -c '^## User' "$DIGEST" || true)
    keeper=$(read_field keeper "")
    url=$(read_field url "")

    echo "TURNS=$turns"
    echo "MIN_TURNS=$MIN_TURNS"
    echo "KEEPER=$keeper"
    echo "URL=$url"
    echo "PUBLISHED=$([ -n "$url" ] && echo true || echo false)"

    if [ "$turns" -lt "$MIN_TURNS" ]; then
      echo "ACTION=SKIP"
      echo "REASON=below-threshold"
    elif [ -z "$keeper" ]; then
      echo "ACTION=SPAWN"
    else
      echo "ACTION=DISPATCH"
    fi
    ;;
  *)
    echo "turn.sh: unknown command '${1}'" >&2
    exit 2
    ;;
esac
