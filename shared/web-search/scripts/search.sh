#!/usr/bin/env bash
# Web search via SearXNG — no API key needed
# Usage: search.sh "query" [count]
# Prints one block per result, "No results for ..." for an empty list (exit 0),
# or a single "ERROR: ..." line (exit 1).
set -euo pipefail

QUERY="${1:?Usage: search.sh \"query\" [count]}"
COUNT="${2:-5}"
SEARXNG_URL="${SEARXNG_URL:-http://searxng.selfhosted.svc.cluster.local:8080}"

ENCODED_QUERY=$(printf '%s' "$QUERY" | sed 's/ /+/g; s/[^a-zA-Z0-9+._-]/%&/g')

BODYFILE=$(mktemp); ERRFILE=$(mktemp)
trap 'rm -f "$BODYFILE" "$ERRFILE"' EXIT
rc=0
code=$(curl -sS --max-time 15 -o "$BODYFILE" -w '%{http_code}' \
  "${SEARXNG_URL}/search?q=${ENCODED_QUERY}&format=json" 2>"$ERRFILE") || rc=$?

# curl itself failed: the server could not be reached
if [ "$rc" -ne 0 ]; then
  detail=$(tr '\n' ' ' < "$ERRFILE" | sed 's/ *$//')
  case "$rc" in
    6)  why="DNS lookup failed" ;;
    7)  why="connection refused" ;;
    28) why="timed out" ;;
    *)  why="curl exit $rc" ;;
  esac
  hint=""
  case "$rc" in
    6|7|28) hint=" (blocked by the knight's egress policy? add the host to spec.egress.allowedHosts or allowedServices)" ;;
  esac
  echo "ERROR: SearXNG unreachable at ${SEARXNG_URL}: ${why}${hint}${detail:+ [${detail}]}"
  exit 1
fi

if [ "$code" -lt 200 ] || [ "$code" -ge 300 ]; then
  echo "ERROR: SearXNG at ${SEARXNG_URL} returned HTTP ${code}"
  exit 1
fi

if [ -z "$(tr -d '[:space:]' < "$BODYFILE")" ]; then
  echo "ERROR: SearXNG at ${SEARXNG_URL} returned an empty response"
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  if ! n=$(jq -r '(.results // []) | length' "$BODYFILE" 2>/dev/null); then
    echo "ERROR: SearXNG at ${SEARXNG_URL} returned invalid JSON"
    exit 1
  fi
  if [ "$n" -eq 0 ]; then
    echo "No results for \"$QUERY\""
    exit 0
  fi
  jq -r --argjson n "$COUNT" '
    .results[:$n][] |
    "---\nTitle: \(.title // "")\nURL: \(.url // "")\nSnippet: \(.content // "")"' "$BODYFILE"
  exit 0
fi

# Fallback without jq: grep and paste. Fields are paired by position, so this
# assumes each result has url, title and content in that order.
if grep -Eq '"results"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]' "$BODYFILE"; then
  echo "No results for \"$QUERY\""
  exit 0
fi
grep -oP '"title"\s*:\s*"[^"]*"|"url"\s*:\s*"[^"]*"|"content"\s*:\s*"[^"]*"' "$BODYFILE" \
  | paste - - - \
  | head -n "$COUNT" \
  | while IFS=$'\t' read -r title url content; do
    t=$(echo "$title" | sed 's/.*"title"\s*:\s*"//;s/"$//')
    u=$(echo "$url" | sed 's/.*"url"\s*:\s*"//;s/"$//')
    c=$(echo "$content" | sed 's/.*"content"\s*:\s*"//;s/"$//')
    echo "---"
    echo "Title: $t"
    echo "URL: $u"
    echo "Snippet: $c"
  done
