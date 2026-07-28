#!/bin/bash
# Print "<session_id>\t<transcript_path>" for the CURRENT Claude Code session,
# derived from the working directory. Claude Code stores transcripts under
# ~/.claude/projects/<encoded-cwd>/<session_id>.jsonl where <encoded-cwd> is the
# absolute cwd with every "/" and "." replaced by "-".

set -u
enc=$(pwd | sed 's#[/.]#-#g')
dir="$HOME/.claude/projects/$enc"
tx=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -1)
if [ -z "$tx" ]; then
  echo "locate-session.sh: no transcript under $dir" >&2
  exit 1
fi
sid=$(basename "$tx" .jsonl)
printf '%s\t%s\n' "$sid" "$tx"
