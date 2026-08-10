#!/bin/bash
# Emit the current repo's pull requests as JSON for the artifact keeper.
#
# PR state changes on GitHub's clock, not the conversation's — checks finish and
# reviews land while nobody is talking about them. So the keeper re-runs this
# every turn rather than relying on the delta to mention a PR.
#
# Degrades quietly: if gh is missing, unauthenticated, or this isn't a GitHub
# repo, it prints {"available":false,...,"prs":[]} and exits 0. A missing `gh`
# must never break artifact mode.
#
# Usage: prs.sh
# Env:   AM_PR_LIMIT (default 10) — how many PRs to fetch

set -u
LIMIT="${AM_PR_LIMIT:-10}"

emit_unavailable() { printf '{"available":false,"reason":"%s","prs":[]}\n' "$1"; exit 0; }

command -v gh  >/dev/null 2>&1 || emit_unavailable "gh not installed"
command -v jq  >/dev/null 2>&1 || emit_unavailable "jq not installed"
git rev-parse --git-dir >/dev/null 2>&1 || emit_unavailable "not a git repository"
gh auth status >/dev/null 2>&1 || emit_unavailable "gh not authenticated"

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

raw=$(gh pr list --state all --limit "$LIMIT" \
        --json number,title,url,state,isDraft,headRefName,reviewDecision,updatedAt,statusCheckRollup \
        2>/dev/null) || emit_unavailable "no GitHub remote, or gh pr list failed"

[ -z "$raw" ] && raw='[]'

printf '%s' "$raw" | jq -c --arg branch "$branch" '
  # A rollup entry is either a CheckRun (.conclusion/.status) or a legacy
  # commit Status (.state). Normalise both to one word.
  def check_state:
    if .conclusion? and (.conclusion | length) > 0 then .conclusion
    elif .state? and (.state | length) > 0 then .state
    elif .status? then .status
    else "PENDING" end;

  def rollup:
    (. // []) as $c
    | if ($c | length) == 0 then "none"
      elif [$c[] | check_state] | any(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED") then "failing"
      elif [$c[] | check_state] | any(. == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED" or . == "WAITING") then "pending"
      elif [$c[] | check_state] | all(. == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED") then "passing"
      else "mixed" end;

  {
    available: true,
    prs: [ .[] | {
      number, title, url,
      # Draft is a distinct display state from plain OPEN.
      state:   (if .isDraft and .state == "OPEN" then "DRAFT" else .state end),
      branch:  .headRefName,
      review:  (if (.reviewDecision // "") == "" then "none" else .reviewDecision end),
      checks:  (.statusCheckRollup | rollup),
      updated: .updatedAt,
      # True for the PR belonging to the branch currently checked out.
      current: (.headRefName == $branch)
    } ]
    # Open work first, then most recently touched.
    | sort_by(
        (if .state == "OPEN" or .state == "DRAFT" then 0 else 1 end),
        (.updated | explode | map(-.))
      )
  }
'
