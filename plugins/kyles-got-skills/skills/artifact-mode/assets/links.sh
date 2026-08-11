#!/bin/bash
# Collect the session's important links, grouped by type, as JSON for the
# artifact keeper.
#
# Two sources:
#   1. The repo's pull requests (via gh) — the most important links in a coding
#      session, and they carry live state that moves on GitHub's clock.
#   2. URLs harvested from the conversation digest — JIRA tickets, artifacts,
#      docs, anything that got mentioned.
#
# Titles are resolved where it is safe and cheap to do so: via `gh` for GitHub
# pull requests, issues and commits, and from surrounding markdown link text
# otherwise. No arbitrary URL is ever fetched — resolving titles by fetching
# links out of a conversation would be both slow and a way to pull untrusted
# content into the page.
#
# Degrades quietly: missing gh or a non-GitHub repo simply drops that source.
# Always prints valid JSON and exits 0.
#
# Usage: links.sh [digest.md]
# Env:   AM_PR_LIMIT       (default 10) PRs to fetch
#        AM_LINK_MAX       (default 40) cap on harvested links
#        AM_RESOLVE_MAX    (default 15) cap on gh title lookups
#        AM_JIRA_HOST      e.g. acme.atlassian.net — enables bare TICKET-123
#                          detection. Without it, only full JIRA URLs count.

set -u
DIGEST="${1:-}"
PR_LIMIT="${AM_PR_LIMIT:-10}"
LINK_MAX="${AM_LINK_MAX:-40}"
RESOLVE_MAX="${AM_RESOLVE_MAX:-15}"
JIRA_HOST="${AM_JIRA_HOST:-}"

command -v jq >/dev/null 2>&1 || { printf '{"available":false,"reason":"jq not installed","groups":[]}\n'; exit 0; }

TMP=$(mktemp -t am-links.XXXXXX) || { printf '{"available":false,"reason":"mktemp failed","groups":[]}\n'; exit 0; }
trap 'rm -f "$TMP" "$TMP.res"' EXIT

have_gh=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then have_gh=true; fi

# ---------------------------------------------------------------- source 1: PRs
if $have_gh && git rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  gh pr list --state all --limit "$PR_LIMIT" \
     --json number,title,url,state,isDraft,headRefName,reviewDecision,updatedAt,statusCheckRollup \
     2>/dev/null \
  | jq -c --arg branch "$branch" '
      def check_state:
        if .conclusion? and (.conclusion | length) > 0 then .conclusion
        elif .state? and (.state | length) > 0 then .state
        elif .status? then .status else "PENDING" end;
      def rollup:
        (. // []) as $c
        | if ($c | length) == 0 then "none"
          elif [$c[] | check_state] | any(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED") then "failing"
          elif [$c[] | check_state] | any(. == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED" or . == "WAITING") then "pending"
          elif [$c[] | check_state] | all(. == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED") then "passing"
          else "mixed" end;
      .[] | {
        type: "pull-request",
        slug: ("#" + (.number | tostring)),
        title, url,
        state:   (if .isDraft and .state == "OPEN" then "DRAFT" else .state end),
        checks:  (.statusCheckRollup | rollup),
        review:  (if (.reviewDecision // "") == "" then "none" else .reviewDecision end),
        updated: .updatedAt,
        current: (.headRefName == $branch)
      }' >> "$TMP" 2>/dev/null || true
fi

# ------------------------------------------------- source 2: links in the digest
if [ -n "$DIGEST" ] && [ -f "$DIGEST" ]; then
  # Markdown links first, so [text](url) contributes a free title.
  grep -oE '\[[^]]{1,120}\]\(https?://[^) ]+\)' "$DIGEST" 2>/dev/null \
    | sed -E 's|^\[(.*)\]\((https?://[^) ]+)\)$|\2\t\1|' > "$TMP.md" || true
  # Then every bare URL. Markdown emphasis and sentence punctuation cling to the
  # end of a URL ("**<url>**", "<url>."); left on, they defeat deduplication
  # against the same URL from the gh source.
  grep -oE 'https?://[^ )>"'"'"'`]+' "$DIGEST" 2>/dev/null \
    | sed -E 's/[*_~.,;:!?)'"'"'"]+$//' | sed -E 's/\t.*//' > "$TMP.urls" || true

  {
    cat "$TMP.md" 2>/dev/null
    # bare urls get an empty title column
    sed 's/$/\t/' "$TMP.urls" 2>/dev/null
  } | awk -F'\t' '!seen[$1]++' | head -n "$LINK_MAX" \
  | while IFS=$'\t' read -r url mdtitle; do
      [ -z "$url" ] && continue
      host=$(printf '%s' "$url" | sed -E 's|^https?://([^/]+).*|\1|')
      type="reference"; slug="$host"
      case "$url" in
        *github.com/*/pull/*)
          type="pull-request"
          slug="#$(printf '%s' "$url" | sed -E 's|.*/pull/([0-9]+).*|\1|')" ;;
        *github.com/*/issues/*)
          type="issue"
          slug="#$(printf '%s' "$url" | sed -E 's|.*/issues/([0-9]+).*|\1|')" ;;
        *github.com/*/commit/*)
          type="commit"
          slug=$(printf '%s' "$url" | sed -E 's|.*/commit/([0-9a-f]+).*|\1|' | cut -c1-7) ;;
        *atlassian.net/browse/*)
          type="jira"
          slug=$(printf '%s' "$url" | sed -E 's|.*/browse/([A-Z][A-Z0-9]+-[0-9]+).*|\1|') ;;
        *claude.ai/*artifact*)
          type="artifact"
          # Distinguish multiple artifacts by a short id rather than collapsing
          # them all onto the same slug.
          slug="artifact $(printf '%s' "$url" | sed -E 's|.*/([^/?#]+)[?#]?.*|\1|' | cut -c1-8)" ;;
      esac
      jq -nc --arg t "$type" --arg s "$slug" --arg u "$url" --arg ti "$mdtitle" \
        '{type:$t, slug:$s, title:$ti, url:$u}'
    done >> "$TMP"

  # Bare JIRA keys, only when we know the host to build a URL from.
  #
  # PREFIX-123 is also the shape of half the standards and hash names in
  # existence (UTF-8, SHA-256, RFC-2119, CVE-2021...), so anything matching a
  # known non-ticket prefix is dropped. Full JIRA URLs bypass this entirely.
  if [ -n "$JIRA_HOST" ]; then
    NOT_JIRA='^(UTF|SHA|MD|AES|DES|RSA|ECDSA|HMAC|PBKDF|CRC|BASE|ASCII|ISO|RFC|CVE|CWE|IEEE|ANSI|ECMA|PEP|ES|TLS|SSL|HTTP|IPV|IP|X|UUID|GPT|LTS|CSS|HTML|JSON|XML|SQL|API|LTE|USB|PCI|RGB|CMYK|WCAG|FIPS|NIST)$'
    grep -oE '\b[A-Z][A-Z0-9]{1,9}-[0-9]+\b' "$DIGEST" 2>/dev/null | sort -u | head -20 \
    | while read -r key; do
        prefix=${key%%-*}
        printf '%s' "$prefix" | grep -qE "$NOT_JIRA" && continue
        jq -nc --arg s "$key" --arg u "https://$JIRA_HOST/browse/$key" \
          '{type:"jira", slug:$s, title:"", url:$u}'
      done >> "$TMP"
  fi
fi

# ------------------------------------------------------- resolve missing titles
: > "$TMP.res"
resolved=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  title=$(printf '%s' "$line" | jq -r '.title // ""')
  url=$(printf '%s' "$line"   | jq -r '.url')
  type=$(printf '%s' "$line"  | jq -r '.type')
  if [ -z "$title" ] && $have_gh && [ "$resolved" -lt "$RESOLVE_MAX" ]; then
    got=""
    case "$type" in
      pull-request) got=$(gh pr view "$url" --json title --jq .title 2>/dev/null || true) ;;
      issue)        got=$(gh issue view "$url" --json title --jq .title 2>/dev/null || true) ;;
      commit)
        slug=$(printf '%s' "$line" | jq -r '.slug')
        got=$(git log -1 --format=%s "$slug" 2>/dev/null || true) ;;
    esac
    if [ -n "$got" ]; then
      line=$(printf '%s' "$line" | jq -c --arg t "$got" '.title = $t')
      resolved=$((resolved + 1))
    fi
  fi
  printf '%s\n' "$line" >> "$TMP.res"
done < "$TMP"

# --------------------------------------------------------------- group & output
jq -s -c '
  # Later duplicates lose; the PR source runs first and is richer.
  reduce .[] as $l ({}; if has($l.url) then . else . + {($l.url): $l} end)
  | [ .[] ]
  | group_by(.type)
  | map({
      type:  .[0].type,
      label: ( { "pull-request":"Pull requests", "issue":"Issues", "jira":"JIRA",
                 "commit":"Commits", "artifact":"Artifacts", "reference":"References"
               }[.[0].type] // .[0].type ),
      links: ( sort_by(
                 (if (.current // false) then 0 else 1 end),
                 (if (.state // "") == "OPEN" or (.state // "") == "DRAFT" then 0 else 1 end),
                 .slug
               ) )
    })
  | sort_by( { "pull-request":0, "issue":1, "jira":2, "commit":3,
               "artifact":4, "reference":5 }[.type] // 9 )
  | { available: (length > 0), groups: . }
' "$TMP.res"
